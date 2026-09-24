package com.aichar.ai_character_app

import com.aichar.ai_character_app.companion.CompanionVideoViewFactory
import com.aichar.ai_character_app.keepalive.KeepAliveChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.aichar.ai_character_app/lifecycle",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "moveTaskToBack" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        KeepAliveChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "companion_video_view",
                CompanionVideoViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
    }
}
