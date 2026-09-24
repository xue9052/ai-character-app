package com.aichar.ai_character_app.keepalive

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Dart 侧控制常驻服务 + 电池优化白名单的方法通道。 */
object KeepAliveChannel {

    private const val CHANNEL = "com.aichar.ai_character_app/keepalive"

    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> result.success(start(activity, call.argument<String>("text")))
                "stop" -> {
                    stop(activity)
                    result.success(true)
                }
                "isRunning" -> result.success(ConnectionService.isRunning)
                "isIgnoringBatteryOptimizations" ->
                    result.success(isIgnoringBatteryOptimizations(activity))
                "requestIgnoreBatteryOptimizations" ->
                    result.success(requestIgnoreBatteryOptimizations(activity))
                else -> result.notImplemented()
            }
        }
    }

    private fun start(context: Context, text: String?): Boolean {
        val intent = Intent(context, ConnectionService::class.java).apply {
            if (!text.isNullOrBlank()) putExtra(ConnectionService.EXTRA_TEXT, text)
        }
        return try {
            ContextCompat.startForegroundService(context, intent)
            true
        } catch (e: Exception) {
            // Android 12+ 从后台拉起前台服务会被拒；此时退回推送兜底，不影响主流程
            false
        }
    }

    private fun stop(context: Context) {
        val intent = Intent(context, ConnectionService::class.java).apply {
            action = ConnectionService.ACTION_STOP
        }
        try {
            context.startService(intent)
        } catch (e: Exception) {
            context.stopService(Intent(context, ConnectionService::class.java))
        }
    }

    private fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun requestIgnoreBatteryOptimizations(activity: Activity): Boolean {
        if (isIgnoringBatteryOptimizations(activity)) return true
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val direct = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${activity.packageName}"),
        )
        return try {
            activity.startActivity(direct)
            true
        } catch (e: Exception) {
            try {
                activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                true
            } catch (e2: Exception) {
                false
            }
        }
    }
}
