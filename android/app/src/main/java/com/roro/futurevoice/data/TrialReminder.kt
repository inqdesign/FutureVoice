package com.roro.futurevoice.data

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.roro.futurevoice.MainActivity
import com.roro.futurevoice.R

/**
 * The "your trial ends in two days" notice the paywall promises, and the one
 * place that promise is kept or knowingly withdrawn (iOS `TrialReminder`).
 *
 * Two days is enough to cancel without hurrying and late enough to still be
 * about this week. Scheduling replaces any pending notice, and [cancel] takes
 * it back — someone who cancelled on day two must not hear "your trial
 * converts in 2 days" on day five.
 */
object TrialReminder {
    private const val REQUEST_CODE = 0x54_000001
    private const val NOTIFICATION_ID = 0x54_000002
    /** Days before the end that the notice fires. */
    const val LEAD_DAYS = 2

    /** Returns whether the notice will actually arrive, so the caller can
     *  stop claiming it if it won't. */
    fun schedule(context: Context, trialDays: Int, now: Long = System.currentTimeMillis()): Boolean {
        if (trialDays <= LEAD_DAYS) return false
        if (!androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        val at = now + (trialDays - LEAD_DAYS) * 24L * 3600_000L
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(context))
        return true
    }

    fun cancel(context: Context) {
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pending(context))
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIFICATION_ID)
    }

    private fun pending(context: Context): PendingIntent =
        PendingIntent.getBroadcast(context, REQUEST_CODE, Intent(context, TrialEndingReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun notifyEnding(context: Context) {
        ReviewQueue.ensureChannel(context)
        val open = PendingIntent.getActivity(context, REQUEST_CODE,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(context, ReviewQueue.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(context.getString(R.string.your_free_trial_ends_soon))
            .setContentText(context.getString(R.string.trial_becomes_paid_play, LEAD_DAYS))
            .setAutoCancel(true).setContentIntent(open).build()
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, n)
    }
}

class TrialEndingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = TrialReminder.notifyEnding(context)
}
