package com.roro.futurevoice.audio

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * 16-bit mono PCM → AAC-LC with the platform encoder. Two uses, both from the
 * Speech tab: a whole take sent to the reader as ADTS (iOS sends 32 kbps AAC
 * for the same reason — a three-minute take is ~6 MB of WAV and ~0.7 MB of
 * AAC), and the voice track muxed under the take's video.
 */
object AacEncoder {
    private const val MIME = MediaFormat.MIMETYPE_AUDIO_AAC

    /**
     * Encodes [samples]; [onFormat] gets the output format once (for a
     * muxer), [onSample] every encoded access unit (config buffers skipped).
     * False when the device's encoder refused.
     */
    fun encode(
        samples: ShortArray,
        sampleRate: Int,
        bitrate: Int = 32_000,
        onFormat: (MediaFormat) -> Unit = {},
        onSample: (ByteBuffer, MediaCodec.BufferInfo) -> Unit,
    ): Boolean {
        val format = MediaFormat.createAudioFormat(MIME, sampleRate, 1).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16_384)
        }
        val codec = runCatching { MediaCodec.createEncoderByType(MIME) }.getOrNull() ?: return false
        return try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val info = MediaCodec.BufferInfo()
            var fed = 0
            var inputDone = false
            var outputDone = false
            var spins = 0
            while (!outputDone) {
                if (!inputDone) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buf = codec.getInputBuffer(inIndex)!!
                        buf.clear()
                        val room = buf.remaining() / 2
                        val n = minOf(room, samples.size - fed)
                        val pts = fed.toLong() * 1_000_000 / sampleRate
                        if (n <= 0) {
                            codec.queueInputBuffer(inIndex, 0, 0, pts, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            val bytes = ByteBuffer.allocate(n * 2).order(ByteOrder.LITTLE_ENDIAN)
                            for (i in fed until fed + n) bytes.putShort(samples[i])
                            buf.put(bytes.array())
                            codec.queueInputBuffer(inIndex, 0, n * 2, pts, 0)
                            fed += n
                        }
                    }
                }
                val outIndex = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> onFormat(codec.outputFormat)
                    outIndex >= 0 -> {
                        val out = codec.getOutputBuffer(outIndex)!!
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0 && info.size > 0) {
                            out.position(info.offset); out.limit(info.offset + info.size)
                            onSample(out, info)
                        }
                        codec.releaseOutputBuffer(outIndex, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                        spins = 0
                    }
                    else -> if (inputDone && ++spins > 500) outputDone = true   // a stuck encoder
                }
            }
            true
        } catch (_: Exception) {
            false
        } finally {
            runCatching { codec.stop() }
            runCatching { codec.release() }
        }
    }

    /** ADTS-framed AAC of a 16-bit mono WAV, or null. */
    fun adts(pcm: WavPcm, bitrate: Int = 32_000): ByteArray? {
        val freqIndex = when (pcm.sampleRate) {
            96000 -> 0; 88200 -> 1; 64000 -> 2; 48000 -> 3; 44100 -> 4; 32000 -> 5
            24000 -> 6; 22050 -> 7; 16000 -> 8; 12000 -> 9; 11025 -> 10; 8000 -> 11
            else -> return null
        }
        val out = ByteArrayOutputStream()
        val ok = encode(pcm.samples, pcm.sampleRate, bitrate) { buf, info ->
            val len = info.size + 7
            val header = byteArrayOf(
                0xFF.toByte(), 0xF1.toByte(),
                ((1 shl 6) or (freqIndex shl 2) or (1 shr 2)).toByte(),   // LC (profile-1 = 1), mono
                (((1 and 3) shl 6) or (len shr 11)).toByte(),
                ((len shr 3) and 0xFF).toByte(),
                (((len and 7) shl 5) or 0x1F).toByte(),
                0xFC.toByte(),
            )
            out.write(header)
            val bytes = ByteArray(info.size)
            buf.get(bytes)
            out.write(bytes)
        }
        return if (ok && out.size() > 0) out.toByteArray() else null
    }
}
