package com.swiftreceipt.swiftreceipt

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

    companion object {
        const val CHANNEL_ID = "swiftreceipt_sms_station"
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
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
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

                val notification = buildNotification("Listening for Telebirr & CBE Birr receipts...")
                startForeground(NOTIFICATION_ID, notification)
            }
        }

        return START_STICKY
    }

    private fun handleIncomingSms(sender: String, body: String, timestamp: Long) {
        // Forward to Flutter UI if attached
        MainActivity.sendSmsToFlutter(sender, body, timestamp)

        // Asynchronously post to Supabase RPC
        thread {
            try {
                val prefs = getPrefs(this)
                val orgId = prefs.getString(KEY_ORG_ID, null)
                val sbUrl = prefs.getString(KEY_SUPABASE_URL, null)
                val sbKey = prefs.getString(KEY_SUPABASE_KEY, null)

                if (orgId.isNullOrEmpty() || sbUrl.isNullOrEmpty() || sbKey.isNullOrEmpty()) {
                    return@thread
                }

                // Call Supabase /rest/v1/rpc/ingest_bank_sms
                val endpoint = if (sbUrl.endsWith("/")) "${sbUrl}rest/v1/rpc/ingest_bank_sms" else "$sbUrl/rest/v1/rpc/ingest_bank_sms"
                val url = URL(endpoint)
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.connectTimeout = 8000
                conn.readTimeout = 8000
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("apikey", sbKey)
                conn.setRequestProperty("Authorization", "Bearer $sbKey")

                val payload = JSONObject().apply {
                    put("p_org_id", orgId)
                    put("p_raw_sms", body)
                    put("p_provider", sender)
                    // Leave reference & amount extraction to the smart database trigger or client parser
                    put("p_reference", "")
                    put("p_amount", 0.0)
                }

                OutputStreamWriter(conn.outputStream).use { writer ->
                    writer.write(payload.toString())
                    writer.flush()
                }

                val responseCode = conn.responseCode
                conn.disconnect()
            } catch (_: Exception) {
            }
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

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Mela SMS Station",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitors business SIM for customer bank payment receipts"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
