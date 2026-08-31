package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.SuggestedTopic
import kotlinx.serialization.Serializable
import java.io.File

/**
 * Daily per-language cache for news topics (`NewsTopicStore.swift`, same
 * `news_topics.json` shape under `lang/<code>/`). Invalidated when the
 * interest set changes or after 24 h; `seenTitles` is display rotation,
 * not freshness.
 */
class NewsTopicStore private constructor(context: Context) {

    companion object {
        @Volatile private var instance: NewsTopicStore? = null
        fun shared(context: Context): NewsTopicStore =
            instance ?: synchronized(this) {
                instance ?: NewsTopicStore(context.applicationContext).also { instance = it }
            }
        private const val FILE_NAME = "news_topics.json"
        private const val MAX_AGE_MS = 24 * 60 * 60 * 1000L

        fun key(interests: List<String>): String =
            interests.map { it.lowercase().trim() }.filter { it.isNotEmpty() }
                .sorted().joinToString("|")
    }

    @Serializable
    private data class Cached(
        val interestsKey: String,
        @Serializable(with = IsoDateMillisSerializer::class) val fetchedAt: Long,
        val topics: List<SuggestedTopic>,
        val seenTitles: List<String>? = null,
    )

    private val appContext = context.applicationContext

    private fun file(language: String): File =
        File(LanguageScope.directory(appContext, language), FILE_NAME)

    fun valid(interests: List<String>, language: String, now: Long = System.currentTimeMillis()): List<SuggestedTopic>? {
        val c = load(language) ?: return null
        if (c.interestsKey != key(interests)) return null
        if (now - c.fetchedAt >= MAX_AGE_MS || c.topics.isEmpty()) return null
        return c.topics
    }

    fun save(topics: List<SuggestedTopic>, interests: List<String>, language: String,
             now: Long = System.currentTimeMillis()) {
        val carried = load(language)?.takeIf { it.interestsKey == key(interests) }?.seenTitles
        write(language, Cached(key(interests), now, topics, carried))
    }

    fun seenTitles(interests: List<String>, language: String): List<String> =
        load(language)?.takeIf { it.interestsKey == key(interests) }?.seenTitles ?: emptyList()

    fun markSeen(titles: List<String>, interests: List<String>, language: String) {
        val c = load(language)?.takeIf { it.interestsKey == key(interests) } ?: return
        val seen = (c.seenTitles ?: emptyList()).toMutableList()
        for (t in titles) if (t !in seen) seen.add(t)
        while (seen.size > 100) seen.removeAt(0)
        write(language, c.copy(seenTitles = seen))
    }

    private fun load(language: String): Cached? {
        val f = file(language)
        if (!f.exists()) return null
        return runCatching {
            StoreJson.json.decodeFromString(Cached.serializer(), f.readText())
        }.getOrNull()
    }

    private fun write(language: String, cached: Cached) {
        val target = file(language)
        val tmp = File(target.parentFile, "$FILE_NAME.tmp")
        tmp.writeText(StoreJson.json.encodeToString(Cached.serializer(), cached))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }
}
