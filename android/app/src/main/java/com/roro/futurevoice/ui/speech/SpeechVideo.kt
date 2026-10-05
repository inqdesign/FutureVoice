package com.roro.futurevoice.ui.speech

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.view.Surface
import com.roro.futurevoice.audio.AacEncoder
import com.roro.futurevoice.audio.WavPcm
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer

/**
 * Makes the take's video — iOS `SpeechVideoComposer` (`c91d87e5`,
 * `a214c3ad`): every camera frame is drawn into the take screen's own layout,
 * the rolling script on top and the camera card below, at 9:16 1080×1920,
 * and written to a movie. The app draws it, so nothing asks to record the
 * screen and none of the buttons is in the picture.
 *
 * Frames are drawn with a hardware canvas on the encoder's input surface;
 * their time is the moment they were posted (`System.nanoTime`), the clock
 * [com.roro.futurevoice.audio.SpeechCapture.startNanos] is on, so the merge
 * can line the picture up with the voice.
 */
class SpeechVideoComposer {

    /** Where things are on the take screen, in SCREEN pixels, top-left origin. */
    data class Layout(
        val canvasW: Float,
        val canvasH: Float,
        val prompter: RectF,
        val card: RectF,
        val cardRadius: Float,
        val background: Int,
        val topFade: Float = 0.015f,
        val bottomFade: Float = 0.14f,
    )

    data class Result(val file: File, val firstFrameNanos: Long)

    @Volatile private var layout: Layout? = null
    @Volatile private var column: PrompterColumn? = null
    /** Column y drawn at the top of the prompter area. */
    @Volatile var offset: Float = 0f

    private val lock = Any()
    /** Held while a frame is drawn: the surface is never released mid-draw. */
    private val drawLock = Any()
    private var codec: MediaCodec? = null
    private var surface: Surface? = null
    private var muxer: MediaMuxer? = null
    private var track = -1
    private var firstPtsUs = -1L
    private var file: File? = null
    private var drainer: Thread? = null
    @Volatile private var recording = false
    @Volatile private var failed = false
    private var eosSent = false

    private val bgPaint = Paint()
    private val bitmapPaint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val fadePaint = Paint()

    fun prepare(layout: Layout, column: PrompterColumn?) {
        this.layout = layout
        this.column = column
    }

    val isPrepared: Boolean get() = layout != null && column != null

    /** Frames from now on are written, into a temp file in [dir]. */
    fun begin(dir: File) {
        synchronized(lock) {
            release()
            failed = false; eosSent = false; firstPtsUs = -1L; track = -1
            val out = File(dir, "speech-take-${System.nanoTime()}.mp4")
            file = out
            try {
                val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, WIDTH, HEIGHT).apply {
                    setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                    setInteger(MediaFormat.KEY_BIT_RATE, 8_000_000)
                    setInteger(MediaFormat.KEY_FRAME_RATE, 30)
                    setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                }
                val c = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
                c.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                surface = c.createInputSurface()
                c.start()
                codec = c
                muxer = MediaMuxer(out.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                recording = true
                drainer = Thread({ drainLoop(c) }, "SpeechVideoDrain").apply { start() }
            } catch (_: Exception) {
                failed = true
                release()
            }
        }
    }

    /** One camera frame, already a bitmap; [rotation] as the camera reports
     *  it. Called on the camera's analysis thread. */
    fun append(frame: Bitmap, rotation: Int, cropWidth: Int) {
        synchronized(drawLock) {
            if (!recording || failed) return
            val l = layout ?: return
            val s = surface ?: return
            val canvas = runCatching { s.lockHardwareCanvas() }.getOrNull() ?: return
            try {
                draw(canvas, l, frame, rotation, cropWidth)
            } finally {
                runCatching { s.unlockCanvasAndPost(canvas) }
            }
        }
    }

    suspend fun finish(): Result? = withContext(Dispatchers.IO) {
        val c: MediaCodec
        synchronized(drawLock) { if (!recording) return@withContext null; recording = false }
        synchronized(lock) {
            c = codec ?: return@withContext null
            if (!eosSent) { runCatching { c.signalEndOfInputStream() }; eosSent = true }
        }
        drainer?.join(5000)
        drainer = null
        val out = file
        val first = firstPtsUs
        val ok = synchronized(lock) {
            val good = !failed && track >= 0
            runCatching { if (track >= 0) muxer?.stop() }
            release()
            good
        }
        if (!ok || out == null || first < 0) { out?.delete(); null }
        else Result(out, first * 1000)
    }

    fun cancel() {
        synchronized(drawLock) { recording = false }
        synchronized(lock) {
            runCatching { codec?.signalEndOfInputStream() }
            eosSent = true
        }
        drainer?.join(2000)
        drainer = null
        synchronized(lock) {
            runCatching { if (track >= 0) muxer?.stop() }
            release()
            file?.delete()
        }
    }

    private fun drainLoop(c: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        while (true) {
            val index = try { c.dequeueOutputBuffer(info, 10_000) } catch (_: Exception) { failed = true; return }
            when {
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> synchronized(lock) {
                    val m = muxer ?: return
                    track = m.addTrack(c.outputFormat)
                    m.start()
                }
                index >= 0 -> {
                    val buf = c.getOutputBuffer(index)
                    val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    if (buf != null && info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                        synchronized(lock) {
                            if (track >= 0) {
                                if (firstPtsUs < 0) firstPtsUs = info.presentationTimeUs
                                buf.position(info.offset); buf.limit(info.offset + info.size)
                                val shifted = MediaCodec.BufferInfo().apply {
                                    set(0, info.size, info.presentationTimeUs - firstPtsUs, info.flags)
                                }
                                runCatching { muxer?.writeSampleData(track, buf, shifted) }
                            }
                        }
                    }
                    runCatching { c.releaseOutputBuffer(index, false) }
                    if (eos) return
                }
                else -> if (!recording && eosSent && index == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    // keep waiting for the EOS buffer; the join() bounds it
                }
            }
        }
    }

    private fun release() {
        runCatching { codec?.stop() }
        runCatching { codec?.release() }
        codec = null
        runCatching { surface?.release() }
        surface = null
        runCatching { muxer?.release() }
        muxer = null
    }

    // MARK: - Drawing

    private fun draw(canvas: Canvas, l: Layout, frame: Bitmap, rotation: Int, cropWidth: Int) {
        val k = WIDTH / l.canvasW
        canvas.save()
        canvas.scale(k, k)
        bgPaint.color = l.background
        canvas.drawRect(0f, 0f, l.canvasW, l.canvasH, bgPaint)

        // The script, cropped to the prompter area, with its fades.
        column?.let { col ->
            canvas.save()
            canvas.clipRect(l.prompter)
            canvas.translate(l.prompter.left, l.prompter.top - offset)
            col.draw(canvas, offset - col.lineHeight, offset + l.prompter.height() + col.lineHeight)
            canvas.restore()
            val top = l.prompter.height() * l.topFade
            fadePaint.shader = LinearGradient(0f, l.prompter.top, 0f, l.prompter.top + top,
                l.background, l.background and 0x00FFFFFF, Shader.TileMode.CLAMP)
            canvas.drawRect(l.prompter.left, l.prompter.top, l.prompter.right, l.prompter.top + top, fadePaint)
            val bottom = l.prompter.height() * l.bottomFade
            fadePaint.shader = LinearGradient(0f, l.prompter.bottom - bottom, 0f, l.prompter.bottom,
                l.background and 0x00FFFFFF, l.background, Shader.TileMode.CLAMP)
            canvas.drawRect(l.prompter.left, l.prompter.bottom - bottom, l.prompter.right, l.prompter.bottom, fadePaint)
        }

        // The camera card: aspect-fill, mirrored like the preview, rounded.
        val card = l.card
        canvas.save()
        canvas.clipPath(Path().apply { addRoundRect(card, l.cardRadius, l.cardRadius, Path.Direction.CW) })
        val srcW = cropWidth.toFloat(); val srcH = frame.height.toFloat()
        val rotated = rotation % 180 != 0
        val shownW = if (rotated) srcH else srcW
        val shownH = if (rotated) srcW else srcH
        val fill = maxOf(card.width() / shownW, card.height() / shownH)
        val m = Matrix()
        m.postTranslate(-srcW / 2, -srcH / 2)
        m.postRotate(rotation.toFloat())
        m.postScale(-fill, fill)   // front camera: mirrored, as the preview shows it
        m.postTranslate(card.centerX(), card.centerY())
        canvas.concat(m)
        // Only the visible width: a padded row stride leaves junk columns.
        canvas.drawBitmap(frame, android.graphics.Rect(0, 0, cropWidth, frame.height),
            RectF(0f, 0f, srcW, srcH), bitmapPaint)
        canvas.restore()
        canvas.restore()
    }

    companion object {
        const val WIDTH = 1080
        const val HEIGHT = 1920
    }
}

/**
 * Puts the take's voice under its picture — iOS `SpeechMediaMerger`. The
 * picture's samples are COPIED (no re-encode); the voice is encoded to AAC.
 * [videoLeadInNanos]: how long the picture started before the voice (cut
 * from the picture); negative = the voice started first (cut from the voice).
 */
object SpeechMediaMerger {
    suspend fun merge(video: File, wav: File, out: File, videoLeadInNanos: Long): Boolean = withContext(Dispatchers.IO) {
        val pcm = WavPcm.read(wav) ?: return@withContext false
        val vLeadUs = maxOf(0L, videoLeadInNanos / 1000)
        val aLeadSamples = (maxOf(0L, -videoLeadInNanos) * pcm.sampleRate / 1_000_000_000L).toInt()
        val samples = if (aLeadSamples in 1 until pcm.samples.size)
            pcm.samples.copyOfRange(aLeadSamples, pcm.samples.size) else pcm.samples
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        try {
            extractor.setDataSource(video.path)
            val vIndex = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            } ?: return@withContext false
            extractor.selectTrack(vIndex)
            val vFormat = extractor.getTrackFormat(vIndex)
            val audioDurationUs = samples.size.toLong() * 1_000_000 / pcm.sampleRate
            out.delete()
            val mx = MediaMuxer(out.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = mx
            val vTrack = mx.addTrack(vFormat)
            // The voice, encoded first into memory: the muxer needs every
            // track added before it starts.
            var aFormat: MediaFormat? = null
            val aSamples = ArrayList<Pair<ByteArray, MediaCodec.BufferInfo>>()
            val ok = AacEncoder.encode(samples, pcm.sampleRate, 64_000, onFormat = { aFormat = it }) { buf, info ->
                val bytes = ByteArray(info.size); buf.get(bytes)
                aSamples += bytes to MediaCodec.BufferInfo().apply {
                    set(0, info.size, info.presentationTimeUs, info.flags)
                }
            }
            val af = aFormat
            if (!ok || af == null) return@withContext false
            val aTrack = mx.addTrack(af)
            mx.start()
            val buf = ByteBuffer.allocate(4 * 1024 * 1024)
            val info = MediaCodec.BufferInfo()
            if (vLeadUs > 0) extractor.seekTo(vLeadUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            var wrote = 0
            while (true) {
                val size = extractor.readSampleData(buf, 0)
                if (size < 0) break
                val t = extractor.sampleTime - vLeadUs
                if (t > audioDurationUs) break
                info.set(0, size, maxOf(0L, t), extractor.sampleFlags and MediaCodec.BUFFER_FLAG_KEY_FRAME)
                mx.writeSampleData(vTrack, buf, info)
                wrote++
                extractor.advance()
            }
            for ((bytes, i) in aSamples) mx.writeSampleData(aTrack, ByteBuffer.wrap(bytes), i)
            mx.stop()
            wrote > 0
        } catch (_: Exception) {
            false
        } finally {
            runCatching { muxer?.release() }
            extractor.release()
        }
    }
}
