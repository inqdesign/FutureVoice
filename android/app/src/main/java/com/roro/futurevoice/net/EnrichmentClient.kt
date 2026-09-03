package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.UserPersona
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.UUID

/**
 * A thin drill card turned into something a learner can internalize: three
 * examples grounded in THEIR life, alternate phrasings, and a memory hook.
 *
 * The prompt lives server-side (`drill-enrichment`), extracted from the Swift
 * engine by script. This side sends the card and the persona lines, which is
 * the half that has to stay on the client — only the client knows who the
 * learner is.
 */
class EnrichmentClient(private val auth: AuthRepository) {

    @Serializable data class Example(val situation: String = "", val sentence: String = "")
    @Serializable data class Variant(val phrase: String = "", val note: String = "")

    @Serializable
    data class Enrichment(
        val examples: List<Example> = emptyList(),
        val variants: List<Variant> = emptyList(),
        val memory_hook: String = "",
    )

    @Serializable private data class PartR(val text: String? = null)
    @Serializable private data class ContentR(val parts: List<PartR>? = null)
    @Serializable private data class CandidateR(val content: ContentR? = null)
    @Serializable private data class ApiResponse(val candidates: List<CandidateR>? = null)

    suspend fun generate(
        card: DrillCard,
        persona: UserPersona?,
        targetLanguage: String,
        nativeLanguage: String,
    ): Enrichment = withContext(Dispatchers.IO) {
        val body = buildJsonObject {
            put("target_phrase", card.targetPhrase)
            card.sourcePhrase.takeIf { it.isNotBlank() }?.let { put("source_phrase", it) }
            card.reason.takeIf { it.isNotBlank() }?.let { put("reason", it) }
            put("target_language", targetLanguage)
            put("native_language", nativeLanguage)
            putJsonArray("persona") { personaLines(persona).forEach { add(it) } }
        }
        val request = Request.Builder()
            .url(Config.functionUrl("drill-enrichment"))
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("X-Idempotency-Key", UUID.randomUUID().toString())
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        Edge.client.newCall(request).execute().use { resp ->
            val raw = resp.body.string()
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, raw.take(512))
            val joined = Edge.json.decodeFromString(ApiResponse.serializer(), raw)
                .candidates?.firstOrNull()?.content?.parts?.mapNotNull { it.text }
                ?.joinToString("").orEmpty()
            val json = Edge.extractJson(joined) ?: throw EdgeError.JsonNotFound(joined)
            Edge.json.decodeFromString(Enrichment.serializer(), json)
        }
    }

    /**
     * The persona as the prompt wants it — the learner's own life, so the
     * examples land in their city and their work rather than a textbook's.
     * A sparse persona says so out loud instead of sending empty fields: the
     * prompt has a branch for it.
     */
    private fun personaLines(p: UserPersona?): List<String> {
        if (p == null) return emptyList()
        val out = ArrayList<String>()
        p.displayName.takeIf { it.isNotBlank() }?.let { out.add("- name: $it") }
        listOf(p.city, p.country).filter { it.isNotBlank() }.joinToString(", ")
            .takeIf { it.isNotBlank() }?.let { out.add("- lives in: $it") }
        p.occupation.takeIf { it.isNotBlank() }?.let { out.add("- work: $it") }
        p.household.takeIf { it.isNotBlank() }?.let { out.add("- household: $it") }
        p.interests.takeIf { it.isNotEmpty() }
            ?.let { out.add("- interests: ${it.joinToString(", ")}") }
        p.situations.takeIf { it.isNotEmpty() }
            ?.let { out.add("- target-language situations: ${it.joinToString(", ")}") }
        return out
    }
}
