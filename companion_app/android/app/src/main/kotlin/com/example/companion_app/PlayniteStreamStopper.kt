package com.example.companion_app

import android.content.Context

/** Stops the Mac host stream, native video session, and stream notification. */
object PlayniteStreamStopper {
    fun stopAll(context: Context, reason: String) {
        val host = PlayniteStreamSession.host
        if (host.isNotEmpty()) {
            PlayniteHostControlClient.stopStreamOnHost(host)
        }
        val video = PlayniteVideoActivity.current
        if (video != null) {
            video.runOnUiThread { video.finishFromHost() }
        } else if (PlayniteStreamSession.hostStreamActive) {
            PlayniteStreamSession.clear()
            PlayniteStreamLog.endSession(reason)
            PlayniteStreamNotificationHelper.dismiss(context)
        } else {
            PlayniteStreamNotificationHelper.dismiss(context)
        }
    }
}
