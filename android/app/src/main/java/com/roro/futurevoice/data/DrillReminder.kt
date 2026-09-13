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
import java.util.Calendar

/**
 * One local notification for the review queue — spaced repetition only works
 * if something pulls the learner back when cards come due, and the per-item
 * callbacks ([ReviewQueue]) answer "you asked to see THIS again", not
 * "something is waiting".
 *
 * Policy (deliberately quiet, iOS `DrillReminder`):
 *   • At most ONE pending reminder, always rebuilt from the current queue —
 *     never a stack of stale notifications.
 *   • Fires when the next card becomes due, clamped into 09:00–21:00 local
 *     time so a 3-day interval landing at 2am waits for morning.
 *   • If cards are ALREADY due while the learner is in the app, it waits for
 *     tomorrow morning — nudging about a queue they can see is noise.
 */
object DrillReminder {
    private const val REQUEST_CODE = 0x44_000001
    private const val NOTIFICATION_ID = 0x44_000002
    private const val DAY_START_HOUR = 9
    private const val DAY_END_HOUR = 21

    /** Recompute and replace the pending reminder from the current queue —
     *  drill cards AND the words/expressions the daily deck snoozed. */
    suspend fun reschedule(context: Context, now: Long = System.currentTimeMillis()) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pending(context, 0))
        val cards = runCatching { DrillStore.shared(context).load().map { it.nextReviewAt } }.getOrDefault(emptyList())
        val study = runCatching {
            StudyScheduleStore.shared(context).snapshot(LanguageScope.active(context)).upcoming(0L).map { it.at }
        }.getOrDefault(emptyList())
        val all = cards + study
        if (all.isEmpty()) return
        val hasDueNow = all.any { it <= now }
        val nextDue = all.filter { it > now }.minOrNull()
        val fireAt = fireDate(now, nextDue, hasDueNow) ?: return
        if (fireAt <= now) return
        val countAtFire = all.count { it <= fireAt }
        if (countAtFire == 0) return
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pending(context, countAtFire))
    }

    /** When to fire, clamped into the waking-hours window. */
    fun fireDate(now: Long, nextDue: Long?, hasDueNow: Boolean): Long? {
        val cal = Calendar.getInstance()
        val candidate: Long = when {
            // They can see today's queue right now — remind tomorrow morning.
            hasDueNow -> {
                cal.timeInMillis = now
                cal.add(Calendar.DAY_OF_YEAR, 1)
                morning(cal)
            }
            nextDue != null -> nextDue
            else -> return null
        }
        // A due time inside the next 12 hours came from an explicit choice in
        // a bin tray — every ladder interval is a day or longer, and box 0 is
        // "due now" (handled above). Fire exactly then rather than parking a
        // short snooze until 9am.
        if (candidate - now < 12 * 3600_000L) return candidate
        cal.timeInMillis = candidate
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        if (hour < DAY_START_HOUR) return morning(cal)
        if (hour >= DAY_END_HOUR) { cal.add(Calendar.DAY_OF_YEAR, 1); return morning(cal) }
        return candidate
    }

    private fun morning(cal: Calendar): Long {
        cal.set(Calendar.HOUR_OF_DAY, DAY_START_HOUR)
        cal.set(Calendar.MINUTE, 0); cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    private fun pending(context: Context, count: Int): PendingIntent =
        PendingIntent.getBroadcast(context, REQUEST_CODE,
            Intent(context, DrillDueReceiver::class.java).putExtra("count", count),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun notifyDue(context: Context, count: Int) {
        ReviewQueue.ensureChannel(context)
        val open = PendingIntent.getActivity(context, REQUEST_CODE,
            Intent(context, MainActivity::class.java)
                .putExtra(ReviewQueue.OPEN_REVIEW_EXTRA, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        // Counts everything waiting at fire time, not just the snooze that
        // triggered it — so the body says "waiting", not "you asked for this".
        val body = if (count == 1) context.getString(R.string.s_1_word_phrase_or_line_is_waiting)
        else context.getString(R.string.lld_words_phrases_and_lines_are_waiting, count)
        val n = NotificationCompat.Builder(context, ReviewQueue.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentTitle(context.getString(R.string.ready_to_review))
            .setContentText(body).setAutoCancel(true).setContentIntent(open).build()
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, n)
    }
}

class DrillDueReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        DrillReminder.notifyDue(context, intent.getIntExtra("count", 1).coerceAtLeast(1))
    }
}
