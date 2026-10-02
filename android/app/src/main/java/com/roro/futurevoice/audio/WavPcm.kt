package com.roro.futurevoice.audio

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * 16-bit PCM out of a WAV file, mono-mixed — what every shadow measurement
 * reads (the onset, the duet, the file recognizer). Pure JVM so the onset
 * and the alignment can be tested on synthetic files.
 *
 * Walks the RIFF chunks instead of assuming a 44-byte header: `WavRecorder`
 * writes 44, but anything else (a `say` take in the tests, a backup from
 * iOS) may carry a `LIST`/`FLLR` chunk before `data`.
 */
class WavPcm(val sampleRate: Int, val samples: ShortArray) {

    val durationMs: Int get() =
        if (sampleRate <= 0) 0 else (samples.size.toLong() * 1000 / sampleRate).toInt()

    /** Raw little-endian bytes — what `EXTRA_AUDIO_SOURCE` wants. */
    fun pcmBytes(): ByteArray {
        val out = ByteBuffer.allocate(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        samples.forEach { out.putShort(it) }
        return out.array()
    }

    /** A canonical 44-byte-header mono WAV of these samples. */
    fun wavBytes(): ByteArray = wav(samples, sampleRate)

    companion object {
        fun read(file: File): WavPcm? = runCatching { parse(file.readBytes()) }.getOrNull()

        fun parse(bytes: ByteArray): WavPcm? {
            if (bytes.size < 12) return null
            val b = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            if (String(bytes, 0, 4, Charsets.US_ASCII) != "RIFF" ||
                String(bytes, 8, 4, Charsets.US_ASCII) != "WAVE") return null
            var pos = 12
            var rate = 0
            var channels = 1
            var bits = 16
            var format = 1
            while (pos + 8 <= bytes.size) {
                val id = String(bytes, pos, 4, Charsets.US_ASCII)
                val size = b.getInt(pos + 4)
                val body = pos + 8
                when (id) {
                    "fmt " -> {
                        format = b.getShort(body).toInt() and 0xFFFF
                        channels = maxOf(1, b.getShort(body + 2).toInt())
                        rate = b.getInt(body + 4)
                        bits = b.getShort(body + 14).toInt()
                    }
                    "data" -> {
                        // A recorder killed mid-take leaves size 0 / garbage:
                        // read what is actually there.
                        val avail = bytes.size - body
                        val len = if (size in 1..avail) size else avail
                        if (bits != 16 || (format != 1 && format != 0xFFFE) || rate <= 0) return null
                        val frames = len / (2 * channels)
                        val out = ShortArray(frames)
                        for (f in 0 until frames) {
                            var sum = 0
                            for (c in 0 until channels) sum += b.getShort(body + (f * channels + c) * 2)
                            out[f] = (sum / channels).toShort()
                        }
                        return WavPcm(rate, out)
                    }
                }
                pos = body + size + (size and 1)
                if (size < 0) return null
            }
            return null
        }

        fun wav(samples: ShortArray, sampleRate: Int): ByteArray {
            val data = samples.size * 2
            val out = ByteBuffer.allocate(44 + data).order(ByteOrder.LITTLE_ENDIAN)
            out.put("RIFF".toByteArray()); out.putInt(36 + data); out.put("WAVE".toByteArray())
            out.put("fmt ".toByteArray()); out.putInt(16); out.putShort(1); out.putShort(1)
            out.putInt(sampleRate); out.putInt(sampleRate * 2); out.putShort(2); out.putShort(16)
            out.put("data".toByteArray()); out.putInt(data)
            samples.forEach { out.putShort(it) }
            return out.array()
        }
    }
}
