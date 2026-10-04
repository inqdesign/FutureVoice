package com.roro.futurevoice.data

import android.app.AlarmManager
import android.app.NotificationChannel
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import java.io.File
import java.time.DayOfWeek
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId

/**
 * JSON-on-disk store for weekly tests, one file per language
 * (`lang/<code>/weekly-tests.json`, iOS `WeeklyTestStore`). A test is minted
 * once per opening and then only ever gains answers. Not synced on Android.
 */
class WeeklyTestStore private constructor(context: Context) {

    companion object {
        @Volatile private var instance: WeeklyTestStore? = null
        fun shared(context: Context): WeeklyTestStore =
            instance ?: synchronized(this) {
                instance ?: WeeklyTestStore(context.applicationContext).also { instance = it }
            }
        private const val FILE_NAME = "weekly-tests.json"
        private const val WEEK_MS = 7 * 86_400_000L

        /** The newest WEEKLY paper — the one a new week is built after. The
         *  store also holds monthly papers. */
        fun latestWeekly(tests: List<WeeklyTest>): WeeklyTest? =
            tests.sortedByDescending { it.createdAt }.firstOrNull { !it.isMonthly }

        /** Weeks in a row with a finished test, counting back from the
         *  current opening (which counts only once its test is finished). */
        fun weekStreak(tests: List<WeeklyTest>, schedule: WeeklyTestSchedule,
                       now: Long = System.currentTimeMillis(),
                       zone: ZoneId = ZoneId.systemDefault()): Int {
            val finished = tests.filter { !it.isMonthly }.mapNotNull { it.finishedAt }
            if (finished.isEmpty()) return 0
            var start = schedule.currentOpening(now, zone)
            fun inWeek(s: Long) = finished.any { it >= s && it < s + WEEK_MS }
            if (!inWeek(start)) start -= WEEK_MS
            var streak = 0
            while (inWeek(start)) { streak++; start -= WEEK_MS }
            return streak
        }
    }

    private val appContext = context.applicationContext
    private val mutex = Mutex()

    private fun file(language: String) = File(LanguageScope.directory(appContext, language), FILE_NAME)

    /** Newest first. */
    suspend fun load(language: String): List<WeeklyTest> = mutex.withLock { read(language) }

    private suspend fun read(language: String): List<WeeklyTest> = withContext(Dispatchers.IO) {
        val f = file(language)
        if (!f.exists()) emptyList()
        else runCatching {
            StoreJson.json.decodeFromString(ListSerializer(WeeklyTest.serializer()), f.readText())
        }.getOrElse { emptyList() }.sortedByDescending { it.createdAt }
    }

    suspend fun save(test: WeeklyTest) = mutex.withLock {
        val language = test.targetLanguage
        write(language, read(language).filterNot { it.id == test.id } + test)
    }

    /** Capture runs start from an empty week. */
    suspend fun removeAll(language: String) = mutex.withLock { write(language, emptyList()) }

    private suspend fun write(language: String, list: List<WeeklyTest>) = withContext(Dispatchers.IO) {
        val target = file(language)
        target.parentFile?.mkdirs()
        val tmp = File(target.parentFile, "$FILE_NAME.tmp")
        tmp.writeText(StoreJson.json.encodeToString(ListSerializer(WeeklyTest.serializer()), list))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }
}

/**
 * The weekly opening: one weekday and time (iOS `WeeklyTestSchedule`). Every
 * moment belongs to the week that opened most recently — a test taken on
 * Tuesday is still "this week's".
 *
 * [weekday] is iOS's Gregorian number, 1 = Sunday … 7 = Saturday, so the two
 * platforms store the same value.
 */
data class WeeklyTestSchedule(val weekday: Int, val hour: Int, val minute: Int) {

    private val dayOfWeek: DayOfWeek
        get() = if (weekday == 1) DayOfWeek.SUNDAY else DayOfWeek.of((weekday - 1).coerceIn(1, 6))

    private fun at(date: java.time.LocalDate, zone: ZoneId): Long =
        date.atTime(hour, minute).atZone(zone).toInstant().toEpochMilli()

    /** The most recent opening at or before [now] — at 10:00:00 sharp the
     *  opening is now, not last week's. */
    fun currentOpening(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): Long {
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        for (i in 0L..7L) {
            val d = today.minusDays(i)
            if (d.dayOfWeek != dayOfWeek) continue
            val t = at(d, zone)
            if (t <= now) return t
        }
        return now
    }

    /** The first opening strictly after [now]. */
    fun nextOpening(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): Long {
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        for (i in 0L..7L) {
            val d = today.plusDays(i)
            if (d.dayOfWeek != dayOfWeek) continue
            val t = at(d, zone)
            if (t > now) return t
        }
        return now + 7 * 86_400_000L
    }

    sealed interface State {
        /** No test yet this week; tap builds one. */
        data object Ready : State
        data class InProgress(val test: WeeklyTest) : State
        data class Done(val test: WeeklyTest, val next: Long) : State
        /** This week's build found too little material. */
        data class Thin(val next: Long) : State
    }

    fun state(tests: List<WeeklyTest>, isThin: (Long) -> Boolean,
              now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): State {
        val opening = currentOpening(now, zone)
        val next = nextOpening(now, zone)
        tests.sortedByDescending { it.createdAt }
            .firstOrNull { !it.isMonthly && it.createdAt >= opening }?.let {
                return if (it.isFinished) State.Done(it, next) else State.InProgress(it)
            }
        if (isThin(opening)) return State.Thin(next)
        return State.Ready
    }

    // ── Monthly

    sealed interface MonthlyState {
        data object None : MonthlyState
        data class Ready(val sources: List<WeeklyTest>) : MonthlyState
        data class InProgress(val test: WeeklyTest) : MonthlyState
        data class Done(val test: WeeklyTest) : MonthlyState
    }

    /** The first opening in the calendar month [currentOpening] falls in. */
    fun monthOpening(now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): Long {
        var opening = Instant.ofEpochMilli(currentOpening(now, zone)).atZone(zone)
        val month = YearMonth.from(opening)
        while (true) {
            val previous = opening.minusWeeks(1)
            if (YearMonth.from(previous) != month) return opening.toInstant().toEpochMilli()
            opening = previous
        }
    }

    /** It opens with the FIRST weekly opening of each calendar month and
     *  collects the misses of every weekly test finished since the previous
     *  month's first opening. */
    fun monthlyState(tests: List<WeeklyTest>, now: Long = System.currentTimeMillis(),
                     zone: ZoneId = ZoneId.systemDefault()): MonthlyState {
        val opening = monthOpening(now, zone)
        tests.sortedByDescending { it.createdAt }
            .firstOrNull { it.isMonthly && it.createdAt >= opening }?.let {
                return if (it.isFinished) MonthlyState.Done(it) else MonthlyState.InProgress(it)
            }
        val previousOpening = monthOpening(opening - 1, zone)
        val sources = tests.filter { t ->
            val finished = t.finishedAt ?: return@filter false
            !t.isMonthly && finished >= previousOpening && finished < opening
        }
        val wrong = sources.flatMap { t ->
            val missed = t.answers.filter { !it.correct }.map { it.itemId }.toSet()
            t.items.filter { it.id in missed }.map(WeeklyTestEngine::itemKey)
        }.toSet()
        return if (wrong.size >= WeeklyTestEngine.MIN_ITEMS) MonthlyState.Ready(sources) else MonthlyState.None
    }
}

/**
 * When the test opens each week, and whether the phone says so — DEVICE-
 * LOCAL, like the daily call (iOS `WeeklyTestSettings`, same keys).
 */
object WeeklyTestSettings {
    private const val PREFS = "futurevoice"
    private const val WEEKDAY = "futurevoice.weeklyTest.weekday"
    private const val HOUR = "futurevoice.weeklyTest.hour"
    private const val MINUTE = "futurevoice.weeklyTest.minute"
    private const val REMINDER = "futurevoice.weeklyTest.reminder"
    private const val SOUNDS = "futurevoice.weeklyTest.sounds"
    private const val THIN = "futurevoice.weeklyTest.thinOpening"

    /** Bumped on every change, so a screen showing a setting redraws. */
    val revision = MutableStateFlow(0)

    private fun p(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Gregorian 1 = Sunday … 7 = Saturday. Default Saturday 10:00. */
    fun weekday(c: Context) = p(c).getInt(WEEKDAY, 7)
    fun hour(c: Context) = p(c).getInt(HOUR, 10)
    fun minute(c: Context) = p(c).getInt(MINUTE, 0)
    /** Off until the learner turns it on — it needs notification permission. */
    fun reminderOn(c: Context) = p(c).getBoolean(REMINDER, false)
    /** The answer sounds. On by default. */
    fun soundsOn(c: Context) = p(c).getBoolean(SOUNDS, true)

    fun schedule(c: Context) = WeeklyTestSchedule(weekday(c), hour(c), minute(c))

    fun setWeekday(c: Context, v: Int) { p(c).edit().putInt(WEEKDAY, v).apply(); changed(c) }
    fun setTime(c: Context, hour: Int, minute: Int) {
        p(c).edit().putInt(HOUR, hour).putInt(MINUTE, minute).apply(); changed(c)
    }
    fun setReminderOn(c: Context, on: Boolean) { p(c).edit().putBoolean(REMINDER, on).apply(); changed(c) }
    fun setSoundsOn(c: Context, on: Boolean) { p(c).edit().putBoolean(SOUNDS, on).apply(); revision.value++ }

    private fun changed(c: Context) {
        revision.value++
        WeeklyTestReminder.reschedule(c)
    }

    /** The opening whose build came back too thin, so the tab doesn't
     *  rebuild on every appearance until material arrives or the week turns. */
    fun markThin(c: Context, opening: Long) { p(c).edit().putLong(THIN, opening).apply() }
    fun isThin(c: Context, opening: Long) = p(c).getLong(THIN, -1) == opening
    fun clearThin(c: Context) { p(c).edit().remove(THIN).apply() }
}

/**
 * One alarm at the next opening; firing posts the notification and arms the
 * one after. Since 2026-09-30 it is the "Your week" notice too: iOS writes the
 * body when the app leaves the foreground, Android when the alarm fires —
 * either way it carries the closed week's real numbers.
 */
object WeeklyTestReminder {
    const val CHANNEL_ID = "weekly_test"
    private const val REQUEST_CODE = 0x5754_0001

    private fun pending(c: Context): PendingIntent =
        PendingIntent.getBroadcast(c, REQUEST_CODE, Intent(c, WeeklyTestReminderReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun reschedule(c: Context) {
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pending(c))
        if (!WeeklyTestSettings.reminderOn(c)) return
        if (!NotificationManagerCompat.from(c).areNotificationsEnabled()) return
        val at = WeeklyTestSettings.schedule(c).nextOpening()
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(c))
    }

    /**
     * The week has turned: "Your week" is ready and the test opens (iOS
     * `WeeklyTestReminder.makeContent`, 2026-09-30). The body carries the week
     * that just CLOSED — counted here, at fire time, from the logs the app
     * keeps — and a tap opens its cards. A week with nothing in it gets the
     * plain test notice and lands on the test. [forceRecap]: the developer
     * button, which always exercises the recap path.
     */
    fun notifyReady(c: Context, now: Long = System.currentTimeMillis(), forceRecap: Boolean = false) {
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // Chrome speaks the app language, not the phone's.
        val res = UILanguage.contextFor(c, UILanguage.current(c))
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL_ID,
                res.getString(R.string.weekly_test), NotificationManager.IMPORTANCE_DEFAULT))
        }
        val (start, end) = WeekRecapBuilder.lastWeek(c, now)
        val talkSeconds = WeekRecapBuilder.talkSeconds(c, start, end)
        val active = WeekRecapBuilder.days(start).count { TalkTimeLog.studied(c, it) }
        val recap = active > 0 || forceRecap
        val title = if (recap) res.getString(R.string.wr_your_week_is_ready)
            else res.getString(R.string.your_weekly_test_is_ready)
        val body = when {
            !recap -> res.getString(R.string.a_few_minutes_made_from_this_week_s_talks)
            talkSeconds >= 60 -> res.resources.getQuantityString(R.plurals.wr_notif_body_talk, active, talkSeconds / 60, active)
            else -> res.resources.getQuantityString(R.plurals.wr_notif_body_days, active, active)
        }
        val link = if (recap) "futurevoice://weekrecap" else "futurevoice://weeklytest"
        val open = PendingIntent.getActivity(c, REQUEST_CODE,
            Intent(Intent.ACTION_VIEW, Uri.parse(link), c, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(c, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_agenda)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        runCatching { nm.notify(REQUEST_CODE, n) }
    }
}

class WeeklyTestReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        WeeklyTestReminder.notifyReady(context)
        WeeklyTestReminder.reschedule(context)
    }
}

/** "Open the weekly test" — set by the `futurevoice://weeklytest` link, read
 *  by the Practice tab once it is on screen. */
object WeeklyTestInbox {
    val pending = MutableStateFlow(false)
}
