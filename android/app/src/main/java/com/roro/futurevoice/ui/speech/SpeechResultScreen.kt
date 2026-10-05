package com.roro.futurevoice.ui.speech

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.widget.VideoView
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.FactCheck
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.SpeechLibrary
import com.roro.futurevoice.data.SpeechStore
import com.roro.futurevoice.data.SpeechTake
import com.roro.futurevoice.ui.FormCard
import com.roro.futurevoice.ui.FormDivider
import com.roro.futurevoice.ui.FormSection
import com.roro.futurevoice.ui.SheetHeader
import com.roro.futurevoice.ui.bottomBarInsets
import com.roro.futurevoice.ui.brand.IosGlassButton
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.DateFormat
import java.util.Date

/**
 * One scored take — iOS `SpeechResultView`: the overall score, the coach's
 * notes, the recording, and every measured number with what it was measured
 * against.
 */
@Composable
internal fun SpeechResultScreen(takeId: String, live: SpeechTake?, onBack: () -> Unit, onAgain: (() -> Unit)?) {
    val context = LocalContext.current
    val store = remember { SpeechStore.shared(context) }
    val takes by store.takes.collectAsStateWithLifecycle()
    val pending by store.videoPending.collectAsStateWithLifecycle()
    val stored = takes.firstOrNull { it.id == takeId }
    val take = if (live != null && stored?.coaching == null && live.coaching != null) live else stored ?: live
    val script = take?.let { store.script(it.scriptId) }

    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        SheetHeader(
            take?.let { takeDateLabel(it.createdAt) }.orEmpty(),
            leading = { IosGlassTextButton(stringResource(R.string.done), onClick = onBack) },
            trailing = onAgain?.let { again -> {
                IosGlassButton(onClick = again) {
                    Icon(Icons.Filled.Refresh, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(stringResource(R.string.again), color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.SemiBold)
                }
            } },
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
        if (take == null || script == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.take_not_found), style = MaterialTheme.typography.titleMedium)
            }
            return@Column
        }
        val m = take.metrics
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).bottomBarInsets()
            .padding(horizontal = 16.dp).padding(bottom = 32.dp)) {
            FormSection(script.title) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    ScoreRing(m.overall)
                    Spacer(Modifier.width(18.dp))
                    val coaching = take.coaching
                    if (coaching != null) {
                        Text(coaching.headline, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                    } else {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.writing_feedback), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                take.coaching?.tips?.forEach { tip ->
                    FormDivider()
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
                        Icon(Icons.AutoMirrored.Filled.ArrowForward, null, tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(10.dp))
                        Text(tip, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }

            Playback(take, take.id in pending)

            FormSection(stringResource(R.string.measured)) {
                MetricRow(stringResource(R.string.accuracy), Icons.Filled.FactCheck, "${m.accuracy}%", null, m.accuracy)
                FormDivider(inset = 52.dp)
                MetricRow(stringResource(R.string.pace), Icons.Filled.Speed, rateLabel(m.rate, script.language),
                    stringResource(R.string.comfortable_lld_lld, m.rateLow, m.rateHigh),
                    // Outside the band is never shown as good, however close.
                    if (m.rate in m.rateLow..m.rateHigh) 100 else minOf(m.paceScore, 80))
                FormDivider(inset = 52.dp)
                MetricRow(stringResource(R.string.pauses), Icons.Filled.PauseCircle,
                    stringResource(R.string.lld_of_lld, m.pausesAtBreaks, m.breaks),
                    if (m.hesitations > 0) stringResource(R.string.breaths_at_sentence_ends_long_stops_lld, m.hesitations)
                    else stringResource(R.string.breaths_at_sentence_ends), m.pauseScore)
                FormDivider(inset = 52.dp)
                MetricRow(stringResource(R.string.fillers), Icons.Filled.MoreHoriz, "${m.fillers}", null, m.fillerScore)
                FormDivider(inset = 52.dp)
                MetricRow(stringResource(R.string.steady_voice), Icons.Filled.GraphicEq, "${m.steadiness}",
                    stringResource(R.string.holding_your_volume_to_the_end_of_each_sentence), m.steadiness)
            }

            if (m.missed.isNotEmpty()) {
                FormSection(stringResource(R.string.skipped_or_changed)) {
                    Text(m.missed.joinToString("  ·  "), color = Color(0xFFFF3B30),
                        style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(16.dp))
                }
            }

            var heard by remember { mutableStateOf(false) }
            FormSection(null) {
                Row(Modifier.fillMaxWidth().clickable { heard = !heard }.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.what_the_mic_heard), modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyLarge)
                    Icon(if (heard) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null,
                        tint = MaterialTheme.colorScheme.primary)
                }
                if (heard) {
                    SelectionContainer {
                        Text(take.transcript, style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun rateLabel(value: Int, language: String): String = when (SpeechLibrary.rateUnit(language)) {
    SpeechLibrary.RateUnit.WORDS -> stringResource(R.string.lld_words_min, value)
    SpeechLibrary.RateUnit.SYLLABLES -> stringResource(R.string.lld_syllables_min, value)
    SpeechLibrary.RateUnit.CHARACTERS -> stringResource(R.string.lld_characters_min, value)
}

@Composable
private fun ScoreRing(score: Int) {
    val track = MaterialTheme.colorScheme.outlineVariant
    val color = scoreColor(score)
    Box(Modifier.size(80.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(72.dp)) {
            val w = 7.dp.toPx()
            val inset = w / 2
            val arcSize = Size(size.width - w, size.height - w)
            drawArc(track, 0f, 360f, false, Offset(inset, inset), arcSize, style = Stroke(w))
            drawArc(color, -90f, 360f * score / 100f, false, Offset(inset, inset), arcSize,
                style = Stroke(w, cap = StrokeCap.Round))
        }
        Text("$score", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun MetricRow(title: String, icon: ImageVector, value: String, detail: String?, score: Int) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(14.dp))
        Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.End) {
            Text(value, style = MaterialTheme.typography.bodyLarge, color = scoreColor(score))
            detail?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.End)
            }
        }
    }
}

/** The take's video (tap to play / pause, iOS `cf89d935`), "Preparing your
 *  video…", or the voice alone. */
@Composable
private fun Playback(take: SpeechTake, pending: Boolean) {
    val context = LocalContext.current
    val store = remember { SpeechStore.shared(context) }
    val scope = rememberCoroutineScope()
    val video = take.videoFilename
    var saved by remember(video) { mutableStateOf(false) }
    var photoError by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    val deniedText = stringResource(R.string.photos_access_is_off_turn_it_on_in_settings_to_save_videos)

    fun save(file: File) {
        scope.launch {
            saved = saveVideoToGallery(context, file)
            if (!saved) photoError = deniedText
        }
    }
    val storagePermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok && video != null) save(SpeechStore.mediaFile(context, video)) else photoError = deniedText
    }

    when {
        video != null -> FormSection(null,
            footer = stringResource(R.string.videos_stay_on_this_phone_and_aren_t_backed_up_save_the_ones_c9d7ac)) {
            val file = SpeechStore.mediaFile(context, video)
            var aspect by remember(video) { mutableStateOf(9f / 16f) }
            LaunchedEffect(video) { videoAspect(file)?.let { aspect = it } }
            Box(Modifier.padding(8.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
                TakeVideo(file, Modifier.heightIn(max = 520.dp).aspectRatio(aspect).clip(RoundedCornerShape(12.dp)))
            }
            FormDivider()
            ActionRow(if (saved) Icons.Filled.Check else Icons.Filled.Download,
                stringResource(if (saved) R.string.saved_to_photos else R.string.save_to_photos), enabled = !saved) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && ContextCompat.checkSelfPermission(context,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                    storagePermission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                } else save(file)
            }
            FormDivider()
            ActionRow(Icons.Filled.Delete, stringResource(R.string.delete_video), destructive = true) { confirmDelete = true }
        }
        pending -> FormSection(null) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(10.dp))
                Text(stringResource(R.string.preparing_your_video), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        else -> FormSection(null) {
            var player by remember { mutableStateOf<MediaPlayer?>(null) }
            DisposableEffect(take.id) { onDispose { player?.release(); player = null } }
            val playing = player != null
            ActionRow(if (playing) Icons.Filled.Stop else Icons.Filled.PlayArrow,
                stringResource(if (playing) R.string.stop else R.string.play_your_take)) {
                if (playing) { player?.release(); player = null }
                else player = runCatching {
                    MediaPlayer().apply {
                        setDataSource(SpeechStore.mediaFile(context, take.audioFilename).path)
                        setOnCompletionListener { it.release(); player = null }
                        prepare(); start()
                    }
                }.getOrNull()
            }
        }
    }
    if (confirmDelete) {
        AlertDialog(onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.delete_the_video_your_voice_and_score_stay)) },
            confirmButton = {
                TextButton(onClick = { confirmDelete = false; store.deleteVideo(take.id) }) {
                    Text(stringResource(R.string.delete_video), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel)) } })
    }
    photoError?.let { msg ->
        AlertDialog(onDismissRequest = { photoError = null },
            title = { Text(stringResource(R.string.couldn_t_save_to_photos)) }, text = { Text(msg) },
            confirmButton = { TextButton(onClick = { photoError = null }) { Text(stringResource(R.string.ok)) } })
    }
}

@Composable
private fun ActionRow(icon: ImageVector, label: String, enabled: Boolean = true, destructive: Boolean = false,
                      onClick: () -> Unit) {
    val color = when {
        destructive -> MaterialTheme.colorScheme.error
        enabled -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Row(Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = color, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(14.dp))
        Text(label, color = color, style = MaterialTheme.typography.bodyLarge)
    }
}

/** The take's video: the picture, and one tap to play or pause — no control
 *  bar to bring up first. A play glyph shows while it is stopped; at the end
 *  a tap plays it again from the start. */
@Composable
private fun TakeVideo(file: File, modifier: Modifier) {
    var playing by remember { mutableStateOf(false) }
    var view by remember { mutableStateOf<VideoView?>(null) }
    DisposableEffect(file) { onDispose { view?.stopPlayback() } }
    Box(modifier.background(Color.Black).clickable {
        val v = view ?: return@clickable
        if (playing) { v.pause(); playing = false }
        else {
            if (v.duration > 0 && v.currentPosition >= v.duration - 100) v.seekTo(0)
            v.start(); playing = true
        }
    }, contentAlignment = Alignment.Center) {
        AndroidView(factory = { ctx ->
            VideoView(ctx).apply {
                setVideoPath(file.path)
                setOnPreparedListener { it.isLooping = false; seekTo(1) }
                setOnCompletionListener { playing = false }
                view = this
            }
        }, modifier = Modifier.fillMaxSize())
        if (!playing) {
            Box(Modifier.size(68.dp).background(Color.Black.copy(alpha = 0.45f), CircleShape),
                contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.PlayArrow, stringResource(R.string.play), tint = Color.White,
                    modifier = Modifier.size(36.dp))
            }
        }
    }
}

private suspend fun videoAspect(file: File): Float? = withContext(Dispatchers.IO) {
    runCatching {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(file.path)
            val w = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toFloat() ?: return@runCatching null
            val h = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toFloat() ?: return@runCatching null
            val rot = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (rot % 180 != 0) h / w else w / h
        } finally { r.release() }
    }.getOrNull()
}

/** The mp4 into the shared gallery (Movies/nawana). API 29+ goes through
 *  MediaStore with no permission and holds the row PENDING until written. */
private suspend fun saveVideoToGallery(context: Context, file: File): Boolean = withContext(Dispatchers.IO) {
    runCatching {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, "nawana-speech-${System.currentTimeMillis()}.mp4")
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/nawana")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
        }
        val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values) ?: return@runCatching false
        val ok = resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) }; true } ?: false
        if (!ok) { resolver.delete(uri, null, null); return@runCatching false }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            resolver.update(uri, ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }, null, null)
        }
        true
    }.getOrDefault(false)
}
