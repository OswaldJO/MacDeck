package com.example.companion_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.playnite.companion/streaming_bridge"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "discoverHosts" -> {
                    val hosts = listOf(
                        mapOf(
                            "id" to "local-mac",
                            "name" to "My Mac Host",
                            "address" to "192.168.1.10",
                            "paired" to false
                        )
                    )
                    result.success(hosts)
                }

                "pairWithPin" -> {
                    val pin = call.argument<String>("pin").orEmpty()
                    result.success(pin.length >= 4)
                }

                "startStream" -> result.success(true)
                "stopStream" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }
}
