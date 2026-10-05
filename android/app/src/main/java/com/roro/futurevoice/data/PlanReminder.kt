package com.roro.futurevoice.data

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.roro.futurevoice.MainActivity
import com.roro.futurevoice.R
import com.roro.futurevoice.core.UILanguage
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * A local reminder at each hand-placed routine block that isn't a talk or a
 * review, for the next week (iOS `PlanReminder`). Talk blocks ring as the
 * daily call and review blocks go through [DrillReminder], so today that
 * leaves "say it again" (and any legacy words/expressions/shadow block).
 *
 * Rebuilt from the plan every time — on a plan edit and on the app's
 * foreground — so a moved or deleted block can never leave a stale reminder
 * behind. It never asks for permission itself.
 */
object PlanReminder {
    const val HORIZON_DAYS = 7
    /** Alarm slots: request codes BASE..BASE+MAX_SLOTS-1. */
    private const val BASE = 0x50_0000
    private const val MAX_SLOTS = 32
    private const val NOTIFICATION_ID = 0x50_1000
    private const val KIND_EXTRA = "planKind"
    private const val AMOUNT_EXTRA = "planAmount"

    /** A say-it-again reminder was tapped: the root opens the talk picker. */
    val pendingSayItAgain = MutableStateFlow(false)
    /** A Speech block came due, or its routine line was tapped: the root
     *  opens the Speech tab (iOS `DailyCallInbox.pendingSpeech`). */
    val pendingSpeech = MutableStateFlow(false)

    private val remindedKinds = setOf(StudyPlan.Kind.SAY_IT_AGAIN, StudyPlan.Kind.SPEECH, StudyPlan.Kind.WORDS,
        StudyPlan.Kind.EXPRESSIONS, StudyPlan.Kind.SHADOW)

    fun reschedule(c: Context, now: Long = System.currentTimeMillis()) {
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (slot in 0 until MAX_SLOTS) am.cancel(pending(c, slot, null, 0))
        if (!NotificationManagerCompat.from(c).areNotificationsEnabled()) return
        val plan = StudyPlanStore.current(c)
        val today = StudyPlan.startOfDay(now)
        val fires = (0 until HORIZON_DAYS).flatMap { off ->
            plan.occurrences(StudyPlan.addDays(today, off)).filter {
                it.remind && !it.anytime && it.start > now && it.blockId != null && it.kind in remindedKinds
            }
        }.sortedBy { it.start }.take(MAX_SLOTS)
        fires.forEachIndexed { slot, occ ->
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, occ.start, pending(c, slot, occ.kind, occ.amount))
        }
    }

    private fun pending(c: Context, slot: Int, kind: StudyPlan.Kind?, amount: Int): PendingIntent =
        PendingIntent.getBroadcast(c, BASE + slot,
            Intent(c, PlanReminderReceiver::class.java)
                .putExtra(KIND_EXTRA, kind?.raw).putExtra(AMOUNT_EXTRA, amount),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun notify(c: Context, kindRaw: String?, amount: Int) {
        val kind = StudyPlan.Kind.entries.firstOrNull { it.raw == kindRaw } ?: return
        ReviewQueue.ensureChannel(c)
        val res = UILanguage.localized(c)
        val sayAgain = kind == StudyPlan.Kind.SAY_IT_AGAIN
        // Say it again lands on the talk picker; the rest on the review queue.
        val intent = Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val speech = kind == StudyPlan.Kind.SPEECH
        if (sayAgain) intent.data = Uri.parse("futurevoice://sayitagain")
        else if (speech) intent.data = Uri.parse("futurevoice://speech")
        else intent.putExtra(ReviewQueue.OPEN_REVIEW_EXTRA, true)
        val open = PendingIntent.getActivity(c, NOTIFICATION_ID, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val title = res.getString(when (kind) {
            StudyPlan.Kind.WORDS -> R.string.routine_time_for_your_words
            StudyPlan.Kind.EXPRESSIONS -> R.string.routine_time_for_your_expressions
            StudyPlan.Kind.SHADOW -> R.string.routine_time_for_shadowing
            StudyPlan.Kind.SAY_IT_AGAIN -> R.string.routine_time_to_say_it_again
            StudyPlan.Kind.SPEECH -> R.string.time_for_your_speech
            else -> R.string.routine_time_to_practice
        })
        val body = if (sayAgain) res.getString(R.string.routine_pick_a_recent_talk_and_say_it_again)
        else if (speech) res.getString(R.string.pick_a_script_and_read_it_out_loud)
        else res.getString(R.string.routine_s_as_planned, RoutineText.titled(res.resources, kind, amount))
        val n = NotificationCompat.Builder(c, ReviewQueue.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentTitle(title).setContentText(body)
            .setAutoCancel(true).setContentIntent(open).build()
        (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, n)
    }
}

class PlanReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        PlanReminder.notify(context, intent.getStringExtra("planKind"), intent.getIntExtra("planAmount", 1))
    }
}

/** A block's name and amount in the learner's language — shared by the
 *  routine page, the editor and the reminders (iOS `Kind.label/amountText`). */
object RoutineText {
    fun label(res: android.content.res.Resources, kind: StudyPlan.Kind): String = res.getString(when (kind) {
        StudyPlan.Kind.TALK -> R.string.routine_kind_talk
        StudyPlan.Kind.REVIEW -> R.string.routine_kind_review
        StudyPlan.Kind.WORDS -> R.string.routine_kind_words
        StudyPlan.Kind.EXPRESSIONS -> R.string.routine_kind_expressions
        StudyPlan.Kind.SHADOW -> R.string.routine_kind_shadowing
        StudyPlan.Kind.SAY_IT_AGAIN -> R.string.routine_kind_say_it_again
        StudyPlan.Kind.TEST -> R.string.routine_kind_weekly_test
        StudyPlan.Kind.SPEECH -> R.string.speech_d00d85
    })

    /** Minutes for a talk, a count otherwise; empty for a one-off. */
    fun amount(res: android.content.res.Resources, kind: StudyPlan.Kind, n: Int): String = when (kind) {
        StudyPlan.Kind.TALK -> res.getString(R.string.routine_n_min, n)
        StudyPlan.Kind.WORDS, StudyPlan.Kind.EXPRESSIONS, StudyPlan.Kind.REVIEW ->
            res.getString(R.string.routine_n_items, n)
        StudyPlan.Kind.SHADOW -> res.getString(R.string.routine_n_lines, n)
        StudyPlan.Kind.SAY_IT_AGAIN, StudyPlan.Kind.TEST, StudyPlan.Kind.SPEECH ->
            if (n == 1) "" else res.getString(R.string.routine_n_times, n)
    }

    /** "Review 20 items", or just "Say it again". */
    fun titled(res: android.content.res.Resources, kind: StudyPlan.Kind, n: Int): String {
        val a = amount(res, kind, n)
        return if (a.isEmpty()) label(res, kind) else label(res, kind) + " " + a
    }
}
