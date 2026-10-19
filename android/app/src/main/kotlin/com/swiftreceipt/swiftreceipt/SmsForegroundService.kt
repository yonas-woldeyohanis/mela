package com.swiftreceipt.swiftreceipt

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class SmsForegroundService : Service() {

    data class ParsedPayment(
        val provider: String,
        val reference: String,
        val amount: Double,
        val sender: String? = null
    )

    companion object {
        const val CHANNEL_ID = "swiftreceipt_sms_station"
        const val CHANNEL_ID_VERIFIED = "swiftreceipt_verified_payments"
        const val NOTIFICATION_ID = 991
        const val ACTION_START = "START_LISTENER"
        const val ACTION_STOP = "STOP_LISTENER"
        const val ACTION_SMS_RECEIVED = "SMS_RECEIVED"
        const val PREFS_NAME = "swiftreceipt_station_prefs"
        const val KEY_ENABLED = "station_enabled"
        const val KEY_ORG_ID = "org_id"
        const val KEY_SUPABASE_URL = "supabase_url"
        const val KEY_SUPABASE_KEY = "supabase_key"

        var isRunning = false
            private set

        fun getPrefs(context: Context): SharedPreferences {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }

        fun parsePaymentInfo(sender: String, body: String): ParsedPayment? {
            val text = body.replace("\r", "").trim()
            val lower = text.lowercase()
            val senderUpper = sender.trim().uppercase()

            // Filter out any debit / outgoing transfer
            if (SmsFilterConfig.isDebitOrOutgoing(body)) {
                return null
            }

            var provider = "Bank"
            var ref: String? = null
            var amt: Double? = null
            var senderName: String? = null

            val curr = """(?:ETB|Birr|Br|ብር|Qarshii)"""
            val numRegex = """([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)"""

            // 1. CBE / CBE Birr
            if (senderUpper.contains("CBE") || lower.contains("commercial bank of ethiopia") || lower.contains("የኢትዮጵያ ንግድ ባንክ")) {
                provider = if (senderUpper.contains("BIRR") || lower.contains("cbe birr") || lower.contains("cbebirr")) "CBE Birr" else "CBE"

                val urlMatch = Regex("""mbreciept\.cbe\.com\.et/([A-Za-z0-9_\-]+)""", RegexOption.IGNORE_CASE).find(text)
                if (urlMatch != null) {
                    ref = urlMatch.groupValues[1].trim()
                }
                if (ref == null) {
                    val ftMatch = Regex("""\b(FT[0-9A-Z]{8,22})\b""", RegexOption.IGNORE_CASE).find(text)
                    if (ftMatch != null) ref = ftMatch.groupValues[1].trim().uppercase()
                }
                if (ref == null) {
                    val txnMatch = Regex("""(?:txn\s*id|transaction\s*id|ref(?:erence)?\s*(?:no|number)?)\s*[:\-]?\s*([A-Za-z0-9]{8,24})""", RegexOption.IGNORE_CASE).find(text)
                    if (txnMatch != null) ref = txnMatch.groupValues[1].trim().uppercase()
                }

                val amtMatch = Regex("""(?:credited\s*(?:with)?|received|amount\s*of)\s*(?:$curr\.?\s*)?$numRegex""", RegexOption.IGNORE_CASE).find(text)
                    ?: Regex("""(?:$curr\.?\s*)$numRegex""", RegexOption.IGNORE_CASE).find(text)
                if (amtMatch != null) {
                    amt = amtMatch.groupValues[1].replace(",", "").toDoubleOrNull()
                }

                val nameMatch = Regex("""(?:by|from|ከ)\s+([A-Za-z\s]+?)(?:\s*\.|\s+ref|\s+txn|\s+on|\s+at|\s+to)""", RegexOption.IGNORE_CASE).find(text)
                if (nameMatch != null) senderName = nameMatch.groupValues[1].trim()
            }
            // 2. Telebirr
            else if (senderUpper == "127" || senderUpper.contains("TELEBIRR") || lower.contains("telebirr") || lower.contains("ቴሌብር")) {
                provider = "Telebirr"

                val refMatch = Regex("""(?:(?:by\s+)?transaction\s*(?:number|no|id)|የግብይት\s*ቁጥር)\s*(?:is|:)?\s*([A-Za-z0-9]{8,18})""", RegexOption.IGNORE_CASE).find(text)
                    ?: Regex("""\b([A-Z0-9]{10})\b""").find(text)
                if (refMatch != null) ref = refMatch.groupValues[1].trim().uppercase()

                val amtMatch = Regex("""(?:received|ደርሶዎታል|ገቢ)\s*(?:$curr\.?\s*)?$numRegex""", RegexOption.IGNORE_CASE).find(text)
                    ?: Regex("""(?:$curr\.?\s*)$numRegex""", RegexOption.IGNORE_CASE).find(text)
                if (amtMatch != null) {
                    amt = amtMatch.groupValues[1].replace(",", "").toDoubleOrNull()
                }

                val nameMatch = Regex("""(?:from|ከ)\s+([A-Za-z0-9\s]+?)(?:\s+to\s+your|\s*\(|\s+on|\s+at|\s*\.|\s+ደርሶዎታል)""", RegexOption.IGNORE_CASE).find(text)
                if (nameMatch != null) senderName = nameMatch.groupValues[1].trim()
            }
            // 3. Abyssinia / BOA
            else if (senderUpper.contains("ABYSSINIA") || senderUpper.contains("BOA") || senderUpper.contains("APOLLO") || lower.contains("abyssinia")) {
                provider = "Abyssinia"
                val urlMatch = Regex("""(?:slip/\?trx=|trx=)([A-Za-z0-9]{8,24})""", RegexOption.IGNORE_CASE).find(text)
                if (urlMatch != null) ref = urlMatch.groupValues[1].trim().uppercase()
                if (ref == null) {
                    val ftMatch = Regex("""\b(FT[0-9A-Z]{8,22})\b""", RegexOption.IGNORE_CASE).find(text)
                    if (ftMatch != null) ref = ftMatch.groupValues[1].trim().uppercase()
                }
                if (ref == null) {
                    val refMatch = Regex("""(?:ref(?:erence)?|txn\s*id|code)\s*[:\-]?\s*([A-Za-z0-9]{6,24})""", RegexOption.IGNORE_CASE).find(text)
                    if (refMatch != null) ref = refMatch.groupValues[1].trim().uppercase()
                }
                val amtMatch = Regex("""(?:credited\s*(?:with)?|deposited|amount\s*(?:of)?|received)\s*(?:$curr\.?\s*)?$numRegex""", RegexOption.IGNORE_CASE).find(text)
                if (amtMatch != null) amt = amtMatch.groupValues[1].replace(",", "").toDoubleOrNull()
            }
            // 4. Awash
            else if (senderUpper.contains("AWASH") || senderUpper == "881" || lower.contains("awash")) {
                provider = "Awash"
                val refMatch = Regex("""(?:trans\s*ref|ref(?:erence)?|txn\s*id)\s*[:\-]?\s*([A-Za-z0-9]{6,24})""", RegexOption.IGNORE_CASE).find(text)
                    ?: Regex("""\b(AW[0-9A-Z]{6,18})\b""", RegexOption.IGNORE_CASE).find(text)
                if (refMatch != null) ref = refMatch.groupValues[1].trim().uppercase()
                val amtMatch = Regex("""(?:credited\s*(?:with)?|amount|received)\s*(?:$curr\.?\s*)?$numRegex""", RegexOption.IGNORE_CASE).find(text)
                if (amtMatch != null) amt = amtMatch.groupValues[1].replace(",", "").toDoubleOrNull()
            }
            // 5. Dashen
            else if (senderUpper.contains("DASHEN") || senderUpper.contains("AMOLE") || senderUpper == "8899" || lower.contains("dashen")) {
                provider = "Dashen"
                val refMatch = Regex("""(?:txn\s*ref|ref(?:erence)?|txn\s*id)\s*[:\-]?\s*([A-Za-z0-9]{6,24})""", RegexOption.IGNORE_CASE).find(text)
                    ?: Regex("""\b(DA[0-9A-Z]{6,18})\b""", RegexOption.IGNORE_CASE).find(text)
                if (refMatch != null) ref = refMatch.groupValues[1].trim().uppercase()
                val amtMatch = Regex("""(?:credited\s*(?:with)?|amount|received)\s*(?:$curr\.?\s*)?$numRegex""", RegexOption.IGNORE_CASE).find(text)
                if (amtMatch != null) amt = amtMatch.groupValues[1].replace(",", "").toDoubleOrNull()
            }
            // 6. Universal Bank Fallback
            else {
                for (b in SmsFilterConfig.allowedSenders) {
                    if (senderUpper.contains(b.uppercase()) || lower.contains(b)) {
                        provider = b.replaceFirstChar { it.uppercase() }
                        break
                    }
                }
                val refMatch = Regex("""(?:ref(?:erence)?|txn\s*(?:id|no)|transaction\s*(?:id|no)|code|መለያ|ማጣቀሻ)\s*[:\-]?\s*([A-Za-z0-9]{6,26})""", RegexOption.IGNORE_CASE).find(text)
                    ?: Regex("""\b(?=[A-Z0-9]*\d)(?=[A-Z0-9]*[A-Z])[A-Z0-9]{8,18}\b""").find(text)
                if (refMatch != null) ref = refMatch.groupValues[1].trim().uppercase()

                val amtMatch = Regex("""(?:credited\s*(?:with)?|amount\s*(?:of)?|received|ገቢ)\s*(?:$curr\.?\s*)?$numRegex""", RegexOption.IGNORE_CASE).find(text)
                    ?: Regex("""(?:$curr\.?\s*)$numRegex""", RegexOption.IGNORE_CASE).find(text)
                if (amtMatch != null) amt = amtMatch.groupValues[1].replace(",", "").toDoubleOrNull()
            }

            if (ref != null && amt != null && amt > 0) {
                return ParsedPayment(
                    provider = provider,
                    reference = ref,
                    amount = amt,
                    sender = senderName
                )
            }
            return null
        }

        fun postToSupabase(context: Context, provider: String, reference: String, amount: Double, sender: String?, rawSms: String) {
            thread {
                try {
                    val prefs = getPrefs(context)
                    val orgId = prefs.getString(KEY_ORG_ID, null)
                    val sbUrl = prefs.getString(KEY_SUPABASE_URL, null)
                    val sbKey = prefs.getString(KEY_SUPABASE_KEY, null)

                    if (orgId.isNullOrEmpty() || sbUrl.isNullOrEmpty() || sbKey.isNullOrEmpty()) {
                        return@thread
                    }

                    val endpoint = if (sbUrl.endsWith("/")) "${sbUrl}rest/v1/rpc/ingest_bank_sms" else "$sbUrl/rest/v1/rpc/ingest_bank_sms"
                    val url = URL(endpoint)
                    val conn = url.openConnection() as HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.connectTimeout = 10000
                    conn.readTimeout = 10000
                    conn.doOutput = true
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.setRequestProperty("apikey", sbKey)
                    conn.setRequestProperty("Authorization", "Bearer $sbKey")

                    val payload = JSONObject().apply {
                        put("p_org_id", orgId)
                        put("p_raw_sms", rawSms)
                        put("p_provider", provider)
                        put("p_reference", reference)
                        put("p_amount", amount)
                        if (!sender.isNullOrEmpty()) {
                            put("p_sender", sender)
                        }
                    }

                    OutputStreamWriter(conn.outputStream).use { writer ->
                        writer.write(payload.toString())
                        writer.flush()
                    }

                    conn.responseCode
                    conn.disconnect()
                } catch (_: Exception) {}
            }
        }

        fun showVerifiedNotification(context: Context, payment: ParsedPayment) {
            try {
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                val content = "Received ETB ${String.format("%.2f", payment.amount)} · Ref: ${payment.reference}${if (!payment.sender.isNullOrEmpty()) " (${payment.sender})" else ""}"

                val notif = NotificationCompat.Builder(context, CHANNEL_ID_VERIFIED)
                    .setContentTitle("${payment.provider} Payment Verified")
                    .setContentText(content)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(content))
                    .setSmallIcon(android.R.drawable.stat_notify_sync)
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setDefaults(NotificationCompat.DEFAULT_ALL)
                    .setAutoCancel(true)
                    .setContentIntent(pendingIntent)
                    .build()

                val manager = context.getSystemService(NotificationManager::class.java)
                val notifId = (System.currentTimeMillis() % 100000).toInt()
                manager?.notify(notifId, notif)
            } catch (_: Exception) {}
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START

        when (action) {
            ACTION_STOP -> {
                isRunning = false
                getPrefs(this).edit().putBoolean(KEY_ENABLED, false).apply()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_SMS_RECEIVED -> {
                ensureForegroundNotification()

                val sender = intent?.getStringExtra("sender") ?: ""
                val body = intent?.getStringExtra("body") ?: ""
                val timestamp = intent?.getLongExtra("timestamp", System.currentTimeMillis()) ?: System.currentTimeMillis()
                handleIncomingSms(sender, body, timestamp)
            }

            ACTION_START -> {
                isRunning = true
                val orgId = intent?.getStringExtra("org_id")
                val supabaseUrl = intent?.getStringExtra("supabase_url")
                val supabaseKey = intent?.getStringExtra("supabase_key")

                val prefs = getPrefs(this).edit().putBoolean(KEY_ENABLED, true)
                if (!orgId.isNullOrEmpty()) prefs.putString(KEY_ORG_ID, orgId)
                if (!supabaseUrl.isNullOrEmpty()) prefs.putString(KEY_SUPABASE_URL, supabaseUrl)
                if (!supabaseKey.isNullOrEmpty()) prefs.putString(KEY_SUPABASE_KEY, supabaseKey)
                prefs.apply()

                ensureForegroundNotification()
            }
        }

        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        val prefs = getPrefs(this)
        val isEnabled = prefs.getBoolean(KEY_ENABLED, false)
        if (isEnabled) {
            // Guarantee service restarts if swiped from recent apps
            val restartIntent = Intent(applicationContext, SmsForegroundService::class.java).apply {
                action = ACTION_START
            }
            val pendingIntent = PendingIntent.getService(
                applicationContext,
                101,
                restartIntent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            try {
                alarmManager?.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + 1000,
                    pendingIntent
                )
            } catch (_: Exception) {
                alarmManager?.set(
                    AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + 1000,
                    pendingIntent
                )
            }
        }
    }

    private fun ensureForegroundNotification() {
        val notification = buildNotification("Listening for incoming customer payments...")
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun handleIncomingSms(sender: String, body: String, timestamp: Long) {
        // 1. Forward to Flutter UI if attached
        MainActivity.sendSmsToFlutter(sender, body, timestamp)

        // 2. Parse payment info directly in native background
        val parsed = parsePaymentInfo(sender, body)

        if (parsed != null) {
            // Show verified heads-up alert to the business owner
            showVerifiedNotification(this, parsed)

            // Post to Supabase RPC with extracted reference & amount
            postToSupabase(
                context = this,
                provider = parsed.provider,
                reference = parsed.reference,
                amount = parsed.amount,
                sender = parsed.sender,
                rawSms = body
            )
        }
    }

    private fun buildNotification(contentText: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Mela Verification Station")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // Channel 1: Background Listener Status (Low importance, silent)
            val stationChannel = NotificationChannel(
                CHANNEL_ID,
                "Mela Station Status",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitors business SIM for incoming customer payment receipts"
            }
            manager?.createNotificationChannel(stationChannel)

            // Channel 2: Verified Payments (High importance, banner + sound)
            val verifiedChannel = NotificationChannel(
                CHANNEL_ID_VERIFIED,
                "Verified Customer Payments",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Immediate alerts when a customer bank payment is confirmed"
                enableVibration(true)
            }
            manager?.createNotificationChannel(verifiedChannel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
