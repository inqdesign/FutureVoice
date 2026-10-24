package com.roro.futurevoice.audio

import android.content.Context
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.talk.VoicePreset
import java.io.File
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.sqrt

/**
 * How high a voice sits, and which preset sits closest to it (iOS
 * `VoicePitch`, 2026-10-24).
 *
 * The meet act offers a preset beside the learner's own clone, and the one
 * offered should be the one most like them — a man shouldn't be handed a
 * woman's voice as "yours, but different". Pitch is the one likeness code
 * can measure honestly and cheaply on the phone: the median fundamental
 * frequency of the recording, against the same number for each preset's
 * bundled preview in the target language. It says nothing about timbre, so
 * the screen calls the pick "similar voice", never "sounds like you".
 *
 * Gender is the slot's (every language keeps the slots' F/M split), so the
 * pick is made inside the gender the pitch points to, then by distance.
 */
object VoicePitch {
    /** Below this median F0 a voice reads as male. */
    const val MALE_BELOW_HZ = 165.0

    /** Median F0 over voiced frames of a WAV, or null when too little was
     *  voiced to say. Reads at most [maxSeconds] of audio. */
    fun medianF0(file: File, maxSeconds: Double = 12.0): Double? {
        val pcm = WavPcm.read(file) ?: return null
        return medianF0(pcm, maxSeconds)
    }

    fun medianF0(pcm: WavPcm, maxSeconds: Double = 12.0): Double? {
        val (samples, rate) = monoSamples(pcm, maxSeconds) ?: return null
        val frame = (rate * 0.04).toInt()
        val hop = (rate * 0.02).toInt()
        val minLag = (rate / 400).toInt()
        val maxLag = (rate / 70).toInt()
        if (frame <= maxLag || samples.size <= frame) return null

        // A frame quieter than a tenth of the loudest one is a pause, and a
        // pause has no pitch.
        var peak = 0f
        for (s in samples) peak = maxOf(peak, abs(s))
        if (peak <= 0f) return null
        val gate = peak * 0.1f

        val pitches = ArrayList<Double>()
        var start = 0
        while (start + frame <= samples.size) {
            var energy = 0f
            var loud = 0f
            for (i in start until start + frame) {
                val v = samples[i]; energy += v * v; loud = maxOf(loud, abs(v))
            }
            if (loud >= gate && energy > 0f) {
                var bestLag = 0
                var best = 0f
                for (lag in minLag..maxLag) {
                    var sum = 0f
                    var e2 = 0f
                    for (i in 0 until frame - lag) {
                        val a = samples[start + i]
                        val b = samples[start + i + lag]
                        sum += a * b
                        e2 += b * b
                    }
                    val r = sum / maxOf(1e-9f, sqrt(energy * e2))
                    if (r > best) { best = r; bestLag = lag }
                }
                // Clearly periodic only: breath and fricatives score low.
                if (best > 0.6f && bestLag > 0) pitches.add(rate / bestLag)
            }
            start += hop
        }
        if (pitches.size < 10) return null
        pitches.sort()
        return pitches[pitches.size / 2]
    }

    /** The preset to offer beside the clone: same gender as the recording,
     *  nearest in pitch. Falls back to the first preset of that gender when a
     *  preview can't be measured. */
    fun closestPreset(context: Context, ownPitch: Double, language: String): StockPerson? {
        val male = ownPitch < MALE_BELOW_HZ
        val candidates = StockPerson.catalog.filter { VoicePreset.isMale(it.voiceId) == male }
        val measured = candidates.mapNotNull { p -> presetF0(context, p.voiceId, language)?.let { p to it } }
        measured.minByOrNull { abs(ln(it.second / ownPitch)) }?.let { return it.first }
        return candidates.firstOrNull()
    }

    private val presetCache = HashMap<String, Double>()

    /** A preset's median F0 in a language, from its bundled preview. */
    fun presetF0(context: Context, id: String, language: String): Double? {
        val lang = language.substringBefore('-')
        val key = "$lang|$id"
        synchronized(presetCache) { presetCache[key]?.let { return it } }
        val bytes = runCatching {
            context.assets.open("voice_previews/preview-$lang-$id.mp3").use { it.readBytes() }
        }.getOrNull() ?: return null
        val pcm = AudioDecode.decode(bytes) ?: return null
        val f0 = medianF0(pcm) ?: return null
        synchronized(presetCache) { presetCache[key] = f0 }
        return f0
    }

    private fun monoSamples(pcm: WavPcm, maxSeconds: Double): Pair<FloatArray, Double>? {
        val rate = pcm.sampleRate.toDouble()
        val n = minOf(pcm.samples.size.toDouble(), rate * maxSeconds).toInt()
        if (n <= 0) return null
        // Down to ~16 kHz by averaging: pitch lives far below 8 kHz, and the
        // autocorrelation costs the square of the rate.
        val step = maxOf(1, (rate / 16_000).toInt())
        val mono = FloatArray(n / step)
        val scale = 1f / (step * 32768f)
        for (j in mono.indices) {
            var sum = 0f
            for (k in 0 until step) sum += pcm.samples[j * step + k]
            mono[j] = sum * scale
        }
        return mono to rate / step
    }
}
