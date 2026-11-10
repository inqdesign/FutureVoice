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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
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
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.talk.ShadowScore
import com.roro.futurevoice.talk.SpeechAnalyzer
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.SpanStyle
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
internal fun SpeechResultScreen(takeId: String, live: SpeechTake?, onBack: () -> Unit, onAgain: (() -> Unit)?,
                                onSeeBoard: (() -> Unit)? = null,
                                pages: List<String>? = null, onPage: ((String) -> Unit)? = null,
                                indicator: (@Composable () -> Unit)? = null) {
    val context = LocalContext.current
    val store = remember { SpeechStore.shared(context) }
    val takes by store.takes.collectAsStateWithLifecycle()
    val pending by store.videoPending.collectAsStateWithLifecycle()
    val stored = takes.firstOrNull { it.id == takeId }
    val take = if (live != null && stored?.coaching == null && live.coaching != null) live else stored ?: live
    val script = take?.let { store.script(it.scriptId) }
    val challenges = remember { com.roro.futurevoice.data.SpeechChallenges.shared(context) }
    val entries by challenges.entries.collectAsStateWithLifecycle()
    val standings by challenges.standings.collectAsStateWithLifecycle()
    val moments by challenges.moments.collectAsStateWithLifecycle()
    moments[takeId]?.let { moment ->
        SpeechChallengeMomentSheet(moment, onSeeBoard = onSeeBoard ?: {},
            onDismiss = { challenges.dismissMoment(takeId) })
    }

    if (take != null && script != null) {
        SpeechTakePage(take, script, take.id in pending, entries[take.id], standings[script.id], onBack, onAgain,
            pages, onPage, indicator)
        return
    }

    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        SheetHeader("", leading = { IosGlassTextButton(stringResource(R.string.done), onClick = onBack) },
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.take_not_found), style = MaterialTheme.typography.titleMedium)
        }
    }
}

/** What a take from before Season 2's scoring measured, each number with
 *  what it was measured against — iOS's "Measured" section. */
@Composable
internal fun MeasuredSection(take: SpeechTake, script: com.roro.futurevoice.data.SpeechScript) {
    val context = LocalContext.current
    val m = take.metrics
    FormSection(stringResource(R.string.measured)) {
        MetricRow(stringResource(R.string.accuracy), Icons.Filled.FactCheck, "${m.accuracy}%", null, m.accuracy)
        FormDivider(inset = 52.dp)
        // Measured per phoneme; its own row, not in the overall (the
        // board's weighting is checked server-side). What stood out:
        // this take's low SOUNDS (English), or a word low here that is
        // low across recent takes — a word low once is not said
        // (iOS 0971c05d, 14706881).
        m.pronunciation?.let { pron ->
            val detail = remember(take.id, pron) { pronunciationDetail(context, take, script.language) }
            // The whole assessment is a tap away when the take kept
            // it (iOS 53ec4f49).
            val all = take.assessments
            if (!all.isNullOrEmpty()) {
                var showingPronunciation by remember { mutableStateOf(false) }
                Row(Modifier.fillMaxWidth().clickable { showingPronunciation = true },
                    verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) {
                        MetricRow(stringResource(R.string.pronunciation), Icons.Filled.GraphicEq, "$pron", detail, pron)
                    }
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null,
                        Modifier.padding(end = 12.dp).size(18.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
                }
                if (showingPronunciation) {
                    com.roro.futurevoice.ui.PronunciationDetailSheet(all, script.language) {
                        showingPronunciation = false
                    }
                }
            } else {
                MetricRow(stringResource(R.string.pronunciation), Icons.Filled.GraphicEq, "$pron", detail, pron)
            }
            FormDivider(inset = 52.dp)
        }
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
}

@Composable
private fun rateLabel(value: Int, language: String): String = when (SpeechLibrary.rateUnit(language)) {
    SpeechLibrary.RateUnit.WORDS -> stringResource(R.string.lld_words_min, value)
    SpeechLibrary.RateUnit.SYLLABLES -> stringResource(R.string.lld_syllables_min, value)
    SpeechLibrary.RateUnit.CHARACTERS -> stringResource(R.string.lld_characters_min, value)
}

private fun pronunciationDetail(context: android.content.Context, take: SpeechTake, language: String): String {
    com.roro.futurevoice.data.PronunciationLedger.shared(context).entry(take.id, language)?.let { entry ->
        return com.roro.futurevoice.data.PronunciationProfile.current(context, language).noteLine(context, entry)
            ?: context.getString(R.string.no_sound_stood_out)
    }
    // A take from before the ledger: its own marked words.
    val weak = take.pronunciationWords.orEmpty().filter { it.isJudged }.take(3).map { it.word }
    return if (weak.isEmpty()) context.getString(R.string.no_sound_stood_out)
    else context.getString(R.string.work_on, weak.joinToString(" · "))
}

@Composable
private fun MetricRow(title: String, icon: ImageVector, value: String, detail: String?, score: Int) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(14.dp))
        Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        // A long detail line must wrap under the value, never squeeze the title.
        Column(Modifier.padding(start = 12.dp).widthIn(max = 190.dp), horizontalAlignment = Alignment.End) {
            Text(value, style = MaterialTheme.typography.bodyLarge, color = scoreColor(score))
            detail?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.End)
            }
        }
    }
}

/** The take's video: the picture, and one tap to play or pause — no control
 *  bar to bring up first. A play glyph shows while it is stopped; at the end
 *  a tap plays it again from the start. */
@Composable
internal fun TakeVideo(file: File, modifier: Modifier, autoplay: Boolean = false) {
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
                setOnPreparedListener {
                    it.isLooping = false
                    if (autoplay) { start(); playing = true } else seekTo(1)
                }
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
internal suspend fun saveVideoToGallery(context: Context, file: File): Boolean = withContext(Dispatchers.IO) {
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

/** The script as flowing text, each misread word in red: underlined with
 *  what the mic heard written small beside it, or struck through when it
 *  was skipped — iOS `SpeechMarkedScript`. [held] and [pauses] are by the
 *  script word's index across paragraphs: seconds a word was held longer than
 *  the native reading, and seconds of a stop after it where the native reading
 *  has none (Season 2 takes only). */
@Composable
internal fun MarkedScript(paragraphs: List<List<SpeechAnalyzer.ScriptMark>>, language: String,
                          held: Map<Int, Double> = emptyMap(), pauses: Map<Int, Double> = emptyMap()) {
    val red = Color(0xFFFF3B30)
    val orange = Color(0xFFFF9500)
    val gap = if (LanguageCatalog.writesSpaces(language)) " " else ""
    val seconds = stringResource(R.string.speech_seconds)
    fun label(s: Double) = seconds.format("%.1f".format(java.util.Locale.US, s))
    fun note(color: Color) = SpanStyle(color = color, fontSize = 11.sp, fontWeight = FontWeight.SemiBold,
        baselineShift = BaselineShift(0.5f))
    SelectionContainer {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            var first = 0
            paragraphs.forEach { line ->
                if (line.isEmpty()) return@forEach
                val start = first
                first += line.size
                Text(buildAnnotatedString {
                    line.forEachIndexed { i, mark ->
                        if (i > 0) append(gap)
                        val heldFor = held[start + i]
                        val wordColor = if (mark.op == ShadowScore.DiffOp.DEL || mark.op == ShadowScore.DiffOp.SUB) red else Color.Unspecified
                        val decoration = when (mark.op) {
                            ShadowScore.DiffOp.DEL -> TextDecoration.LineThrough
                            ShadowScore.DiffOp.SUB -> TextDecoration.Underline
                            else -> null
                        }
                        withStyle(SpanStyle(color = wordColor, textDecoration = decoration,
                            background = if (heldFor != null) orange.copy(alpha = 0.25f) else Color.Unspecified)) {
                            append(mark.word)
                        }
                        if (heldFor != null) {
                            withStyle(note(if (wordColor == red) red else orange)) { append(" " + label(heldFor)) }
                        }
                        val heard = mark.heard
                        if (mark.op == ShadowScore.DiffOp.SUB && !heard.isNullOrEmpty()) {
                            withStyle(SpanStyle(color = red, fontSize = 11.sp, fontStyle = FontStyle.Italic,
                                baselineShift = BaselineShift(0.5f))) { append(" " + heard) }
                        }
                        mark.added.forEach { extra -> withStyle(note(red)) { append(" +$extra") } }
                        pauses[start + i]?.let { s -> withStyle(note(orange)) { append(" ⏸︎" + label(s)) } }
                    }
                }, style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 30.sp))
            }
        }
    }
}

