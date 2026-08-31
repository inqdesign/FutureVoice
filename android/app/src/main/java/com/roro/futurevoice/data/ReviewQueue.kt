package com.roro.futurevoice.data

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.roro.futurevoice.MainActivity
import com.roro.futurevoice.R

/**
 * The one answer to "what is waiting to come back, right now" — shared by
 * the review reminder (which RINGS for it) and the review deck (which DEALS
 * it). They have to agree: a notification saying an item is back that opens
 * onto an empty deck is worse than no notification at all.
 *
 * Every deck resolves through here rather than touching [StudyScheduleStore]
 * directly, because the promise and the thing that keeps it must not be
 * separable — a new entry point writing straight to the store would silently
 * schedule items nothing will ever ring for.
 *
 * The staleness this prunes is real, not hypothetical: marking a word known
 * from the notebook retires the item without touching its schedule entry.
 */
object ReviewQueue {

    const val CHANNEL_ID = "review_due"
    const val OPEN_REVIEW_EXTRA = "openReview"

    /**
     * Write a return time AND arm the reminder for it. The alarm is named
     * after the item, so the notification is about the card the learner just
     * put away rather than a pile.
     */
    suspend fun snooze(context: Context, kind: StudyScheduleStore.Kind, text: String,
                       language: String, delayMillis: Long) {
        val at = System.currentTimeMillis() + delayMillis
        StudyScheduleStore.shared(context).snooze(kind, text, language, at)
        arm(context, kind, text, at)
    }

    /** The item is known — drop its schedule and take back its callback. */
    suspend fun retire(context: Context, kind: StudyScheduleStore.Kind, text: String,
                       language: String) {
        StudyScheduleStore.shared(context).clear(kind, text, language)
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(firePendingIntent(context, requestCode(kind, text), kind, text))
    }

    // MARK: - The reminder

    /**
     * One alarm per item, keyed by a hash of its text so re-snoozing the same
     * word REPLACES its pending alarm instead of stacking a second one
     * (`FLAG_UPDATE_CURRENT` on a stable request code). `setAndAllowWhileIdle`
     * rather than an exact alarm: a review is a nudge, and asking for the
     * exact-alarm permission to be a few minutes punctual about a word would
     * spend the one permission prompt that the daily CALL actually needs.
     */
    private fun arm(context: Context, kind: StudyScheduleStore.Kind, text: String, at: Long) {
        ensureChannel(context)
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at,
            firePendingIntent(context, requestCode(kind, text), kind, text))
    }

    /** Stable per-item, and never collides with the daily call's 4801. */
    private fun requestCode(kind: StudyScheduleStore.Kind, text: String): Int =
        0x52_000000 or ((kind.raw + "|" + text.trim().lowercase()).hashCode() and 0x00FFFFFF)

    private fun firePendingIntent(context: Context, code: Int,
                                  kind: StudyScheduleStore.Kind, text: String): PendingIntent =
        PendingIntent.getBroadcast(context, code,
            Intent(context, ReviewDueReceiver::class.java)
                .putExtra("kind", kind.raw).putExtra("text", text).putExtra("code", code),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun ensureChannel(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.review_reminders),
            // DEFAULT, not HIGH: the daily call is the habit anchor and must
            // not be competed with by a word coming back.
            NotificationManager.IMPORTANCE_DEFAULT))
    }

    fun notifyDue(context: Context, text: String, code: Int) {
        ensureChannel(context)
        val open = PendingIntent.getActivity(context, code,
            Intent(context, MainActivity::class.java).putExtra(OPEN_REVIEW_EXTRA, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n: Notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentTitle(context.getString(R.string.back_for_review))
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(code, n)
    }
}

class ReviewDueReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val text = intent.getStringExtra("text") ?: return
        ReviewQueue.notifyDue(context, text, intent.getIntExtra("code", 0))
    }
}
