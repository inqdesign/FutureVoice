package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * The `session-summary` Edge Function — the post-talk analysis with its
 * prompt held server-side (brain-lift #1). The client sends only DATA: the
 * transcript block, the deterministic metrics, the profile; the prompt lives
 * in `supabase/functions/session-summary/index.ts`.
 *
 * Streamed for the same reason iOS streams its summary (CLAUDE.md): nothing
 * here is usable before the payload closes, but the wrap-up board can only
 * move while the model writes if the partial text is visible. `onPartial`
 * receives the accumulated text so far; the return is the whole JSON text.
 */
class SessionSummaryClient(private val auth: AuthRepository) {

    @Serializable
    data class RequestBody(
        val target_language: String,
        val native_language: String,
        val profile: JsonObject,
        val known_about_user: List<String>,
        val expression_budget: Int,
        val transcript: String,
        val metrics: JsonObject,
        val stream: Boolean = true,
    )

    @Serializable
    private data class PartR(val text: String? = null)
    @Serializable
    private data class ContentR(val parts: List<PartR>? = null)
    @Serializable
    private data class CandidateR(val content: ContentR? = null, val finishReason: String? = null)
    @Serializable
    private data class ApiResponse(val candidates: List<CandidateR>? = null)

    /** Raw JSON text of the summary (first `{` … last `}`), or throws. */
    suspend fun summarize(
        body: RequestBody,
        idempotencyKey: String,
        onPartial: ((String) -> Unit)? = null,
    ): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(Config.functionUrl("session-summary"))
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("X-Idempotency-Key", idempotencyKey)
            .post(
                Edge.json.encodeToString(RequestBody.serializer(), body)
                    .toRequestBody("application/json".toMediaType())
            )
            .build()

        Edge.client.newCall(request).execute().use { resp ->
            if (resp.code !in 200..299) {
                val snippet = runCatching { resp.body.source().readByteString(512L) }
                    .getOrNull()?.utf8().orEmpty()
                if (resp.code == 402) throw EdgeError.wall(snippet)
                throw EdgeError.Http(resp.code, snippet)
            }
            val raw = StringBuilder()
            var finishReason: String? = null
            if (resp.header("X-Gemini-Stream") != "sse") {
                val decoded = Edge.json.decodeFromString(ApiResponse.serializer(), resp.body.string())
                val candidate = decoded.candidates?.firstOrNull()
                finishReason = candidate?.finishReason
                raw.append(candidate?.content?.parts?.mapNotNull { it.text }?.joinToString("").orEmpty())
            } else {
                val source = resp.body.source()
                while (true) {
                    val line = source.readUtf8Line() ?: break
                    if (!line.startsWith("data:")) continue
                    val event = line.removePrefix("data:").trim()
                    if (event.isEmpty() || event == "[DONE]") continue
                    val chunk = runCatching {
                        Edge.json.decodeFromString(ApiResponse.serializer(), event)
                    }.getOrNull() ?: continue
                    val candidate = chunk.candidates?.firstOrNull()
                    candidate?.finishReason?.let { finishReason = it }
                    val delta = candidate?.content?.parts?.mapNotNull { it.text }?.joinToString("").orEmpty()
                    if (delta.isEmpty()) continue
                    raw.append(delta)
                    onPartial?.invoke(raw.toString())
                }
            }
            val text = raw.toString().trim()
            Edge.extractJson(text)
                ?: throw if (finishReason == "MAX_TOKENS") EdgeError.Truncated else EdgeError.JsonNotFound(text)
        }
    }
}
