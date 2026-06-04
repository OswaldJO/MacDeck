package com.example.companion_app

import android.content.Context
import android.os.Handler
import android.os.Looper

/** Stops the Mac host stream, native video session, and stream notification. */
object PlayniteStreamStopper {
    private val mainHandler = Handler(Looper.getMainLooper())

    fun stopAll(
        context: Context,
        reason: String,
        blockUntilMacStop: Boolean = false,
        recordPendingLogForResume: Boolean = false,
    ) {
        val app = context.applicationContext
        val host = PlayniteStreamSession.host
        PlayniteStreamSession.deactivate()
        PlayniteStreamNotificationHelper.dismiss(app)
        val macStop = Thread {
            if (host.isNotEmpty()) {
                PlayniteHostControlClient.stopStreamOnHost(host)
            }
        }
        macStop.start()
        if (blockUntilMacStop) {
            macStop.join()
        }
        val video = PlayniteVideoActivity.current
        if (video != null) {
            mainHandler.post {
                video.finishFromHost()
                if (recordPendingLogForResume) {
                    PlayniteStreamSession.recordExternalStopLog(app)
                }
            }
        } else {
            PlayniteStreamSession.clear()
            PlayniteStreamLog.endSession(reason)
            if (recordPendingLogForResume) {
                PlayniteStreamSession.recordExternalStopLog(app)
            }
        }
    }
}
