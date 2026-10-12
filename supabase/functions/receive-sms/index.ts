// Supabase Edge Function: receive-sms
// Automatically parses SMS notifications from Telebirr, CBE, and other Ethiopian payment providers,
// and saves credits to the `bank_credits` table to match against waiter scans.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("SMS_WEBHOOK_SECRET"); // Optional secret header check

interface SmsPayload {
  org_id?: string;
  sender?: string; // SMS sender address (e.g., '127', 'telebirr', 'CBE')
  message?: string; // The SMS text body
  text?: string;
  body?: string;
  timestamp?: number | string;
}

interface ParsedPayment {
  reference: string;
  amount: number;
  senderName?: string;
  provider: string;
}

// Parser for Ethiopian Mobile Money & Bank SMS
function parseSms(senderHeader: string, text: string): ParsedPayment | null {
  const clean = text.replace(/,/g, "");
  const senderLower = (senderHeader || "").toLowerCase();

  // 1. Telebirr SMS (usually from 127 or 'telebirr')
  // Example: "You have received 250.00 ETB from ABEBE KEBEDE (251911******). Transaction number is CI87X12345."
  // or "Dear Customer, you have received ETB 150.00 from ..."
  if (senderLower.includes("127") || senderLower.includes("telebirr") || clean.toLowerCase().includes("telebirr")) {
    const refMatch = clean.match(/(?:transaction (?:number|no|id)|txnid|txn)\s*(?:is|:)?\s*([A-Za-z0-9]+)/i) ||
                     clean.match(/\b([A-Z0-9]{8,14})\b/);
    const amountMatch = clean.match(/(?:received|transferred)\s+(?:ETB\s*)?([0-9]+(?:\.[0-9]{1,2})?)\s*(?:ETB)?/i) ||
                        clean.match(/([0-9]+(?:\.[0-9]{1,2})?)\s*ETB/i);
    const personMatch = clean.match(/from\s+([A-Za-z\s]+?)(?:\s*\(|\s+on|\s+at|\s*\.|\s+trans)/i);

    if (refMatch && amountMatch) {
      return {
        provider: "telebirr",
        reference: refMatch[1].trim().toUpperCase(),
        amount: parseFloat(amountMatch[1]),
        senderName: personMatch ? personMatch[1].trim() : undefined,
      };
    }
  }

  // 2. CBE / CBE Birr
  // Example: "Your account 1000*** was credited with ETB 500.00 by TESFAYE ALEMU. Txn ID: FT24123ABC..."
  if (senderLower.includes("cbe") || clean.toLowerCase().includes("commercial bank of ethiopia") || clean.includes("credited with")) {
    const refMatch = clean.match(/(?:txn\s*id|transaction\s*id|ref(?:erence)?\s*(?:no|number)?)\s*(?:is|:)?\s*([A-Za-z0-9]+)/i) ||
                     clean.match(/\b(FT[0-9A-Z]+)\b/i);
    const amountMatch = clean.match(/(?:credited with|received)\s+(?:ETB\s*)?([0-9]+(?:\.[0-9]{1,2})?)/i) ||
                        clean.match(/ETB\s*([0-9]+(?:\.[0-9]{1,2})?)/i);
    const personMatch = clean.match(/(?:by|from)\s+([A-Za-z\s]+?)(?:\s*\.|\s+ref|\s+txn)/i);

    if (refMatch && amountMatch) {
      return {
        provider: "cbe",
        reference: refMatch[1].trim().toUpperCase(),
        amount: parseFloat(amountMatch[1]),
        senderName: personMatch ? personMatch[1].trim() : undefined,
      };
    }
  }

  // 3. Fallback generic extractor
  const genericRef = clean.match(/\b([A-Z0-9]{10,14})\b/);
  const genericAmount = clean.match(/([0-9]+\.[0-9]{2})/);
  if (genericRef && genericAmount) {
    return {
      provider: "other",
      reference: genericRef[1].toUpperCase(),
      amount: parseFloat(genericAmount[1]),
    };
  }

  return null;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  // Optional webhook secret check
  if (WEBHOOK_SECRET) {
    const headerSecret = req.headers.get("x-webhook-secret");
    if (headerSecret !== WEBHOOK_SECRET) {
      return new Response("Unauthorized", { status: 401 });
    }
  }

  try {
    const payload: SmsPayload = await req.json();
    const smsText = payload.message || payload.text || payload.body || "";
    const smsSender = payload.sender || "";
    const orgId = payload.org_id || req.headers.get("x-org-id");

    if (!smsText) {
      return new Response(JSON.stringify({ error: "Missing SMS message content" }), { status: 400 });
    }

    if (!orgId) {
      return new Response(JSON.stringify({ error: "Missing org_id in payload or header" }), { status: 400 });
    }

    const parsed = parseSms(smsSender, smsText);
    if (!parsed) {
      return new Response(JSON.stringify({
        warning: "Could not parse reference/amount from message",
        raw: smsText,
      }), { status: 422 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Call ingest_bank_sms RPC to save and auto-match
    const { data, error } = await supabase.rpc("ingest_bank_sms", {
      p_org_id: orgId,
      p_reference: parsed.reference,
      p_amount: parsed.amount,
      p_sender: parsed.senderName || null,
      p_provider: parsed.provider,
      p_raw_sms: smsText,
    });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), { status: 500 });
    }

    return new Response(JSON.stringify({
      success: true,
      parsed,
      result: data,
    }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: `${err}` }), { status: 500 });
  }
});
