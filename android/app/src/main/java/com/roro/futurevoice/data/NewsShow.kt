package com.roro.futurevoice.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * One episode of the nawana Podcast (iOS `NewsShowEpisode`, 2026-10-19).
 *
 * One episode a day, the same for everyone: two hosts talk one news story
 * through, a different category each weekday (Monday tech, Tuesday
 * fashion…). Made once on the platform side (`scripts/news-show-daily.py`)
 * and read by every install from R2 as a FEED — `shows/<lang>/latest.json`,
 * newest first, every episode numbered — plus one mp3 per line. Listening
 * is free and needs no `BillingGate`.
 *
 * An episode is played by the situations player, line by line, so it gets
 * the same karaoke caption, translation and lock screen as a scene. Its
 * files are a CACHE (cache/NewsShow), fetched when the episode is picked,
 * and dropped once the episode leaves the feed.
 */
data class NewsShowEpisode(
    val id: String,
    val title: String,
    /** Counted across days by the publisher: EP 1 is the show's first. */
    val number: Int,
    /** The episode's day, epoch millis at local midnight. */
    val date: Long,
    val category: String?,
    val minutes: Int,
    val lines: List<PlaylistLine>,
    /** The episode as a Speech script, so it opens on the Speech tab's own
     *  script page (founder, 2026-10-19). */
    val script: SpeechScript,
    internal val shippedStudy: NewsShow.ShippedStudy?,
    internal val translations: List<Map<String, String>>,
    /** The line files, relative to the feed, for [NewsShow.prepare]. */
    internal val files: List<String>,
    internal val language: String,
) {
    /** Every line's audio is on the phone. */
    val isReady: Boolean get() = lines.all { it.hasAudio }

    /**
     * The study made when the episode was published, in [native]: the
     * highlights placed in the script and each line's translation as its
     * paragraph note. Null when the episode has none in that language — a
     * podcast's study is never made on the phone.
     */
    fun study(native: String): ScriptStudy? {
        val shipped = shippedStudy ?: return null
        val same = LanguageCatalog.sameLanguage(native, script.language)
        val candidates = shipped.highlights.mapNotNull { h ->
            val kind = ScriptStudy.Kind.from(h.kind) ?: return@mapNotNull null
            val note = if (same) "" else h.notes?.get(native) ?: return@mapNotNull null
            ScriptStudy.Candidate(text = h.text, kind = kind, lemma = h.lemma, note = note, example = h.example)
        }
        if (candidates.isEmpty()) return null
        val paragraphs = ScriptStudy.paragraphs(script.body)
        val highlights = ScriptStudy.locate(candidates, paragraphs,
            spaced = LanguageCatalog.writesSpaces(script.language))
        val notes = paragraphs.indices.map { i ->
            if (same || i >= translations.size) "" else translations[i][native] ?: ""
        }
        return ScriptStudy(highlights = highlights, paragraphNotes = notes)
    }
}

object NewsShow {
    /** The bucket's public r2.dev address. English only while the show's
     *  reaction is tested (founder, 2026-10-19). */
    const val BASE = "https://pub-83c97a52f2e549718b126bf60f710f1a.r2.dev/shows"
    val languages: Set<String> = setOf("en")

    @Serializable
    data class ShippedStudy(val highlights: List<Highlight> = emptyList()) {
        @Serializable
        data class Highlight(
            val text: String,
            val kind: String,
            val lemma: String? = null,
            val example: String? = null,
            /** Native language → the note, every app language at once. */
            val notes: Map<String, String>? = null,
        )
    }

    @Serializable
    private data class Feed(
        /** The first test day's per-day manifest had a top-level date; the
         *  daily feed dates each episode. */
        val date: String? = null,
        val episodes: List<Episode> = emptyList(),
    ) {
        @Serializable
        data class Episode(
            val id: String,
            val number: Int? = null,
            val date: String? = null,
            val category: String? = null,
            val title: String,
            val seconds: Int? = null,
            val lines: List<Line> = emptyList(),
            val study: ShippedStudy? = null,
        )

        @Serializable
        data class Line(
            val speaker: String,
            val text: String,
            val audio: String,
            /** Native language → meaning, made by the publisher. */
            val translations: Map<String, String>? = null,
        )
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val http = OkHttpClient.Builder().callTimeout(15, TimeUnit.SECONDS).build()
    private val files = OkHttpClient.Builder().callTimeout(60, TimeUnit.SECONDS).build()

    /** The feed for [language], newest first. Offline, the last feed fetched.
     *  Nothing is downloaded here; [prepare] fetches an episode when picked. */
    suspend fun episodes(context: Context, language: String): List<NewsShowEpisode> = withContext(Dispatchers.IO) {
        val lang = language.lowercase().split("-").first()
        if (lang !in languages) return@withContext emptyList()
        val dir = cacheDirectory(context, lang)
        val feedFile = File(dir, "latest.json")

        val fresh = runCatching {
            val request = Request.Builder().url("$BASE/$lang/latest.json")
                .header("Cache-Control", "no-cache").build()
            http.newCall(request).execute().use { r ->
                if (r.code != 200) null else r.body?.string()
            }
        }.getOrNull()
        val feed: Feed = fresh?.let { text -> runCatching { json.decodeFromString(Feed.serializer(), text) }.getOrNull() }
            ?.also { runCatching { feedFile.writeText(fresh) } }
            ?: runCatching { json.decodeFromString(Feed.serializer(), feedFile.readText()) }.getOrNull()
            ?: return@withContext emptyList()

        val episodes = feed.episodes.mapIndexed { index, episode ->
            val id = stableId(episode.id)
            val number = episode.number ?: (index + 1)
            val lines = episode.lines.map { line ->
                PlaylistLine(bookId = id, text = line.text, voiceId = "", speaker = line.speaker,
                    isOther = true, bookTitle = episode.title,
                    localFile = File(dir, line.audio),
                    translations = line.translations,
                    episodeNumber = number,
                    episodeCategory = episode.category)
            }
            val script = SpeechScript(
                id = id, title = episode.title, genre = SpeechGenre.NEWS, topic = episode.category ?: "",
                body = episode.lines.joinToString("\n") { "${it.speaker}: ${it.text}" },
                summary = "", keyTerms = emptyList(), sources = emptyList(), language = lang,
                targetSeconds = episode.seconds ?: 0, createdAt = System.currentTimeMillis(), isBuiltIn = false)
            NewsShowEpisode(
                id = id, title = episode.title, number = number,
                date = (episode.date ?: feed.date)?.let { day ->
                    runCatching { LocalDate.parse(day).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli() }
                        .getOrNull()
                } ?: System.currentTimeMillis(),
                category = episode.category,
                minutes = maxOf(1, Math.round((episode.seconds ?: 0) / 60.0).toInt()),
                lines = lines, script = script, shippedStudy = episode.study,
                translations = episode.lines.map { it.translations ?: emptyMap() },
                files = episode.lines.map { it.audio }, language = lang)
        }
        prune(dir, keeping = feed.episodes.flatMap { it.lines }
            .mapNotNull { it.audio.split("/").firstOrNull() }.toSet())
        episodes
    }

    /** Fetch whatever of [episode] isn't on the phone yet. */
    suspend fun prepare(context: Context, episode: NewsShowEpisode) = withContext(Dispatchers.IO) {
        val dir = cacheDirectory(context, episode.language)
        val missing = episode.files.filter { !File(dir, it).exists() }
        coroutineScope {
            missing.map { path ->
                async {
                    runCatching {
                        val target = File(dir, path)
                        val request = Request.Builder().url("$BASE/${episode.language}/$path").build()
                        files.newCall(request).execute().use { r ->
                            if (r.code != 200) return@use
                            val bytes = r.body?.bytes() ?: return@use
                            target.parentFile?.mkdirs()
                            // Atomic, so a cut-off download is never a file that "exists".
                            val tmp = File(target.parentFile, target.name + ".part")
                            tmp.writeBytes(bytes)
                            tmp.renameTo(target)
                        }
                    }
                }
            }.awaitAll()
        }
    }

    /** Only what the feed still lists stays on the phone. */
    private fun prune(dir: File, keeping: Set<String>) {
        dir.listFiles()?.forEach { f ->
            if (f.name !in keeping && f.name != "latest.json") f.deleteRecursively()
        }
    }

    private fun cacheDirectory(context: Context, lang: String): File =
        File(context.cacheDir, "NewsShow/$lang").apply { mkdirs() }

    /** The same episode is the same id on every load, so the player can tell
     *  it is still playing the list the sheet just rebuilt (iOS: the first
     *  16 bytes of SHA-256, stamped as a version-5 UUID). */
    internal fun stableId(key: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(key.toByteArray()).copyOf(16)
        bytes[6] = ((bytes[6].toInt() and 0x0F) or 0x50).toByte()
        bytes[8] = ((bytes[8].toInt() and 0x3F) or 0x80).toByte()
        var msb = 0L
        var lsb = 0L
        for (i in 0 until 8) msb = (msb shl 8) or (bytes[i].toLong() and 0xFF)
        for (i in 8 until 16) lsb = (lsb shl 8) or (bytes[i].toLong() and 0xFF)
        return UUID(msb, lsb).toString().uppercase()
    }
}
