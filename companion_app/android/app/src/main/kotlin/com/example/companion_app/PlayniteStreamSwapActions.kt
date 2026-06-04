package com.example.companion_app

import android.content.Context
import android.widget.Toast

object PlayniteStreamSwapActions {
    fun toggle(context: Context) {
        if (!PlayniteStreamSession.hostStreamActive) return
        PlayniteStreamSession.swapMouseModeActive = !PlayniteStreamSession.swapMouseModeActive
        if (!PlayniteStreamSession.swapMouseModeActive) {
            PlayniteVideoActivity.current?.onSwapMouseModeDisabled()
        }
        PlayniteStreamNotificationHelper.refresh(context)
        val message = if (PlayniteStreamSession.swapMouseModeActive) {
            "Swap on — stick moves cursor, A/B/X click and drag"
        } else {
            "Swap off — using Controller tab mappings"
        }
        Toast.makeText(context.applicationContext, message, Toast.LENGTH_SHORT).show()
    }
}
