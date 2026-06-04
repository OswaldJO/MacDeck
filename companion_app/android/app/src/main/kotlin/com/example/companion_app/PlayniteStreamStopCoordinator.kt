package com.example.companion_app

import android.content.Context

/**
 * Single stop path for Session tab Stop and notification Stop so teardown stays consistent.
 */
object PlayniteStreamStopCoordinator {
    data class StopResult(val logPath: String?)

    /**
     * @param notifyFlutter When true, tells Flutter the session ended outside the video UI (notification Stop).
     */
    fun stopSession(context: Context, notifyFlutter: Boolean): StopResult {
        val app = context.applicationContext
        val host = PlayniteStreamSession.host
        PlayniteStreamSession.deactivate()
        PlayniteStreamNotificationHelper.dismiss(app)
        PlayniteStreamSession.clearPendingExternalStopLog()
        val video = PlayniteVideoActivity.current
        if (video != null) {
            video.finishFromHost()
        } else {
            PlayniteStreamSession.clear()
            PlayniteStreamLog.endSession("stop requested from companion")
        }
        if (host.isNotEmpty()) {
            val macStop = Thread {
                PlayniteHostControlClient.stopStreamOnHost(host)
            }
            macStop.start()
            macStop.join(8_000)
        }
        val logPath = PlayniteStreamLog.logFilePath(app)
        if (notifyFlutter) {
            MainActivity.notifyFlutterStreamStoppedExternally()
        }
        return StopResult(logPath)
    }
}
