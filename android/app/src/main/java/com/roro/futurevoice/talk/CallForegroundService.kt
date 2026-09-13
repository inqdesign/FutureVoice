package com.roro.futurevoice.talk

import android.app.Notification
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
import com.roro.futurevoice.MainActivity
import com.roro.futurevoice.R

/**
 * The call as the LOCK SCREEN sees it — and the reason it survives one.
 *
 * A live call holds the mic and a socket. Without a foreground service,
 * Android 14+ takes both the moment the screen locks or the learner switches
 * apps: the mic is silenced and the process is a candidate for death, and
 * coming back finds a call that is still on screen and stone deaf. This is
 * the Android half of iOS's `UIBackgroundModes: audio` + `CallNowPlaying`.
 *
 * The notification is the only control a locked phone has: the call's title,
 * what it is doing, and the two things the mic button does — pause/resume
 * and hang up. Actions reach the view model through [CallControls]; a
 * service can't hold a view model, and the view model already owns the
 * socket.
 *
 * Declared `microphone|mediaPlayback` because that is what it does, and
 * started only from the foreground with RECORD_AUDIO granted — the only time
 * Android 14 allows a microphone-typed service to begin.
 */
class CallForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "live_call"
        private const val NOTIFICATION_ID = 4802
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_HINT = "hint"
        private const val EXTRA_PAUSED = "paused"
        const val ACTION_TOGGLE = "com.roro.futurevoice.call.TOGGLE"
        const val ACTION_END = "com.roro.futurevoice.call.END"

        fun start(context: Context, title: String, hint: String, paused: Boolean) {
            val i = Intent(context, CallForegroundService::class.java)
                .putExtra(EXTRA_TITLE, title).putExtra(EXTRA_HINT, hint).putExtra(EXTRA_PAUSED, paused)
            runCatching { context.startForegroundService(i) }
        }

        fun stop(context: Context) {
            runCatching { context.stopService(Intent(context, CallForegroundService::class.java)) }
        }

        fun ensureChannel(context: Context) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) != null) return
            // Low importance: this is a status, not an alert. It must never
            // make a sound over the call it describes.
            nm.createNotificationChannel(NotificationChannel(
                CHANNEL_ID, context.getString(R.string.talk), NotificationManager.IMPORTANCE_LOW))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TOGGLE -> { CallControls.handler?.invoke(CallControls.Action.TOGGLE_PAUSE); return START_NOT_STICKY }
            ACTION_END -> { CallControls.handler?.invoke(CallControls.Action.END); return START_NOT_STICKY }
        }
        ensureChannel(this)
        val n = notification(
            intent?.getStringExtra(EXTRA_TITLE) ?: getString(R.string.talk),
            intent?.getStringExtra(EXTRA_HINT).orEmpty(),
            intent?.getBooleanExtra(EXTRA_PAUSED, false) ?: false,
        )
        val type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) startForeground(NOTIFICATION_ID, n, type)
        else startForeground(NOTIFICATION_ID, n)
        // Not sticky: a call the system had to kill is not a call to resurrect
        // with no socket behind it.
        return START_NOT_STICKY
    }

    private fun notification(title: String, hint: String, paused: Boolean): Notification {
        fun action(a: String, req: Int): PendingIntent = PendingIntent.getService(
            this, req, Intent(this, CallForegroundService::class.java).setAction(a),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(title)
            .setContentText(hint)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(0, getString(if (paused) R.string.resume else R.string.pause), action(ACTION_TOGGLE, 1))
            .addAction(0, getString(R.string.end), action(ACTION_END, 2))
            .build()
    }
}

/** The bridge from the notification's buttons to the live call's owner. */
object CallControls {
    enum class Action { TOGGLE_PAUSE, END }
    @Volatile var handler: ((Action) -> Unit)? = null
}
