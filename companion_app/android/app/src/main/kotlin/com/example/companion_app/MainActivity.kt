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
                "discoverHosts" -> result.success(emptyList<Map<String, Any>>())

                "pairWithPin" -> {
                    val pin = call.argument<String>("pin").orEmpty()
                    result.success(pin.length >= 4)
                }

                "startStream" -> {
                    val args = call.arguments as? Map<String, Any?> ?: run {
                        result.error("invalid_args", "Missing stream configuration", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val started = StreamLaunchHelper.startStream(this, args)
                        result.success(started)
                    } catch (e: IllegalStateException) {
                        result.error(
                            "identity_sync_failed",
                            e.message ?: "Could not sync Moonlight client certificate",
                            null,
                        )
                    } catch (e: Exception) {
                        result.error("stream_start_failed", e.message, null)
                    }
                }

                "stopStream" -> {
                    StreamLaunchHelper.stopStream()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}
