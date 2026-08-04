package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.Serializable
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.UUID

/**
 * Gemini via the `gemini` Edge Function. The app never holds a Google key.
 *
 * Wire contract: `docs/contracts/edge-api.md` §POST /gemini.
 */
class GeminiClient(private val auth: AuthRepository) {

    enum class Model(val id: String) {
        /** Default brain — conversation turns, analysis, generation. */
        FLASH_36("gemini-3.6-flash"),

        /** Cheap fast tier for utility calls (translation, parsing, openers). */
        FLASH_LITE_31("gemini-3.1-flash-lite"),

        /** Rollback hatch only; the 2.5 family retires 2026-10-16. */
        FLASH_25("gemini-2.5-flash");

        /** Gen-3 takes `thinkingLevel` and prefers DEFAULT sampling. */
        val isGen3: Boolean get() = this != FLASH_25
    }

    data class InlineAudio(val mimeType: String, val base64Data: String)

    data class Message(
        val role: Role,
        val content: String,
        val inlineAudio: InlineAudio? = null,
    ) {
        enum class Role(val wire: String) { USER("user"), MODEL("model") }
    }

    // MARK: - Wire types

    @Serializable
    private data class InlineDataDto(val mimeType: String, val data: String)

    @Serializable
    private data class PartDto(val text: String? = null, val inlineData: InlineDataDto? = null)

    @Serializable
    private data class ContentDto(val role: String, val parts: List<PartDto>)

    @Serializable
    private data class SystemInstructionDto(val parts: List<PartDto>)

    @Serializable
    private data class ThinkingConfigDto(
        val thinkingBudget: Int? = null,   // 2.5 family: 0 = thinking off
        val thinkingLevel: String? = null, // gen-3: "low" = minimum
    )

    @Serializable
    private data class GenerationConfigDto(
        val temperature: Double? = null,
        val maxOutputTokens: Int,
        val thinkingConfig: ThinkingConfigDto,
        val responseMimeType: String? = null,
    )

    @Serializable
    private class EmptyObject

    @Serializable
    private data class ToolDto(val google_search: EmptyObject)

    @Serializable
    private data class BodyDto(
        val model: String,
        val system_instruction: SystemInstructionDto,
        val contents: List<ContentDto>,
        val generationConfig: GenerationConfigDto,
        val tools: List<ToolDto>? = null,
        val purpose: String? = null,
        val stream: Boolean? = null,
    )

    @Serializable
    private data class PartR(val text: String? = null)

    @Serializable
    private data class ContentR(val parts: List<PartR>? = null)

    @Serializable
    private data class CandidateR(val content: ContentR? = null, val finishReason: String? = null)

    @Serializable
    private data class ApiResponse(val candidates: List<CandidateR>? = null)

    // MARK: - Public

    /**
     * Fire-and-forget warm-up, called during the VAD silence window so the
     * TCP+TLS handshake (and a fresh cached auth token) happens BEFORE the turn
     * request instead of on its critical path — on a cold cellular radio that
     * handshake alone is 200–600ms. The OPTIONS preflight needs no auth and
     * bills nothing; ElevenLabs shares the same host, so one warm-up covers both.
     */
    suspend fun preconnect() = withContext(Dispatchers.IO) {
        runCatching {
            val request = Request.Builder()
                .url(Config.functionUrl("gemini"))
                .method("OPTIONS", null)
                .build()
            Edge.client.newCall(request).execute().use { }
        }
        auth.warmToken()
        Unit
    }

    /** Buffered structured call — summaries, analysis, anything not a live turn. */
    suspend fun <T> sendJson(
        system: String,
        messages: List<Message>,
        serializer: DeserializationStrategy<T>,
        model: Model = Model.FLASH_36,
        maxTokens: Int = 1024,
        temperature: Double = 0.4,
        searchGrounding: Boolean = false,
        purpose: String? = null,
        idempotencyKey: String? = null,
    ): T = withContext(Dispatchers.IO) {
        val request = buildRequest(
            system, messages, model, maxTokens, temperature, searchGrounding,
            purpose, idempotencyKey, jsonResponse = true, stream = false,
        )
        val (raw, finishReason) = Edge.client.newCall(request).execute().use { response ->
            val bytes = response.body.bytes()
            validate(response.code, bytes)
            val decoded = Edge.json.decodeFromString(ApiResponse.serializer(), String(bytes))
            val candidate = decoded.candidates?.firstOrNull()
            val text = candidate?.content?.parts?.mapNotNull { it.text }?.joinToString("").orEmpty()
            text.trim() to candidate?.finishReason
        }
        // Reclassify ONLY after parsing has actually failed — never on the flag
        // alone, so a response that happens to be complete is still used.
        val truncated = finishReason == "MAX_TOKENS"
        val body = Edge.extractJson(raw)
            ?: throw if (truncated) EdgeError.Truncated else EdgeError.JsonNotFound(raw)
        try {
            Edge.json.decodeFromString(serializer, body)
        } catch (e: Exception) {
            if (truncated) throw EdgeError.Truncated else throw e
        }
    }

    /**
     * Streaming sibling of [sendJson], for the conversation turn.
     *
     * `earlyField` fires the moment that field's closing quote arrives — TTS
     * goes out while the model is still writing the tail. Degrades in three
     * silent steps (see `docs/contracts/edge-api.md`):
     *  • no `X-Gemini-Stream: sse` handshake → buffer the plain body, no early fire;
     *  • stream dies AFTER the early field → rebuild from what arrived;
     *  • stream dies BEFORE it → throw, and the caller retries buffered on the
     *    SAME idempotency key (no second charge).
     */
    suspend fun <T> sendJsonStream(
        system: String,
        messages: List<Message>,
        serializer: DeserializationStrategy<T>,
        model: Model = Model.FLASH_36,
        maxTokens: Int = 1024,
        temperature: Double = 0.4,
        purpose: String? = null,
        idempotencyKey: String? = null,
        earlyField: String,
        onEarlyField: suspend (String) -> Unit,
        fallbackFromEarly: (String) -> T?,
    ): T = withContext(Dispatchers.IO) {
        val request = buildRequest(
            system, messages, model, maxTokens, temperature, searchGrounding = false,
            purpose = purpose, idempotencyKey = idempotencyKey,
            jsonResponse = true, stream = true,
        )

        // One immediate re-dial on a transient connect failure, matching the TTS
        // stream: a radio blip at stream OPEN otherwise drops the turn into the
        // buffered path and costs more than it saves.
        val response = try {
            Edge.client.newCall(request).execute()
        } catch (e: java.io.IOException) {
            Edge.client.newCall(request).execute()
        }

        response.use { resp ->
            if (resp.code !in 200..299) {
                val snippet = runCatching { resp.body.source().readByteString(512L) }
                    .getOrNull()?.utf8().orEmpty()
                if (resp.code == 402) throw EdgeError.InsufficientCredits
                throw EdgeError.Http(resp.code, snippet)
            }

            // No handshake → this deploy ignored `stream` and sent one JSON body.
            if (resp.header("X-Gemini-Stream") != "sse") {
                val text = resp.body.string()
                val decoded = Edge.json.decodeFromString(ApiResponse.serializer(), text)
                val candidate = decoded.candidates?.firstOrNull()
                val joined =
                    candidate?.content?.parts?.mapNotNull { it.text }?.joinToString("").orEmpty()
                val body = Edge.extractJson(joined)
                    ?: throw if (candidate?.finishReason == "MAX_TOKENS") EdgeError.Truncated
                    else EdgeError.JsonNotFound(joined)
                return@withContext Edge.json.decodeFromString(serializer, body)
            }

            val raw = StringBuilder()
            var finishReason: String? = null
            var early: String? = null

            try {
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
                    val delta =
                        candidate?.content?.parts?.mapNotNull { it.text }?.joinToString("").orEmpty()
                    if (delta.isEmpty()) continue
                    raw.append(delta)
                    if (early == null) {
                        val value = JsonFieldScanner.completedStringField(earlyField, raw.toString())
                        if (value != null) {
                            early = value
                            onEarlyField(value)
                        }
                    }
                }
            } catch (e: Exception) {
                val salvaged = early?.let(fallbackFromEarly)
                if (salvaged != null) return@withContext salvaged
                throw e
            }

            val trimmed = raw.toString().trim()
            val truncated = finishReason == "MAX_TOKENS"
            val body = Edge.extractJson(trimmed)
            if (body == null) {
                val salvaged = early?.let(fallbackFromEarly)
                if (salvaged != null) return@withContext salvaged
                throw if (truncated) EdgeError.Truncated else EdgeError.JsonNotFound(trimmed)
            }
            try {
                Edge.json.decodeFromString(serializer, body)
            } catch (e: Exception) {
                // The reply already shipped; a malformed or cut-off tail must not
                // undo a turn the user has heard.
                val salvaged = early?.let(fallbackFromEarly)
                if (salvaged != null) return@withContext salvaged
                if (truncated) throw EdgeError.Truncated else throw e
            }
        }
    }

    // MARK: - Helpers

    private suspend fun buildRequest(
        system: String,
        messages: List<Message>,
        model: Model,
        maxTokens: Int,
        temperature: Double,
        searchGrounding: Boolean,
        purpose: String?,
        idempotencyKey: String?,
        jsonResponse: Boolean,
        stream: Boolean,
    ): Request {
        val body = BodyDto(
            model = model.id,
            system_instruction = SystemInstructionDto(listOf(PartDto(text = system))),
            contents = messages.map { msg ->
                val parts = buildList {
                    // Audio FIRST, text rides along as the ASR hint.
                    msg.inlineAudio?.let {
                        add(PartDto(inlineData = InlineDataDto(it.mimeType, it.base64Data)))
                    }
                    add(PartDto(text = msg.content))
                }
                ContentDto(msg.role.wire, parts)
            },
            generationConfig = GenerationConfigDto(
                // Gen-3: Google recommends DEFAULT sampling — sub-1.0 temperatures
                // can degrade or loop these models, so the caller's value is only
                // honored on the 2.5 family.
                temperature = if (model.isGen3) null else temperature,
                maxOutputTokens = maxTokens,
                // Latency floor for the phone-call loop: thinking OFF on 2.5, the
                // minimum "low" level on gen-3 (which can't fully disable).
                thinkingConfig = if (model.isGen3) ThinkingConfigDto(thinkingLevel = "low")
                else ThinkingConfigDto(thinkingBudget = 0),
                // Force JSON at the API level — prompt-only JSON drifts back to
                // prose in long conversations because the model imitates its own
                // (plain-text) turns in the history. Incompatible with grounding.
                responseMimeType = if (jsonResponse && !searchGrounding) "application/json" else null,
            ),
            tools = if (searchGrounding) listOf(ToolDto(EmptyObject())) else null,
            purpose = purpose,
            stream = if (stream) true else null,
        )

        val payload = Edge.json.encodeToString(BodyDto.serializer(), body)
        return Request.Builder()
            .url(Config.functionUrl("gemini"))
            .header("Authorization", "Bearer ${auth.accessToken()}")
            // A caller-supplied key makes retries of the SAME logical request
            // free — the ledger dedupes charges on it.
            .header("X-Idempotency-Key", idempotencyKey ?: UUID.randomUUID().toString())
            .post(payload.toRequestBody("application/json".toMediaType()))
            .build()
    }

    private fun validate(status: Int, body: ByteArray) {
        if (status in 200..299) return
        if (status == 402) throw EdgeError.InsufficientCredits
        throw EdgeError.Http(status, String(body).take(512))
    }
}
