package com.roro.futurevoice.data

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import androidx.core.app.NotificationCompat
import com.roro.futurevoice.MainActivity
import com.roro.futurevoice.R
import java.util.Calendar

/**
 * The daily call — the habit anchor, Android half (`android-launch-roadmap`
 * §1.8). Unlike iOS, Android CAN draw a real incoming-call surface: an exact
 * alarm fires a BroadcastReceiver that posts a CATEGORY_CALL full-screen
 * notification ringing the SAME bundled two-tone warble iOS ships
 * (`res/raw/ringtone.wav` — never the learner's voice; the voice arrives the
 * moment they answer, which is what a phone call is anyway).
 *
 * v1: one time a day, Answer opens a free talk. Voicemail scripts, callbacks
 * and outcome history ride in with the VoicemailEngine brain-lift.
 */
object DailyCallStore {
    private const val PREFS = "futurevoice"
    private const val ENABLED = "futurevoice.dailyCall.enabled"
    private const val HOUR = "futurevoice.dailyCall.hour"
    private const val MINUTE = "futurevoice.dailyCall.minute"
    private const val TIMES = "futurevoice.dailyCall.times"
    private const val HISTORY = "futurevoice.dailyCall.history"
    private const val PLAN = "futurevoice.dailyCall.plan"
    /** iOS `DailyCallStore.maxTimes`. */
    const val MAX_TIMES = 4
    /** How long an unanswered ring waits before it counts as missed. */
    private const val RANG_OUT_GRACE_MS = 10L * 60 * 1000

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, 0)

    fun isEnabled(c: Context) = prefs(c).getBoolean(ENABLED, false)

    /**
     * The call times, minutes after midnight, earliest first — more than one
     * call a day (iOS). The single legacy hour/minute migrates into the list
     * on first read; [hour]/[minute] now proxy the FIRST time.
     */
    fun times(c: Context): List<Int> {
        val raw = prefs(c).getString(TIMES, null)
        if (raw != null) return raw.split(',').mapNotNull { it.toIntOrNull() }.sorted()
        val legacy = prefs(c).getInt(HOUR, 8) * 60 + prefs(c).getInt(MINUTE, 0)
        return listOf(legacy)
    }
    fun hour(c: Context) = times(c).first() / 60
    fun minute(c: Context) = times(c).first() % 60

    fun setTimes(c: Context, enabled: Boolean, minutes: List<Int>) {
        val list = minutes.distinct().sorted().take(MAX_TIMES).ifEmpty { listOf(8 * 60) }
        if (enabled) com.roro.futurevoice.core.Analytics.capture("daily_call_scheduled",
            mapOf("times" to list.size))
        val wasEnabled = isEnabled(c)
        prefs(c).edit().putBoolean(ENABLED, enabled).putString(TIMES, list.joinToString(",")).apply()
        // The routine's timed talks ARE the call times (iOS 1.1.4): a time
        // set here goes into the routine, and switching the call on gives an
        // "any time" routine its first call.
        // Turning the call OFF must not pin an "any time" routine to a clock.
        if (enabled || StudyPlanStore.current(c).hasTimedTalk) StudyPlanStore.callTimesChanged(c, list)
        if (enabled && !wasEnabled) StudyPlanStore.callTurnedOn(c)
        if (enabled) DailyCallScheduler.schedule(c) else DailyCallScheduler.cancel(c)
    }

    /** The routine wrote its talk times: keep this list in step without
     *  bouncing them back into the routine. */
    fun mirrorTimes(c: Context, minutes: List<Int>) {
        val list = minutes.distinct().sorted().take(MAX_TIMES)
        if (list.isEmpty() || list == times(c)) return
        prefs(c).edit().putString(TIMES, list.joinToString(",")).apply()
    }

    /** One time — onboarding's picker. Collapses the list to that time. */
    fun set(c: Context, enabled: Boolean, hour: Int, minute: Int) =
        setTimes(c, enabled, listOf(hour * 60 + minute))

    private const val SCRIPT = "futurevoice.dailyCall.script"

    /** Tomorrow's opening words, written at session end; cleared on answer. */
    fun script(c: Context): String? = prefs(c).getString(SCRIPT, null)
    fun setScript(c: Context, script: String?) {
        prefs(c).edit().putString(SCRIPT, script).apply()
    }

    // ── Outcomes: every call settles into one, and the next voicemail is
    // written from them (iOS `DailyCallOutcome`). A decline is not a failure:
    // no scold, no broken counter — it just isn't taking the call.

    enum class Outcome(val raw: String) { ANSWERED("answered"), DECLINED("declined"), MISSED("missed") }

    /** The day's plan: when it last rang, how many rings were declined. */
    private data class Plan(val day: String, val rangAt: Long, val declines: Int)

    private fun dayKey(at: Long) =
        java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date(at))

    private fun plan(c: Context): Plan? = prefs(c).getString(PLAN, null)?.split('|')
        ?.takeIf { it.size == 3 }?.let { Plan(it[0], it[1].toLongOrNull() ?: 0L, it[2].toIntOrNull() ?: 0) }

    private fun savePlan(c: Context, p: Plan?) =
        prefs(c).edit().apply { if (p == null) remove(PLAN) else putString(PLAN, "${p.day}|${p.rangAt}|${p.declines}") }.apply()

    /** A ring went out. */
    fun noteRang(c: Context, now: Long = System.currentTimeMillis()) {
        val p = plan(c)?.takeIf { it.day == dayKey(now) }
        savePlan(c, Plan(dayKey(now), now, p?.declines ?: 0))
    }

    fun history(c: Context): List<Pair<Long, Outcome>> =
        prefs(c).getString(HISTORY, null)?.split('\n')?.mapNotNull { line ->
            val (at, o) = line.split('|').takeIf { it.size == 2 } ?: return@mapNotNull null
            val outcome = Outcome.entries.firstOrNull { it.raw == o } ?: return@mapNotNull null
            (at.toLongOrNull() ?: return@mapNotNull null) to outcome
        }.orEmpty()

    private fun record(c: Context, outcome: Outcome, at: Long) {
        val lines = (history(c) + (at to outcome)).takeLast(30)
        prefs(c).edit().putString(HISTORY, lines.joinToString("\n") { "${it.first}|${it.second.raw}" }).apply()
        savePlan(c, null)
        com.roro.futurevoice.core.Analytics.capture("daily_call_outcome", mapOf("outcome" to outcome.raw))
    }

    fun lastOutcome(c: Context): Outcome? = history(c).lastOrNull()?.second
    fun consecutiveUnanswered(c: Context): Int =
        history(c).reversed().takeWhile { it.second != Outcome.ANSWERED }.size

    /** Answered: the day is settled, the rest of today's rings are dropped. */
    fun onAnswered(c: Context, now: Long = System.currentTimeMillis()) {
        record(c, Outcome.ANSWERED, now)
        DailyCallScheduler.schedule(c, fromTomorrow = true)
    }

    /**
     * Declining is just not taking the call (iOS 2026-09-21): the app does
     * not open and nothing asks when to call back. The learner's own later
     * times today still ring; the day settles as declined once none is left.
     */
    fun onDeclined(c: Context, now: Long = System.currentTimeMillis()) {
        val p = plan(c)?.takeIf { it.day == dayKey(now) } ?: Plan(dayKey(now), now, 0)
        val left = DailyCallScheduler.remainingToday(c, now)
        if (left.isEmpty()) record(c, Outcome.DECLINED, now)
        else savePlan(c, p.copy(declines = p.declines + 1))
    }

    /**
     * A call nobody touched can't be noticed when it happens — nothing is
     * running. Settled on the next launch: a ring older than the grace with
     * no later slot today is MISSED (or DECLINED if one of today's was).
     */
    fun settleIfRangOut(c: Context, now: Long = System.currentTimeMillis()) {
        val p = plan(c) ?: return
        if (p.rangAt <= 0 || now - p.rangAt < RANG_OUT_GRACE_MS) return
        if (p.day == dayKey(now) && DailyCallScheduler.remainingToday(c, now).isNotEmpty()) return
        record(c, if (p.declines > 0) Outcome.DECLINED else Outcome.MISSED, p.rangAt)
    }
}

object DailyCallScheduler {
    const val CHANNEL_ID = "daily_call"
    /** The ring that plays its own alarm-stream sound: vibration only, or
     *  it would ring twice when the phone is not silent. */
    const val RING_CHANNEL_ID = "daily_call_ring"
    const val RING_ID = 4801
    const val ANSWER_EXTRA = "dailyCallAnswer"
    private const val REQUEST = 4801

    /** Today's call times still ahead of [now], as epoch millis — from the
     *  routine, whose timed talk blocks ARE the calls. */
    fun remainingToday(context: Context, now: Long = System.currentTimeMillis()): List<Long> =
        fireDates(context, now).filter { StudyPlan.isSameDay(it, now) }

    /**
     * Every ring to arm (iOS `fireDates`): the routine's remaining timed
     * talks today, else the next day's first. A routine with no talk at a set
     * time rings nothing — there is no second schedule the routine can't show.
     */
    fun fireDates(context: Context, now: Long = System.currentTimeMillis()): List<Long> =
        StudyPlanStore.current(context).callDates(now)

    private fun at(now: Long, minutes: Int, dayOffset: Int): Long = Calendar.getInstance().apply {
        timeInMillis = now
        add(Calendar.DAY_OF_YEAR, dayOffset)
        set(Calendar.HOUR_OF_DAY, minutes / 60); set(Calendar.MINUTE, minutes % 60)
        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    /**
     * Arm EVERY remaining time today at once, else tomorrow's first (iOS
     * `fireDates`). Arming only the next one would be a no-op: the plan is
     * written in the foreground, and the gap between a slept-through 08:00 and
     * a 13:00 has nothing running to arm the second.
     */
    fun schedule(context: Context, fromTomorrow: Boolean = false) {
        ensureChannel(context)
        val now = System.currentTimeMillis()
        cancelAlarms(context)
        // Never arm into a live call (see `holdForLiveCall`); the release
        // re-arms.
        if (liveCallSince != null) return
        // A PARKED voice (see `VoiceParking`) can't write tomorrow's voicemail,
        // and answering would open a call straight into the paywall. Stand
        // down; the revival re-arms it. The learner's setting is untouched.
        if (VoiceParking.parkedId.value != null) return
        val fires = if (fromTomorrow) {
            fireDates(context, StudyPlan.startOfDay(StudyPlan.addDays(now, 1)) - 1)
        } else fireDates(context, now)
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        fires.forEachIndexed { slot, whenMs ->
            // `setAlarmClock` rings through Doze and shows in the status bar,
            // which is what a call at a chosen time needs. It needs the
            // learner-granted SCHEDULE_EXACT_ALARM (USE_EXACT_ALARM is for
            // alarm-clock apps and Play rejects it here); without the grant
            // the call still rings inside a window — later, never lost.
            if (canScheduleExact(am)) {
                am.setAlarmClock(AlarmManager.AlarmClockInfo(whenMs, contentIntent(context)),
                    firePendingIntent(context, slot))
            } else {
                am.setWindow(AlarmManager.RTC_WAKEUP, whenMs, INEXACT_WINDOW_MS,
                    firePendingIntent(context, slot))
            }
        }
    }

    // MARK: - A call already in progress

    /**
     * Set while a conversation is live (iOS `DailyCallScheduler.liveCallSince`,
     * 2026-09-28). In memory on purpose: a killed app drops it, and the next
     * launch's re-arm puts the rings back.
     */
    @Volatile private var liveCallSince: Long? = null

    /**
     * A scheduled ring must not land on a call the learner is already in: the
     * ring takes the audio focus out from under the call, and there is
     * nothing to "answer" — they are on the phone with that same person right
     * now. Every pending ring comes down for the length of the call, and
     * [schedule] refuses to arm one until [releaseAfterLiveCall].
     */
    fun holdForLiveCall(context: Context) {
        if (liveCallSince != null) return
        liveCallSince = System.currentTimeMillis()
        cancelAlarms(context)
    }

    /**
     * The call is over: put the rings back. A slot that came due DURING the
     * call settles as answered — they were talking to their future self at
     * that very moment, and a voicemail asking "couldn't talk yesterday?"
     * would be false. Answering re-arms from tomorrow, exactly as a pickup.
     */
    fun releaseAfterLiveCall(context: Context, now: Long = System.currentTimeMillis()) {
        val since = liveCallSince ?: return
        liveCallSince = null
        if (!DailyCallStore.isEnabled(context)) return
        // A day already settled (answered earlier, or every slot declined)
        // is neither settled twice nor rung again today.
        val settledToday = DailyCallStore.history(context).lastOrNull()
            ?.let { dayOf(it.first) == dayOf(now) } == true
        if (!settledToday && cameDueDuring(DailyCallStore.times(context), since, now)) {
            com.roro.futurevoice.core.Analytics.capture("daily_call_during_talk")
            DailyCallStore.onAnswered(context, now)
            return
        }
        schedule(context, fromTomorrow = settledToday)
    }

    /** Did any of [minutes] (minutes past local midnight) fall in (since, now]? */
    fun cameDueDuring(minutes: List<Int>, since: Long, now: Long): Boolean {
        if (now <= since) return false
        // A call can cross midnight: check each calendar day it touched.
        return (0..((now - since) / 86_400_000L + 1).toInt()).any { offset ->
            minutes.any { m -> at(since, m, offset).let { it > since && it <= now } }
        }
    }

    private fun dayOf(at: Long) =
        java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date(at))

    /** Whether an exact alarm can be armed right now. Always true below
     *  Android 12, where the permission did not exist. */
    fun canScheduleExact(
        am: AlarmManager? = null,
        context: Context? = null,
    ): Boolean {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.S) return true
        val manager = am ?: (context?.getSystemService(Context.ALARM_SERVICE) as? AlarmManager)
        return manager?.canScheduleExactAlarms() == true
    }

    /** How far the system may drift an inexact call. Ten minutes: late enough
     *  for the OS to batch it with other work, early enough that the learner
     *  still reads it as "my 8 o'clock call". */
    private const val INEXACT_WINDOW_MS = 10L * 60 * 1000

    fun cancel(context: Context) {
        cancelAlarms(context)
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(REQUEST)
    }

    private fun cancelAlarms(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (slot in 0 until DailyCallStore.MAX_TIMES) am.cancel(firePendingIntent(context, slot))
    }

    /** One alarm per slot — request codes REQUEST+1…, so re-arming a slot
     *  replaces its own alarm instead of stacking a second. */
    private fun firePendingIntent(context: Context, slot: Int): PendingIntent =
        PendingIntent.getBroadcast(context, REQUEST + 1 + slot,
            Intent(context, DailyCallReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun declinePendingIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(context, REQUEST + 20,
            Intent(context, DailyCallDeclineReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun ringScreenIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(context, REQUEST + 30,
            Intent(context, com.roro.futurevoice.DailyCallRingActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    /** Bumped whenever the ring is dismissed (answered or declined from any
     *  surface), so an open ring screen can close itself. */
    val ringEnded = kotlinx.coroutines.flow.MutableStateFlow(0)

    private fun contentIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(context, REQUEST,
            Intent(context, MainActivity::class.java).putExtra(ANSWER_EXTRA, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun ensureChannel(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val sound = Uri.parse("android.resource://${context.packageName}/${R.raw.ringtone}")
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL_ID, "Daily call", NotificationManager.IMPORTANCE_HIGH).apply {
            setSound(sound, AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            enableVibration(true)
        })
    }

    private fun ensureRingChannel(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(RING_CHANNEL_ID) != null) return
        nm.createNotificationChannel(NotificationChannel(
            RING_CHANNEL_ID, "Daily call", NotificationManager.IMPORTANCE_HIGH).apply {
            setSound(null, null)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 800, 600, 800, 600, 800)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        })
    }

    /** The ring: a call-style, full-screen, insistent notification. */
    fun ring(context: Context) {
        // An alarm armed before the voice was parked: stay silent, and don't
        // re-arm the next one either.
        VoiceParking.init(context)
        if (VoiceParking.parkedId.value != null) { cancelAlarms(context); return }
        // An alarm that slipped past the hold: the learner is on the call
        // right now. Stay silent; the release settles the slot as answered.
        if (liveCallSince != null) return
        ensureChannel(context)
        ensureRingChannel(context)
        val answer = contentIntent(context)
        fun build(channel: String): Notification = NotificationCompat.Builder(context, channel)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(com.roro.futurevoice.core.UILanguage.localized(context).getString(R.string.your_future_self))
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            // A dark or locked screen gets the RING (Answer / Decline), never
            // the answer itself — the system fires this intent unasked, and
            // pointing it at `answer` opened the call on a locked phone.
            .setFullScreenIntent(ringScreenIntent(context), true)
            .setOngoing(true)
            .setAutoCancel(true)
            // Decline runs in the background — the app never opens for a no.
            .addAction(0, com.roro.futurevoice.core.UILanguage.localized(context).getString(R.string.can_t_talk_now), declinePendingIntent(context))
            .addAction(0, com.roro.futurevoice.core.UILanguage.localized(context).getString(R.string.answer), answer)
            .setContentIntent(answer)
            .build()
        // Sound on the alarm stream, through silent mode; if the system won't
        // start the service, the old channel's own ringtone sound is the ring.
        if (!DailyCallRingService.start(context, build(RING_CHANNEL_ID))) {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(REQUEST, build(CHANNEL_ID))
        }
        DailyCallStore.noteRang(context)
        // The next call arms the moment this one rings.
        if (DailyCallStore.isEnabled(context)) schedule(context)
    }

    fun dismissRing(context: Context) {
        ringEnded.value += 1
        DailyCallRingService.stop(context)
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(REQUEST)
    }
}

/** "Not now": settle it quietly — no app, no callback question. */
class DailyCallDeclineReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        DailyCallScheduler.dismissRing(context)
        DailyCallStore.onDeclined(context)
        com.roro.futurevoice.core.Analytics.capture("daily_call_declined")
    }
}

class DailyCallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        android.util.Log.d("DailyCall", "receiver fired")
        DailyCallScheduler.ring(context)
        android.util.Log.d("DailyCall", "ring posted")
    }
}
