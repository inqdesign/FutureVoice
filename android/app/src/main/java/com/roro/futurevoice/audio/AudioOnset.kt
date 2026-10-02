package com.roro.futurevoice.audio

import kotlin.math.sqrt

/**
 * Where the SOUND starts (and stops) in a recording — port of iOS
 * `AudioLoudness.firstVoiceOnset`.
 *
 * "Both at once" lines the two takes up on their first word, and the onset
 * comes from the AUDIO, never from word timings: the learner's timings are
 * missing whenever the take could not be aligned, and a target timeline that
 * is an estimate always starts at 0 while a render always opens on silence —
 * a missing onset read as 0 played the take from the top of the file, and
 * the learner heard their own voice arrive a beat late.
 *
 * It measures an ENVELOPE (10 ms block RMS), not samples: speech crosses
 * zero every few hundred microseconds, so a sample-wise "loud for 40 ms" run
 * never completes and reports silence for every file. The gate is relative
 * to the file's own peak (iOS `speechGateRatio`, 20 dB down), so a quiet take
 * and a loud one are judged alike.
 */
object AudioOnset {

    /** iOS `AudioLoudness.speechGateRatio`. */
    const val SPEECH_GATE_RATIO = 0.1f
    private const val BLOCK_SECONDS = 0.01
    private const val MIN_VOICED_SECONDS = 0.04
    private const val ONSET_LEAD_IN = 0.03

    /** Block RMS levels, 0…1. */
    fun envelope(samples: ShortArray, sampleRate: Int): FloatArray {
        val block = maxOf(1, (BLOCK_SECONDS * sampleRate).toInt())
        val count = samples.size / block
        return FloatArray(count) { b ->
            var sum = 0.0
            val base = b * block
            for (k in 0 until block) { val v = samples[base + k] / 32768.0; sum += v * v }
            sqrt(sum / block).toFloat()
        }
    }

    /** Seconds into the file where speech starts; null for a silent file. */
    fun firstVoiceOnset(samples: ShortArray, sampleRate: Int): Double? {
        if (sampleRate <= 0) return null
        val levels = envelope(samples, sampleRate)
        if (levels.isEmpty()) return null
        val loudest = levels.max()
        if (loudest <= 1e-5f) return null
        val gate = loudest * SPEECH_GATE_RATIO
        val needed = maxOf(1, Math.round(MIN_VOICED_SECONDS / BLOCK_SECONDS).toInt())
        var run = 0
        levels.forEachIndexed { b, level ->
            if (level > gate) {
                run += 1
                if (run >= needed) {
                    val onset = (b - run + 1) * BLOCK_SECONDS - ONSET_LEAD_IN
                    return maxOf(0.0, onset)
                }
            } else run = 0
        }
        return null
    }

    /** Seconds into the file where the last held run of speech ends — the
     *  same gate, read backwards. Ends the last word of a learner timeline
     *  (an onset-only source knows where words START, not where speech stops). */
    fun lastVoiceOffset(samples: ShortArray, sampleRate: Int): Double? {
        if (sampleRate <= 0) return null
        val levels = envelope(samples, sampleRate)
        if (levels.isEmpty()) return null
        val loudest = levels.max()
        if (loudest <= 1e-5f) return null
        val gate = loudest * SPEECH_GATE_RATIO
        val needed = maxOf(1, Math.round(MIN_VOICED_SECONDS / BLOCK_SECONDS).toInt())
        var run = 0
        for (b in levels.indices.reversed()) {
            if (levels[b] > gate) {
                run += 1
                if (run >= needed) return minOf(levels.size * BLOCK_SECONDS, (b + run) * BLOCK_SECONDS)
            } else run = 0
        }
        return null
    }

    fun firstVoiceOnset(file: java.io.File): Double? =
        WavPcm.read(file)?.let { firstVoiceOnset(it.samples, it.sampleRate) }
}
