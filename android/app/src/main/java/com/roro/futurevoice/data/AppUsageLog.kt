package com.roro.futurevoice.data

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Foreground seconds per LOCAL day (`AppUsageLog.swift`) — the day card's
 * "study" figure. Written at the edges of a stint, and never less than the
 * talk figure when read: a call in a pocket is metered but not foregrounded.
 */
object AppUsageLog {
    private const val PREFS = "futurevoice"
    private const val KEY = "futurevoice.appSecondsByDay"
    private const val KEEP_DAYS = 45
    private var enteredAt = 0L

    fun begin() { enteredAt = System.currentTimeMillis() }

    fun end(context: Context) {
        val start = enteredAt
        if (start == 0L) return
        enteredAt = 0L
        val seconds = ((System.currentTimeMillis() - start) / 1000).toInt()
        if (seconds <= 0) return
        val map = load(context).toMutableMap()
        val k = dayKey(System.currentTimeMillis())
        map[k] = (map[k] ?: 0) + seconds
        save(context, prune(map))
    }

    fun secondsOn(context: Context, dayMillis: Long): Int =
        load(context)[dayKey(dayMillis)] ?: 0

    /** The day's seconds with today's open stint added (iOS
     *  `AppUsageLog.seconds(on:now:)`) — the effort page reads it live. */
    fun secondsWithOpenStint(context: Context, dayMillis: Long, now: Long = System.currentTimeMillis()): Int {
        val stored = secondsOn(context, dayMillis)
        if (dayKey(dayMillis) != dayKey(now)) return stored
        val start = enteredAt
        val open = if (start == 0L) 0 else maxOf(0, ((now - start) / 1000).toInt())
        return stored + open
    }

    private fun dayKey(now: Long) = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(now))

    private fun prune(map: Map<String, Int>): Map<String, Int> {
        val cutoff = dayKey(System.currentTimeMillis() - KEEP_DAYS * 86_400_000L)
        return map.filterKeys { it >= cutoff }
    }

    private fun load(context: Context): Map<String, Int> =
        context.getSharedPreferences(PREFS, 0).getString(KEY, null)?.let { raw ->
            runCatching {
                raw.split(',').filter { it.contains('=') }.associate {
                    it.substringBeforeLast('=') to it.substringAfterLast('=').toInt()
                }
            }.getOrNull()
        } ?: emptyMap()

    private fun save(context: Context, map: Map<String, Int>) {
        context.getSharedPreferences(PREFS, 0).edit()
            .putString(KEY, map.entries.joinToString(",") { "${it.key}=${it.value}" }).apply()
    }
}
