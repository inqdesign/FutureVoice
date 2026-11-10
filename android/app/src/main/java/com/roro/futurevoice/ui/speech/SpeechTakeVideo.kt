package com.roro.futurevoice.ui.speech

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.os.Build
import android.view.Surface
import android.view.TextureView
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.FormatAlignLeft
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.SmartDisplay
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.SpeechPrompterRecord
import com.roro.futurevoice.data.SpeechStore
import com.roro.futurevoice.data.SpeechTake
import com.roro.futurevoice.ui.SheetHeader
import com.roro.futurevoice.ui.brand.IosButton
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import com.roro.futurevoice.ui.brand.IosOutlinedButton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * The picture behind the score — iOS `SpeechHeroPlayer`: six seconds looping
 * without sound, or the whole take with sound once play is pressed, back to
 * the loop at its end.
 */
internal class SpeechHeroPlayer {
    var isPlaying by mutableStateOf(false)
        private set
    /** The whole take is loaded, playing or paused, not the silent loop. */
    var isFull by mutableStateOf(false)
        private set
    /** The picture's own shape, once known. */
    var videoSize by mutableStateOf(0 to 0)
        private set

    private var player: MediaPlayer? = null
    private var prepared = false
    private var surface: Surface? = null
    private var file: File? = null
    private var loopStart = 0
    private var loopEnd = 0

    fun show(file: File?) {
        if (file == this.file) return
        release()
        this.file = file
        file ?: return
        val p = MediaPlayer()
        player = p
        try {
            p.setDataSource(file.path)
            surface?.let { p.setSurface(it) }
            p.setOnVideoSizeChangedListener { _, w, h -> if (w > 0 && h > 0) videoSize = w to h }
            p.setOnPreparedListener {
                if (player === it) { prepared = true; startLoop() }
            }
            // The whole take ended, or a loop shorter than six seconds did.
            p.setOnCompletionListener { if (player === it) startLoop() }
            p.setOnErrorListener { _, _, _ -> true }
            p.prepareAsync()
        } catch (_: Exception) {
            release()
        }
    }

    private fun startLoop() {
        val p = player ?: return
        if (!prepared) return
        runCatching {
            val duration = p.duration
            // Skips the first breath of the take when there is enough of it.
            loopStart = if (duration > (LOOP_START + LOOP_SECONDS) * 1000) LOOP_START * 1000 else 0
            loopEnd = minOf(duration, loopStart + LOOP_SECONDS * 1000)
            isFull = false
            isPlaying = false
            p.setVolume(0f, 0f)
            p.seekTo(loopStart.toLong(), MediaPlayer.SEEK_CLOSEST)
            p.start()
        }
    }

    /** Called a few times a second: the loop's end sends it back to its start. */
    fun tick() {
        val p = player ?: return
        if (!prepared || isFull) return
        runCatching {
            if (p.currentPosition >= loopEnd - 60) p.seekTo(loopStart.toLong(), MediaPlayer.SEEK_CLOSEST)
        }
    }

    fun toggle() {
        val p = player ?: return
        if (!prepared) return
        runCatching {
            if (isFull) {
                if (isPlaying) p.pause() else p.start()
                isPlaying = !isPlaying
            } else {
                isFull = true
                isPlaying = true
                p.setVolume(1f, 1f)
                p.seekTo(0L, MediaPlayer.SEEK_CLOSEST)
                p.start()
            }
        }
    }

    /** Where the take is, in seconds of its video. */
    val seconds: Double
        get() = if (prepared) runCatching { (player?.currentPosition ?: 0) / 1000.0 }.getOrDefault(0.0) else 0.0

    fun attach(surface: Surface?) {
        this.surface = surface
        runCatching { player?.setSurface(surface) }
    }

    /** The app left the screen: nothing keeps playing behind it. */
    fun background() {
        if (!prepared) return
        runCatching { player?.pause() }
        if (isFull) isPlaying = false
    }

    fun foreground() {
        if (prepared && !isFull) runCatching { player?.start() }
    }

    fun stop() {
        release()
        file = null
    }

    private fun release() {
        runCatching { player?.release() }
        player = null
        prepared = false
        isFull = false
        isPlaying = false
        videoSize = 0 to 0
    }

    companion object {
        const val LOOP_SECONDS = 6
        const val LOOP_START = 3
    }
}

/** The take's picture filling the page, its edges cut — iOS
 *  `PlayerLayerView(fill: true)`. */
@Composable
internal fun HeroVideo(hero: SpeechHeroPlayer, modifier: Modifier = Modifier) {
    val size = hero.videoSize
    fun fill(view: TextureView, video: Pair<Int, Int>) {
        val vw = view.width.toFloat(); val vh = view.height.toFloat()
        val (w, h) = video
        if (vw <= 0 || vh <= 0 || w <= 0 || h <= 0) return
        val scale = maxOf(vw / w, vh / h)
        view.setTransform(Matrix().apply { setScale(w * scale / vw, h * scale / vh, vw / 2, vh / 2) })
    }
    AndroidView(modifier = modifier, factory = { context ->
        TextureView(context).apply {
            isOpaque = false
            var held: Surface? = null
            surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
                    held = Surface(texture)
                    hero.attach(held)
                }
                override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {}
                override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
                    hero.attach(null)
                    held?.release()
                    held = null
                    return true
                }
                override fun onSurfaceTextureUpdated(texture: SurfaceTexture) {}
            }
            addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ ->
                @Suppress("UNCHECKED_CAST")
                (v.tag as? Pair<Int, Int>)?.let { fill(v as TextureView, it) }
            }
        }
    }, update = { view ->
        view.tag = size
        fill(view, size)
    })
}

/**
 * The script rolling over the camera while a take plays — iOS
 * `SpeechScriptOverlay`: drawn here, not stored in the video, always white on
 * the picture, each word lit as it was said.
 */
@Composable
internal fun SpeechScriptOverlay(record: SpeechPrompterRecord, hero: SpeechHeroPlayer, modifier: Modifier = Modifier) {
    val density = LocalDensity.current.density
    val column = remember(record.text, record.language, record.width, record.textSize, density) {
        SpeechVideoExporter.column(record, dark = true, density = density)
    }
    val layout = remember(record.width, density) { SpeechVideoExporter.layout(record, SpeechVideoStyle.SPLIT, density) }
    var seconds by remember { mutableDoubleStateOf(hero.seconds) }
    LaunchedEffect(hero) { while (true) withFrameNanos { seconds = hero.seconds } }
    Box(modifier.fillMaxSize()) {
        // Keeps the white script readable on any picture.
        Box(Modifier.fillMaxWidth().height(520.dp).background(Brush.verticalGradient(
            listOf(Color.Black.copy(alpha = 0.6f), Color.Black.copy(alpha = 0.35f), Color.Transparent))))
        Canvas(
            Modifier.statusBarsPadding().fillMaxWidth().aspectRatio(layout.canvasW / layout.prompter.height())
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    drawRect(Brush.verticalGradient(0f to Color.Transparent, layout.topFade to Color.Black,
                        1 - layout.bottomFade to Color.Black, 1f to Color.Transparent), blendMode = BlendMode.DstIn)
                },
        ) {
            val k = size.width / layout.canvasW
            val offset = (record.offset(seconds) * density).toFloat()
            drawContext.canvas.nativeCanvas.apply {
                save()
                clipRect(0f, 0f, size.width, size.height)
                scale(k, k)
                translate(0f, -offset)
                column.draw(this, offset - column.lineHeight, offset + layout.prompter.height() + column.lineHeight,
                    record.reached(seconds), SpeechPrompterRecord.UNREAD_OPACITY.toFloat())
                restore()
            }
        }
    }
}

/** Shown only while the take plays: the script over the picture, or not. */
@Composable
internal fun ScriptToggle(on: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(modifier.size(48.dp).clip(CircleShape)
        .background(if (on) Color.White else Color.Black.copy(alpha = 0.45f))
        .clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(Icons.AutoMirrored.Filled.FormatAlignLeft,
            stringResource(if (on) R.string.speech_hide_script else R.string.speech_show_script),
            tint = if (on) Color.Black else Color.White, modifier = Modifier.size(22.dp))
    }
}

/** What the save sheet has done so far; kept by the page, so it is still
 *  true when the sheet is opened again. */
internal class SpeechVideoSaveState {
    /** How far the video with the script has been made, while it is. */
    var exporting by mutableStateOf<Float?>(null)
    /** The layouts already saved to the gallery (`SpeechVideoStyle.raw`). */
    val saved = mutableStateListOf<String>()
    var error by mutableStateOf<String?>(null)
}

/**
 * What can be done with the take's video, from the header's button — iOS
 * `videoOptions`. A camera-only take picks a layout on its own picture, then
 * posts or saves it; a take from before the camera was kept has the script in
 * its video already.
 */
@Composable
internal fun SpeechVideoSheet(take: SpeechTake, file: File, state: SpeechVideoSaveState, scope: CoroutineScope,
                              onWatch: () -> Unit, onDeleted: () -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val density = LocalDensity.current.density
    val prefs = remember { context.getSharedPreferences("futurevoice", Context.MODE_PRIVATE) }
    val record = take.prompter
    var style by remember { mutableStateOf(SpeechVideoStyle.from(prefs.getString(EXPORT_STYLE_KEY, null))) }
    var confirmDelete by remember { mutableStateOf(false) }
    var frame by remember(file) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(file) { frame = layoutFrame(file) }
    val denied = stringResource(R.string.photos_access_is_off_turn_it_on_in_settings_to_save_videos)
    val failed = stringResource(R.string.speech_couldnt_make_video)

    fun fail(message: String) {
        onDismiss()
        state.error = message
    }
    suspend fun saveToPhotos(video: File, mark: String) {
        if (saveVideoToGallery(context, video)) { if (mark !in state.saved) state.saved += mark } else fail(denied)
    }
    /** Instagram gives an app no way to post by itself: the finished video
     *  goes to the system's share sheet, and Instagram's own screen takes it
     *  from there. */
    fun produce(sharing: Boolean) {
        val picked = style
        scope.launch {
            if (picked == SpeechVideoStyle.CAMERA_ONLY || record == null) {
                if (sharing) shareVideo(context, file) else saveToPhotos(file, SpeechVideoStyle.CAMERA_ONLY.raw)
                return@launch
            }
            state.exporting = 0f
            val started = System.currentTimeMillis()
            val made = SpeechVideoExporter.render(file, record, picked, density, File(context.cacheDir, "share")) { value ->
                scope.launch { if (state.exporting != null) state.exporting = value }
            }
            Analytics.capture("speech_video_export", mapOf(
                "ok" to (made != null), "ms" to (System.currentTimeMillis() - started),
                "seconds" to record.offsets.size / 10, "style" to picked.raw,
                "to" to if (sharing) "instagram" else "photos"))
            state.exporting = null
            if (made == null) { fail(failed); return@launch }
            if (sharing) { shareVideo(context, made); return@launch }
            saveToPhotos(made, picked.raw)
            made.delete()
        }
    }
    val storagePermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) produce(sharing = false) else fail(denied)
    }
    fun save() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && ContextCompat.checkSelfPermission(context,
                Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            storagePermission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        } else produce(sharing = false)
    }
    val footer = stringResource(R.string.videos_stay_on_this_phone_and_aren_t_backed_up_save_the_ones_c9d7ac)

    SpeechSheet(onDismiss, fullHeight = record != null, medium = record == null) {
        SheetHeader(if (record != null) stringResource(R.string.speech_save_video) else "", trailing = {
            IosGlassTextButton(stringResource(R.string.done), bold = true, onClick = onDismiss)
        })
        if (record != null) {
            // The layout picked on the take's own picture, then one thing to
            // do with it. What is rarely wanted sits small underneath.
            val busy = state.exporting != null
            Row(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.Top) {
                LayoutTile(SpeechVideoStyle.CAMERA_ONLY, stringResource(R.string.speech_layout_full_screen),
                    style, record, frame, !busy) { style = it; prefs.edit().putString(EXPORT_STYLE_KEY, it.raw).apply() }
                LayoutTile(SpeechVideoStyle.FULL_SCREEN, stringResource(R.string.speech_layout_full_screen_captions),
                    style, record, frame, !busy) { style = it; prefs.edit().putString(EXPORT_STYLE_KEY, it.raw).apply() }
                LayoutTile(SpeechVideoStyle.SPLIT, stringResource(R.string.speech_layout_split),
                    style, record, frame, !busy) { style = it; prefs.edit().putString(EXPORT_STYLE_KEY, it.raw).apply() }
            }
            Spacer(Modifier.height(24.dp))
            val progress = state.exporting
            if (progress != null) {
                Column(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth())
                    Text(stringResource(R.string.preparing_your_video), style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                val saved = style.raw in state.saved
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    IosButton(onClick = { produce(sharing = true) }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.speech_post_to_instagram))
                    }
                    IosOutlinedButton(onClick = { save() }, enabled = !saved, modifier = Modifier.fillMaxWidth()) {
                        if (saved) {
                            Icon(Icons.Filled.Check, null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text(stringResource(R.string.saved_to_photos))
                        } else Text(stringResource(R.string.save_to_photos))
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
            SheetAction(Icons.Filled.Delete, stringResource(R.string.delete_video), destructive = true,
                padded = false) { confirmDelete = true }
            Text(footer, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 14.dp))
        } else {
            // A take from before the camera was kept: the script is in its video.
            val saved = SpeechVideoStyle.CAMERA_ONLY.raw in state.saved
            com.roro.futurevoice.ui.FormSection(null, footer = footer) {
                SheetAction(Icons.Filled.SmartDisplay, stringResource(R.string.speech_watch_script_video)) {
                    onDismiss()
                    onWatch()
                }
                com.roro.futurevoice.ui.FormDivider()
                SheetAction(if (saved) Icons.Filled.Check else Icons.Filled.Download,
                    stringResource(if (saved) R.string.saved_to_photos else R.string.save_to_photos), enabled = !saved) { save() }
                com.roro.futurevoice.ui.FormDivider()
                SheetAction(Icons.Filled.Delete, stringResource(R.string.delete_video), destructive = true) {
                    confirmDelete = true
                }
            }
        }
    }
    if (confirmDelete) {
        AlertDialog(onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.delete_the_video_your_voice_and_score_stay)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    onDeleted()
                    SpeechStore.shared(context).deleteVideo(take.id)
                    onDismiss()
                }) { Text(stringResource(R.string.delete_video), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel)) } })
    }
}

private const val EXPORT_STYLE_KEY = "speech.exportStyle"

@Composable
private fun SheetAction(icon: ImageVector, label: String, enabled: Boolean = true, destructive: Boolean = false,
                        padded: Boolean = true, onClick: () -> Unit) {
    val color = when {
        destructive -> MaterialTheme.colorScheme.error
        enabled -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Row(Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick)
        .padding(if (padded) 16.dp else 0.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = color, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(if (padded) 14.dp else 8.dp))
        Text(label, color = color, style = if (padded) MaterialTheme.typography.bodyLarge else MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun RowScope.LayoutTile(style: SpeechVideoStyle, title: String, picked: SpeechVideoStyle,
                                record: SpeechPrompterRecord, frame: Bitmap?, enabled: Boolean,
                                onPick: (SpeechVideoStyle) -> Unit) {
    val selected = picked == style
    val accent = MaterialTheme.colorScheme.primary
    Column(Modifier.weight(1f).semantics { this.selected = selected }
        .clickable(enabled = enabled, interactionSource = remember { MutableInteractionSource() }, indication = null) {
            onPick(style)
        }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val shape = RoundedCornerShape(14.dp)
        Box(Modifier.fillMaxWidth().aspectRatio(9f / 16f).clip(shape)
            .border(if (selected) 3.dp else 1.dp, if (selected) accent else MaterialTheme.colorScheme.outlineVariant, shape)) {
            LayoutPreview(style, record, frame)
        }
        Text(title, style = MaterialTheme.typography.bodySmall,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (selected) accent else MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun LayoutPreview(style: SpeechVideoStyle, record: SpeechPrompterRecord, frame: Bitmap?) {
    @Composable
    fun Script(color: Color, modifier: Modifier) {
        Text(record.text.take(90), color = color, fontSize = 7.sp, lineHeight = 9.sp, fontWeight = FontWeight.SemiBold,
            overflow = TextOverflow.Clip, modifier = modifier.padding(6.dp))
    }
    when (style) {
        SpeechVideoStyle.CAMERA_ONLY -> LayoutPicture(frame, Modifier.fillMaxSize())
        SpeechVideoStyle.FULL_SCREEN -> Box(Modifier.fillMaxSize()) {
            LayoutPicture(frame, Modifier.fillMaxSize())
            Box(Modifier.fillMaxWidth().fillMaxHeight(0.5f).background(Brush.verticalGradient(
                listOf(Color.Black.copy(alpha = 0.6f), Color.Transparent))))
            Script(Color.White, Modifier.fillMaxSize())
        }
        SpeechVideoStyle.SPLIT -> Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface),
            verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Script(MaterialTheme.colorScheme.onSurface, Modifier.weight(1f).fillMaxWidth())
            LayoutPicture(frame, Modifier.weight(1f).fillMaxWidth()
                .padding(start = 4.dp, end = 4.dp, bottom = 4.dp).clip(RoundedCornerShape(8.dp)))
        }
    }
}

/** A picture of any shape fills its box and is cut. With no frame (still
 *  loading, or the file can't be read) a figure stands in for the speaker, so
 *  the three layouts still read as three layouts and not three grey boxes. */
@Composable
private fun LayoutPicture(frame: Bitmap?, modifier: Modifier) {
    Box(modifier.background(MaterialTheme.colorScheme.surfaceContainerHighest), contentAlignment = Alignment.BottomCenter) {
        if (frame != null) {
            Image(frame.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        } else {
            Icon(Icons.Filled.Person, null, tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                modifier = Modifier.fillMaxWidth(0.6f).aspectRatio(1f))
        }
    }
}

/** A frame 3 s in, or from the middle of a take shorter than 6 s: a time
 *  past the end returns no frame at all. */
private suspend fun layoutFrame(file: File): Bitmap? = withContext(Dispatchers.IO) {
    runCatching {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(file.path)
            val length = (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) / 1000.0
            val at = if (length > 0) minOf(3.0, length / 2) else 0.0
            val full = r.getFrameAtTime((at * 1_000_000).toLong(), MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: return@runCatching null
            val scale = 480f / maxOf(full.width, full.height)
            if (scale >= 1f) full
            else Bitmap.createScaledBitmap(full, (full.width * scale).toInt(), (full.height * scale).toInt(), true)
        } finally { r.release() }
    }.getOrNull()
}

/** The video into the system's share sheet. The take's own file is staged in
 *  the cache first: only the share folder is handed to other apps. */
private suspend fun shareVideo(context: Context, video: File) {
    val uri = withContext(Dispatchers.IO) {
        runCatching {
            val dir = File(context.cacheDir, "share").apply { mkdirs() }
            val staged = if (video.parentFile == dir) video
                else File(dir, "nawana-speech.mp4").also { video.copyTo(it, overwrite = true) }
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", staged)
        }.getOrNull()
    } ?: return
    runCatching {
        context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
            type = "video/mp4"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }, null))
    }
}
