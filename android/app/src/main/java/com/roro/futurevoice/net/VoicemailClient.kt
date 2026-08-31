package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
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
import java.util.UUID

/**
 * `voicemail-script` — tomorrow's call's opening words, written at SESSION
 * END (the one moment the app is foreground with fresh context; a call that
 * fails to generate is a call that opens generic). The caller's memory lives
 * server-side in the prompt; the client sends only facts.
 */
class VoicemailClient(private val auth: AuthRepository) {

    @Serializable private data class Payload(val script: String = "")
    @Serializable private data class PartR(val text: String? = null)
    @Serializable private data class ContentR(val parts: List<PartR>? = null)
    @Serializable private data class CandidateR(val content: ContentR? = null)
    @Serializable private data class ApiResponse(val candidates: List<CandidateR>? = null)

    suspend fun writeScript(
        targetLanguage: String, nativeLanguage: String, proficiency: String,
        personaName: String?, lastTopic: String?, lastPhrases: List<String>,
        daysSinceLastTalk: Int?, dueCount: Int,
    ): String = withContext(Dispatchers.IO) {
        val body: JsonObject = buildJsonObject {
            put("target_language", targetLanguage)
            put("native_language", nativeLanguage)
            put("proficiency", proficiency)
            personaName?.takeIf { it.isNotBlank() }?.let { put("persona_name", it) }
            lastTopic?.takeIf { it.isNotBlank() }?.let { put("last_topic", it) }
            putJsonArray("last_phrases") { lastPhrases.take(4).forEach { add(it) } }
            daysSinceLastTalk?.let { put("days_since_last_talk", it) }
            put("due_count", dueCount)
        }
        val request = Request.Builder()
            .url(Config.functionUrl("voicemail-script"))
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
            sanitize(Edge.json.decodeFromString(Payload.serializer(), json).script)
        }
    }

    companion object {
        const val MAX_SCRIPT_CHARACTERS = 260

        /** `VoicemailEngine.sanitize`: strip stage directions, whole-sentence trim. */
        fun sanitize(raw: String): String {
            var s = raw.trim()
            s = Regex("\\*[^*]*\\*").replace(s, "")
            s = Regex("\\[[^\\]]*\\]").replace(s, "")
            s = Regex("\\s+").replace(s, " ").trim()
            if (s.length <= MAX_SCRIPT_CHARACTERS) return s
            val clipped = s.take(MAX_SCRIPT_CHARACTERS)
            val cut = clipped.indexOfLast { it in ".!?？！。" }
            return if (cut >= 0) clipped.substring(0, cut + 1) else clipped
        }
    }
}
