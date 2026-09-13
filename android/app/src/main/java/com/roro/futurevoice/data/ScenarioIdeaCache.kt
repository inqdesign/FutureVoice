package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.SuggestedTopic
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File

/**
 * On-disk cache for the composer's drill-down chips.
 *
 * The same path gives the same buckets for a month, and a learner who backs
 * up one step and comes forward again was paying a full Gemini round-trip
 * for chips they had already seen. Keyed by (person, path).
 */
object ScenarioIdeaCache {
    private const val TTL_MS = 30L * 24 * 3600 * 1000
    private const val MAX_ENTRIES = 150

    @Serializable private data class Entry(val topics: List<SuggestedTopic> = emptyList(), val savedAt: Long = 0)

    private fun file(c: Context) = File(c.filesDir, "scenario-ideas.json")
    private var memo: MutableMap<String, Entry>? = null

    fun key(personId: String?, path: List<String>) = (personId ?: "-") + "|" + path.joinToString("›")

    private suspend fun all(c: Context): MutableMap<String, Entry> = withContext(Dispatchers.IO) {
        memo ?: run {
            val cutoff = System.currentTimeMillis() - TTL_MS
            val loaded = runCatching {
                StoreJson.json.decodeFromString<Map<String, Entry>>(file(c).readText())
            }.getOrDefault(emptyMap()).filterValues { it.savedAt > cutoff }.toMutableMap()
            memo = loaded
            loaded
        }
    }

    suspend fun topics(c: Context, key: String): List<SuggestedTopic>? {
        val e = all(c)[key] ?: return null
        return if (e.savedAt > System.currentTimeMillis() - TTL_MS) e.topics else null
    }

    suspend fun store(c: Context, key: String, topics: List<SuggestedTopic>) {
        if (topics.isEmpty()) return
        val map = all(c)
        map[key] = Entry(topics, System.currentTimeMillis())
        if (map.size > MAX_ENTRIES) {
            val keep = map.entries.sortedByDescending { it.value.savedAt }.take(MAX_ENTRIES)
            map.clear(); keep.forEach { map[it.key] = it.value }
        }
        val snapshot = map.toMap()
        withContext(Dispatchers.IO) {
            runCatching { file(c).writeText(StoreJson.json.encodeToString(snapshot)) }
        }
    }
}
