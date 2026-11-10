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
 * One microphone for a whole run of takes — Say it again (iOS 8a753a84: the
 * engine opens once, the answers play over it, and a take is
 * `LiveTranscriber.beginTake`/`finishTake` plus a recorder that leaves the
 * session alone).
 *
 * Opened per line, the mic cost half a second or more each time and the first
 * sound after it was lost. Here one `AudioRecord` runs from [open] to
 * [close]; a take is only a file that the same buffers are written into
 * between [beginTake] and [finishTake] (16 kHz mono 16-bit WAV, the app's
 * recording contract). Nothing is recorded between takes.
 */
class RunMic {

    @Volatile var isOpen: Boolean = false; private set
    /** 0…1 mic level, the same dBFS curve `WavRecorder` draws. */
    @Volatile var level: Float = 0f; private set
    /** Wall-clock ms the mic last read at or above [voicedLevel] in this
     *  take. Null until then; cleared by [beginTake]. */
    @Volatile var lastVoicedAtMs: Long? = null; private set
    /** The level that counts as someone talking. */
    @Volatile var voicedLevel: Float = 0.35f

    /** Every buffer as it is read (on the capture thread) — how the live
     *  recognizer hears the SAME audio ([LiveTranscriber.feed]). Must not block. */
    @Volatile var tap: ((ShortArray, Int) -> Unit)? = null

    @Volatile private var record: AudioRecord? = null
    private val lock = Any()
    private var take: RandomAccessFile? = null
    private var takeFile: File? = null
    private var takeFrames = 0L

    /** Throws when the microphone can't be opened. */
    @SuppressLint("MissingPermission")   // asked by the screen before a run
    fun open() {
        if (isOpen) return
        val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = AudioRecord(MediaRecorder.AudioSource.MIC, SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(minBuf, 8192))
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            throw IllegalStateException("Microphone unavailable")
        }
        try { rec.startRecording() } catch (e: Exception) { rec.release(); throw e }
        record = rec
        isOpen = true
        level = 0f
        lastVoicedAtMs = null
        thread(name = "RunMic") {
            val buf = ShortArray(1600)   // 100 ms
            val bytes = ByteBuffer.allocate(buf.size * 2).order(ByteOrder.LITTLE_ENDIAN)
            // Its own record: a mic closed and opened again at once must not
            // be read (or released) by the thread of the one before.
            while (record === rec) {
                val n = rec.read(buf, 0, buf.size)
                if (n < 0) break
                if (n == 0) continue
                tap?.invoke(buf, n)
                synchronized(lock) {
                    take?.let { raf ->
                        bytes.clear()
                        for (i in 0 until n) bytes.putShort(buf[i])
                        runCatching { raf.write(bytes.array(), 0, n * 2) }
                        takeFrames += n
                    }
                }
                var sum = 0.0
                for (i in 0 until n) { val v = buf[i] / 32768.0; sum += v * v }
                val db = 20 * log10(max(sqrt(sum / n), 1e-7))
                val l = (((db + 50f) / 50f).toFloat()).coerceIn(0f, 1f)
                level = l
                if (l >= voicedLevel) lastVoicedAtMs = System.currentTimeMillis()
            }
            runCatching { rec.stop() }
            rec.release()
        }
    }

    /** Start writing the take into [file]. The mic is already listening, so
     *  nothing of the first sound is lost. */
    fun beginTake(file: File) {
        synchronized(lock) {
            closeTake(keep = false)
            file.parentFile?.mkdirs()
            take = RandomAccessFile(file, "rw").apply { setLength(0); write(ByteArray(44)) }
            takeFile = file
            takeFrames = 0
        }
        lastVoicedAtMs = null
    }

    /** End the take and finalize its file; the mic keeps running. Safe to
     *  call with no take open. */
    fun finishTake() { synchronized(lock) { closeTake(keep = true) } }

    /** End the take and drop its file. */
    fun discardTake() { synchronized(lock) { closeTake(keep = false) } }

    /** Close the mic. A take still open is finalized. Never blocks: the
     *  capture thread releases its own recorder. */
    fun close() {
        if (!isOpen) return
        isOpen = false
        record = null
        tap = null
        level = 0f
        synchronized(lock) { closeTake(keep = true) }
    }

    private fun closeTake(keep: Boolean) {
        val raf = take ?: return
        val file = takeFile
        take = null; takeFile = null
        runCatching {
            if (keep) writeHeader(raf, takeFrames)
            raf.close()
        }
        if (!keep) file?.delete()
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
