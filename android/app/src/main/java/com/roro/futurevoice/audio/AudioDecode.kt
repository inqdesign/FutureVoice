package com.roro.futurevoice.audio

import android.media.MediaCodec
import android.media.MediaDataSource
import android.media.MediaExtractor
import android.media.MediaFormat
import java.nio.ByteOrder

/**
 * Compressed audio (the target line's MP3) → mono 16-bit PCM, for the two
 * things that have to READ the model line rather than play it: its onset
 * ("Both at once") and the take alignment ([com.roro.futurevoice.talk.TakeAligner]).
 */
object AudioDecode {

    fun decode(bytes: ByteArray): WavPcm? = runCatching {
        val extractor = MediaExtractor()
        extractor.setDataSource(object : MediaDataSource() {
            override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
                if (position >= bytes.size) return -1
                val n = minOf(size, (bytes.size - position).toInt())
                System.arraycopy(bytes, position.toInt(), buffer, offset, n)
                return n
            }
            override fun getSize(): Long = bytes.size.toLong()
            override fun close() {}
        })
        val track = (0 until extractor.trackCount).firstOrNull {
            extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
        } ?: return null
        extractor.selectTrack(track)
        val format = extractor.getTrackFormat(track)
        val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(format, null, null, 0)
        codec.start()
        var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val out = java.io.ByteArrayOutputStream()
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        while (!outputDone) {
            if (!inputDone) {
                val inIndex = codec.dequeueInputBuffer(10_000)
                if (inIndex >= 0) {
                    val buf = codec.getInputBuffer(inIndex)!!
                    val n = extractor.readSampleData(buf, 0)
                    if (n < 0) {
                        codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(inIndex, 0, n, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val outIndex = codec.dequeueOutputBuffer(info, 10_000)
            when {
                outIndex >= 0 -> {
                    val buf = codec.getOutputBuffer(outIndex)!!
                    val chunk = ByteArray(info.size)
                    buf.position(info.offset); buf.get(chunk)
                    out.write(chunk)
                    codec.releaseOutputBuffer(outIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                }
                outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val f = codec.outputFormat
                    rate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                }
            }
        }
        codec.stop(); codec.release(); extractor.release()
        val raw = java.nio.ByteBuffer.wrap(out.toByteArray()).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val frames = raw.remaining() / maxOf(1, channels)
        val mono = ShortArray(frames) { f ->
            var sum = 0
            for (c in 0 until channels) sum += raw.get(f * channels + c)
            (sum / channels).toShort()
        }
        WavPcm(rate, mono)
    }.getOrNull()

    /** Linear-interpolated resample — good enough for an envelope and a
     *  feature track, which is all a re-rated copy is used for. */
    fun resample(pcm: WavPcm, rate: Int): WavPcm {
        if (pcm.sampleRate == rate || pcm.samples.isEmpty()) return pcm
        val ratio = pcm.sampleRate.toDouble() / rate
        val n = (pcm.samples.size / ratio).toInt()
        val src = pcm.samples
        val out = ShortArray(n) { i ->
            val x = i * ratio
            val k = x.toInt()
            val f = x - k
            val a = src[minOf(k, src.size - 1)]
            val b = src[minOf(k + 1, src.size - 1)]
            (a + (b - a) * f).toInt().toShort()
        }
        return WavPcm(rate, out)
    }
}
