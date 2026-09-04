package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.core.InstallSalt
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import okhttp3.MediaType.Companion.toMediaType
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * ElevenLabs via the `elevenlabs-tts` Edge Function. The app never holds an
 * ElevenLabs key; voice settings are fixed server-side.
 *
 * Wire contract: `docs/contracts/edge-api.md` §POST /elevenlabs-tts.
 */
class ElevenLabsClient(private val auth: AuthRepository) {

    companion object {
        /**
         * Live Talk turns. Flash was tried here and reverted: same price per
         * character, but it buys latency by cutting speaker similarity — on the
         * surface where users hear their own clone most. Speaker similarity IS
         * the product.
         */
        const val CONVERSATION_MODEL_ID = "eleven_turbo_v2_5"

        /**
         * Fidelity tier — Watch scenes and the onboarding greeting. Bills ~2x
         * per character upstream while pricing here is model-BLIND, so that 2x
         * is pure margin absorbed. Only for CACHED lines or once-per-user paths.
         * NEVER for live turns.
         */
        const val FIDELITY_MODEL_ID = "eleven_multilingual_v2"

        /** Server streams 16-bit LE mono PCM at this rate. */
        const val STREAM_SAMPLE_RATE = 22_050
    }

    /**
     * `PCM22050` — the server streamed raw PCM and `onPcmChunk` already
     * delivered it; the payload is the FULL accumulated PCM for caching.
     * `MP3` — an older deploy without streaming support; the payload is the
     * fully-buffered MP3 and `onPcmChunk` was never called.
     */
    sealed class StreamedAudio {
        class Pcm22050(val data: ByteArray) : StreamedAudio()
        class Mp3(val data: ByteArray) : StreamedAudio()
    }

    @Serializable
    private data class TtsBody(
        val voice_id: String,
        val text: String,
        val model_id: String,
        val with_timestamps: Boolean = false,
        val stream: Boolean? = null,
        val purpose: String? = null,
        /** One key per SCENE — the server claims the scene count once on it. */
        val scene_key: String? = null,
    )

    /** Buffered synthesis → MP3 bytes. */
    suspend fun synthesize(
        voiceId: String,
        text: String,
        modelId: String = CONVERSATION_MODEL_ID,
        idempotencyKey: String? = null,
        purpose: String? = null,
        sceneKey: String? = null,
    ): ByteArray = withContext(Dispatchers.IO) {
        val request = buildRequest(
            voiceId, text, modelId, withTimestamps = false, stream = false,
            purpose = purpose, idempotencyKey = idempotencyKey, accept = "audio/mpeg",
            sceneKey = sceneKey,
        )
        Edge.client.newCall(request).execute().use { response ->
            val bytes = response.body.bytes()
            if (response.code !in 200..299) {
                if (response.code == 402) throw EdgeError.wall(String(bytes))
                throw EdgeError.Http(response.code, String(bytes).take(512))
            }
            bytes
        }
    }

    /**
     * Streaming TTS: playback starts on the first chunk instead of after the
     * full file. Chunks arrive in order via [onPcmChunk] — 16-bit LE mono PCM
     * at 22.05 kHz, ~8 KB each (~0.18 s).
     */
    suspend fun synthesizeStreaming(
        voiceId: String,
        text: String,
        modelId: String = CONVERSATION_MODEL_ID,
        idempotencyKey: String? = null,
        purpose: String? = null,
        onPcmChunk: suspend (ByteArray) -> Unit,
    ): StreamedAudio = withContext(Dispatchers.IO) {
        val request = buildRequest(
            voiceId, text, modelId, withTimestamps = false, stream = true,
            purpose = purpose, idempotencyKey = idempotencyKey, accept = null,
        )

        // One immediate re-dial on a transient connect failure: a cellular blip
        // at stream OPEN otherwise cascades into the buffered fallback, which
        // doubles perceived latency for the turn.
        val response = try {
            Edge.client.newCall(request).execute()
        } catch (e: java.io.IOException) {
            Edge.client.newCall(request).execute()
        }

        response.use { resp ->
            if (resp.code !in 200..299) {
                val snippet = runCatching { resp.body.source().readByteString(512L) }
                    .getOrNull()?.utf8().orEmpty()
                if (resp.code == 402) throw EdgeError.wall(snippet)
                throw EdgeError.Http(resp.code, snippet)
            }

            // The PCM header is the protocol handshake: without it we're talking
            // to a deploy that ignored `stream` and returned a whole MP3.
            if (resp.header("X-Audio-Format") != "pcm_22050") {
                return@withContext StreamedAudio.Mp3(resp.body.bytes())
            }

            val source = resp.body.source()
            val full = okio.Buffer()
            val pending = okio.Buffer()
            // ~8 KB = ~0.18s at 22.05 kHz s16 mono: small enough for a fast
            // start, big enough to keep scheduling overhead trivial.
            val flushSize = 8 * 1024L

            while (true) {
                val read = source.read(pending, flushSize)
                if (read == -1L) break
                if (pending.size >= flushSize) {
                    // Keep sample alignment: never split an Int16 across flushes.
                    val even = pending.size - (pending.size % 2)
                    val out = pending.readByteArray(even)
                    full.write(out)
                    onPcmChunk(out)
                }
            }
            if (pending.size > 0) {
                val even = pending.size - (pending.size % 2)
                if (even > 0) {
                    val out = pending.readByteArray(even)
                    full.write(out)
                    onPcmChunk(out)
                }
            }
            StreamedAudio.Pcm22050(full.readByteArray())
        }
    }

    private suspend fun buildRequest(
        voiceId: String,
        text: String,
        modelId: String,
        withTimestamps: Boolean,
        stream: Boolean,
        purpose: String?,
        idempotencyKey: String?,
        accept: String?,
        sceneKey: String? = null,): Request {
        val body = TtsBody(
            voice_id = voiceId,
            text = text,
            model_id = modelId,
            with_timestamps = withTimestamps,
            stream = if (stream) true else null,
            purpose = purpose,
            scene_key = sceneKey,
        )
        val builder = Request.Builder()
            .url(Config.functionUrl("elevenlabs-tts"))
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header(
                "X-Idempotency-Key",
                idempotencyKey ?: InstallSalt.ttsKey(text, voiceId, withTimestamps),
            )
            .post(
                Edge.json.encodeToString(TtsBody.serializer(), body)
                    .toRequestBody("application/json".toMediaType())
            )
        if (accept != null) builder.header("Accept", accept)
        return builder.build()
    }
}

/**
 * Accent remixing: audition a few takes of the learner's OWN clone speaking
 * with an instructed accent, then promote the one they keep.
 *
 * Separate from [ElevenLabsClient] because it is a different shape of call —
 * preview generation runs tens of seconds upstream and comes back as a few MB
 * of base64 audio, so it needs its own roomier timeout rather than the call
 * loop's.
 */
class VoiceRemixClient(private val auth: com.roro.futurevoice.data.AuthRepository) {

    data class Preview(val id: String, val audio: ByteArray)

    @kotlinx.serialization.Serializable
    private data class PreviewRow(
        val generated_voice_id: String = "",
        val audio_base_64: String = "",
    )

    @kotlinx.serialization.Serializable
    private data class PreviewsResponse(val previews: List<PreviewRow> = emptyList())

    @kotlinx.serialization.Serializable
    private data class SavedResponse(val voice_id: String = "")

    private val slowClient = Edge.client.newBuilder()
        .readTimeout(180, java.util.concurrent.TimeUnit.SECONDS)
        .callTimeout(240, java.util.concurrent.TimeUnit.SECONDS)
        .build()

    /**
     * Generate accent-remix previews of an existing clone. Same person,
     * instructed accent — see [com.roro.futurevoice.data.VoiceAccentCatalog]
     * for the descriptions. [text] is what the previews speak (upstream wants
     * 100–1000 chars).
     */
    suspend fun previews(
        voiceId: String, voiceDescription: String, text: String,
    ): List<Preview> = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        val body = buildJsonObject {
            put("voice_id", voiceId)
            put("voice_description", voiceDescription)
            put("text", text)
        }
        val raw = post(body.toString())
        Edge.json.decodeFromString(PreviewsResponse.serializer(), raw).previews.mapNotNull { p ->
            runCatching {
                Preview(p.generated_voice_id, android.util.Base64.decode(p.audio_base_64, 0))
            }.getOrNull()
        }
    }

    /**
     * Promote the picked preview into a permanent voice and return its id.
     * The edge function mirrors the new id into `voice_clones`, so the
     * swap-and-delete machinery treats it exactly like a re-record.
     */
    suspend fun save(
        generatedVoiceId: String, name: String, voiceDescription: String,
    ): String = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        val body = buildJsonObject {
            put("generated_voice_id", generatedVoiceId)
            put("voice_name", name)
            put("voice_description", voiceDescription)
        }
        Edge.json.decodeFromString(SavedResponse.serializer(), post(body.toString())).voice_id
    }

    private suspend fun post(json: String): String {
        val req = okhttp3.Request.Builder()
            .url(com.roro.futurevoice.core.Config.functionUrl("elevenlabs-voice-remix"))
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("X-Idempotency-Key", java.util.UUID.randomUUID().toString())
            .post(json.toRequestBody("application/json".toMediaType()))
            .build()
        return slowClient.newCall(req).execute().use { resp ->
            val raw = resp.body.string()
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, raw.take(512))
            raw
        }
    }
}
