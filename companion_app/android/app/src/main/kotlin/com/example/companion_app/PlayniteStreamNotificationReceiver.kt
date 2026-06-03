package com.example.companion_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PlayniteStreamNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            PlayniteStreamNotificationHelper.ACTION_STOP ->
                PlayniteStreamStopper.stopAll(context, "stop from notification")

            PlayniteStreamNotificationHelper.ACTION_MAPPING ->
                PlayniteStreamMappingActions.openMappingUi(context)
        }
    }
}
