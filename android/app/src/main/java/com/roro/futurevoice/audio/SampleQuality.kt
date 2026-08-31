package com.roro.futurevoice.audio

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * On-device quality check for a recorded clone sample — port of
 * `AudioSampleQuality.swift`, same thresholds: the few things that actually
 * wreck an ElevenLabs clone (too short, clipping, a noisy room, a
 * near-silent take). Frame-RMS percentiles approximate SNR (p90 − p10).
 */
data class SampleQuality(
    val durationSeconds: Double,
    val peakDbfs: Float,
    val rmsDbfs: Float,
    val clippedPercent: Float,
    val estimatedSnrDb: Float,
    val issues: List<String>,
    val rating: Rating,
) {
    enum class Rating { GOOD, OKAY, POOR }

    companion object {

        fun analyze(file: File): SampleQuality? {
            val samples = readMono16(file) ?: return null
            val n = samples.size
            if (n == 0) return null
            val sr = WavRecorder.SAMPLE_RATE
            val duration = n / sr.toDouble()

            var peak = 0f; var sumSq = 0.0; var clipped = 0
            for (s in samples) {
                val v = s / 32768f
                val a = abs(v)
                if (a > peak) peak = a
                sumSq += (v * v).toDouble()
                if (a >= 0.99f) clipped += 1
            }
            val rms = sqrt(sumSq / n).toFloat()
            val clippedPct = clipped.toFloat() / n * 100

            val frameLen = max(1, (sr * 0.05).toInt())
            val frameDbs = ArrayList<Float>(n / frameLen)
            var i = 0
            while (i + frameLen <= n) {
                var s = 0.0
                for (j in i until i + frameLen) { val v = samples[j] / 32768f; s += (v * v) }
                frameDbs.add(20 * log10(max(sqrt(s / frameLen).toFloat(), 1e-7f)))
                i += frameLen
            }
            frameDbs.sort()
            fun percentile(p: Double): Float {
                if (frameDbs.isEmpty()) return -120f
                return frameDbs[min(frameDbs.size - 1, max(0, (frameDbs.size * p).toInt()))]
            }
            val snr = percentile(0.90) - percentile(0.10)
            val peakDb = 20 * log10(max(peak, 1e-7f))
            val rmsDb = 20 * log10(max(rms, 1e-7f))

            val issues = mutableListOf<String>()
            var rating = Rating.GOOD
            fun demote(r: Rating) { if (r == Rating.POOR || rating == Rating.GOOD) rating = r }

            if (duration < 30) {
                issues.add("Too short (${duration.toInt()}s) — aim for 60–90s."); demote(Rating.POOR)
            } else if (duration < 45) {
                issues.add("A little short — 60–90s clones best."); demote(Rating.OKAY)
            }
            if (clippedPct > 0.05f || peakDb > -0.3f) {
                issues.add("Clipping detected — move a little further from the mic."); demote(Rating.POOR)
            }
            if (snr < 14) {
                issues.add("Noisy background — try a quieter spot (a closet works great)."); demote(Rating.POOR)
            } else if (snr < 22) {
                issues.add("Some background noise — quieter is better."); demote(Rating.OKAY)
            }
            if (rmsDb < -34) {
                issues.add("Quiet take — we'll boost it, but closer to the mic helps."); demote(Rating.OKAY)
            }
            return SampleQuality(duration, peakDb, rmsDb, clippedPct, snr, issues, rating)
        }

        /**
         * `AudioLoudness.peakNormalizedWAV`: boost-only gain toward −1 dBFS
         * (capped +30 dB); an already-healthy take is returned untouched.
         * Writes a sibling file; returns the original on any failure.
         */
        fun peakNormalized(file: File): File {
            val samples = readMono16(file) ?: return file
            if (samples.isEmpty()) return file
            var peak = 0f
            for (s in samples) { val a = abs(s / 32768f); if (a > peak) peak = a }
            if (peak <= 1e-5f) return file
            var gain = 10f.pow(-1f / 20f) / peak
            if (gain <= 1.01f) return file
            gain = min(gain, 10f.pow(30f / 20f))
            val out = File(file.parentFile, "normalized-${file.name}")
            return runCatching {
                RandomAccessFile(out, "rw").use { raf ->
                    raf.setLength(0)
                    val header = ByteArray(44)
                    RandomAccessFile(file, "r").use { it.read(header) }
                    raf.write(header)
                    val bytes = ByteBuffer.allocate(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
                    for (s in samples) {
                        val v = (s * gain).toInt().coerceIn(-32768, 32767)
                        bytes.putShort(v.toShort())
                    }
                    raf.write(bytes.array())
                }
                out
            }.getOrDefault(file)
        }

        /** 16-bit LE mono samples from a canonical 44-byte-header WAV. */
        private fun readMono16(file: File): ShortArray? = runCatching {
            val bytes = file.readBytes()
            if (bytes.size <= 44) return@runCatching null
            val data = ByteBuffer.wrap(bytes, 44, bytes.size - 44).order(ByteOrder.LITTLE_ENDIAN)
            val out = ShortArray((bytes.size - 44) / 2)
            data.asShortBuffer().get(out)
            out
        }.getOrNull()
    }
}
