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
    /** What a per-item reminder points at (iOS `ItemReminder.Target`):
     *  "word" / "expression" + the text, or "sentence" + the card id. They
     *  ride the tap back so it opens THAT item, not the pile. */
    const val ITEM_KIND_EXTRA = "reviewItemKind"
    const val ITEM_VALUE_EXTRA = "reviewItemValue"
    const val SENTENCE = "sentence"

    /**
     * Write a return time AND arm the reminder for it. The alarm is named
     * after the item, so the notification is about the card the learner just
     * put away rather than a pile.
     */
    suspend fun snooze(context: Context, kind: StudyScheduleStore.Kind, text: String,
                       language: String, delayMillis: Long) {
        val at = System.currentTimeMillis() + delayMillis
        StudyScheduleStore.shared(context).snooze(kind, text, language, at)
        if (kind == StudyScheduleStore.Kind.WORD) VocabStore.shared(context).markPracticed(text, language)
        arm(context, kind, text, at)
    }

    /** The item is known — drop its schedule and take back its callback. */
    suspend fun retire(context: Context, kind: StudyScheduleStore.Kind, text: String,
                       language: String) {
        StudyScheduleStore.shared(context).clear(kind, text, language)
        cancel(context, kind.raw, text)
    }

    /** A sentence card put in a folder by hand gets its own callback, named
     *  after the line (iOS `DrillSheet` → `ItemReminder.schedule(.sentence)`). */
    fun armSentence(context: Context, card: com.roro.futurevoice.talk.DrillCard, at: Long) =
        arm(context, SENTENCE, card.id, card.targetPhrase, at)

    /** The card is settled — a callback for it would teach them to ignore these. */
    fun cancelSentence(context: Context, cardId: String) = cancel(context, SENTENCE, cardId)

    private fun cancel(context: Context, kind: String, value: String) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(firePendingIntent(context, requestCode(kind, value), kind, value, ""))
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
    private fun arm(context: Context, kind: StudyScheduleStore.Kind, text: String, at: Long) =
        arm(context, kind.raw, text, text, at)

    private fun arm(context: Context, kind: String, value: String, text: String, at: Long) {
        ensureChannel(context)
        val now = System.currentTimeMillis()
        // Clamped into waking hours like the aggregate reminder — a "later"
        // drop made at 2am shouldn't ring at 2am.
        val fireAt = DrillReminder.fireDate(now, at, hasDueNow = false) ?: return
        if (fireAt <= now) return
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt,
            firePendingIntent(context, requestCode(kind, value), kind, value, text))
    }

    /** Stable per-item, and never collides with the daily call's 4801. */
    private fun requestCode(kind: String, value: String): Int =
        0x52_000000 or ((kind + "|" + value.trim().lowercase()).hashCode() and 0x00FFFFFF)

    private fun firePendingIntent(context: Context, code: Int,
                                  kind: String, value: String, text: String): PendingIntent =
        PendingIntent.getBroadcast(context, code,
            Intent(context, ReviewDueReceiver::class.java)
                .putExtra("kind", kind).putExtra("value", value)
                .putExtra("text", text).putExtra("code", code),
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

    fun notifyDue(context: Context, kind: String, value: String, text: String, code: Int) {
        ensureChannel(context)
        // Tapping opens THIS item — the promise was about it, not the pile.
        val open = PendingIntent.getActivity(context, code,
            Intent(context, MainActivity::class.java)
                .putExtra(ITEM_KIND_EXTRA, kind).putExtra(ITEM_VALUE_EXTRA, value)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n: Notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentTitle(context.getString(R.string.back_for_review))
            .setContentText(trimmed(text))
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(code, n)
    }
}

/** Lock-screen bodies get truncated anyway; keep whole words (iOS `trimmed`). */
private fun trimmed(text: String, max: Int = 90): String {
    val clean = text.trim()
    if (clean.length <= max) return clean
    val cut = clean.take(max)
    val lastSpace = cut.lastIndexOf(' ').takeIf { it > 0 } ?: cut.length
    return clean.take(lastSpace) + "…"
}

class ReviewDueReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val text = intent.getStringExtra("text") ?: return
        // An alarm armed by an older build carries no value: the text is it.
        val kind = intent.getStringExtra("kind") ?: StudyScheduleStore.Kind.WORD.raw
        val value = intent.getStringExtra("value") ?: text
        ReviewQueue.notifyDue(context, kind, value, text, intent.getIntExtra("code", 0))
    }
}
