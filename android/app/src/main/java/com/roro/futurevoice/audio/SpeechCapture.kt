package com.roro.futurevoice.audio

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioRecordingConfiguration
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * The microphone for a Speech take — one `AudioRecord`, three outputs:
 *
 *  - the take itself, a 16 kHz mono WAV (the app's recording contract), which
 *    is what gets scored;
 *  - PIECES of it, cut on request at a pause, so the take can be read while
 *    it is still being spoken (iOS `625f13d5` `rotateCaptureChunk`);
 *  - the voice level and "last voiced" moment ([FluencyMeter], the same 0…1
 *    dBFS curve iOS taps), which keep the prompter flowing.
 *
 * The live recognizer that follows the reader's position is a SECOND mic
 * consumer (`SpeechRecognizer`). Where a device can't feed both, the one that
 * started last wins — so this starts AFTER the recognizer, and reports
 * through [onSilenced] if the system silences it anyway, so the caller can
 * drop the recognizer and keep the take whole.
 */
class SpeechCapture(private val context: Context) {

    @Volatile var level: Float = 0f; private set
    private val meter = FluencyMeter()
    val lastVoicedAtMs: Long? get() = meter.lastVoicedAt()
    /** `System.nanoTime()` of the first sample written — the clock camera
     *  frames are stamped on too. */
    @Volatile var startNanos: Long = 0L; private set
    @Volatile var isRunning = false; private set

    /** Called (on the main thread) when the system silenced this capture
     *  for another app's — the recognizer's — benefit. */
    var onSilenced: (() -> Unit)? = null

    private var record: AudioRecord? = null
    private var worker: Thread? = null
    private val lock = Any()
    private var main: RandomAccessFile? = null
    private var mainFrames = 0L
    private var chunk: RandomAccessFile? = null
    private var chunkFile: File? = null
    private var chunkFrames = 0L
    private var chunkDir: File? = null
    private var callback: AudioManager.AudioRecordingCallback? = null

    @SuppressLint("MissingPermission")   // asked by the screen before a take
    fun start(out: File, piecesDir: File) {
        if (isRunning) return
        val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(minBuf, 8192))
        record = rec
        meter.reset()
        level = 0f
        chunkDir = piecesDir.apply { mkdirs() }
        synchronized(lock) {
            out.parentFile?.mkdirs()
            main = RandomAccessFile(out, "rw").apply { setLength(0); write(ByteArray(44)) }
            mainFrames = 0
            openChunk()
        }
        watchSilencing(rec)
        isRunning = true
        startNanos = 0L
        worker = thread(name = "SpeechCapture") {
            val buf = ShortArray(1600)   // 100 ms
            val bytes = ByteBuffer.allocate(buf.size * 2).order(ByteOrder.LITTLE_ENDIAN)
            rec.startRecording()
            while (isRunning) {
                val n = rec.read(buf, 0, buf.size)
                if (n <= 0) continue
                if (startNanos == 0L) startNanos = System.nanoTime() - n * 1_000_000_000L / SAMPLE_RATE
                bytes.clear()
                for (i in 0 until n) bytes.putShort(buf[i])
                synchronized(lock) {
                    main?.write(bytes.array(), 0, n * 2); mainFrames += n
                    chunk?.write(bytes.array(), 0, n * 2); chunkFrames += n
                }
                var sum = 0.0
                for (i in 0 until n) { val v = buf[i] / 32768.0; sum += v * v }
                val db = 20 * log10(max(sqrt(sum / n), 1e-7))
                val l = (((db + 50) / 50).toFloat()).coerceIn(0f, 1f)
                level = l
                meter.feed(l, n / SAMPLE_RATE.toDouble(), System.currentTimeMillis())
            }
            runCatching { rec.stop() }
            rec.release()
        }
    }

    /** Closes the current piece and starts the next. Null when the piece is
     *  too short to be worth reading. */
    fun rotatePiece(): File? = synchronized(lock) {
        val closed = closeChunk()
        openChunk()
        closed
    }

    /** Stops; returns the last piece (the tail still to be read). */
    fun stop(): File? {
        if (!isRunning) return null
        isRunning = false
        worker?.join(2000); worker = null
        record = null
        level = 0f
        unwatch()
        return synchronized(lock) {
            main?.let { finalize(it, mainFrames); it.close() }
            main = null
            closeChunk()
        }
    }

    private fun openChunk() {
        val dir = chunkDir ?: return
        val f = File(dir, "speech-piece-${System.nanoTime()}.wav")
        chunkFile = f
        chunk = RandomAccessFile(f, "rw").apply { setLength(0); write(ByteArray(44)) }
        chunkFrames = 0
    }

    private fun closeChunk(): File? {
        val raf = chunk ?: return null
        val file = chunkFile
        finalize(raf, chunkFrames)
        raf.close()
        chunk = null; chunkFile = null
        // Under half a second holds no words worth a round trip.
        if (chunkFrames < SAMPLE_RATE / 2) { file?.delete(); return null }
        return file
    }

    private fun finalize(raf: RandomAccessFile, frames: Long) {
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

    private fun watchSilencing(rec: AudioRecord) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        val session = rec.audioSessionId
        val cb = object : AudioManager.AudioRecordingCallback() {
            override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>?) {
                val mine = configs?.firstOrNull { it.clientAudioSessionId == session } ?: return
                if (mine.isClientSilenced) onSilenced?.invoke()
            }
        }
        callback = cb
        am.registerAudioRecordingCallback(cb, Handler(Looper.getMainLooper()))
    }

    private fun unwatch() {
        val cb = callback ?: return
        callback = null
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        runCatching { am.unregisterAudioRecordingCallback(cb) }
    }

    companion object { const val SAMPLE_RATE = 16_000 }
}
