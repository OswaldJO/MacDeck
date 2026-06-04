package com.example.companion_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/** Ongoing stream controls in the system notification shade (Stop + Controller mapping). */
object PlayniteStreamNotificationHelper {
    const val CHANNEL_ID = "playnite_stream_session"
    private const val NOTIFICATION_ID = 28765

    const val ACTION_STOP = "com.playnite.companion.STREAM_STOP"
    const val ACTION_MAPPING = "com.playnite.companion.STREAM_MAPPING"
    const val ACTION_SHORTCUTS = "com.playnite.companion.STREAM_SHORTCUTS"

    fun show(context: Context, hostLabel: String) {
        val text = if (hostLabel.isNotEmpty()) "Streaming from $hostLabel" else "Streaming Mac desktop"
        showWithText(context, text)
    }

    private fun showWithText(context: Context, contentText: String) {
        val appContext = context.applicationContext
        createChannel(appContext)
        if (!canPostNotifications(appContext)) return

        val stopIntent = Intent(appContext, PlayniteStreamNotificationReceiver::class.java).apply {
            action = ACTION_STOP
        }
        val mappingIntent = Intent(appContext, PlayniteStreamNotificationReceiver::class.java).apply {
            action = ACTION_MAPPING
        }
        val shortcutsIntent = Intent(appContext, PlayniteStreamNotificationReceiver::class.java).apply {
            action = ACTION_SHORTCUTS
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

        val stopPending = PendingIntent.getBroadcast(appContext, 1, stopIntent, flags)
        val mappingPending = PendingIntent.getBroadcast(appContext, 2, mappingIntent, flags)
        val shortcutsPending = PendingIntent.getBroadcast(appContext, 4, shortcutsIntent, flags)

        val launchIntent = Intent(appContext, MainActivity::class.java).apply {
            this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentPending = PendingIntent.getActivity(appContext, 3, launchIntent, flags)

        val notification = NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Playnite stream")
            .setContentText(contentText)
            .setContentIntent(contentPending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setShowWhen(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPending)
            .addAction(android.R.drawable.ic_menu_manage, "Controller", mappingPending)
            .addAction(android.R.drawable.ic_menu_edit, "Shortcuts", shortcutsPending)
            .build()

        NotificationManagerCompat.from(appContext).notify(NOTIFICATION_ID, notification)
    }

    fun dismiss(context: Context) {
        NotificationManagerCompat.from(context.applicationContext).cancel(NOTIFICATION_ID)
    }

    fun updateViewerHint(context: Context, hostLabel: String, viewerOpen: Boolean) {
        if (!PlayniteStreamSession.hostStreamActive) {
            dismiss(context)
            return
        }
        val base = if (hostLabel.isNotEmpty()) "Streaming from $hostLabel" else "Streaming Mac desktop"
        val text = if (viewerOpen) base else "$base — tap Shortcuts, Controller, or open app"
        showWithText(context, text)
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Playnite stream",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Controls while streaming your Mac desktop"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun canPostNotifications(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }
}
