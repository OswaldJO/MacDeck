package com.example.companion_app

import android.content.Context
import android.content.Intent

object PlayniteStreamShortcutActions {
    const val EXTRA_OPEN_SHORTCUTS = "openStreamShortcuts"

    fun openShortcutsUi(context: Context) {
        val video = PlayniteVideoActivity.current
        if (video != null) {
            video.runOnUiThread { video.showStreamShortcutsOverlay() }
            return
        }
        val launch = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_OPEN_SHORTCUTS, true)
        }
        context.startActivity(launch)
    }
}
