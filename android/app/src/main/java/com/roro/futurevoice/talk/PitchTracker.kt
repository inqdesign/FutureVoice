package com.roro.futurevoice.talk

import com.roro.futurevoice.audio.AudioOnset
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.log2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * How much the voice's pitch MOVES over a take, in semitones, and its median
 * pitch, which picks a reading's reference — iOS `PitchTracker`.
 *
 * Normalized autocorrelation per 40 ms frame (10 ms hop), 75–500 Hz, a frame
 * voiced when it is loud enough and its best peak is ≥ 0.45. The first peak
 * within 85% of the best is taken, so a period's double (the classic
 * octave-down error) never wins over it.
 */
object PitchTracker {
    data class Stats(
        /** 90th minus 10th percentile of the voiced frames, semitones from the median. */
        val rangeSemitones: Double,
        /** Standard deviation, same scale. */
        val sdSemitones: Double,
        val voicedFrames: Int,
        /** The voice's median pitch, Hz (`SpeechReading.FEMALE_ABOVE_HZ`). */
        val medianHz: Double = 0.0,
    )

    const val FLOOR_HZ = 75.0
    const val CEILING_HZ = 500.0
    const val VOICING_THRESHOLD = 0.45f

    /** Per-frame F0 in Hz (0 = unvoiced). */
    fun track(x: FloatArray, rate: Double): DoubleArray {
        val frame = (0.04 * rate).toInt()
        val hop = (0.01 * rate).toInt()
        val minLag = (rate / CEILING_HZ).toInt()
        val maxLag = (rate / FLOOR_HZ).toInt()
        if (x.size <= frame + maxLag + 1 || frame <= 0 || hop <= 0) return DoubleArray(0)

        // Loudness gate, relative to the take's loudest frame.
        var peak = 0f
        for (v in x) if (abs(v) > peak) peak = abs(v)
        if (peak <= 1e-5f) return DoubleArray(0)
        // Prefix sums of squares, for each lag's window energy.
        val prefix = DoubleArray(x.size + 1)
        for (i in x.indices) prefix[i + 1] = prefix[i] + (x[i] * x[i]).toDouble()
        fun energy(start: Int, length: Int) = prefix[start + length] - prefix[start]

        val gate = (peak * AudioOnset.SPEECH_GATE_RATIO).toDouble()
        val lags = maxLag - minLag + 1
        val norm = FloatArray(lags)
        val out = ArrayList<Double>(x.size / hop + 1)
        var start = 0
        while (start + frame + maxLag < x.size) {
            val e0 = energy(start, frame)
            val rms = sqrt(e0 / frame)
            if (rms <= gate * 0.5) { out += 0.0; start += hop; continue }
            var best = 0f
            for (k in 0 until lags) {
                // corr[k] = Σ x[start+t] · x[start+minLag+k+t], t < frame
                var corr = 0f
                val offset = start + minLag + k
                for (t in 0 until frame) corr += x[offset + t] * x[start + t]
                val d = sqrt(e0 * energy(offset, frame))
                norm[k] = if (d > 0) (corr.toDouble() / d).toFloat() else 0f
                best = max(best, norm[k])
            }
            if (best < VOICING_THRESHOLD) { out += 0.0; start += hop; continue }
            // First local maximum within 85% of the best.
            var pick = -1
            for (k in 1 until lags - 1) {
                if (norm[k] >= 0.85f * best && norm[k] >= norm[k - 1] && norm[k] >= norm[k + 1]) { pick = k; break }
            }
            if (pick < 0) { out += 0.0; start += hop; continue }
            // Parabolic interpolation around the peak.
            val a = norm[pick - 1]; val b = norm[pick]; val c = norm[pick + 1]
            val denom = a - 2 * b + c
            val shift = if (denom != 0f) (0.5f * (a - c) / denom).toDouble() else 0.0
            val lag = (minLag + pick) + shift
            out += if (lag > 0) rate / lag else 0.0
            start += hop
        }
        return out.toDoubleArray()
    }

    /**
     * Cleans a track the way a listener hears it: a voiced run shorter than
     * 30 ms is a click, not a pitch; a frame an octave or more from the take's
     * median is folded back by octaves; what is left is smoothed by a 5-frame
     * median within each run.
     */
    fun cleaned(raw: DoubleArray): DoubleArray {
        val f = raw.copyOf()
        val voiced = f.filter { it > 0 }.sorted()
        if (voiced.isEmpty()) return f
        val median = voiced[voiced.size / 2]
        for (k in f.indices) {
            if (f[k] <= 0) continue
            var st = 12 * log2(f[k] / median)
            while (st > 9) st -= 12
            while (st < -9) st += 12
            f[k] = median * 2.0.pow(st / 12)
        }
        var i = 0
        while (i < f.size) {
            if (f[i] <= 0) { i++; continue }
            var j = i
            while (j < f.size && f[j] > 0) j++
            if (j - i < 3) {
                for (k in i until j) f[k] = 0.0
            } else {
                val run = f.copyOfRange(i, j)
                for (k in run.indices) {
                    val window = run.copyOfRange(max(0, k - 2), min(run.size, k + 3)).sorted()
                    f[i + k] = window[window.size / 2]
                }
            }
            i = j
        }
        return f
    }

    /** The take's pitch movement; null under half a second of voiced frames. */
    fun stats(x: FloatArray, rate: Double): Stats? {
        val f0 = cleaned(track(x, rate)).filter { it > 0 }
        if (f0.size < 50) return null
        val sorted = f0.sorted()
        val median = sorted[sorted.size / 2]
        val st = sorted.map { 12 * log2(it / median) }
        fun pct(p: Double): Double {
            val pos = p * (st.size - 1)
            val lo = floor(pos).toInt()
            val hi = min(st.size - 1, lo + 1)
            return st[lo] + (st[hi] - st[lo]) * (pos - lo)
        }
        val mean = st.sum() / st.size
        val sd = sqrt(st.sumOf { (it - mean) * (it - mean) } / st.size)
        return Stats(pct(0.9) - pct(0.1), sd, f0.size, median)
    }
}
