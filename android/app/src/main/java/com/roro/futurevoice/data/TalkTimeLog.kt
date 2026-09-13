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

    /** The day's metered seconds in ONE language — what the streak is judged
     *  on. The ring's number pools every language; a day counts for one. */
    fun secondsOn(context: Context, at: Long, language: String): Int {
        val k = dayKey(at) + SEPARATOR + language.lowercase()
        return load(context)[k] ?: 0
    }

    /** Did this day clear the Core's daily bar in the language being
     *  practised? The one predicate the streak is built from — anything that
     *  needs to say "today counts" asks THIS, never the learner's own daily
     *  goal. The goal fills a ring; the bar decides a day. */
    fun metCoreBar(context: Context, at: Long = System.currentTimeMillis()): Boolean =
        secondsOn(context, at, LanguageScope.active(context)) >= CoreBar.seconds(context)

    /**
     * Consecutive days over the Core's daily bar, in the language being
     * practised, anchored to TODAY when today already counts and to yesterday
     * otherwise — a streak is alive until its day is over, and without that
     * every learner reads 0 each morning.
     *
     * It used to be "any day with any metered second, in any language", which
     * let a two-second call keep a streak alive and pooled languages together.
     * There is one rule now and it is the Core's, so the number on Home and
     * the number the club promotes from can never disagree.
     */
    fun streakDays(context: Context, now: Long = System.currentTimeMillis()): Int {
        val cal = Calendar.getInstance()
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
        if (!metCoreBar(context, cursor)) {
            cursor = dayBefore(cursor)
            if (!metCoreBar(context, cursor)) return 0
        }
        var count = 0
        while (metCoreBar(context, cursor)) { count += 1; cursor = dayBefore(cursor) }
        return count
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
