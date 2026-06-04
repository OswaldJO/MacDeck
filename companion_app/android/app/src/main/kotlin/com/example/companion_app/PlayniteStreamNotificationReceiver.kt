package com.example.companion_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PlayniteStreamNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            PlayniteStreamNotificationHelper.ACTION_MAPPING ->
                PlayniteStreamMappingActions.openMappingUi(context)

            PlayniteStreamNotificationHelper.ACTION_SHORTCUTS ->
                PlayniteStreamShortcutActions.openShortcutsUi(context)

            PlayniteStreamNotificationHelper.ACTION_STOP ->
                PlayniteStreamStopCoordinator.stopSession(context, notifyFlutter = true)

            PlayniteStreamNotificationHelper.ACTION_SWAP ->
                PlayniteStreamSwapActions.toggle(context)
        }
        // After launching UI; best-effort only — must not crash if blocked by the OS.
        NotificationShadeUtils.collapse(context)
    }
}
