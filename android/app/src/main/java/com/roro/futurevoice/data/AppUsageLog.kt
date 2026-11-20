package com.roro.futurevoice.data

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Foreground seconds per LOCAL day (`AppUsageLog.swift`) — the day card's
 * "study" figure. Written at the edges of a stint, and never less than the
 * talk figure when read: a call in a pocket is metered but not foregrounded.
 *
 * Two maps, as on iOS (2026-11-19): two devices used on one day must ADD UP.
 * The per-day map syncs by the bigger device's number, so the smaller one's
 * minutes that day dropped out. The per-DEVICE map keys each count by
 * `day|device`: one writer per key, so the max merge is exact and a day is
 * the sum of its devices. The per-day map is still written for builds that
 * don't know the device map; a day reads the larger of the two.
 */
object AppUsageLog {
    private const val PREFS = "futurevoice"
    private const val KEY = "futurevoice.appSecondsByDay"
    const val DEVICE_KEY = "futurevoice.appSecondsByDevice"
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
        val devices = load(context, DEVICE_KEY).toMutableMap()
        val dk = k + "|" + device(context)
        devices[dk] = (devices[dk] ?: 0) + seconds
        save(context, prune(devices), DEVICE_KEY)
    }

    fun secondsOn(context: Context, dayMillis: Long): Int {
        val day = dayKey(dayMillis)
        return maxOf(load(context)[day] ?: 0, deviceSum(load(context, DEVICE_KEY), day))
    }

    /** Every device's seconds for a day (`yyyy-MM-dd|<device>` keys). */
    fun deviceSum(map: Map<String, Int>, day: String): Int =
        map.entries.sumOf { if (it.key.startsWith("$day|")) it.value else 0 }

    /** This install's name in the device map: ANDROID_ID, which differs per
     *  device and is never restored onto a new phone with the app's backup
     *  (a stored id in prefs would be). [PracticeLog] uses the same name. */
    fun device(context: Context): String =
        android.provider.Settings.Secure.getString(context.contentResolver,
            android.provider.Settings.Secure.ANDROID_ID)?.takeIf { it.isNotBlank() } ?: "android"

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

    private fun load(context: Context, key: String = KEY): Map<String, Int> =
        context.getSharedPreferences(PREFS, 0).getString(key, null)?.let { raw ->
            runCatching {
                raw.split(',').filter { it.contains('=') }.associate {
                    it.substringBeforeLast('=') to it.substringAfterLast('=').toInt()
                }
            }.getOrNull()
        } ?: emptyMap()

    private fun save(context: Context, map: Map<String, Int>, key: String = KEY) {
        context.getSharedPreferences(PREFS, 0).edit()
            .putString(key, map.entries.joinToString(",") { "${it.key}=${it.value}" }).apply()
    }
}
