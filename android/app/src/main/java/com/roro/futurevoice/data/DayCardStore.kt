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
    private fun snapshotFile(context: Context, day: Long) = File(dir(context), "${key(day)}.json")

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

    fun snapshot(context: Context, day: Long): DayCardData? {
        val f = snapshotFile(context, day)
        if (!f.exists()) return null
        return runCatching {
            val fr = StoreJson.json.decodeFromString(Frozen.serializer(), f.readText())
            DayCardData(day, fr.talkMinutes, fr.studyMinutes, fr.streakDays,
                fr.talks, fr.reviews, fr.shadowTakes, fr.topics)
        }.getOrNull()
    }

    fun freeze(context: Context, data: DayCardData) {
        snapshotFile(context, data.date).writeText(StoreJson.json.encodeToString(
            Frozen.serializer(), Frozen(data.talkMinutes, data.studyMinutes, data.streakDays,
                data.talks, data.reviews, data.shadowTakes, data.topics)))
    }
}
