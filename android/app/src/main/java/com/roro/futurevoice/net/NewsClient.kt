package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.talk.SuggestedTopic
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.UUID

/**
 * `news-topics` — the platform news pool (`NewsTopicEngine.swift`). The
 * server answers with whatever is generated plus `pending` (categories still
 * cooking); the caller polls and paints each as it lands. Free, shared
 * editorial content.
 */
class NewsClient(private val auth: AuthRepository) {

    data class Pool(val topics: List<SuggestedTopic>, val pending: List<String>, val growing: Boolean) {
        val isComplete: Boolean get() = pending.isEmpty()
    }

    @Serializable
    private data class RequestPayload(
        val categories: List<String>, val language: String, val refresh: Boolean)

    @Serializable
    private data class ServerTopic(
        val category: String = "", val title: String = "", val blurb: String = "",
        val facts: List<String> = emptyList())

    @Serializable
    private data class ResponsePayload(
        val topics: List<ServerTopic> = emptyList(),
        val pending: List<String> = emptyList(),
        val growing: Boolean = false)

    suspend fun fetch(interests: List<String>, targetLanguage: String, refresh: Boolean = false): Pool =
        withContext(Dispatchers.IO) {
            val request = Request.Builder()
                .url(Config.functionUrl("news-topics"))
                .header("Authorization", "Bearer ${auth.accessToken()}")
                .header("X-Idempotency-Key", UUID.randomUUID().toString())
                .post(Edge.json.encodeToString(RequestPayload.serializer(),
                    RequestPayload(interests, targetLanguage, refresh))
                    .toRequestBody("application/json".toMediaType()))
                .build()
            Edge.client.newCall(request).execute().use { resp ->
                val text = resp.body.string()
                if (resp.code !in 200..299) throw EdgeError.Http(resp.code, text.take(512))
                val payload = Edge.json.decodeFromString(ResponsePayload.serializer(), text)
                Pool(interleaved(payload.topics), payload.pending, payload.growing)
            }
        }

    /** Round-robin across categories so the shown handful has variety. */
    private fun interleaved(items: List<ServerTopic>): List<SuggestedTopic> {
        val byCategory = LinkedHashMap<String, MutableList<ServerTopic>>()
        for (item in items) byCategory.getOrPut(item.category) { mutableListOf() }.add(item)
        val out = mutableListOf<SuggestedTopic>()
        var round = 0
        while (true) {
            var added = false
            for (list in byCategory.values) {
                if (round < list.size) {
                    val t = list[round]
                    out.add(SuggestedTopic(title = t.title, blurb = t.blurb,
                        category = t.category, facts = t.facts))
                    added = true
                }
            }
            if (!added) break
            round += 1
        }
        return out
    }

    companion object {
        const val MAX_SHOWN = 6
        const val MAX_POLLS = 6
        const val POLL_INTERVAL_MS = 5_000L
    }
}
