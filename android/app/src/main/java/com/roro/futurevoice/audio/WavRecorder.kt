package com.roro.futurevoice.audio

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Raw-PCM recorder for the voice-clone sample — 16 kHz mono 16-bit WAV, the
 * app-wide recording contract (`behavior.md` §6; don't change it without
 * checking both providers). `AudioRecord` rather than `MediaRecorder` because
 * the sample must be uncompressed and the level meter needs the frames.
 */
class WavRecorder {

    @Volatile var isRecording: Boolean = false; private set
    /** 0…1 mic level for the meter, smoothed like the call's. */
    @Volatile var level: Float = 0f; private set
    @Volatile var elapsedSeconds: Double = 0.0; private set

    private var record: AudioRecord? = null
    private var worker: Thread? = null

    @SuppressLint("MissingPermission")   // RECORD_AUDIO is granted before this screen opens
    fun start(outFile: File) {
        if (isRecording) return
        val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = AudioRecord(MediaRecorder.AudioSource.MIC, SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(minBuf, 8192))
        record = rec
        isRecording = true
        elapsedSeconds = 0.0
        worker = thread(name = "WavRecorder") {
            val buf = ShortArray(2048)
            outFile.parentFile?.mkdirs()
            RandomAccessFile(outFile, "rw").use { raf ->
                raf.setLength(0)
                raf.write(ByteArray(44))   // header placeholder
                rec.startRecording()
                var frames = 0L
                val bytes = ByteBuffer.allocate(buf.size * 2).order(ByteOrder.LITTLE_ENDIAN)
                while (isRecording) {
                    val n = rec.read(buf, 0, buf.size)
                    if (n <= 0) continue
                    bytes.clear()
                    for (i in 0 until n) bytes.putShort(buf[i])
                    raf.write(bytes.array(), 0, n * 2)
                    frames += n
                    elapsedSeconds = frames / SAMPLE_RATE.toDouble()
                    // RMS → dBFS → the same 0…1 curve the call meter draws.
                    var sum = 0.0
                    for (i in 0 until n) { val v = buf[i] / 32768.0; sum += v * v }
                    val db = 20 * log10(max(sqrt(sum / n), 1e-7))
                    level = (((db + 50f) / 50f).toFloat()).coerceIn(0f, 1f)
                }
                rec.stop(); rec.release()
                writeHeader(raf, frames)
            }
        }
    }

    /** Stops and finalizes the WAV header; safe to call twice. */
    fun stop() {
        if (!isRecording) return
        isRecording = false
        worker?.join(2000); worker = null
        record = null
        level = 0f
    }

    private fun writeHeader(raf: RandomAccessFile, frames: Long) {
        val dataSize = frames * 2
        val h = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        h.put("RIFF".toByteArray()); h.putInt((36 + dataSize).toInt())
        h.put("WAVE".toByteArray()); h.put("fmt ".toByteArray())
        h.putInt(16); h.putShort(1); h.putShort(1)
        h.putInt(SAMPLE_RATE); h.putInt(SAMPLE_RATE * 2)
        h.putShort(2); h.putShort(16)
        h.put("data".toByteArray()); h.putInt(dataSize.toInt())
        raf.seek(0); raf.write(h.array())
    }

    companion object { const val SAMPLE_RATE = 16_000 }
}
