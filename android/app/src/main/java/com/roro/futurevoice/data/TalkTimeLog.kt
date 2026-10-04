package com.roro.futurevoice.data

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * The day's talk seconds as they were actually METERED — `TalkTimeLog.swift`.
 * Appended only for ticks the server ACCEPTED (a 402'd tick was refused, and
 * counting it would put the ring ahead of the receipt). Keyed to the LOCAL
 * day (a habit belongs to the day the learner is living in) and to the
 * spoken language (the streak counts one language; the ring counts them all).
 */
object TalkTimeLog {

    private const val PREFS = "futurevoice"
    private const val KEY = "futurevoice.talkSecondsByDay"
    private const val KEEP_DAYS = 45
    private const val SEPARATOR = "|"

    fun add(context: Context, seconds: Int, language: String?, now: Long = System.currentTimeMillis()) {
        if (seconds <= 0) return
        val map = load(context).toMutableMap()
        val k = key(now, language)
        map[k] = (map[k] ?: 0) + seconds
        save(context, prune(map, now))
    }

    /** Every language's seconds for the day — what the ring reads. */
    fun secondsToday(context: Context, now: Long = System.currentTimeMillis()): Int {
        val prefix = dayKey(now)
        return load(context).entries.sumOf { (k, v) ->
            if (k == prefix || k.startsWith(prefix + SEPARATOR)) v else 0
        }
    }

    /**
     * Seconds per day for the last [days] days, oldest first — the effort
     * strip. Reads the same rows the ring does, so the strip's last bar and
     * today's number can never disagree.
     */
    fun recentSeconds(context: Context, days: Int,
                      now: Long = System.currentTimeMillis()): List<Pair<Long, Int>> {
        val map = load(context)
        return (days - 1 downTo 0).map { back ->
            val at = now - back * 86_400_000L
            val prefix = dayKey(at)
            at to map.entries.sumOf { (k, v) ->
                if (k == prefix || k.startsWith(prefix + SEPARATOR)) v else 0
            }
        }
    }

    /** Every second on file, all languages — the log keeps 45 days, so this
     *  is "recently", not "ever". */
    fun totalSeconds(context: Context): Int = load(context).values.sum()

    /** How many distinct days carry talk — coming back is the verdict that
     *  twenty minutes in one sitting cannot give. */
    fun daysWithTalk(context: Context): Int =
        load(context).entries.filter { it.value > 0 }
            .map { it.key.substringBefore(SEPARATOR) }.distinct().size

    /** The day's metered seconds in ONE language — what the streak is judged
     *  on. The ring's number pools every language; a day counts for one. */
    fun secondsOn(context: Context, at: Long, language: String): Int {
        val k = dayKey(at) + SEPARATOR + language.lowercase()
        return load(context)[k] ?: 0
    }

    /**
     * Did this day clear the CORE's daily bar, in the language being
     * practised? The club's rule and nothing else — the Home streak asks a
     * different question ([streakDays]), and merging the two is what made a
     * day of reviews read as a failure. Kept for the club's own surfaces.
     */
    fun metCoreBar(context: Context, at: Long = System.currentTimeMillis()): Boolean =
        secondsOn(context, at, LanguageScope.active(context)) >= CoreBar.seconds(context)

    /**
     * Consecutive ACTIVE days, anchored to TODAY when today already counts
     * and to yesterday otherwise — a streak is alive until its day is over,
     * and without that every learner reads 0 each morning.
     *
     * A day counts when the learner DID something: metered talk in ANY
     * language, a talk they spoke in, or any practice rep — cards, words,
     * expressions, shadow takes, a Watch scene. Opening the app is not
     * enough.
     *
     * This is NOT the Core's streak, and the two were one rule from 2026-08
     * until 2026-09-19. On Home that read as a punishment: a day of reviews,
     * shadowing and a scene, or a day spent in the other language, reset it
     * to 0. The Core keeps its hard bar and its own server-computed number on
     * its own page — don't re-merge them, and don't harden this one back
     * toward the bar.
     */
    fun streakDays(context: Context, now: Long = System.currentTimeMillis()): Int {
        val spoken = spokenDays(context)
        // The RULE is the learner's own (iOS 1.1.4, "나의 루틴"): until the
        // routine is a promise a day counts when they studied at all; from
        // then, only when the day's routine was kept, and a day with nothing
        // planned rests.
        return PromiseStreak.streak(now, floor = null) { at ->
            PromiseStreak.standing(context, at) { studied(context, it, spoken) }
        }
    }

    /**
     * Every day key (`yyyy-MM-dd`) that counts as STUDIED over the last
     * [days] days, read in one pass — what a page drawing many days at once
     * (the routine's strips and calendars) asks instead of [studied] per day.
     */
    fun activeDayKeys(context: Context, days: Int, now: Long = System.currentTimeMillis()): Set<String> {
        val out = HashSet<String>(spokenDays(context))
        load(context).forEach { (k, v) -> if (v > 0) out += k.substringBefore(SEPARATOR) }
        PracticeLog.recent(context, days, now).forEach { (k, d) -> if (d.didSomething) out += k }
        return out
    }

    /** Is TODAY already kept, by the same rule as [streakDays]? What lights
     *  the Talk header's flame (iOS `21df988`). */
    fun keptToday(context: Context, now: Long = System.currentTimeMillis()): Boolean {
        val spoken = spokenDays(context)
        return PromiseStreak.standing(context, now) { studied(context, it, spoken) } ==
            PromiseStreak.Standing.KEPT
    }

    /**
     * The walk itself, pure so the rule is testable (plan 5.1): anchor on
     * today if [active], else on yesterday, else 0; then count back while
     * [active] holds.
     */
    internal fun streakWalk(now: Long, cal: Calendar = Calendar.getInstance(),
                            active: (Long) -> Boolean): Int {
        fun startOfDay(at: Long): Long {
            cal.timeInMillis = at
            cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
            return cal.timeInMillis
        }
        // Calendar steps, never a fixed 86 400 000: a DST day is 23 or 25
        // hours long and fixed arithmetic silently skips or repeats one.
        fun dayBefore(at: Long): Long {
            cal.timeInMillis = at
            cal.add(Calendar.DAY_OF_YEAR, -1)
            return cal.timeInMillis
        }
        var cursor = startOfDay(now)
        if (!active(cursor)) {
            cursor = dayBefore(cursor)
            if (!active(cursor)) return 0
        }
        var count = 0
        while (active(cursor)) { count += 1; cursor = dayBefore(cursor) }
        return count
    }

    // MARK: - Days a talk was spoken in

    private const val SPOKEN_KEY = "futurevoice.spokenDays"

    /**
     * Every local day a learner line was said in a saved talk, any language
     * (iOS `PracticeStats.activeDays` walks `SessionStore.loadAcrossLanguages`
     * for exactly this). The meter's log keeps 45 days, so without it a
     * learner who only TALKS had a streak capped at 45 — found by 5.1.
     * Sessions load suspended, and the streak is read from places that
     * can't wait, so [SessionStore] folds the days in here as it reads and
     * writes. A union: a deleted talk's day stays lit, which errs toward
     * the learner.
     */
    fun noteSpokenDays(context: Context, sessions: List<com.roro.futurevoice.talk.Session>) {
        val days = sessions.flatMap { s ->
            s.turns.filter { it.role == com.roro.futurevoice.talk.TurnRole.USER }.map { dayKey(it.timestamp) }
        }.toSet()
        if (days.isEmpty()) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val have = prefs.getStringSet(SPOKEN_KEY, null) ?: emptySet()
        if (have.containsAll(days)) return
        prefs.edit().putStringSet(SPOKEN_KEY, HashSet(have + days)).apply()
    }

    private fun spokenDays(context: Context): Set<String> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(SPOKEN_KEY, null) ?: emptySet()

    /**
     * Does this day count toward the Home streak? The ONE predicate
     * [streakDays] counts with, public so the widget's "done today" face is
     * decided by the same rule as the number beside it (iOS
     * `PracticeStats.studied`).
     */
    fun studied(context: Context, at: Long = System.currentTimeMillis()): Boolean =
        studied(context, at, spokenDays(context))

    private fun studied(context: Context, at: Long, spoken: Set<String>): Boolean {
        val prefix = dayKey(at)
        if (prefix in spoken) return true
        val talked = load(context).entries.any { (k, v) ->
            v > 0 && (k == prefix || k.startsWith(prefix + SEPARATOR))
        }
        return talked || PracticeLog.day(context, at)?.didSomething == true
    }

    // MARK: - Server backfill (iOS `syncFromServer`)

    @kotlinx.serialization.Serializable
    private data class LedgerRow(val created_at: String, val metadata: Meta? = null) {
        @kotlinx.serialization.Serializable
        data class Meta(val seconds: Int? = null, val language: String? = null)
    }

    private const val BACKFILL_DAYS = 14
    private const val CORRECT_DOWN_DAYS = 3

    /**
     * Rebuild the log from `usage_ledger`, where the meter's accepted ticks
     * actually landed. The local log only counts whole 30 s ticks the phone
     * sent itself — a call's last partial tick lands on the server alone
     * (the gateway meters it), so without this the ring under-reads every
     * call (measured 2026-10-02: 18 s billed, 1 s on the ring), and a
     * reinstall or a second device reads 0 for a day the receipt counts.
     * Today is corrected only with no meter running; older days up to
     * [CORRECT_DOWN_DAYS] back are the ledger's figure, further back a floor.
     */
    suspend fun syncFromServer(context: Context, now: Long = System.currentTimeMillis()): Boolean =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            val auth = AuthRepository()
            val uid = auth.userId ?: return@withContext false
            val token = runCatching { auth.accessToken() }.getOrNull() ?: return@withContext false
            val cal = Calendar.getInstance().apply {
                timeInMillis = now; add(Calendar.DAY_OF_YEAR, -(BACKFILL_DAYS - 1))
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            val since = java.time.Instant.ofEpochMilli(cal.timeInMillis).toString()
            val url = "${com.roro.futurevoice.core.Config.supabaseUrl.trimEnd('/')}/rest/v1/usage_ledger" +
                "?select=created_at,metadata&user_id=eq.$uid&action=eq.talk_time" +
                "&created_at=gte.${java.net.URLEncoder.encode(since, "UTF-8")}&limit=4000"
            val rows = runCatching {
                val req = okhttp3.Request.Builder().url(url)
                    .header("Authorization", "Bearer $token")
                    .header("apikey", com.roro.futurevoice.core.Config.supabaseAnonKey).build()
                com.roro.futurevoice.net.Edge.client.newCall(req).execute().use { resp ->
                    if (!resp.isSuccessful) null
                    else com.roro.futurevoice.net.Edge.json.decodeFromString(
                        kotlinx.serialization.builtins.ListSerializer(LedgerRow.serializer()), resp.body.string())
                }
            }.getOrNull() ?: return@withContext false

            val server = mutableMapOf<String, Int>()
            for (r in rows) {
                val sec = r.metadata?.seconds ?: continue
                if (sec <= 0) continue
                val at = runCatching { java.time.OffsetDateTime.parse(r.created_at.replace(" ", "T")).toInstant().toEpochMilli() }
                    .getOrNull() ?: continue
                val k = key(at, r.metadata.language)
                server[k] = (server[k] ?: 0) + sec
            }
            if (server.isEmpty()) return@withContext false
            val map = load(context).toMutableMap()
            val before = map.toMap()
            val today = dayKey(now)
            val correctableFrom = dayKey(now - CORRECT_DOWN_DAYS * 86_400_000L)
            fun correctable(date: String) =
                if (date == today) !com.roro.futurevoice.talk.TalkMeter.isRunning else date >= correctableFrom
            for (k in map.keys.toList()) {
                if (correctable(k.substringBefore(SEPARATOR)) && server[k] == null) map.remove(k)
            }
            for ((k, sec) in server) {
                if (correctable(k.substringBefore(SEPARATOR))) map[k] = sec
                else if (sec > (map[k] ?: 0)) map[k] = sec
            }
            val next = prune(map, now)
            if (next == before) return@withContext false
            save(context, next)
            true
        }

    private fun dayKey(now: Long): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(now))

    private fun key(now: Long, language: String?): String =
        language?.takeIf { it.isNotBlank() }
            ?.let { dayKey(now) + SEPARATOR + it.lowercase() } ?: dayKey(now)

    private fun prune(map: Map<String, Int>, now: Long): Map<String, Int> {
        val cutoff = dayKey(now - KEEP_DAYS * 86_400_000L)
        return map.filterKeys { it.substringBefore(SEPARATOR) >= cutoff }
    }

    private fun load(context: Context): Map<String, Int> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, null)?.let { raw ->
                runCatching {
                    raw.split(',').filter { it.contains('=') }.associate {
                        it.substringBeforeLast('=') to it.substringAfterLast('=').toInt()
                    }
                }.getOrNull()
            } ?: emptyMap()

    private fun save(context: Context, map: Map<String, Int>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY, map.entries.joinToString(",") { "${it.key}=${it.value}" })
            .apply()
    }
}
