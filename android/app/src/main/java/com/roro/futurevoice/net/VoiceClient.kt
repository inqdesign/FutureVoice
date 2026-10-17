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
 * Speech in the learner's voice (Cartesia) via the `tts` Edge Function.
 * The app never holds a provider key; voice settings
 * are fixed server-side (iOS `VoiceClient`).
 *
 * Wire contract: `docs/contracts/edge-api.md` §POST /tts.
 */
class VoiceClient(private val auth: AuthRepository) {

    companion object {
        private val CARTESIA = Regex(
            "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(:[a-z-]+)?$")

        /** A Cartesia voice id: a UUID, optionally carrying an accent
         *  ("<uuid>:british"). Every voice is one since 2026-10-15 (iOS
         *  `VoiceClient.isCartesiaVoice`). */
        fun isCartesiaVoice(id: String) = CARTESIA.matches(id)

        /**
         * The language a line is pinned to upstream (`language_code`), or null
         * to let the model guess as it always has (iOS `pinnedLanguage`,
         * `73f0faac`). Korean only: a learner of Korean who isn't Korean
         * recorded the clone in their own language, and in a blind test by a
         * native ear the pinned take was preferred — same model, same price.
         * Pinned only when the LINE is Korean too, so an English line read to
         * the same learner is never forced into Korean sounds. The edge
         * function forwards it only for turbo/flash; an older deploy drops it.
         */
        fun pinnedLanguage(text: String, activeLanguage: String?): String? {
            if (activeLanguage?.substringBefore('-') != "ko") return null
            if (!com.roro.futurevoice.data.TextScript.isInTargetScript(text, "ko")) return null
            return "ko"
        }

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
        val with_timestamps: Boolean = false,
        val stream: Boolean? = null,
        val purpose: String? = null,
        /** One key per SCENE — the server claims the scene count once on it. */
        val scene_key: String? = null,
        /** `voice_settings.speed` (0.7–1.2) — the learner's rung, see `SpeechSpeed`. */
        val speed: Double? = null,
        /** Pins the line's language upstream — Korean only ([pinnedLanguage]). */
        val language_code: String? = null,
        /** A Speech script's voiceover (iOS `synthesizeVoiceoverLine`): with
         *  `purpose: "script-voiceover"` the line is claimed against the
         *  reservation, never metered per character. */
        val voiceover_key: String? = null,
    )

    /** Buffered synthesis → MP3 bytes. */
    suspend fun synthesize(
        voiceId: String,
        text: String,
        idempotencyKey: String? = null,
        purpose: String? = null,
        sceneKey: String? = null,
        /** An explicit rung — the onboarding pills audition one before it is
         *  the setting. Null = the learner's current speed. */
        speed: Double? = null,
    ): ByteArray = withContext(Dispatchers.IO) {
        val request = buildRequest(
            voiceId, text, withTimestamps = false, stream = false,
            purpose = purpose, idempotencyKey = idempotencyKey, accept = "audio/mpeg",
            sceneKey = sceneKey, speed = speed,
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

    @Serializable
    private data class AlignmentDto(
        val characters: List<String> = emptyList(),
        val character_start_times_seconds: List<Double> = emptyList(),
        val character_end_times_seconds: List<Double> = emptyList(),
    )

    @Serializable
    private data class TimestampsResponse(
        val audio_base64: String,
        val alignment: AlignmentDto? = null,
        val normalized_alignment: AlignmentDto? = null,
    )

    /**
     * Same TTS through the `with-timestamps` endpoint: MP3 bytes plus one
     * MEASURED window per word (iOS `synthesizeWithTimestamps`). Used only
     * for the FIRST synthesis of a shadow line — the one place that line is
     * ever billed — so its karaoke and its rhythm grade stand on where the
     * synthesizer really put each word. Any failure of the timestamps path
     * falls back to plain audio under the same idempotency key (one logical
     * synthesis, one charge) with no timings.
     */
    suspend fun synthesizeWithTimestamps(
        voiceId: String,
        text: String,
        language: String,
        idempotencyKey: String? = null,
        purpose: String? = null,
    ): Pair<ByteArray, List<com.roro.futurevoice.talk.WordTiming>> = withContext(Dispatchers.IO) {
        val key = idempotencyKey ?: InstallSalt.ttsKey(text, voiceId, true)
        val viaTimestamps = runCatching {
            val request = buildRequest(
                voiceId, text, withTimestamps = true, stream = false,
                purpose = purpose, idempotencyKey = key, accept = "application/json",
            )
            Edge.client.newCall(request).execute().use { response ->
                val raw = response.body.string()
                if (response.code !in 200..299) {
                    if (response.code == 402) throw EdgeError.wall(raw)
                    throw EdgeError.Http(response.code, raw.take(512))
                }
                val decoded = Edge.json.decodeFromString(TimestampsResponse.serializer(), raw)
                val audio = android.util.Base64.decode(decoded.audio_base64, android.util.Base64.DEFAULT)
                // RAW alignment first, always: `normalized_alignment` indexes
                // the synthesizer's own normalized text, which romanizes Korean.
                val align = decoded.alignment ?: decoded.normalized_alignment
                val timings = align?.let {
                    com.roro.futurevoice.talk.TtsAlignment.wordTimings(
                        it.characters, it.character_start_times_seconds, it.character_end_times_seconds, language)
                }.orEmpty()
                audio to if (com.roro.futurevoice.talk.TtsAlignment.alignmentMatches(text, timings)) timings
                else emptyList()
            }
        }
        viaTimestamps.getOrElse { e ->
            // A wall is a wall on either endpoint — never retried as plain.
            if (e === EdgeError.InsufficientCredits || e === EdgeError.DailyCapReached ||
                e === EdgeError.SceneCapReached || e === EdgeError.FairUseLimit) throw e
            synthesize(voiceId, text, idempotencyKey = key, purpose = purpose) to emptyList()
        }
    }

    /**
     * One line of a Speech script's voiceover ("Hear it in my voice", iOS
     * `synthesizeVoiceoverLine`). Never metered per character: the edge
     * function claims it against the reservation [com.roro.futurevoice.data.ScriptVoiceoverCenter]
     * made, and the whole voiceover is charged once afterwards. Deliberately
     * WITHOUT the plain-synthesis fallback [synthesizeWithTimestamps] has —
     * that request would carry no key and be metered as an ordinary line.
     * Audio is MP3 (or WAV for a Cartesia voice); timings may be empty when
     * the alignment doesn't describe the text.
     */
    suspend fun synthesizeVoiceoverLine(
        voiceId: String, text: String, language: String, voiceoverKey: String, index: Int,
    ): Pair<ByteArray, List<com.roro.futurevoice.talk.WordTiming>> = withContext(Dispatchers.IO) {
        val request = buildRequest(
            voiceId, text, withTimestamps = true, stream = false,
            purpose = "script-voiceover", idempotencyKey = "$voiceoverKey:$index",
            accept = "application/json", voiceoverKey = voiceoverKey,
        )
        Edge.client.newCall(request).execute().use { response ->
            val raw = response.body.string()
            if (response.code !in 200..299) {
                if (response.code == 402) throw EdgeError.wall(raw)
                throw EdgeError.Http(response.code, raw.take(512))
            }
            val decoded = Edge.json.decodeFromString(TimestampsResponse.serializer(), raw)
            val audio = android.util.Base64.decode(decoded.audio_base64, android.util.Base64.DEFAULT)
            val align = decoded.alignment ?: decoded.normalized_alignment
            val timings = align?.let {
                com.roro.futurevoice.talk.TtsAlignment.wordTimings(
                    it.characters, it.character_start_times_seconds, it.character_end_times_seconds, language)
            }.orEmpty()
            audio to if (com.roro.futurevoice.talk.TtsAlignment.alignmentMatches(text, timings)) timings
            else emptyList()
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
        idempotencyKey: String? = null,
        purpose: String? = null,
        /** One key per SCENE (Watch) — the server claims the scene count once on it. */
        sceneKey: String? = null,
        onPcmChunk: suspend (ByteArray) -> Unit,
    ): StreamedAudio = withContext(Dispatchers.IO) {
        val request = buildRequest(
            voiceId, text, withTimestamps = false, stream = true,
            purpose = purpose, idempotencyKey = idempotencyKey, accept = null,
            sceneKey = sceneKey,
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
        withTimestamps: Boolean,
        stream: Boolean,
        purpose: String?,
        idempotencyKey: String?,
        accept: String?,
        sceneKey: String? = null,
        speed: Double? = null,
        voiceoverKey: String? = null,): Request {
        // A parked voice no longer exists upstream (see `VoiceParking`).
        // Refused before the network with the error every surface already
        // answers with its paywall; the revival happens at a launcher's tap.
        if (com.roro.futurevoice.data.VoiceParking.isParked(voiceId)) throw EdgeError.InsufficientCredits
        // A preset slot speaks in the target language's own voice (see
        // `VoicePreset.speaking`); the idempotency key below follows the voice
        // that actually speaks.
        val voiceId = com.roro.futurevoice.talk.VoicePreset.speaking(voiceId)
        val body = TtsBody(
            voice_id = voiceId,
            text = text,
            with_timestamps = withTimestamps,
            stream = if (stream) true else null,
            purpose = purpose,
            scene_key = sceneKey,
            speed = speed ?: com.roro.futurevoice.data.SpeechSpeed.currentMultiplier(),
            language_code = pinnedLanguage(text, com.roro.futurevoice.data.CoreVocabulary.activeLanguage()),
            voiceover_key = voiceoverKey,
        )
        val builder = Request.Builder()
            .url(Config.functionUrl("tts"))
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header(
                "X-Idempotency-Key",
                IdempotencyKey.headerSafe(idempotencyKey ?: InstallSalt.ttsKey(text, voiceId, withTimestamps)),
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
 * Separate from [VoiceClient] because it is a different shape of call —
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
        // A remix is built FROM the voice; a parked one no longer exists.
        if (com.roro.futurevoice.data.VoiceParking.isParked(voiceId)) throw EdgeError.InsufficientCredits
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
        /** `"default"` marks the remix made right after a clone (the accent
         *  picked in setup) — part of that clone, not the learner's one voice
         *  change (`_shared/voice-changes.ts`). */
        purpose: String? = null,
    ): String = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        val body = buildJsonObject {
            put("generated_voice_id", generatedVoiceId)
            put("voice_name", name)
            put("voice_description", voiceDescription)
            if (purpose != null) put("purpose", purpose)
        }
        Edge.json.decodeFromString(SavedResponse.serializer(), post(body.toString())).voice_id
    }

    private suspend fun post(json: String): String {
        val req = okhttp3.Request.Builder()
            .url(com.roro.futurevoice.core.Config.functionUrl("voice-remix"))
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("X-Idempotency-Key", java.util.UUID.randomUUID().toString())
            .post(json.toRequestBody("application/json".toMediaType()))
            .build()
        return slowClient.newCall(req).execute().use { resp ->
            val raw = resp.body.string()
            com.roro.futurevoice.data.VoiceChangeLimit.from(resp.code, raw)?.let { throw it }
            // The month's voices are spent: a date in the app language, never
            // the raw JSON (iOS `VoiceQuota.pausedLine`).
            if (resp.code !in 200..299) com.roro.futurevoice.data.VoiceQuotaFull.from(raw)?.let { throw it }
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, raw.take(512))
            raw
        }
    }
}
