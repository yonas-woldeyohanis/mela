package com.swiftreceipt.swiftreceipt

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsMessage

class SmsBroadcastReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        val prefs = SmsForegroundService.getPrefs(context)
        val isEnabled = prefs.getBoolean(SmsForegroundService.KEY_ENABLED, false)
        if (!isEnabled) {
            return
        }

        val messages: Array<SmsMessage>? = try {
            Telephony.Sms.Intents.getMessagesFromIntent(intent)
        } catch (_: Exception) {
            null
        }

        if (messages.isNullOrEmpty()) {
            return
        }

        val sender = messages[0].displayOriginatingAddress ?: ""
        val timestamp = messages[0].timestampMillis

        // Concatenate multi-part SMS messages into single string
        val bodyBuilder = StringBuilder()
        for (msg in messages) {
            val body = msg.displayMessageBody
            if (!body.isNullOrEmpty()) {
                bodyBuilder.append(body)
            }
        }
        val fullBody = bodyBuilder.toString()

        // Filter out non-banking SMS, personal chats, and OTP spam
        if (!SmsFilterConfig.shouldProcessSms(sender, fullBody)) {
            return
        }

        // 1. Deliver to Foreground Service for persistent network delivery
        val serviceIntent = Intent(context, SmsForegroundService::class.java).apply {
            action = SmsForegroundService.ACTION_SMS_RECEIVED
            putExtra("sender", sender)
            putExtra("body", fullBody)
            putExtra("timestamp", timestamp)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (_: Exception) {
            // Direct callback fallback
            MainActivity.sendSmsToFlutter(sender, fullBody, timestamp)
        }
    }
}
