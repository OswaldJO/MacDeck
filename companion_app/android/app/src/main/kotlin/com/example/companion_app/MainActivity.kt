package com.example.companion_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicBoolean
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.playnite.companion/streaming_bridge"
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        @Volatile
        var pendingOpenMapping: Boolean = false

        private const val REQUEST_POST_NOTIFICATIONS = 9001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "discoverHosts" -> result.success(emptyList<Map<String, Any>>())

                "pairWithPin" -> result.success(true)

                "getStreamSession" -> result.success(PlayniteStreamSession.toMap())

                "startStream" -> {
                    val host = call.argument<String>("host").orEmpty()
                    val port = call.argument<Int>("videoPort") ?: 28766
                    val audioPort = call.argument<Int>("audioPort") ?: 28767
                    val audioTcpPort = call.argument<Int>("audioTcpPort") ?: 28769
                    val inputPort = call.argument<Int>("inputPort") ?: 28768
                    val width = call.argument<Int>("width") ?: 1920
                    val height = call.argument<Int>("height") ?: 1080
                    val cursorSpeed = (call.argument<Double>("cursorSpeed") ?: 1.0).toFloat()
                    val tapSlopPercent = call.argument<Int>("tapSlopPercent") ?: 100
                    val tapTimeoutMs = call.argument<Int>("tapTimeoutMs")?.toLong()
                        ?: PlayniteInputSender.TAP_TIMEOUT_MS
                    val tapPressure = (call.argument<Double>("tapPressure") ?: 0.35).toFloat()
                    val bindingsJson = call.argument<String>("controllerBindingsJson").orEmpty()
                    if (host.isEmpty()) {
                        result.error("invalid_args", "Missing host", null)
                        return@setMethodCallHandler
                    }
                    PlayniteStreamSession.host = host
                    PlayniteStreamSession.videoPort = port
                    PlayniteStreamSession.audioPort = audioPort
                    PlayniteStreamSession.audioTcpPort = audioTcpPort
                    PlayniteStreamSession.inputPort = inputPort
                    PlayniteStreamSession.width = width
                    PlayniteStreamSession.height = height
                    PlayniteStreamSession.cursorSpeed = cursorSpeed
                    PlayniteStreamSession.tapSlopPercent = tapSlopPercent
                    PlayniteStreamSession.tapTimeoutMs = tapTimeoutMs
                    PlayniteStreamSession.tapPressure = tapPressure
                    PlayniteStreamSession.controllerBindingsJson = bindingsJson
                    PlayniteStreamSession.hostStreamActive = true
                    launchStreamActivity(result)
                }

                "resumeStream" -> {
                    if (!PlayniteStreamSession.hostStreamActive || PlayniteStreamSession.host.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    if (PlayniteVideoActivity.current != null) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    launchStreamActivity(result)
                }

                "stopStream" -> {
                    PlayniteStreamStopper.stopAll(this, "stop requested from companion")
                    val logPath = PlayniteStreamLog.logFilePath(applicationContext)
                    result.success(
                        hashMapOf(
                            "logPath" to logPath,
                        ),
                    )
                }

                "showStreamMappingOverlay" -> {
                    val video = PlayniteVideoActivity.current
                    if (video != null) {
                        video.runOnUiThread { video.showControllerMappingOverlay() }
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }

                "consumePendingOpenMapping" -> {
                    val pending = pendingOpenMapping
                    pendingOpenMapping = false
                    result.success(pending)
                }

                "syncStreamNotification" -> {
                    val active = call.argument<Boolean>("active") == true
                    val host = call.argument<String>("host").orEmpty()
                    if (active) {
                        ensureNotificationPermissionForStream()
                        PlayniteStreamNotificationHelper.show(
                            this,
                            host.ifEmpty { PlayniteStreamSession.host },
                        )
                    } else {
                        PlayniteStreamNotificationHelper.dismiss(this)
                    }
                    result.success(null)
                }

                "listConnectedControllers" -> {
                    result.success(ConnectedControllerProbe.list(this))
                }

                "awaitGamepadButtonPress" -> {
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 15_000
                    val completed = AtomicBoolean(false)
                    if (!GamepadLinkCapture.beginListening { event ->
                        if (!completed.compareAndSet(false, true)) return@beginListening
                        mainHandler.post {
                            result.success(
                                hashMapOf(
                                    "keyCode" to event.keyCode,
                                    "label" to GamepadKeyCodes.labelForKeyCode(event.keyCode),
                                    "elementId" to (GamepadKeyCodes.elementIdForKeyCode(event.keyCode) ?: ""),
                                ),
                            )
                        }
                    }) {
                        result.error("busy", "Already waiting for a gamepad button", null)
                        return@setMethodCallHandler
                    }
                    mainHandler.postDelayed({
                        if (!completed.compareAndSet(false, true)) return@postDelayed
                        GamepadLinkCapture.cancel()
                        result.error("timeout", "No gamepad button pressed", null)
                    }, timeoutMs.toLong())
                }

                "cancelGamepadButtonPress" -> {
                    GamepadLinkCapture.cancel()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(PlayniteStreamMappingActions.EXTRA_OPEN_MAPPING, false)) {
            pendingOpenMapping = true
        }
    }

    private fun launchStreamActivity(result: MethodChannel.Result) {
        ensureNotificationPermissionForStream()
        PlayniteStreamNotificationHelper.show(this, PlayniteStreamSession.host)
        val intent = Intent(this, PlayniteVideoActivity::class.java)
        PlayniteStreamSession.toIntentFlags(intent)
        startActivity(intent)
        result.success(true)
    }

    private fun ensureNotificationPermissionForStream() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (GamepadLinkCapture.tryConsume(event)) {
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
