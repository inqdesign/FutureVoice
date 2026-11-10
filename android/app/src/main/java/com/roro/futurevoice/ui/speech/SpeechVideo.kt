package com.roro.futurevoice.ui.speech

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Shader
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.view.Surface
import com.roro.futurevoice.audio.AacEncoder
import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.data.SpeechPrompterRecord
import com.roro.futurevoice.talk.SpeechPrompterTrack
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import kotlin.coroutines.coroutineContext
import kotlin.math.abs
import kotlin.math.roundToInt

/** How the script sits in a video made from a take, the learner's pick when
 *  saving — iOS `SpeechVideoStyle`, same raw values. */
enum class SpeechVideoStyle(val raw: String) {
    /** The camera as it was recorded, no script: nothing to make. */
    CAMERA_ONLY("cameraOnly"),
    /** The camera fills the frame and the script rolls over it in white, as
     *  on the take's own replay. */
    FULL_SCREEN("fullScreen"),
    /** The take screen: script on the top half, the camera card below. */
    SPLIT("split");

    companion object {
        fun from(raw: String?): SpeechVideoStyle = entries.firstOrNull { it.raw == raw } ?: FULL_SCREEN
    }
}

/**
 * A video encoder fed by drawing on its input surface, written to an MP4 as
 * it comes out. Frames carry the moment they were posted (`System.nanoTime`);
 * [ptsFor] turns that into the time written to the file.
 */
private class SurfaceEncoder(
    val out: File, width: Int, height: Int, mime: String, bitRate: Int,
    /** A sound track carried along, added beside the picture's. */
    private val audioFormat: MediaFormat? = null,
    /** (the frame's posted time, the first frame's) → the time to write, in µs. */
    private val ptsFor: (Long, Long) -> Long,
) {
    val surface: Surface
    private val codec: MediaCodec
    private val muxer: MediaMuxer
    private val lock = Any()
    @Volatile var failed = false
        private set
    @Volatile var firstPtsUs = -1L
        private set
    private var videoTrack = -1
    private var audioTrack = -1
    private var lastWritten = -1L
    private var wrote = 0
    private var released = false
    private val drainer: Thread

    init {
        val format = MediaFormat.createVideoFormat(mime, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            // Said out loud, so the export reads the picture back the way it
            // was written.
            setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709)
            setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
            setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
        }
        val c = MediaCodec.createEncoderByType(mime)
        var s: Surface? = null
        var m: MediaMuxer? = null
        try {
            c.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            s = c.createInputSurface()
            c.start()
            m = MediaMuxer(out.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        } catch (e: Exception) {
            runCatching { s?.release() }
            runCatching { c.release() }
            runCatching { m?.release() }
            throw e
        }
        codec = c; surface = s; muxer = m
        drainer = Thread({ drain() }, "SpeechVideoDrain").apply { start() }
    }

    private fun drain() {
        val info = MediaCodec.BufferInfo()
        while (true) {
            val index = try { codec.dequeueOutputBuffer(info, 10_000) } catch (_: Exception) { failed = true; return }
            when {
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> synchronized(lock) {
                    try {
                        videoTrack = muxer.addTrack(codec.outputFormat)
                        audioFormat?.let { audioTrack = muxer.addTrack(it) }
                        muxer.start()
                    } catch (_: Exception) { failed = true; return }
                }
                index >= 0 -> {
                    val buf = runCatching { codec.getOutputBuffer(index) }.getOrNull()
                    val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    if (buf != null && info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                        synchronized(lock) {
                            if (videoTrack >= 0) {
                                if (firstPtsUs < 0) firstPtsUs = info.presentationTimeUs
                                var at = maxOf(0L, ptsFor(info.presentationTimeUs, firstPtsUs))
                                if (at <= lastWritten) at = lastWritten + 1
                                lastWritten = at
                                buf.position(info.offset); buf.limit(info.offset + info.size)
                                val shifted = MediaCodec.BufferInfo().apply { set(0, info.size, at, info.flags) }
                                if (runCatching { muxer.writeSampleData(videoTrack, buf, shifted) }.isSuccess) wrote++
                            }
                        }
                    }
                    runCatching { codec.releaseOutputBuffer(index, false) }
                    if (eos) return
                }
            }
        }
    }

    /** Ends the picture, lets [audio] write the sound track (muxer, track),
     *  and closes the file. False: nothing usable was written. */
    fun finish(audio: ((MediaMuxer, Int) -> Unit)? = null): Boolean {
        runCatching { codec.signalEndOfInputStream() }
        drainer.join(10_000)
        return synchronized(lock) {
            var ok = !failed && !drainer.isAlive && videoTrack >= 0 && wrote > 0
            if (ok && audio != null && audioTrack >= 0) ok = runCatching { audio(muxer, audioTrack) }.isSuccess
            if (videoTrack >= 0 && runCatching { muxer.stop() }.isFailure) ok = false
            release()
            if (!ok) out.delete()
            ok
        }
    }

    fun cancel() {
        runCatching { codec.signalEndOfInputStream() }
        drainer.join(2000)
        synchronized(lock) {
            runCatching { if (videoTrack >= 0) muxer.stop() }
            release()
            out.delete()
        }
    }

    private fun release() {
        if (released) return
        released = true
        runCatching { codec.stop() }
        runCatching { codec.release() }
        runCatching { surface.release() }
        runCatching { muxer.release() }
    }

    companion object {
        /** HEVC where the device can write it at this size, H.264 otherwise. */
        fun cameraMime(width: Int, height: Int): String {
            val hevc = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_HEVC, width, height)
            val found = runCatching { MediaCodecList(MediaCodecList.REGULAR_CODECS).findEncoderForFormat(hevc) }.getOrNull()
            return if (found != null) MediaFormat.MIMETYPE_VIDEO_HEVC else MediaFormat.MIMETYPE_VIDEO_AVC
        }
    }
}

/**
 * Records the take's camera, and where the script was on each moment of it —
 * iOS `SpeechVideoComposer` (`85fca8ba`: keep the camera only, draw the
 * script in code, and make the video with the script when it is exported).
 *
 * Each camera frame is drawn upright and mirrored, as the preview shows it,
 * on the encoder's input surface, at the camera's own size (1080p where it
 * can). Frames carry the moment they were posted (`System.nanoTime`), the
 * clock [com.roro.futurevoice.audio.SpeechCapture.startNanos] is on, so the
 * merge can line the picture up with the voice.
 */
class SpeechVideoComposer {

    data class Result(
        val file: File,
        val firstFrameNanos: Long,
        /** [offset] every [SpeechPrompterRecord.STEP] seconds from the first frame, in pixels. */
        val offsets: List<Float>,
    )

    /** Column y drawn at the top of the prompter area, in pixels: set by the
     *  screen as the script moves. */
    @Volatile var offset: Float = 0f

    /** Held while a frame is drawn: the surface is never released mid-draw. */
    private val drawLock = Any()
    private var encoder: SurfaceEncoder? = null
    private var dir: File? = null
    private var size: Pair<Int, Int>? = null
    private var firstFrameAt = 0L
    private val offsets = ArrayList<Float>()
    @Volatile private var recording = false
    private var failed = false
    private val bitmapPaint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val matrix = Matrix()

    /** Frames from now on are written, into a temp file in [dir]. */
    fun begin(dir: File) {
        synchronized(drawLock) {
            encoder?.cancel()
            encoder = null
            size = null
            firstFrameAt = 0L
            offsets.clear()
            failed = false
            this.dir = dir
            recording = true
        }
    }

    /** One camera frame, already a bitmap; [rotation] as the camera reports
     *  it. Called on the camera's analysis thread. */
    fun append(frame: Bitmap, rotation: Int, cropWidth: Int) {
        synchronized(drawLock) {
            if (!recording || failed) return
            val turned = rotation % 180 != 0
            val w = (if (turned) frame.height else cropWidth) / 2 * 2
            val h = (if (turned) cropWidth else frame.height) / 2 * 2
            if (w <= 0 || h <= 0) return
            if (encoder == null) {
                encoder = open(w, h) ?: run { failed = true; return }
                size = w to h
            }
            // A phone turned mid-take changes the frame's shape; the file
            // keeps the one it started with.
            if (size != (w to h)) return
            val s = encoder?.surface ?: return
            val canvas = runCatching { s.lockHardwareCanvas() }.getOrNull() ?: return
            try {
                val srcW = cropWidth.toFloat(); val srcH = frame.height.toFloat()
                matrix.reset()
                matrix.postTranslate(-srcW / 2, -srcH / 2)
                matrix.postRotate(rotation.toFloat())
                matrix.postScale(-1f, 1f)   // front camera: mirrored, as the preview shows it
                matrix.postTranslate(w / 2f, h / 2f)
                canvas.drawColor(Color.BLACK)
                canvas.save()
                canvas.concat(matrix)
                // Only the visible width: a padded row stride leaves junk columns.
                canvas.drawBitmap(frame, android.graphics.Rect(0, 0, cropWidth, frame.height),
                    RectF(0f, 0f, srcW, srcH), bitmapPaint)
                canvas.restore()
            } finally {
                runCatching { s.unlockCanvasAndPost(canvas) }
            }
            val now = System.nanoTime()
            if (firstFrameAt == 0L) firstFrameAt = now
            val slot = ((now - firstFrameAt) / 1e9 / SpeechPrompterRecord.STEP).toInt()
            while (offsets.size <= slot) offsets += offset
        }
    }

    private fun open(width: Int, height: Int): SurfaceEncoder? {
        val dir = dir ?: return null
        val out = File(dir, "speech-camera-${System.nanoTime()}.mp4")
        // Sized for 1080p and scaled to what the camera gave.
        val scale = width.toLong() * height / (1920.0 * 1080)
        fun make(mime: String, at1080p: Int) = runCatching {
            SurfaceEncoder(out, width, height, mime, maxOf(2_000_000, (at1080p * scale).toInt())) { pts, first -> pts - first }
        }.getOrNull()
        // HEVC where the device can: 1080p in about the room H.264 needs for
        // 720p, so the better picture doesn't cost the phone's space.
        if (SurfaceEncoder.cameraMime(width, height) == MediaFormat.MIMETYPE_VIDEO_HEVC) {
            make(MediaFormat.MIMETYPE_VIDEO_HEVC, 8_000_000)?.let { return it }
            out.delete()
        }
        return make(MediaFormat.MIMETYPE_VIDEO_AVC, 12_000_000)
    }

    suspend fun finish(): Result? = withContext(Dispatchers.IO) {
        val enc: SurfaceEncoder?
        val marks: List<Float>
        synchronized(drawLock) {
            if (!recording) return@withContext null
            recording = false
            enc = encoder
            encoder = null
            marks = offsets.toList()
        }
        enc ?: return@withContext null
        val ok = enc.finish()
        val first = enc.firstPtsUs
        if (!ok || first < 0) { enc.out.delete(); null } else Result(enc.out, first * 1000, marks)
    }

    fun cancel() {
        val enc: SurfaceEncoder?
        synchronized(drawLock) {
            recording = false
            enc = encoder
            encoder = null
        }
        enc?.cancel()
    }
}

/**
 * Makes the video with the script in it, from a camera-only take and its
 * record of how the script moved — iOS `SpeechVideoExporter` and the
 * composing half of `SpeechVideoComposer`. Every camera frame is decoded,
 * drawn into the layout with the script where it was at that moment (the
 * words said so far lit), and written as H.264 at 1080 × 1920; the take's own
 * sound is copied under it.
 */
object SpeechVideoExporter {
    /** Output width in pixels; the layout's canvas is 9:16, so 1080×1920. */
    const val WIDTH = 1080

    /** Where things are, in the pixels of the screen the take was read on,
     *  top-left origin — iOS `Layout`. */
    class Layout(
        val canvasW: Float,
        val canvasH: Float,
        val prompter: RectF,
        val card: RectF,
        val cardRadius: Float,
        val background: Int,
        /** The prompter's fades, as fractions of its height (the screen's mask). */
        val topFade: Float,
        val bottomFade: Float,
        /** The camera is the whole frame and [card] is unused. */
        val fullBleed: Boolean,
    )

    /** The video is 9:16 whatever the phone: script on the top half, the
     *  camera card on the bottom (`Layout.standard`), or the script where
     *  that puts it with the camera behind everything (`Layout.fullScreen`).
     *  Its width is the screen's, so the script wraps as the reader saw it. */
    fun layout(record: SpeechPrompterRecord, style: SpeechVideoStyle, density: Float): Layout {
        val width = record.width.toFloat()
        val height = (width * 16 / 9).roundToInt().toFloat()
        val half = height / 2
        val full = style == SpeechVideoStyle.FULL_SCREEN
        fun px(v: Float) = v * density
        return Layout(
            canvasW = px(width), canvasH = px(height),
            prompter = RectF(0f, 0f, px(width), px(half - 6)),
            card = RectF(px(12f), px(half + 6), px(width - 12), px(height - 12)),
            cardRadius = px(24f),
            background = if (record.dark || full) Color.BLACK else Color.WHITE,
            // Full screen, the script runs to the very top of the picture;
            // without a real fade a line stops there cut in half.
            topFade = if (full) 0.08f else 0.015f, bottomFade = 0.14f, fullBleed = full,
        )
    }

    /** The script laid out as it stood on the reader's screen. Over the
     *  camera it is white, whatever the reader's screen was. */
    fun column(record: SpeechPrompterRecord, dark: Boolean, density: Float): PrompterColumn =
        PrompterColumn(SpeechPrompterTrack(record.text, record.language), record.language,
            widthPx = (record.width * density).toFloat(), textSizePx = (record.textSize * density).toFloat(),
            sidePx = 24 * density, color = if (dark) Color.WHITE else Color.BLACK)

    private class Brushes {
        val bitmap = Paint(Paint.FILTER_BITMAP_FLAG)
        val fill = Paint()
        val scrim = Paint()
        val mask = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN) }
        val matrix = Matrix()
        val path = Path()
    }

    /** [frame], aspect-filling [rect]. */
    private fun drawFilled(canvas: Canvas, frame: Bitmap, rect: RectF, b: Brushes) {
        val fill = maxOf(rect.width() / frame.width, rect.height() / frame.height)
        b.matrix.reset()
        b.matrix.postTranslate(-frame.width / 2f, -frame.height / 2f)
        b.matrix.postScale(fill, fill)
        b.matrix.postTranslate(rect.centerX(), rect.centerY())
        canvas.drawBitmap(frame, b.matrix, b.bitmap)
    }

    private fun draw(canvas: Canvas, l: Layout, column: PrompterColumn, frame: Bitmap, offset: Float,
                     reached: SpeechPrompterRecord.Reached?, b: Brushes) {
        val k = WIDTH / l.canvasW
        canvas.save()
        canvas.scale(k, k)
        if (l.fullBleed) {
            val full = RectF(0f, 0f, l.canvasW, l.canvasH)
            canvas.save()
            canvas.clipRect(full)
            drawFilled(canvas, frame, full, b)
            canvas.restore()
            // The darkening behind white script, the replay's own: black at
            // 60%, 35% halfway, gone at 61% of the height.
            val band = l.canvasH * 0.61f
            b.scrim.shader = LinearGradient(0f, 0f, 0f, band,
                intArrayOf(0x99000000.toInt(), 0x59000000, 0x00000000), floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
            canvas.drawRect(0f, 0f, l.canvasW, band, b.scrim)
        } else {
            b.fill.color = l.background
            canvas.drawRect(0f, 0f, l.canvasW, l.canvasH, b.fill)
        }

        // The script, cut to the prompter area, faded at its top and bottom.
        val p = l.prompter
        val layer = canvas.saveLayer(p, null)
        canvas.save()
        canvas.clipRect(p)
        canvas.translate(p.left, p.top - offset)
        column.draw(canvas, offset - column.lineHeight, offset + p.height() + column.lineHeight,
            reached, SpeechPrompterRecord.UNREAD_OPACITY.toFloat())
        canvas.restore()
        b.mask.shader = LinearGradient(0f, p.top, 0f, p.bottom,
            intArrayOf(Color.TRANSPARENT, Color.BLACK, Color.BLACK, Color.TRANSPARENT),
            floatArrayOf(0f, l.topFade, 1 - l.bottomFade, 1f), Shader.TileMode.CLAMP)
        canvas.drawRect(p, b.mask)
        canvas.restoreToCount(layer)

        if (!l.fullBleed) {
            // The camera card: aspect-fill, rounded corners.
            canvas.save()
            b.path.reset()
            b.path.addRoundRect(l.card, l.cardRadius, l.cardRadius, Path.Direction.CW)
            canvas.clipPath(b.path)
            drawFilled(canvas, frame, l.card, b)
            canvas.restore()
        }
        canvas.restore()
    }

    /**
     * A temporary movie in [dir] (the caller removes it), or null if it
     * couldn't be made. [progress] 0…0.98 as the take's length is covered.
     */
    suspend fun render(video: File, record: SpeechPrompterRecord, style: SpeechVideoStyle, density: Float,
                       dir: File, progress: (Float) -> Unit): File? = withContext(Dispatchers.IO) {
        val layout = layout(record, style, density)
        val column = column(record, record.dark || style == SpeechVideoStyle.FULL_SCREEN, density)
        val height = (WIDTH * layout.canvasH / maxOf(1f, layout.canvasW)).roundToInt() / 2 * 2
        dir.mkdirs()
        // The last one made for a share: nothing says when the share ended.
        dir.listFiles()?.filter { it.name.startsWith("speech-with-script-") }?.forEach { it.delete() }
        val out = File(dir, "speech-with-script-${java.util.UUID.randomUUID()}.mp4")
        val pictures = MediaExtractor()
        val sound = MediaExtractor()
        var decoder: MediaCodec? = null
        var encoder: SurfaceEncoder? = null
        try {
            pictures.setDataSource(video.path)
            val vIndex = (0 until pictures.trackCount).firstOrNull {
                pictures.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            } ?: return@withContext null
            pictures.selectTrack(vIndex)
            val vFormat = pictures.getTrackFormat(vIndex)
            val mime = vFormat.getString(MediaFormat.KEY_MIME) ?: return@withContext null
            val durationUs = if (vFormat.containsKey(MediaFormat.KEY_DURATION)) vFormat.getLong(MediaFormat.KEY_DURATION) else 0L
            if (durationUs <= 0) return@withContext null
            // The camera file's own sound: it is already in step with its picture.
            sound.setDataSource(video.path)
            val aIndex = (0 until sound.trackCount).firstOrNull {
                sound.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            }
            val aFormat = aIndex?.let { sound.selectTrack(it); sound.getTrackFormat(it) }

            // A frame drawn on the encoder's surface is stamped with the
            // moment it was posted, not the camera frame's own time. Each
            // posted frame is remembered with the time it stands for, and a
            // frame coming out of the encoder takes the nearest one's.
            val posted = ArrayDeque<LongArray>()
            var byClock: Boolean? = null
            var lastGiven = 0L
            val enc = SurfaceEncoder(out, WIDTH, height, MediaFormat.MIMETYPE_VIDEO_AVC, 8_000_000, aFormat) { pts, _ ->
                synchronized(posted) {
                    if (posted.isEmpty()) return@synchronized lastGiven + 33_333
                    // Not on the posting clock (never seen): frames in the order they went in.
                    if (byClock == null) byClock = abs(posted.first()[0] - pts) < 500_000
                    if (byClock == true) {
                        while (posted.size > 1 && abs(posted[1][0] - pts) <= abs(posted[0][0] - pts)) posted.removeFirst()
                    }
                    posted.removeFirst()[1].also { lastGiven = it }
                }
            }
            encoder = enc

            vFormat.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            val dec = MediaCodec.createDecoderByType(mime)
            decoder = dec
            dec.configure(vFormat, null, null, 0)
            dec.start()

            val reader = YuvFrame()
            val brushes = Brushes()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var drawn = 0
            while (!outputDone) {
                coroutineContext.ensureActive()
                if (enc.failed) return@withContext null
                if (!inputDone) {
                    val i = dec.dequeueInputBuffer(10_000)
                    if (i >= 0) {
                        val buf = dec.getInputBuffer(i) ?: return@withContext null
                        val size = pictures.readSampleData(buf, 0)
                        if (size < 0) {
                            dec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            dec.queueInputBuffer(i, 0, size, pictures.sampleTime, 0)
                            pictures.advance()
                        }
                    }
                }
                val o = dec.dequeueOutputBuffer(info, 10_000)
                if (o < 0) continue
                val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                val pts = info.presentationTimeUs
                val frame = if (info.size > 0) dec.getOutputImage(o)?.let { image ->
                    try { reader.read(image, dec.outputFormat) } finally { image.close() }
                } else null
                dec.releaseOutputBuffer(o, false)
                if (frame != null) {
                    val seconds = pts / 1_000_000.0
                    val canvas = enc.surface.lockHardwareCanvas()
                    try {
                        draw(canvas, layout, column, frame, (record.offset(seconds) * density).toFloat(),
                            record.reached(seconds), brushes)
                    } finally {
                        synchronized(posted) { posted.addLast(longArrayOf(System.nanoTime() / 1000, pts)) }
                        enc.surface.unlockCanvasAndPost(canvas)
                    }
                    drawn++
                    progress(minOf(0.98f, pts.toFloat() / durationUs))
                }
                if (eos) outputDone = true
            }
            if (drawn == 0) return@withContext null
            encoder = null
            val ok = enc.finish { muxer, track ->
                val buf = ByteBuffer.allocate(1024 * 1024)
                val sample = MediaCodec.BufferInfo()
                while (true) {
                    val size = sound.readSampleData(buf, 0)
                    if (size < 0) break
                    sample.set(0, size, maxOf(0L, sound.sampleTime), sound.sampleFlags and MediaCodec.BUFFER_FLAG_KEY_FRAME)
                    muxer.writeSampleData(track, buf, sample)
                    sound.advance()
                }
            }
            if (ok) out else null
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        } finally {
            runCatching { decoder?.stop() }
            runCatching { decoder?.release() }
            encoder?.cancel()
            pictures.release()
            sound.release()
        }
    }
}

/**
 * One decoded frame as a bitmap. The decoder hands out YUV 4:2:0 in whatever
 * layout the device uses; this reads it by its strides and turns it into the
 * RGB a canvas draws, by the matrix the stream names (BT.709 video range for
 * the app's own takes).
 */
private class YuvFrame {
    private var pixels = IntArray(0)
    private var bitmap: Bitmap? = null
    private var yRow = ByteArray(0)
    private var uRow = ByteArray(0)
    private var vRow = ByteArray(0)

    fun read(image: Image, format: MediaFormat): Bitmap? {
        val crop = image.cropRect
        val w = crop.width(); val h = crop.height()
        if (w <= 0 || h <= 0 || image.planes.size < 3) return null
        val bt601 = format.containsKey(MediaFormat.KEY_COLOR_STANDARD) &&
            format.getInteger(MediaFormat.KEY_COLOR_STANDARD).let {
                it == MediaFormat.COLOR_STANDARD_BT601_PAL || it == MediaFormat.COLOR_STANDARD_BT601_NTSC
            }
        val fullRange = format.containsKey(MediaFormat.KEY_COLOR_RANGE) &&
            format.getInteger(MediaFormat.KEY_COLOR_RANGE) == MediaFormat.COLOR_RANGE_FULL
        // Fixed point, 8 bits: y scale, then v→r, u→g, v→g, u→b.
        val ky: Int; val rv: Int; val gu: Int; val gv: Int; val bu: Int; val yOff: Int
        if (fullRange) {
            ky = 256; yOff = 0
            if (bt601) { rv = 359; gu = 88; gv = 183; bu = 454 } else { rv = 403; gu = 48; gv = 120; bu = 475 }
        } else {
            ky = 298; yOff = 16
            if (bt601) { rv = 409; gu = 100; gv = 208; bu = 516 } else { rv = 459; gu = 55; gv = 136; bu = 541 }
        }
        if (pixels.size != w * h) pixels = IntArray(w * h)
        val yP = image.planes[0]; val uP = image.planes[1]; val vP = image.planes[2]
        val yBuf = yP.buffer; val uBuf = uP.buffer; val vBuf = vP.buffer
        val yStep = yP.pixelStride; val cStep = uP.pixelStride
        val halfW = (w + 1) / 2
        val yLen = (w - 1) * yStep + 1
        val cLen = (halfW - 1) * cStep + 1
        if (yRow.size < yLen) yRow = ByteArray(yLen)
        if (uRow.size < cLen) { uRow = ByteArray(cLen); vRow = ByteArray(cLen) }
        val cx = crop.left / 2
        var loaded = -1
        for (j in 0 until h) {
            yBuf.position((crop.top + j) * yP.rowStride + crop.left * yStep)
            yBuf.get(yRow, 0, minOf(yLen, yBuf.remaining()))
            val cj = (crop.top + j) / 2
            if (cj != loaded) {
                uBuf.position(cj * uP.rowStride + cx * cStep)
                uBuf.get(uRow, 0, minOf(cLen, uBuf.remaining()))
                vBuf.position(cj * vP.rowStride + cx * cStep)
                vBuf.get(vRow, 0, minOf(cLen, vBuf.remaining()))
                loaded = cj
            }
            var at = j * w
            for (i in 0 until w) {
                val c = ((yRow[i * yStep].toInt() and 0xFF) - yOff) * ky
                val ci = (i shr 1) * cStep
                val d = (uRow[ci].toInt() and 0xFF) - 128
                val e = (vRow[ci].toInt() and 0xFF) - 128
                var r = (c + rv * e + 128) shr 8
                var g = (c - gu * d - gv * e + 128) shr 8
                var b = (c + bu * d + 128) shr 8
                if (r < 0) r = 0 else if (r > 255) r = 255
                if (g < 0) g = 0 else if (g > 255) g = 255
                if (b < 0) b = 0 else if (b > 255) b = 255
                pixels[at++] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        val out = bitmap?.takeIf { it.width == w && it.height == h }
            ?: Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also { bitmap = it }
        out.setPixels(pixels, 0, w, 0, 0, w, h)
        return out
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
