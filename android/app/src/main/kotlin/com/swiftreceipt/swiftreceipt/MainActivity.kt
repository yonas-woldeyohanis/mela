package com.swiftreceipt.swiftreceipt

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.swiftreceipt/sms_listener"
        private const val EVENT_CHANNEL = "com.swiftreceipt/sms_stream"
        private const val SMS_PERMISSION_REQ_CODE = 4040

        private var eventSink: EventChannel.EventSink? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        fun sendSmsToFlutter(sender: String, body: String, timestamp: Long) {
            mainHandler.post {
                val data = mapOf(
                    "sender" to sender,
                    "body" to body,
                    "timestamp" to timestamp
                )
                try {
                    eventSink?.success(data)
                } catch (_: Exception) {}
            }
        }
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingStartArgs: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermissions" -> {
                    val hasPerm = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECEIVE_SMS
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(hasPerm)
                }

                "isListenerRunning" -> {
                    val prefs = SmsForegroundService.getPrefs(this)
                    val enabled = SmsForegroundService.isRunning || prefs.getBoolean(SmsForegroundService.KEY_ENABLED, false)
                    result.success(enabled)
                }

                "startListener" -> {
                    val orgId = call.argument<String>("org_id")
                    val supabaseUrl = call.argument<String>("supabase_url")
                    val supabaseKey = call.argument<String>("supabase_key")

                    val hasReceive = ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

                    if (!hasReceive) {
                        pendingResult = result
                        pendingStartArgs = mapOf(
                            "org_id" to orgId,
                            "supabase_url" to supabaseUrl,
                            "supabase_key" to supabaseKey
                        )
                        val perms = mutableListOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            perms.add(Manifest.permission.POST_NOTIFICATIONS)
                        }
                        ActivityCompat.requestPermissions(this, perms.toTypedArray(), SMS_PERMISSION_REQ_CODE)
                    } else {
                        startStationService(orgId, supabaseUrl, supabaseKey)
                        result.success(true)
                    }
                }

                "stopListener" -> {
                    stopStationService()
                    result.success(false)
                }

                else -> result.notImplemented()
            }
        }

        // 2. Event Channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    private fun startStationService(orgId: String?, supabaseUrl: String?, supabaseKey: String?) {
        requestIgnoreBatteryOptimizationIfNeeded()
        val serviceIntent = Intent(this, SmsForegroundService::class.java).apply {
            action = SmsForegroundService.ACTION_START
            putExtra("org_id", orgId)
            putExtra("supabase_url", supabaseUrl)
            putExtra("supabase_key", supabaseKey)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun requestIgnoreBatteryOptimizationIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (powerManager != null && !powerManager.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                } catch (_: Exception) {}
            }
        }
    }

    private fun stopStationService() {
        val serviceIntent = Intent(this, SmsForegroundService::class.java).apply {
            action = SmsForegroundService.ACTION_STOP
        }
        startService(serviceIntent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERMISSION_REQ_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                val args = pendingStartArgs
                val orgId = args?.get("org_id") as? String
                val supabaseUrl = args?.get("supabase_url") as? String
                val supabaseKey = args?.get("supabase_key") as? String
                startStationService(orgId, supabaseUrl, supabaseKey)
                pendingResult?.success(true)
            } else {
                pendingResult?.error("PERMISSION_DENIED", "SMS receive permission is required for SMS station mode.", null)
            }
            pendingResult = null
            pendingStartArgs = null
        }
    }
}
