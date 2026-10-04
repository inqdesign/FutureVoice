package com.roro.futurevoice.talk

import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.ElevenLabsClient
import kotlinx.coroutines.ensureActive
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.regex.Pattern
import kotlin.coroutines.coroutineContext
import kotlin.math.sqrt

/**
 * A line of more than one sentence, synthesized so the voice BREATHES between
 * them (iOS `PacedSpeech`, `9f81572`, 2026-09-30).
 *
 * Reported: "the fluent self doesn't stop between sentences, especially in
 * Korean". Measured on the founder's clone in ko/en/ja/de: ElevenLabs puts
 * 0.08–0.29 s between sentences it is given in one text, against the
 * 0.5–0.8 s people leave. The live call was fixed in the gateway by sending
 * one sentence per generation; this is the same result for the lines the APP
 * synthesizes whole — on Android, the call's cached opener (the voicemail is
 * spoken by the gateway, which already paces it).
 *
 * Splitting alone does not reproduce it over HTTP: `previous_text` /
 * `next_text` conditioning glues the pieces back together, and without it
 * every clip carries its own 0–0.43 s of edge silence. So each sentence is
 * synthesized as PCM, its INNER edges are trimmed to the voice, and one fixed
 * gap goes between. New audio only — nothing already cached is re-made.
 */
object PacedSpeech {
    /** Silence between two sentences, voice to voice. */
    const val SENTENCE_GAP_SECONDS = 0.42

    /** Kept either side of a trimmed edge so a soft onset or a fading
     *  syllable is never clipped. */
    const val EDGE_MARGIN_SECONDS = 0.03

    /**
     * Where a sentence ends — the gateway's rule, kept identical
     * (`CallSession.sentenceEnd`): a terminator followed by whitespace; the
     * CJK full stops, which take no space, before the next character; never
     * after a title abbreviation or inside a quote closed by と/って.
     */
    private val sentenceEnd: Pattern = Pattern.compile(
        """(?<!\b(?:Mr|Mrs|Ms|Dr|St|Prof|Nr|vs|etc|ca|bzw|e\.g|i\.e|z\.B))[.!?…][)"'”’」』]*\s+|[。！？](?:[)"'”’」』]*\s+|(?=[^)"'”’」』\s])|[)"'”’」』]+(?=[^\sとっ)"'”’」』]))""",
        Pattern.UNICODE_CHARACTER_CLASS,
    )

    /** The sentences of `text`, trimmed, empty ones dropped. */
    fun sentences(text: String): List<String> {
        val out = mutableListOf<String>()
        val m = sentenceEnd.matcher(text)
        var start = 0
        while (m.find()) {
            out.add(text.substring(start, m.end()))
            start = m.end()
        }
        out.add(text.substring(start))
        return out.map { it.trim() }.filter { it.isNotEmpty() }
    }

    /**
     * Synthesize `text` sentence by sentence and join the takes with
     * [SENTENCE_GAP_SECONDS] between them, as a WAV. Null when the text is a
     * single sentence (the caller's ordinary path is already right) or the
     * server answered in MP3 (an edge deploy with no streaming — nothing to
     * join; the caller falls back).
     */
    suspend fun synthesizeWav(voiceId: String, text: String, modelId: String, purpose: String): ByteArray? {
        val parts = sentences(text)
        if (parts.size <= 1) return null
        val client = ElevenLabsClient(AuthRepository())
        val takes = mutableListOf<ByteArray>()
        for (part in parts) {
            coroutineContext.ensureActive()
            val audio = client.synthesizeStreaming(
                voiceId = voiceId, text = part, modelId = modelId, purpose = purpose,
                onPcmChunk = {},
            )
            if (audio !is ElevenLabsClient.StreamedAudio.Pcm22050) return null
            takes.add(audio.data)
        }
        val rate = ElevenLabsClient.STREAM_SAMPLE_RATE
        val pcm = joined(takes, rate.toDouble())
        val shorts = ShortArray(pcm.size / 2)
        ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(shorts)
        return WavPcm.wav(shorts, rate)
    }

    /** Join 16-bit LE mono takes: each INNER edge trimmed to its voice (the
     *  line's own start and end are left as synthesized), one fixed gap between. */
    fun joined(takes: List<ByteArray>, sampleRate: Double): ByteArray {
        val margin = (EDGE_MARGIN_SECONDS * sampleRate).toInt()
        val gapSamples = maxOf(0, (SENTENCE_GAP_SECONDS * sampleRate).toInt() - 2 * margin)
        val out = java.io.ByteArrayOutputStream()
        for ((i, take) in takes.withIndex()) {
            val samples = take.size / 2
            if (samples <= 0) continue
            val (on, off) = voicedSpan(take, sampleRate) ?: (0 to samples)
            val from = if (i == 0) 0 else maxOf(0, on - margin)
            val to = if (i == takes.size - 1) samples else minOf(samples, off + margin)
            if (to <= from) continue
            if (out.size() > 0) out.write(ByteArray(gapSamples * 2))
            out.write(take, from * 2, (to - from) * 2)
        }
        return out.toByteArray()
    }

    /**
     * First and last sample of speech, read off a 10 ms RMS envelope against
     * the take's own loudest block (the envelope, not samples — speech
     * crosses zero every few hundred microseconds). The gate sits well under
     * the level gate: this cuts silence, and must never eat a soft consonant.
     */
    fun voicedSpan(pcm: ByteArray, sampleRate: Double): Pair<Int, Int>? {
        val count = pcm.size / 2
        val block = maxOf(1, (sampleRate / 100).toInt())
        if (count < block) return null
        val s = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val rms = ArrayList<Float>(count / block)
        var i = 0
        while (i + block <= count) {
            var sum = 0f
            for (j in i until i + block) { val v = s.get(j) / 32768f; sum += v * v }
            rms.add(sqrt(sum / block))
            i += block
        }
        val loudest = rms.maxOrNull() ?: return null
        if (loudest <= 0f) return null
        val gate = loudest * 0.03f
        val first = rms.indexOfFirst { it > gate }
        val last = rms.indexOfLast { it > gate }
        if (first < 0 || last < 0) return null
        return first * block to (last + 1) * block
    }
}
