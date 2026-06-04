package com.example.companion_app

import android.content.Context
import android.widget.Toast

object PlayniteStreamSwapActions {
    fun toggle(context: Context) {
        if (!PlayniteStreamSession.hostStreamActive) return
        val wasActive = PlayniteStreamSession.swapMouseModeActive
        // Release keys held from prior mappings so Enter/modifiers are not stuck on the Mac.
        PlayniteStreamSession.keyboardSender()?.releaseAllKeys()
        PlayniteStreamSession.swapMouseModeActive = !wasActive
        if (!PlayniteStreamSession.swapMouseModeActive) {
            PlayniteVideoActivity.current?.onSwapMouseModeDisabled()
        } else {
            PlayniteVideoActivity.current?.gamepadMouseSender()?.releaseAll()
        }
        PlayniteStreamNotificationHelper.refresh(context)
        PlayniteStreamLog.i(
            if (PlayniteStreamSession.swapMouseModeActive) {
                "Swap on — stick moves cursor; A/B/X click and drag; other mappings still active"
            } else {
                "Swap off — controller mappings restored"
            },
        )
        val message = if (PlayniteStreamSession.swapMouseModeActive) {
            "Swap on — stick moves cursor, A/B/X click and drag"
        } else {
            "Swap off — using Controller tab mappings"
        }
        Toast.makeText(context.applicationContext, message, Toast.LENGTH_SHORT).show()
    }
}
