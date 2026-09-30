package com.naniger.aika

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

private const val CHANNEL_ID = "aika_chat_keep_alive"
private const val NOTIFICATION_ID = 0x41494B41 // "AIKA"

/**
 * "Stay reachable for messages": a foreground service that keeps the app
 * process at foreground priority while Aika is in the background, so
 * Android does not kill it or cut its network, and chat messages keep
 * arriving over the local network.
 *
 * It holds no logic of its own: the chat server lives in the Flutter
 * engine owned by [MainActivity]. When the user swipes the app away from
 * the recent apps, that engine is destroyed, so the service stops too
 * rather than claiming a reachability it no longer provides.
 */
class ChatKeepAliveService : Service() {
    companion object {
        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, ChatKeepAliveService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ChatKeepAliveService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()

        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.chat_keep_alive_title))
            .setContentText(getString(R.string.chat_keep_alive_text))
            .setContentIntent(openApp)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        // "remoteMessaging" (Android 14+) is the type meant for continuing
        // text messaging from one device to another.
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
        } else {
            0
        }
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)

        // Not restarted by the system after being killed: without the
        // Flutter engine there would be nothing to keep reachable.
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        stopSelf()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.chat_keep_alive_channel),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.chat_keep_alive_channel_description)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }
}
