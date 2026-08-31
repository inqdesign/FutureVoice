package com.roro.futurevoice.data

import android.content.Context
import java.text.SimpleDateFormat
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
     * Consecutive days with metered talk, anchored to TODAY when today
     * already has some and to yesterday otherwise — a streak is alive until
     * its day is over, and without that every learner reads 0 each morning.
     */
    fun streakDays(context: Context, now: Long = System.currentTimeMillis()): Int {
        val map = load(context)
        fun met(dayMillis: Long): Boolean {
            val prefix = dayKey(dayMillis)
            return map.entries.any { (k, v) ->
                v > 0 && (k == prefix || k.startsWith(prefix + SEPARATOR))
            }
        }
        var cursor = if (met(now)) now else now - 86_400_000L
        if (!met(cursor)) return 0
        var count = 0
        while (met(cursor)) { count += 1; cursor -= 86_400_000L }
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
