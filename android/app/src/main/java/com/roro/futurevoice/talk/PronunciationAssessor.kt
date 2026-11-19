package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.PronunciationProfile
import com.roro.futurevoice.data.WordSplitter
import com.roro.futurevoice.net.Edge
import com.roro.futurevoice.net.IdempotencyKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import okhttp3.ConnectionPool
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * How the learner PRONOUNCED a take — per phoneme, against a native model —
 * from the `pronunciation` edge function (Azure Speech, scripted assessment).
 * Port of iOS `PronunciationAssessor.swift` (0971c05d, fede7981, 247383e9,
 * 14706881); the on-disk shape is iOS's, so a record crosses a backup.
 *
 * Every other speaking score in the app is a transcript compared with the
 * target, and a transcriber writes the word the learner was reaching for —
 * an intelligible accent scored 100. This is the one reader that hears the
 * SOUNDS, and it is an UPGRADE on every surface that uses it, never a
 * requirement: a null leaves the take scored exactly as before.
 *
 * NOT part of `ShadowAttempt.overallScore` or `SpeechMetrics.overall` (yet).
 */
@Serializable
data class PronunciationResult(
    /** Azure's `PronScore`, 0–100. */
    val score: Int,
    /** How closely the phonemes matched a native speaker's, 0–100. */
    val accuracy: Int,
    val fluency: Int,
    val completeness: Int? = null,
    /** Assessed for en-US only; null everywhere else. */
    val prosody: Int? = null,
    val locale: String = "",
    val recognized: String = "",
    val words: List<Word> = emptyList(),
    /** The same take read against the sentence with the lesson's sound
     *  swapped ([PronunciationContrast]). null unless the app asked. */
    val alternates: List<Alternate>? = null,
) {
    @Serializable
    data class Alternate(val reference: String, val words: List<Scored> = emptyList()) {
        @Serializable data class Scored(val word: String, val accuracy: Int? = null, val error: String = "None")
    }

    @Serializable
    data class Word(
        val word: String,
        /** Null for a word Azure never heard (an Omission). */
        val accuracy: Int? = null,
        /** "None" · "Mispronunciation" · "Omission" · "Insertion" · … */
        val error: String = "None",
        val offsetMs: Int = 0,
        val durationMs: Int = 0,
        val phonemes: List<Phoneme> = emptyList(),
    ) {
        val isInsertion: Boolean get() = error == "Insertion"
        val isOmission: Boolean get() = error == "Omission"
        /** A word whose SOUNDS were heard and scored — an Omission or an
         *  Insertion says nothing about how a sound was made (an omitted "a"
         *  was shown red as mispronounced, iOS 14706881). */
        val isJudged: Boolean get() = !isOmission && !isInsertion
        /** The weakest SOUND in the word — the accent lives in the phonemes
         *  (a Korean-accented "think" scored 94 as a word with θ at 32). */
        val worstPhoneme: Int? get() = phonemes.mapNotNull { it.accuracy }.minOrNull()
        /** Red: a word under 50 or a sound under 35. Orange: a word under 70
         *  or a sound under 45 (from the probe; a native slip reads orange
         *  at worst, never red). */
        val isMispronounced: Boolean get() =
            isJudged && ((accuracy ?: 100) < 50 || (worstPhoneme ?: 100) < 35)
        val isShaky: Boolean get() =
            isJudged && !isMispronounced && ((accuracy ?: 100) < 70 || (worstPhoneme ?: 100) < 45)
        /** The sounds that let the word down, worst first. Phonemes are named
         *  (IPA) for English only; an empty name is kept out of anything shown. */
        val weakPhonemes: List<Phoneme> get() =
            phonemes.filter { it.phoneme.isNotEmpty() && (it.accuracy ?: 100) < 60 }
                .sortedBy { it.accuracy ?: 0 }
    }

    @Serializable
    data class Phoneme(
        val phoneme: String,
        val accuracy: Int? = null,
        /** What Azure heard this sound AS, best first (en-US only, iOS
         *  ffaf0c58): "f" with p at 100 here is an f that came out as p. */
        val heard: List<Candidate>? = null,
    ) {
        @Serializable data class Candidate(val phoneme: String, val score: Int)
    }

    /** Reference words only, in reference order. */
    val referenceWords: List<Word> get() = words.filter { !it.isInsertion }
    /** The words whose sounds were actually scored. */
    val judgedWords: List<Word> get() = words.filter { it.isJudged }

    /** THE pronunciation number everywhere it is shown or kept: Azure's
     *  accuracy (the sounds), never `score`, which folds in fluency and
     *  completeness — measured elsewhere in the app. */
    val soundScore: Int get() = accuracy

    /** Phoneme samples with a NAME (en-US only), over the judged words. */
    val namedPhonemes: List<Phoneme> get() =
        judgedWords.flatMap { it.phonemes }.filter { it.phoneme.isNotEmpty() && it.accuracy != null }

    /** The words worth telling the learner about, worst first. */
    val weakWords: List<Word> get() =
        referenceWords.filter { it.isMispronounced || it.isShaky }.sortedBy { it.accuracy ?: 0 }

    companion object {
        /** A word's mark as the beat's colour scale: 0 red · 1 orange · 2 fine. */
        fun grade(word: Word): Int = if (word.isMispronounced) 0 else if (word.isShaky) 1 else 2
    }
}

object PronunciationAssessor {

    /** The REST endpoint assesses up to ~30 s; a longer take is the caller's to cut. */
    const val MAX_SECONDS = 30.0
    /** 16 kHz mono PCM16 — 32,000 bytes a second, plus the header. */
    const val MAX_WAV_BYTES = 44 + 30 * 32_000

    enum class Outcome(val raw: String) {
        SCORED("scored"), SILENT("silent"), UNCONFIGURED("unconfigured"),
        CAPPED("capped"), FAILED("failed"), SKIPPED("skipped"),
    }

    data class Answer(val result: PronunciationResult?, val outcome: Outcome)

    @Serializable
    private data class Body(
        val audio_b64: String,
        val language: String,
        val reference: String,
        val accent: String? = null,
        val surface: String,
        /** null (left out of the body) when there are none. */
        val alternates: List<String>? = null,
    )

    @Serializable
    private data class Wire(
        val locale: String? = null,
        val score: Int? = null,
        val accuracy: Int? = null,
        val fluency: Int? = null,
        val completeness: Int? = null,
        val prosody: Int? = null,
        val recognized: String? = null,
        val words: List<W>? = null,
        val alternates: List<A>? = null,
    ) {
        @Serializable data class A(val reference: String, val words: List<AW>? = null)
        @Serializable data class AW(val word: String, val accuracy: Int? = null, val error: String? = null)
        @Serializable data class W(
            val word: String,
            val accuracy: Int? = null,
            val error: String? = null,
            val offset_ms: Int? = null,
            val duration_ms: Int? = null,
            val phonemes: List<P>? = null,
        )
        @Serializable data class P(val phoneme: String, val accuracy: Int? = null,
                                   val heard: List<PronunciationResult.Phoneme.Candidate>? = null)
    }

    /** Its own connection pool: the take's base64 must not sit in front of
     *  the transcribe call it runs beside (iOS `edgeFunctionsBackground`). */
    private val client: OkHttpClient by lazy {
        Edge.client.newBuilder().connectionPool(ConnectionPool()).build()
    }

    private fun code(language: String): String =
        LanguageCatalog.targets.firstOrNull { it.code == language }?.code ?: language

    /**
     * Score [wav] (16 kHz mono PCM16, ≤ [MAX_SECONDS]) against [reference].
     * A null result on any failure — the take is scored by words as before.
     */
    suspend fun assess(
        context: Context,
        wav: ByteArray,
        reference: String,
        language: String,
        surface: String,
        timeoutMs: Long = 15_000,
        alternates: List<String> = emptyList(),
    ): Answer = withContext(Dispatchers.IO) {
        val ref = reference.trim()
        if (ref.isEmpty() || wav.size <= 1_000 || wav.size > MAX_WAV_BYTES || !supports(language)) {
            return@withContext Answer(null, Outcome.SKIPPED)
        }
        val code = code(language)
        // English is judged by en-US whatever the voice's accent: en-GB/en-AU
        // score words only, no sounds. Sent as null here too, so a server a
        // deploy behind still lands on en-US.
        val accent = if (code == "en") null else
            context.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)
                .getString("futurevoice.voiceAccentId", null)
        val body = Body(
            audio_b64 = android.util.Base64.encodeToString(wav, android.util.Base64.NO_WRAP),
            language = code, reference = ref, accent = accent, surface = surface,
            alternates = alternates.ifEmpty { null },
        )
        runCatching {
            val token = AuthRepository().accessToken()
            val request = Request.Builder()
                .url(Config.functionUrl("pronunciation"))
                .header("Authorization", "Bearer $token")
                .header("X-Idempotency-Key", IdempotencyKey.headerSafe(UUID.randomUUID().toString().uppercase()))
                .post(Edge.json.encodeToString(Body.serializer(), body)
                    .toRequestBody("application/json".toMediaType()))
                .build()
            val call = client.newCall(request)
            call.timeout().timeout(timeoutMs, TimeUnit.MILLISECONDS)
            // Cancellable: a caller that stops waiting (the shadow read's
            // grace) must take the request down with it, not sit on it.
            awaitResponse(call).use { response ->
                when (response.code) {
                    200 -> Unit
                    204 -> return@runCatching Answer(null, Outcome.SILENT)
                    429 -> return@runCatching Answer(null, Outcome.CAPPED)
                    503 -> return@runCatching Answer(null, Outcome.UNCONFIGURED)
                    else -> return@runCatching Answer(null, Outcome.FAILED)
                }
                val wire = Edge.json.decodeFromString(Wire.serializer(), response.body?.string().orEmpty())
                val score = wire.score; val accuracy = wire.accuracy; val fluency = wire.fluency
                if (score == null || accuracy == null || fluency == null) return@runCatching Answer(null, Outcome.FAILED)
                Answer(PronunciationResult(
                    score = score, accuracy = accuracy, fluency = fluency,
                    completeness = wire.completeness, prosody = wire.prosody,
                    locale = wire.locale.orEmpty(), recognized = wire.recognized.orEmpty(),
                    words = wire.words.orEmpty().map { w ->
                        PronunciationResult.Word(
                            word = w.word, accuracy = w.accuracy, error = w.error ?: "None",
                            offsetMs = w.offset_ms ?: 0, durationMs = w.duration_ms ?: 0,
                            phonemes = w.phonemes.orEmpty().map { PronunciationResult.Phoneme(it.phoneme, it.accuracy, it.heard) })
                    },
                    alternates = wire.alternates?.map { a ->
                        PronunciationResult.Alternate(a.reference, a.words.orEmpty().map {
                            PronunciationResult.Alternate.Scored(it.word, it.accuracy, it.error ?: "None")
                        })
                    },
                ), Outcome.SCORED)
            }
        }.getOrElse { if (it is kotlinx.coroutines.CancellationException) throw it; Answer(null, Outcome.FAILED) }
    }

    private suspend fun awaitResponse(call: okhttp3.Call): okhttp3.Response =
        kotlinx.coroutines.suspendCancellableCoroutine { cont ->
            cont.invokeOnCancellation { call.cancel() }
            call.enqueue(object : okhttp3.Callback {
                override fun onFailure(call: okhttp3.Call, e: java.io.IOException) {
                    if (cont.isActive) cont.resumeWith(Result.failure(e))
                }
                override fun onResponse(call: okhttp3.Call, response: okhttp3.Response) {
                    if (cont.isActive) cont.resumeWith(Result.success(response)) else response.close()
                }
            })
        }

    /** Reads the WAV file (as 16 kHz mono) and assesses it. */
    suspend fun assess(
        context: Context, audio: File, reference: String, language: String,
        surface: String, timeoutMs: Long = 15_000, alternates: List<String> = emptyList(),
    ): Answer {
        val wav = withContext(Dispatchers.IO) { wav16kMono(audio) } ?: return Answer(null, Outcome.SKIPPED)
        return assess(context, wav, reference, language, surface, timeoutMs, alternates)
    }

    /** A canonical 44-byte-header 16 kHz mono PCM16 WAV of the file
     *  (iOS `AudioLoudness.wav16kMono`). The app records at 16 kHz already;
     *  anything else is resampled linearly. */
    fun wav16kMono(file: File): ByteArray? {
        val pcm = WavPcm.read(file) ?: return null
        if (pcm.samples.isEmpty()) return null
        if (pcm.sampleRate == 16_000) return WavPcm.wav(pcm.samples, 16_000)
        val ratio = pcm.sampleRate.toDouble() / 16_000
        val n = (pcm.samples.size / ratio).toInt()
        val out = ShortArray(n) { i ->
            val x = i * ratio
            val a = x.toInt().coerceAtMost(pcm.samples.lastIndex)
            val b = (a + 1).coerceAtMost(pcm.samples.lastIndex)
            val f = x - a
            (pcm.samples[a] * (1 - f) + pcm.samples[b] * f).toInt().toShort()
        }
        return WavPcm.wav(out, 16_000)
    }

    /** A 44-byte-header WAV of raw PCM16 bytes (iOS `AudioLoudness.wavData`). */
    fun wavData(pcm: ByteArray, sampleRate: Int): ByteArray {
        val out = ByteBuffer.allocate(44 + pcm.size).order(ByteOrder.LITTLE_ENDIAN)
        out.put("RIFF".toByteArray()); out.putInt(36 + pcm.size); out.put("WAVE".toByteArray())
        out.put("fmt ".toByteArray()); out.putInt(16); out.putShort(1); out.putShort(1)
        out.putInt(sampleRate); out.putInt(sampleRate * 2); out.putShort(2); out.putShort(16)
        out.put("data".toByteArray()); out.putInt(pcm.size)
        out.put(pcm)
        return out.array()
    }

    /**
     * A 16 kHz mono PCM16 WAV (44-byte header) cut into windows the endpoint
     * can take: about [target] seconds each, cut at the quietest 50 ms in a
     * window's last third so a word is never split, and a remainder under
     * 28 s kept whole so no window is a stub. For a long take read as ONE
     * file (iOS 247383e9).
     */
    fun windows(wav: ByteArray, target: Double = 20.0): List<ByteArray> {
        val header = 44
        val rate = 16_000
        if (wav.size <= header + 2) return emptyList()
        val pcm = wav.copyOfRange(header, wav.size)
        val total = pcm.size / 2
        val s = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val window = (target * rate).toInt()
        val keepWhole = 28 * rate
        val block = rate / 20
        fun energy(from: Int): Long {
            var e = 0L
            for (i in from until minOf(from + block, total)) { val v = s.get(i).toLong(); e += v * v }
            return e
        }
        val cuts = ArrayList<IntRange>()
        var start = 0
        while (start < total) {
            var end = total
            if (total - start > keepWhole) {
                end = start + window
                var best = end
                var bestEnergy = Long.MAX_VALUE
                var i = start + window * 2 / 3
                while (i + block <= start + window) {
                    val e = energy(i)
                    if (e < bestEnergy) { bestEnergy = e; best = i + block / 2 }
                    i += block
                }
                end = best
            }
            cuts += start until end
            start = end
        }
        return cuts.map { wavData(pcm.copyOfRange(it.first * 2, (it.last + 1) * 2), rate) }
    }

    /** Every target language the app ships has a GA Azure locale. */
    fun supports(language: String): Boolean = code(language) in setOf("en", "de", "ja", "ko", "es", "fr", "zh")

    // MARK: - Placing the verdict on a target line

    /**
     * The result's reference words mapped onto the target line's own words:
     * target index → the Azure word. Aligned by edit distance; nothing when
     * fewer than half the words anchor (a mark on the wrong word is worse
     * than none). Unspaced languages are not mapped.
     */
    fun wordMarks(result: PronunciationResult, targetWords: List<String>, language: String):
        Map<Int, PronunciationResult.Word> {
        if (!WordSplitter.spaced(language) || targetWords.isEmpty()) return emptyMap()
        val reference = result.referenceWords
        if (reference.isEmpty()) return emptyMap()
        val pairing = LocalAlignment.align(
            targetWords.map { LocalAlignment.normalized(it) },
            reference.map { LocalAlignment.normalized(it.word) })
        val anchored = pairing.count { it != null }
        if (anchored.toDouble() / targetWords.size < 0.5) return emptyMap()
        val out = HashMap<Int, PronunciationResult.Word>()
        pairing.forEachIndexed { i, j -> if (j != null && j in reference.indices) out[i] = reference[j] }
        return out
    }
}

/**
 * The pronunciation axis as a READ over recent takes, for the scorecard: a
 * talk's transcript cannot judge sounds, so the row shows what every assessed
 * take measured in the last month (`PronunciationLedger`). Computed where it
 * is shown, never stored on a talk (iOS `PronunciationRead`).
 */
object PronunciationRead {
    const val WINDOW_DAYS = 30
    /** Fewer takes than this and one bad morning IS the number. */
    const val MIN_TAKES = 3

    fun recentAxis(context: Context, now: Long = System.currentTimeMillis(),
                   language: String = LanguageScope.active(context)): AxisScore? {
        val profile = PronunciationProfile.current(context, language, now)
        val mean = profile.meanAccuracy
        if (profile.takes < MIN_TAKES || mean == null) return null
        var note = context.getString(R.string.measured_per_sound_over_lld_recent_takes, profile.takes)
        val weak = profile.weakSounds.take(3)
        if (weak.isNotEmpty()) {
            note += " " + context.getString(R.string.sounds_to_work_on,
                weak.joinToString(" · ") { "${it.phoneme} ${it.mean}" })
        }
        return AxisScore(mean, note)
    }
}
