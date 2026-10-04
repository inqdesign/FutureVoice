package com.roro.futurevoice.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.roro.futurevoice.ui.brand.DayCardData
import kotlinx.serialization.Serializable
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * One photo + one frozen snapshot per LOCAL day (`DayCardStore.swift`).
 *
 * A card is FROZEN when it is made: the logs it is drawn from are pruned at
 * 45 days and the streak rule can change, so a card read live months later
 * would lose its minutes or change its streak — and a card is what that day
 * WAS. Today is never frozen by the sweep; it is still being lived.
 *
 * The photo is the place, and that is as precise as it gets: no location
 * permission, ever. Re-encoding on save drops EXIF/GPS.
 */
object DayCardStore {

    @Serializable
    private data class Frozen(
        val talkMinutes: Int, val studyMinutes: Int, val streakDays: Int,
        val talks: Int, val reviews: Int, val shadowTakes: Int, val topics: List<String>,
    )

    private fun dir(context: Context) = File(context.filesDir, "daycards").apply { mkdirs() }
    private fun key(day: Long) = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(day))
    private fun photoFile(context: Context, day: Long) = File(dir(context), "${key(day)}.jpg")

    fun photo(context: Context, day: Long): Bitmap? {
        val f = photoFile(context, day)
        return if (f.exists()) BitmapFactory.decodeFile(f.path) else null
    }

    /** Re-encodes on save, which is what drops EXIF/GPS. */
    fun savePhoto(context: Context, day: Long, bitmap: Bitmap) {
        photoFile(context, day).outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.JPEG, 88, it)
        }
    }

    fun removePhoto(context: Context, day: Long) { photoFile(context, day).delete() }

    fun snapshot(context: Context, day: Long): DayCardData? = snapshotIn(dir(context), day)

    internal fun snapshotIn(dir: File, day: Long): DayCardData? {
        val f = File(dir, "${key(day)}.json")
        if (!f.exists()) return null
        return runCatching {
            val fr = StoreJson.json.decodeFromString(Frozen.serializer(), f.readText())
            DayCardData(day, fr.talkMinutes, fr.studyMinutes, fr.streakDays,
                fr.talks, fr.reviews, fr.shadowTakes, fr.topics)
        }.getOrNull()
    }

    /**
     * A day still being lived cannot be settled, and the rule is enforced HERE
     * so no call site can break it. iOS shipped this as a bug for three days:
     * the share sheet froze the day on every OPEN, so a card looked at in the
     * morning stopped there and read 7 min beside a home ring reading 11.
     * Nothing a snapshot protects against — pruned logs, a changed streak
     * rule — can reach today, so there was never anything to buy.
     */
    fun freeze(context: Context, data: DayCardData) = freezeIn(dir(context), data)

    /**
     * Two more guards iOS `freeze` / `freezePastDays` hold (found by 5.12):
     * a day with nothing in it is not a card, and a settled day is never
     * walked BACKWARDS — a re-settle reads logs that may since have been
     * pruned, and a record is not improved by a smaller one.
     */
    internal fun freezeIn(dir: File, data: DayCardData, now: Long = System.currentTimeMillis()): Boolean {
        if (isToday(data.date, now) || !data.hasActivity) return false
        snapshotIn(dir, data.date)?.let { if (it.talkMinutes > data.talkMinutes) return false }
        File(dir, "${key(data.date)}.json").writeText(StoreJson.json.encodeToString(
            Frozen.serializer(), Frozen(data.talkMinutes, data.studyMinutes, data.streakDays,
                data.talks, data.reviews, data.shadowTakes, data.topics)))
        return true
    }

    /**
     * The day's card: the frozen record if there is one, else the day read
     * live from the logs. TODAY is ALWAYS live — any snapshot for it is
     * ignored rather than trusted.
     */
    fun resolve(context: Context, day: Long, live: () -> DayCardData): DayCardData =
        resolveIn(dir(context), day, live = live)

    internal fun resolveIn(dir: File, day: Long, now: Long = System.currentTimeMillis(),
                           live: () -> DayCardData): DayCardData =
        if (isToday(day, now)) live() else snapshotIn(dir, day) ?: live()

    fun isToday(day: Long, now: Long = System.currentTimeMillis()): Boolean = key(day) == key(now)
}
