package com.roro.futurevoice.ui.speech

import android.content.Context
import android.graphics.Bitmap
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.concurrent.Executors

/**
 * The front camera for a speech take — iOS `SpeechCamera`. VIDEO ONLY: the
 * voice is the app's own mic path ([com.roro.futurevoice.audio.SpeechCapture]).
 * Frames go to [frameHandler] on the camera's analysis thread, where the
 * composer draws the prompter over each one.
 */
class SpeechCamera(private val context: Context) {
    private val _running = MutableStateFlow(false)
    val running: StateFlow<Boolean> = _running

    /** (frame, rotation degrees, visible width) — the bitmap is reused, so a
     *  handler must be done with it before returning. */
    @Volatile var frameHandler: ((Bitmap, Int, Int) -> Unit)? = null
    /** Asked per frame; false skips the copy. */
    @Volatile var wantsFrames: () -> Boolean = { false }

    val previewView: PreviewView by lazy {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }
    }

    private val executor = Executors.newSingleThreadExecutor()
    private var provider: ProcessCameraProvider? = null
    private var reusable: Bitmap? = null

    fun start(owner: LifecycleOwner) {
        if (_running.value) return
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            val p = runCatching { future.get() }.getOrNull() ?: return@addListener
            provider = p
            val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
            val analysis = ImageAnalysis.Builder()
                .setResolutionSelector(ResolutionSelector.Builder()
                    .setResolutionStrategy(ResolutionStrategy(Size(1280, 720),
                        ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER))
                    .build())
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
            analysis.setAnalyzer(executor) { proxy ->
                try {
                    val handler = frameHandler
                    if (handler != null && wantsFrames()) {
                        val plane = proxy.planes[0]
                        val stride = plane.rowStride / plane.pixelStride
                        val buffer = plane.buffer
                        val bmp = if (buffer.remaining() >= stride * proxy.height * 4) {
                            val b = reusable?.takeIf { it.width == stride && it.height == proxy.height }
                                ?: Bitmap.createBitmap(stride, proxy.height, Bitmap.Config.ARGB_8888)
                                    .also { reusable = it }
                            buffer.rewind()
                            b.copyPixelsFromBuffer(buffer)
                            b
                        } else proxy.toBitmap()
                        handler(bmp, proxy.imageInfo.rotationDegrees,
                            if (bmp.width == stride) proxy.width else bmp.width)
                    }
                } catch (_: Exception) {
                } finally {
                    proxy.close()
                }
            }
            runCatching {
                p.unbindAll()
                p.bindToLifecycle(owner, CameraSelector.DEFAULT_FRONT_CAMERA, preview, analysis)
                _running.value = true
            }
        }, ContextCompat.getMainExecutor(context))
    }

    fun stop() {
        runCatching { provider?.unbindAll() }
        _running.value = false
    }
}
