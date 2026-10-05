package com.roro.futurevoice.net

import android.util.Base64
import com.roro.futurevoice.audio.AacEncoder
import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.SpeechCoaching
import com.roro.futurevoice.data.SpeechGenre
import com.roro.futurevoice.data.SpeechKeyTerm
import com.roro.futurevoice.data.SpeechMetrics
import com.roro.futurevoice.data.SpeechScript
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.talk.SpeechPrompts
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.io.File

/**
 * The words of a speech take, from the audio — iOS `SpeechReader`. Same rule
 * as the shadow reader: never shown the script (a word it supplies is a mark
 * the speaker did not earn). Unlike the shadow reader it WRITES fillers down,
 * because counting them is part of the grade.
 */
object SpeechReader {
    data class Reading(val text: String, val audioGrounded: Boolean)

    @Serializable private data class Payload(val transcript: String? = null)

    private fun gemini() = GeminiClient(AuthRepository())

    /** The whole take (AAC). Falls back to the live recognizer's text. */
    suspend fun read(wav: File, liveText: String, language: String): Reading = withContext(Dispatchers.IO) {
        val pcm = WavPcm.read(wav) ?: return@withContext Reading(liveText, false)
        val aac = AacEncoder.adts(pcm)
        if (aac == null || aac.isEmpty() || aac.size > 1_800_000) return@withContext Reading(liveText, false)
        val text = runCatching {
            withTimeout(60_000) { call(aac, "audio/aac", language, maxTokens = 4096) }
        }.getOrNull().orEmpty()
        if (text.isEmpty()) Reading(liveText, false) else Reading(text, true)
    }

    /** One piece read while the rest is still spoken: "" = no speech in it,
     *  null = the read FAILED (the caller reads the whole take instead). */
    suspend fun readPiece(wav: File, language: String): String? = withContext(Dispatchers.IO) {
        val pcm = WavPcm.read(wav) ?: return@withContext null
        // AAC when the encoder obliges; the WAV itself (what the shadow reader
        // sends) otherwise.
        val aac = AacEncoder.adts(pcm)
        val (bytes, mime) = if (aac != null && aac.isNotEmpty()) aac to "audio/aac"
            else wav.readBytes() to "audio/wav"
        if (bytes.size > 1_200_000) return@withContext null
        runCatching { withTimeout(25_000) { call(bytes, mime, language, maxTokens = 1024) } }.getOrNull()
    }

    private suspend fun call(bytes: ByteArray, mime: String, language: String, maxTokens: Int): String =
        gemini().sendJson(
            system = SpeechPrompts.reader(language),
            messages = listOf(GeminiClient.Message(
                role = GeminiClient.Message.Role.USER,
                content = "Transcribe the attached audio.",
                inlineAudio = GeminiClient.InlineAudio(mime, Base64.encodeToString(bytes, Base64.NO_WRAP)))),
            serializer = Payload.serializer(),
            maxTokens = maxTokens,
            purpose = "transcribe",
            fastThinking = true,
        ).transcript?.trim().orEmpty()
}

/** Two or three lines of coaching in the NATIVE language, anchored to the
 *  numbers `SpeechAnalyzer` computed — iOS `SpeechCoach`. */
object SpeechCoach {
    @Serializable private data class Payload(val headline: String? = null, val tips: List<String>? = null)

    suspend fun review(script: SpeechScript, transcript: String, metrics: SpeechMetrics,
                       native: String, level: CefrLevel): SpeechCoaching? = runCatching {
        val p = GeminiClient(AuthRepository()).sendJson(
            system = SpeechPrompts.coachSystem(script, metrics, native, level),
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER,
                SpeechPrompts.coachUser(script, transcript, metrics))),
            serializer = Payload.serializer(),
            maxTokens = 900,
            purpose = "speech-review",
        )
        val headline = p.headline?.trim().orEmpty()
        if (headline.isEmpty()) null
        else SpeechCoaching(headline, p.tips.orEmpty().map { it.trim() }.filter { it.isNotEmpty() }.take(3))
    }.getOrNull()
}

/** Writes a script to be READ ALOUD like a presenter — iOS
 *  `SpeechScriptEngine`. Search-grounded: a made-up figure is worse here than
 *  anywhere, because the learner says it out loud as fact. */
object SpeechScriptEngine {
    class WriteError : Exception("empty script")

    @Serializable private data class Term(val term: String? = null, val meaning: String? = null)
    @Serializable private data class Payload(
        val title: String? = null,
        val body: String? = null,
        val summary: String? = null,
        @SerialName("key_terms") val keyTerms: List<Term>? = null,
        val sources: List<String>? = null,
    )

    suspend fun write(genre: SpeechGenre, topic: String, seconds: Int, language: String,
                      native: String, level: CefrLevel, avoidTitles: List<String>): SpeechScript {
        // The streaming door only for its long read timeout: a grounded
        // write can sit past the shared client's 40 s guard (iOS gives 90 s).
        val p = GeminiClient(AuthRepository()).sendJsonStreamAccumulating(
            system = SpeechPrompts.writerSystem(genre, seconds, language, native, level),
            messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER,
                SpeechPrompts.writerUser(topic, avoidTitles))),
            serializer = Payload.serializer(),
            maxTokens = 4096,
            searchGrounding = true,
            purpose = "speech-script",
            onPartial = {},
        )
        val body = p.body?.trim().orEmpty()
        val title = p.title?.trim().orEmpty()
        if (body.isEmpty() || title.isEmpty()) throw WriteError()
        val terms = p.keyTerms.orEmpty().mapNotNull { t ->
            val term = t.term?.trim().orEmpty()
            if (term.isEmpty() || !body.contains(term, ignoreCase = true)) null
            else SpeechKeyTerm(term, t.meaning?.trim().orEmpty())
        }
        return SpeechScript(
            id = StoreJson.newId(), title = title, genre = genre, topic = topic, body = body,
            summary = p.summary?.trim().orEmpty(), keyTerms = terms,
            sources = p.sources.orEmpty().map { it.trim() }.filter { it.isNotEmpty() },
            language = language.substringBefore('-'), targetSeconds = seconds,
            createdAt = System.currentTimeMillis(), isBuiltIn = false,
        )
    }
}
