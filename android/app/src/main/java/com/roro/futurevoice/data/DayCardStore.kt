package com.roro.futurevoice.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.roro.futurevoice.ui.brand.DayCardData
import kotlinx.serialization.Serializable
import java.io.File
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TurnRole
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * One photo + one frozen snapshot per LOCAL day (`DayCardStore.swift`).
 *
 * A card is FROZEN when it is made: the logs it is drawn from are pruned at
 * 45 days and the streak rule can change, so a card read live months later
 * would lose its minutes or change its streak — and a card is what that day
 * WAS. Every past day with activity is settled on foreground
 * ([freezePastDays]), not only a day with a photo. Today is never frozen; it
 * is still being lived.
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

    /**
     * A picked photo, UPRIGHT and no bigger than the card needs. Re-encoding
     * drops EXIF, and with it the orientation tag a phone camera writes
     * instead of rotating the pixels — so a portrait shot read sideways on
     * the card. The tag is applied here first (as `CounterpartPhotoStore`
     * does), and the decode is sampled down to ~[MAX_EDGE] so a 12 MP original
     * isn't held in memory for a 1080-wide card.
     */
    fun decodeUpright(context: Context, uri: android.net.Uri): Bitmap? {
        val bytes = runCatching {
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        }.getOrNull() ?: return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_EDGE) sample *= 2
        val source = BitmapFactory.decodeByteArray(bytes, 0, bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val degrees = runCatching {
            when (android.media.ExifInterface(bytes.inputStream()).getAttributeInt(
                android.media.ExifInterface.TAG_ORIENTATION, android.media.ExifInterface.ORIENTATION_NORMAL)) {
                android.media.ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                android.media.ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                android.media.ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        }.getOrDefault(0f)
        return if (degrees == 0f) source else Bitmap.createBitmap(source, 0, 0, source.width, source.height,
            android.graphics.Matrix().apply { postRotate(degrees) }, true)
    }

    private const val MAX_EDGE = 2160

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

    // MARK: - The day read live

    /**
     * A day's card read live from the logs — the ONE builder, so the Activity
     * summary, the share sheet and the sweep below can never settle a day
     * three different ways. [talkSeconds] is the meter's figure for that day
     * (the ring's number); [sessions] are that day's talks, any language.
     */
    fun make(context: Context, day: Long, talkSeconds: Int, sessions: List<Session>): DayCardData {
        val practice = PracticeLog.day(context, day)
        val talkMinutes = talkSeconds / 60
        // Never less than the talk figure: a call in a pocket is metered but
        // not foregrounded.
        val studyMinutes = maxOf(AppUsageLog.secondsOn(context, day) / 60, talkMinutes)
        return DayCardData(
            date = day,
            talkMinutes = talkMinutes,
            studyMinutes = studyMinutes,
            streakDays = TalkTimeLog.streakDays(context, day),
            talks = sessions.size,
            reviews = practice?.drillReps ?: 0,
            shadowTakes = practice?.shadowReps ?: 0,
            topics = sessions.sortedByDescending { s ->
                s.turns.filter { it.role == TurnRole.USER }.sumOf { it.durationMs }
            }.mapNotNull { it.displayTitle }.distinct().take(4),
        )
    }

    // MARK: - Settling past days

    /** How far back the sweep looks — the logs' own window. */
    private const val SETTLE_DAYS = 45

    /**
     * iOS `freezePastDays`: settle every past day of the logs' window that
     * has activity and no settled record yet, so a day without a photo keeps
     * its minutes once the 45-day logs prune it. Run on every foreground,
     * off the main thread. Today is never touched — it is still being lived.
     */
    suspend fun freezePastDays(context: Context, now: Long = System.currentTimeMillis()) {
        val byDay = HashMap<String, MutableList<Session>>()
        val store = SessionStore.shared(context)
        LanguageScope.enrolled(context).forEach { lang ->
            runCatching { store.load(lang) }.getOrDefault(emptyList()).forEach {
                byDay.getOrPut(key(it.endedAt ?: it.startedAt)) { mutableListOf() }.add(it)
            }
        }
        freezePastDaysIn(dir(context), now) { day ->
            val talk = TalkTimeLog.secondsToday(context, day)
            val talks = byDay[key(day)].orEmpty()
            // An empty day is never settled, so it is asked again on every
            // foreground: answer it without the streak walk, the one costly
            // read in `make`.
            if (talk < 60 && talks.isEmpty() && AppUsageLog.secondsOn(context, day) < 60) {
                DayCardData(day, 0, 0, 0, 0)
            } else make(context, day, talk, talks)
        }
    }

    /**
     * The sweep, pure over a directory so the rule is testable. Idempotent
     * and cheap: a day already settled is skipped on its file's modification
     * time, without decoding anything. Returns how many days it wrote.
     */
    internal fun freezePastDaysIn(dir: File, now: Long, make: (Long) -> DayCardData): Int {
        val cal = Calendar.getInstance()
        var written = 0
        for (back in 1..SETTLE_DAYS) {
            cal.timeInMillis = now
            // Calendar steps, never a fixed 86 400 000: a DST day is 23 or 25 hours.
            cal.add(Calendar.DAY_OF_YEAR, -back)
            val day = cal.timeInMillis
            if (!needsSettling(dir, day)) continue
            // freezeIn holds the rest: no empty day, never a smaller record.
            if (freezeIn(dir, make(day), now)) written++
        }
        return written
    }

    /**
     * A day with no record, or one whose record was written while that day
     * was still running (iOS builds before 2026-08-31 froze today on every
     * open of the share sheet; a card frozen mid-day stops at whenever the
     * learner happened to look). The rewrite stamps a time past the day's
     * end, so each such day is re-settled once.
     */
    internal fun needsSettling(dir: File, day: Long): Boolean {
        val f = File(dir, "${key(day)}.json")
        if (!f.exists()) return true
        val cal = Calendar.getInstance().apply {
            timeInMillis = day
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            add(Calendar.DAY_OF_YEAR, 1)
        }
        return f.lastModified() < cal.timeInMillis
    }
}
