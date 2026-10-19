package com.swiftreceipt.swiftreceipt

/**
 * Native Android SMS Filter Configuration for Mela.
 *
 * HOW TO ADD YOUR OWN CUSTOM FILTER WORDS:
 * - Add bank sender IDs / numbers to [allowedSenders].
 * - Add incoming money keywords to [incomingKeywords].
 * - Add noise/spam/OTP phrases to [ignoredKeywords].
 */
object SmsFilterConfig {

    val allowedSenders = listOf(
        "127",
        "telebirr",
        "ethiotelecom",
        "cbe",
        "cbebirr",
        "cbe birr",
        "889",
        "881",
        "awash",
        "dashen",
        "amole",
        "abyssinia",
        "boa",
        "sinqee",
        "siinqee",
        "wegagen",
        "hibret",
        "berhan",
        "coop",
        "oromia",
        "nib",
        "zemen",
        "enat",
        "global",
        "tsedey",
        "amhara",
        "gadaa",
        "hijra",
        "zamzam",
        "rammis",
        "sidama"
    )

    val incomingKeywords = listOf(
        "received",
        "credited",
        "credit",
        "deposit",
        "deposited",
        "has been credited",
        "has been credited with",
        "transferred to your account",
        "transferred into your account",
        "payment received",
        "successful credit",
        "ደርሶዎታል",
        "ገቢ ተደርጓል",
        "ገቢ ሆኗል",
        "ገቢ",
        "ሒሳብዎ ገቢ",
        "ክፍያ ደርሶዎታል",
        "galii ta'eera"
    )

    val ignoredKeywords = listOf(
        "otp",
        "verification code",
        "confirmation code",
        "secret code",
        "security code",
        "ይለፍ ቃል",
        "የይለፍ ቃል",
        "የማረጋገጫ ኮድ",
        "airtime bought",
        "bought package",
        "package purchase",
        "data package",
        "voice package",
        "recharge",
        "የአየር ሰዓት",
        "ፓኬጅ ገዝተዋል",
        "you have successfully transferred",
        "you have transferred",
        "successfully transferred",
        "transferred from",
        "transferred out",
        "you transferred",
        "you have successfully paid",
        "you have paid",
        "successfully paid",
        "you paid",
        "payment to",
        "you have sent",
        "you sent",
        "sent to",
        "debited",
        "has been debited",
        "was debited",
        "is debited",
        "withdrawn",
        "withdrew",
        "withdrawal",
        "cash out",
        "cashout",
        "ተቀናሽ ተደርጓል",
        "ተቀናሽ ሆኗል",
        "ተቀናሽ",
        "ወጪ ተደርጓል",
        "ወጪ ሆኗል",
        "ወጪ",
        "አስተላልፈዋል",
        "በተሳካ ሁኔታ አስተላልፈዋል",
        "ከሒሳብዎ ወጪ",
        "ከፍለዋል",
        "ልከዋል",
        "ተልኳል",
        "baasii",
        "ergameera",
        "kan kaffaltan"
    )

    fun isDebitOrOutgoing(body: String): Boolean {
        val b = body.trim().lowercase()

        for (bad in ignoredKeywords) {
            if (b.contains(bad)) return true
        }

        val debitRegex = Regex(
            """(?:you\s+have\s+(?:successfully\s+)?transferred|successfully\s+transferred|transferred\s+(?:[a-z0-9,\.]+\s+)?from|you\s+transferred|transferred\s+out|you\s+have\s+(?:successfully\s+)?paid|successfully\s+paid|you\s+paid|payment\s+to\b|you\s+have\s+sent|you\s+sent|sent\s+to\b|\bdebited\b|has\s+been\s+debited|account\s+debited|\bwithdrawn\b|\bwithdrew\b|\bwithdrawal\b|cash\s*out|airtime\s+bought|package\s+purchase|bought\s+package|recharge\s+successful|ወጪ\s*(?:ተደርጓል|ሆኗል)?|ከ(?:ሒሳብዎ|አካውንትዎ|አካውንት)\s*ወጪ|ተቀናሽ|አስተላልፈዋል|ከፍለዋል|ልከዋል|የአየር\s*ሰዓት|ፓኬጅ\s*ገዝተዋል|\bbaasii\b|\bergameera\b|kan\s+kaffaltan)""",
            RegexOption.IGNORE_CASE
        )
        return debitRegex.containsMatchIn(b)
    }

    fun shouldProcessSms(sender: String, body: String): Boolean {
        val s = sender.trim().lowercase()
        val b = body.trim().lowercase()

        if (b.isEmpty()) return false

        // 1. Block noise / OTP / personal / debit / outgoing transfers
        if (isDebitOrOutgoing(b)) {
            return false
        }

        // 2. Check sender or body contains bank name
        val senderMatches = allowedSenders.any { s.contains(it) || s == it }
        val bodyMentionsBank = allowedSenders.any { b.contains(it) }

        if (!senderMatches && !bodyMentionsBank) {
            return false
        }

        // 3. Must match positive incoming credit keyword
        return incomingKeywords.any { b.contains(it) }
    }
}
