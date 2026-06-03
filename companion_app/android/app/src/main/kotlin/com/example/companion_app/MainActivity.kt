package com.example.companion_app

import android.content.Intent
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

                "pairWithPin" -> result.success(true)

                "startStream" -> {
                    val host = call.argument<String>("host").orEmpty()
                    val port = call.argument<Int>("videoPort") ?: 28766
                    val audioPort = call.argument<Int>("audioPort") ?: 28767
                    val inputPort = call.argument<Int>("inputPort") ?: 28768
                    val width = call.argument<Int>("width") ?: 1920
                    val height = call.argument<Int>("height") ?: 1080
                    if (host.isEmpty()) {
                        result.error("invalid_args", "Missing host", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(this, PlayniteVideoActivity::class.java).apply {
                        putExtra(PlayniteVideoActivity.EXTRA_HOST, host)
                        putExtra(PlayniteVideoActivity.EXTRA_VIDEO_PORT, port)
                        putExtra(PlayniteVideoActivity.EXTRA_AUDIO_PORT, audioPort)
                        putExtra(PlayniteVideoActivity.EXTRA_INPUT_PORT, inputPort)
                        putExtra(PlayniteVideoActivity.EXTRA_WIDTH, width)
                        putExtra(PlayniteVideoActivity.EXTRA_HEIGHT, height)
                    }
                    startActivity(intent)
                    result.success(true)
                }

                "stopStream" -> {
                    val activity = PlayniteVideoActivity.current
                    if (activity != null) {
                        activity.runOnUiThread { activity.finishFromHost() }
                    } else {
                        PlayniteStreamLog.endSession("stop requested (video activity not open)")
                    }
                    val logPath = PlayniteStreamLog.logFilePath(applicationContext)
                    result.success(
                        hashMapOf(
                            "logPath" to logPath,
                        ),
                    )
                }

                "listConnectedControllers" -> {
                    result.success(ConnectedControllerProbe.list(this))
                }

                else -> result.notImplemented()
            }
        }
    }
}
