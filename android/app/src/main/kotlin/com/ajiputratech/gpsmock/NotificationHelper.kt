package com.ajiputratech.gpsmock

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat

object NotificationHelper {
    private const val BROADCAST_CHANNEL_ID = "developer_broadcast_channel"
    private const val BROADCAST_CHANNEL_NAME = "Pengumuman Developer"
    private const val BROADCAST_NOTIFICATION_ID_BASE = 9000

    fun showBroadcastNotification(
        context: Context,
        id: String,
        title: String,
        message: String,
        linkUrl: String? = null,
        badgeText: String? = null
    ) {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create high priority notification channel for Android O (8.0+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                BROADCAST_CHANNEL_ID,
                BROADCAST_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifikasi pengumuman resmi dari developer"
                enableVibration(true)
                enableLights(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Tap action intent
        val intent: Intent = if (!linkUrl.isNullOrBlank()) {
            try {
                Intent(Intent.ACTION_VIEW, Uri.parse(linkUrl)).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
            } catch (e: Exception) {
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
                }
            }
        } else {
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
            }
        }

        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            id.hashCode(),
            intent,
            pendingIntentFlags
        )

        val fullTitle = if (!badgeText.isNullOrBlank()) "[$badgeText] $title" else title

        val builder = NotificationCompat.Builder(context, BROADCAST_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(fullTitle)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)

        // Generate unique integer ID based on string hash code
        val notificationId = BROADCAST_NOTIFICATION_ID_BASE + (id.hashCode() and 0x7FFFFFFF) % 1000
        notificationManager.notify(notificationId, builder.build())
    }
}
