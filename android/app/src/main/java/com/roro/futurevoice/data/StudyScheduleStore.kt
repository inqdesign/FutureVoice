package com.roro.futurevoice.data

import android.content.Context
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File

/**
 * When each word / expression comes back to the deck — the same
 * "10 min · Tomorrow · 3 days" promise the sentence deck keeps via
 * [DrillStore], kept here for items that live in [VocabStore] instead of a
 * card store. Same file, same shape as iOS `StudyScheduleStore`
 * (`lang/<code>/study-schedule.json`).
 *
 * An item with no entry is due immediately (new material, or never snoozed).
 * Marking something known clears its entry — a known item has no return date.
 *
 * The entry keeps the item's DISPLAY text alongside its return time: the key
 * is normalized (lowercased) for lookup, but a review session has to deal the
 * word back the way the learner saw it.
 */
class StudyScheduleStore private constructor(context: Context) {

    companion object {
        @Volatile private var instance: StudyScheduleStore? = null
        fun shared(context: Context): StudyScheduleStore =
            instance ?: synchronized(this) {
                instance ?: StudyScheduleStore(context.applicationContext).also { instance = it }
            }
    }

    enum class Kind(val raw: String) { WORD("word"), EXPRESSION("expression") }

    @Serializable
    data class Entry(
        val text: String,
        @Serializable(with = IsoDateMillisSerializer::class) val at: Long,
    )

    /** One thing waiting to come back — what a review session deals from. */
    data class DueItem(val kind: Kind, val text: String, val at: Long) {
        val id: String get() = kind.raw + "|" + text.lowercase()
    }

    private val appContext = context.applicationContext
    private val mutex = Mutex()

    private fun file(language: String): File =
        File(LanguageScope.directory(appContext, language), "study-schedule.json")

    private fun key(kind: Kind, text: String) = kind.raw + "|" + text.trim().lowercase()

    private fun read(language: String): Map<String, Entry> {
        val f = file(language)
        if (!f.exists()) return emptyMap()
        val text = runCatching { f.readText() }.getOrNull() ?: return emptyMap()
        runCatching {
            return StoreJson.json.decodeFromString(
                MapSerializer(String.serializer(), Entry.serializer()), text)
        }
        // First-format files stored the date alone; recover them by taking the
        // display text from the key (lowercased, but never lost).
        return runCatching {
            StoreJson.json.decodeFromString(
                MapSerializer(String.serializer(), IsoDateMillisSerializer), text)
                .mapValues { (k, at) -> Entry(k.substringAfter('|', k), at) }
        }.getOrElse { emptyMap() }
    }

    private fun write(language: String, entries: Map<String, Entry>) {
        val target = file(language)
        val text = StoreJson.json.encodeToString(
            MapSerializer(String.serializer(), Entry.serializer()), entries)
        val tmp = File(target.parentFile, target.name + ".tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }

    /** null = due now (never scheduled). */
    suspend fun nextReview(kind: Kind, text: String, language: String): Long? = mutex.withLock {
        read(language)[key(kind, text)]?.at
    }

    suspend fun snooze(kind: Kind, text: String, language: String, until: Long) = mutex.withLock {
        val display = text.trim()
        if (display.isEmpty()) return
        write(language, read(language) + (key(kind, text) to Entry(display, until)))
    }

    suspend fun clear(kind: Kind, text: String, language: String) = mutex.withLock {
        val entries = read(language)
        val k = key(kind, text)
        if (!entries.containsKey(k)) return
        write(language, entries - k)
    }

    /**
     * A whole-map snapshot. The deck asks its schedule questions dozens of
     * times per deal (every source, every candidate — see the `add` funnel in
     * `DailyWords.pick`), and each one re-reading the file would be a disk hit
     * per candidate word; the pick takes one snapshot and answers from it.
     */
    suspend fun snapshot(language: String): Snapshot = mutex.withLock { Snapshot(read(language)) }

    class Snapshot(private val entries: Map<String, Entry>) {
        private fun key(kind: Kind, text: String) = kind.raw + "|" + text.trim().lowercase()

        fun nextReview(kind: Kind, text: String): Long? = entries[key(kind, text)]?.at

        fun isDue(kind: Kind, text: String, now: Long = System.currentTimeMillis()): Boolean =
            (nextReview(kind, text) ?: return true) <= now

        /**
         * Everything whose return time has arrived — what the review session
         * deals, longest-waiting first (the 10-minute snooze from an hour ago
         * comes before the one from a minute ago).
         */
        fun dueItems(now: Long = System.currentTimeMillis()): List<DueItem> = items { it <= now }

        /**
         * Everything still WAITING — the mirror image of [dueItems], soonest
         * first. Together the two cover every entry, so a deck's folders can
         * show where a card actually went instead of only what this session
         * happened to touch.
         */
        fun upcoming(now: Long = System.currentTimeMillis()): List<DueItem> = items { it > now }

        private fun items(keep: (Long) -> Boolean): List<DueItem> =
            entries.mapNotNull { (k, e) ->
                if (!keep(e.at)) return@mapNotNull null
                val kind = Kind.entries.firstOrNull { it.raw == k.substringBefore('|') }
                    ?: return@mapNotNull null
                DueItem(kind, e.text, e.at)
            }.sortedBy { it.at }
    }
}
