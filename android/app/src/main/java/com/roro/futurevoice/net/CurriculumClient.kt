package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.talk.DialogueEngineTurn
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.ScenarioCurriculum
import com.roro.futurevoice.talk.UserPersona
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.add
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * `scenario-curriculum` — the Watch scene + study content with its prompt
 * server-side. The payload maps exactly as
 * `ScenarioCurriculumEngine.generate` does: shadow material IS the learner's
 * side of the scene, extracted deterministically.
 */
class CurriculumClient(private val auth: AuthRepository) {

    @Serializable private data class Entry(val text: String = "", val note: String = "", val example: String? = null)
    @Serializable private data class TurnItem(val speaker: String = "", val text: String = "")
    @Serializable private data class Payload(
        val turns: List<TurnItem> = emptyList(),
        val title: String? = null,
        val words: List<Entry> = emptyList(),
        val expressions: List<Entry> = emptyList(),
    )
    @Serializable private data class PartR(val text: String? = null)
    @Serializable private data class ContentR(val parts: List<PartR>? = null)
    @Serializable private data class CandidateR(val content: ContentR? = null, val finishReason: String? = null)
    @Serializable private data class ApiResponse(val candidates: List<CandidateR>? = null)

    suspend fun generate(
        scenario: Scenario,
        persona: UserPersona?,
        castIdentity: String,
        proficiency: String,
        targetLanguage: String,
        avoidTitles: List<String> = emptyList(),
        runKey: String? = null,
    ): ScenarioCurriculum = withContext(Dispatchers.IO) {
        val body: JsonObject = buildJsonObject {
            put("scenario", buildJsonObject {
                put("environment", scenario.environment)
                put("role", scenario.role)
                put("notes", scenario.notes)
                scenario.isTopic?.let { put("is_topic", it) }
            })
            put("cast_identity", castIdentity)
            persona?.takeIf { it.isMinimallyComplete }?.let { p ->
                put("persona", buildJsonObject {
                    put("city", p.city); put("country", p.country)
                    put("occupation", p.occupation); put("household", p.household)
                    putJsonArray("interests") { p.interests.forEach { add(it) } }
                    putJsonArray("situations") { p.situations.forEach { add(it) } }
                    put("free_notes", p.freeNotes)
                })
            }
            put("proficiency", proficiency)
            put("target_language", targetLanguage)
            putJsonArray("avoid_titles") { avoidTitles.forEach { add(it) } }
        }
        val key = runKey?.let { "curriculum-v2:${scenario.id}:$it" } ?: "curriculum-v2:${scenario.id}"
        val request = Request.Builder()
            .url(Config.functionUrl("scenario-curriculum"))
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("X-Idempotency-Key", key)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        Edge.client.newCall(request).execute().use { resp ->
            val raw = resp.body.string()
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, raw.take(512))
            val joined = Edge.json.decodeFromString(ApiResponse.serializer(), raw)
                .candidates?.firstOrNull()?.content?.parts?.mapNotNull { it.text }
                ?.joinToString("").orEmpty()
            val json = Edge.extractJson(joined) ?: throw EdgeError.JsonNotFound(joined)
            val payload = Edge.json.decodeFromString(Payload.serializer(), json)
            val turns = payload.turns.map {
                DialogueEngineTurn(
                    speaker = if (it.speaker.lowercase() == "user") "user" else "counterpart",
                    text = it.text)
            }
            ScenarioCurriculum(
                words = payload.words.map { ScenarioCurriculum.Item(text = it.text, note = it.note, example = it.example) },
                expressions = payload.expressions.map { ScenarioCurriculum.Item(text = it.text, note = it.note, example = it.example) },
                shadowLines = turns.filter { it.speaker == "user" }
                    .map { ScenarioCurriculum.Item(text = it.text) },
                dialogueTitle = payload.title,
                dialogue = turns,
            )
        }
    }
}
