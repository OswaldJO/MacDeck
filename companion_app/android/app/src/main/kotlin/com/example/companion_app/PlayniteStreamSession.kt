package com.example.companion_app

/**
 * Last native stream connection parameters. [hostStreamActive] stays true after the user
 * leaves [PlayniteVideoActivity] with Back until they tap Stop in the companion app.
 */
object PlayniteStreamSession {
    @Volatile var hostStreamActive: Boolean = false
    @Volatile var viewerOpen: Boolean = false

    var host: String = ""
    var videoPort: Int = 28766
    var audioPort: Int = 28767
    var audioTcpPort: Int = 28769
    var inputPort: Int = 28768
    var width: Int = 1920
    var height: Int = 1080
    var cursorSpeed: Float = 1f
    var tapSlopPercent: Int = 100
    var tapTimeoutMs: Long = PlayniteInputSender.TAP_TIMEOUT_MS
    var tapPressure: Float = 0.35f
    var controllerBindingsJson: String = ""

    @Volatile
    private var keyboardSender: PlayniteKeyboardSender? = null

    /** Shared UDP keyboard client for shortcuts and gamepad mapping for the active stream. */
    fun keyboardSender(): PlayniteKeyboardSender? {
        if (!hostStreamActive || host.isEmpty()) return null
        val existing = keyboardSender
        if (existing != null) return existing
        return PlayniteKeyboardSender(host, inputPort).also { keyboardSender = it }
    }

    fun releaseKeyboardSender() {
        keyboardSender?.close()
        keyboardSender = null
    }

    fun applyFromIntent(intent: android.content.Intent) {
        host = intent.getStringExtra(PlayniteVideoActivity.EXTRA_HOST).orEmpty()
        videoPort = intent.getIntExtra(PlayniteVideoActivity.EXTRA_VIDEO_PORT, 28766)
        audioPort = intent.getIntExtra(PlayniteVideoActivity.EXTRA_AUDIO_PORT, 28767)
        audioTcpPort = intent.getIntExtra(PlayniteVideoActivity.EXTRA_AUDIO_TCP_PORT, 28769)
        inputPort = intent.getIntExtra(PlayniteVideoActivity.EXTRA_INPUT_PORT, 28768)
        width = intent.getIntExtra(PlayniteVideoActivity.EXTRA_WIDTH, 1920)
        height = intent.getIntExtra(PlayniteVideoActivity.EXTRA_HEIGHT, 1080)
        cursorSpeed = intent.getFloatExtra(PlayniteVideoActivity.EXTRA_CURSOR_SPEED, 1f)
        tapSlopPercent = intent.getIntExtra(PlayniteVideoActivity.EXTRA_TAP_SLOP_PERCENT, 100)
        tapTimeoutMs = intent.getLongExtra(
            PlayniteVideoActivity.EXTRA_TAP_TIMEOUT_MS,
            PlayniteInputSender.TAP_TIMEOUT_MS,
        )
        tapPressure = intent.getFloatExtra(PlayniteVideoActivity.EXTRA_TAP_PRESSURE, 0.35f)
        controllerBindingsJson =
            intent.getStringExtra(PlayniteVideoActivity.EXTRA_CONTROLLER_BINDINGS_JSON).orEmpty()
    }

    fun toIntentFlags(intent: android.content.Intent) {
        intent.putExtra(PlayniteVideoActivity.EXTRA_HOST, host)
        intent.putExtra(PlayniteVideoActivity.EXTRA_VIDEO_PORT, videoPort)
        intent.putExtra(PlayniteVideoActivity.EXTRA_AUDIO_PORT, audioPort)
        intent.putExtra(PlayniteVideoActivity.EXTRA_AUDIO_TCP_PORT, audioTcpPort)
        intent.putExtra(PlayniteVideoActivity.EXTRA_INPUT_PORT, inputPort)
        intent.putExtra(PlayniteVideoActivity.EXTRA_WIDTH, width)
        intent.putExtra(PlayniteVideoActivity.EXTRA_HEIGHT, height)
        intent.putExtra(PlayniteVideoActivity.EXTRA_CURSOR_SPEED, cursorSpeed)
        intent.putExtra(PlayniteVideoActivity.EXTRA_TAP_SLOP_PERCENT, tapSlopPercent)
        intent.putExtra(PlayniteVideoActivity.EXTRA_TAP_TIMEOUT_MS, tapTimeoutMs)
        intent.putExtra(PlayniteVideoActivity.EXTRA_TAP_PRESSURE, tapPressure)
        intent.putExtra(PlayniteVideoActivity.EXTRA_CONTROLLER_BINDINGS_JSON, controllerBindingsJson)
    }

    fun clear() {
        hostStreamActive = false
        viewerOpen = false
        host = ""
        controllerBindingsJson = ""
        releaseKeyboardSender()
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "hostStreamActive" to hostStreamActive,
        "viewerOpen" to viewerOpen,
        "host" to host,
        "videoPort" to videoPort,
        "audioPort" to audioPort,
        "audioTcpPort" to audioTcpPort,
        "inputPort" to inputPort,
        "width" to width,
        "height" to height,
    )
}
