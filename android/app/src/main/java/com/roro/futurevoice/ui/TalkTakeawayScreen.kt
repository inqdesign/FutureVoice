package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.TalkCurriculum
import com.roro.futurevoice.data.WeeklyTestEngine
import com.roro.futurevoice.net.WordLore
import com.roro.futurevoice.talk.ScenarioCurriculum
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.brand.IosButton
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import java.io.File

/**
 * "Before you go" (iOS `TalkTakeawayView`, 2026-11-17): the one screen shown
 * right after a talk, over its book. One item from each chapter (a word, an
 * expression, a corrected sentence, a line to shadow), chosen by code, so a
 * learner who closes the app now still leaves with the talk's most useful
 * things. Nothing to do and nothing to tick: it is read, then closed, and the
 * book underneath is the same book as always.
 */
data class TalkTakeaway(
    val word: Entry? = null,
    val expression: Entry? = null,
    val fix: Fix? = null,
    val line: Line? = null,
) {
    data class Entry(val text: String, val example: String?)
    data class Fix(val original: String?, val fluent: String, val reason: String)
    data class Line(val turnId: String, val text: String)

    val isEmpty: Boolean get() = word == null && expression == null && fix == null && line == null

    /** Analytics: which of the four were there. */
    val parts: String get() = listOfNotNull(
        word?.let { "word" }, expression?.let { "expression" },
        fix?.let { "fix" }, line?.let { "line" }).joinToString(",")

    companion object {
        /** The curriculum lists are already in teaching order, so the first
         *  unmastered item is the one; a fully mastered list gives its first. */
        fun make(session: Session, curriculum: TalkCurriculum.Snapshot, fix: Fix?): TalkTakeaway {
            val fluentText = session.turns.filter { it.role == TurnRole.FLUENT_SELF }.map { it.transcript }
            fun firstOpen(items: List<ScenarioCurriculum.Item>) =
                items.firstOrNull { it.masteredAt == null } ?: items.firstOrNull()
            fun example(text: String): String? {
                val needle = text.lowercase()
                for (turn in fluentText) for (s in TalkCurriculum.sentences(turn)) {
                    if (s.lowercase().contains(needle)) return s.trim()
                }
                return null
            }
            return TalkTakeaway(
                word = firstOpen(curriculum.words)?.let { Entry(it.text, example(it.text)) },
                expression = firstOpen(curriculum.expressions)?.let {
                    Entry(it.text.replaceFirstChar { c -> c.uppercase() }, example(it.text))
                },
                fix = fix,
                line = firstOpen(curriculum.shadowLines)?.let { Line(it.id, it.text) },
            )
        }
    }
}

@Composable
fun TalkTakeawayDialog(takeaway: TalkTakeaway, session: Session, language: String,
                       onClose: (how: String) -> Unit) {
    var closed by remember { mutableStateOf(false) }
    val shownAt = remember { System.currentTimeMillis() }
    fun close(how: String) {
        if (closed) return
        closed = true
        Analytics.capture("talk_takeaway_closed", mapOf(
            "how" to how, "seconds" to ((System.currentTimeMillis() - shownAt) / 1000).toInt()))
        onClose(how)
    }
    Dialog(
        onDismissRequest = { close("swipe") },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        DialogSystemBarsLikeActivity()
        TalkTakeawayScreen(takeaway, session, language, onClose = ::close)
    }
}

@Composable
private fun TalkTakeawayScreen(takeaway: TalkTakeaway, session: Session, language: String,
                               onClose: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val player = remember { Mp3Player(context.cacheDir, source = "takeaway") }
    var playing by remember { mutableStateOf(false) }
    DisposableEffect(Unit) { onDispose { player.stop() } }
    var wordMeaning by remember { mutableStateOf<String?>(null) }
    var expressionMeaning by remember { mutableStateOf<String?>(null) }
    // One sense each, from the same free, shared dictionary the word card
    // uses. A miss just leaves the line out.
    LaunchedEffect(takeaway) {
        val native = context.getSharedPreferences("futurevoice", 0)
            .getString("futurevoice.nativeLanguage", null) ?: "en"
        val lore = WordLore(AuthRepository())
        val w = takeaway.word?.let { async { runCatching { lore.entry(it.text, native, language, WordLore.Kind.WORD) }.getOrNull() } }
        val e = takeaway.expression?.let { async { runCatching { lore.entry(it.text, native, language, WordLore.Kind.EXPRESSION) }.getOrNull() } }
        wordMeaning = w?.await()?.senses?.firstOrNull()?.meaning
        expressionMeaning = e?.await()?.senses?.firstOrNull()?.meaning
    }
    val lineAudio: File? = remember(takeaway.line) {
        takeaway.line?.let { l -> session.turns.firstOrNull { it.id == l.turnId } }
            ?.let { WeeklyTestEngine.turnAudio(context, it) }
    }
    val ground = MaterialTheme.colorScheme.surfaceContainerLow
    Box(Modifier.fillMaxSize().background(ground)) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp)) {
                IconButton(onClick = { player.stop(); onClose("close") }) {
                    Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close))
                }
            }
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp).padding(bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Column(Modifier.padding(horizontal = 4.dp).padding(bottom = 6.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(R.string.before_you_go),
                        style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                    Text(stringResource(R.string.one_thing_from_each_part_of_this_talk),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                takeaway.word?.let {
                    EntryCard(stringResource(R.string.word), Icons.Filled.MenuBook, Color(0xFFAF52DE), it, wordMeaning)
                }
                takeaway.expression?.let {
                    EntryCard(stringResource(R.string.expression), Icons.Filled.FormatQuote, Color(0xFFFF2D55), it, expressionMeaning)
                }
                takeaway.fix?.let { f ->
                    TakeawayCard {
                        KindLabel(stringResource(R.string.fixed_sentence), Icons.Filled.Edit, Color(0xFFFF9500))
                        if (!f.original.isNullOrBlank()) {
                            Text(f.original, style = MaterialTheme.typography.bodyLarge.copy(
                                textDecoration = TextDecoration.LineThrough),
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        val accent = MaterialTheme.colorScheme.primary
                        val fluent = remember(f, accent) {
                            if (f.original.isNullOrBlank()) AnnotatedString(f.fluent)
                            else correctionLine(f.fluent, f.original, language,
                                SpanStyle(color = accent, fontWeight = FontWeight.Bold))
                        }
                        Text(fluent, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                        if (f.reason.isNotBlank()) {
                            Text(f.reason, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                takeaway.line?.let { l ->
                    TakeawayCard {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            KindLabel(stringResource(R.string.a_line_to_say_after_it), Icons.Filled.GraphicEq,
                                Color(0xFFFFCC00))
                            Spacer(Modifier.weight(1f))
                            if (lineAudio != null) {
                                IconButton(onClick = {
                                    if (playing) { player.stop(); playing = false }
                                    else scope.launch {
                                        playing = true
                                        runCatching { player.play(lineAudio) }
                                        playing = false
                                    }
                                }) {
                                    Icon(if (playing) Icons.Filled.StopCircle else Icons.Filled.PlayCircle,
                                        contentDescription = stringResource(if (playing) R.string.stop else R.string.play),
                                        modifier = Modifier.size(32.dp), tint = MaterialTheme.colorScheme.primary)
                                }
                            }
                        }
                        Text(l.text, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            IosButton(
                onClick = { player.stop(); onClose("book") },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).heightIn(min = 50.dp),
            ) {
                Text(stringResource(R.string.open_the_book), fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun TakeawayCard(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerHighest, RoundedCornerShape(16.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) { content() }
}

@Composable
private fun KindLabel(title: String, icon: ImageVector, tint: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(16.dp), tint = tint)
        Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = tint)
    }
}

@Composable
private fun EntryCard(label: String, icon: ImageVector, tint: Color,
                      entry: TalkTakeaway.Entry, meaning: String?) {
    TakeawayCard {
        KindLabel(label, icon, tint)
        Text(entry.text, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        if (!meaning.isNullOrBlank()) Text(meaning, style = MaterialTheme.typography.bodyLarge)
        entry.example?.let { ex ->
            val strong = MaterialTheme.colorScheme.onSurface
            Text(emphasized(ex, entry.text, strong), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 2.dp))
        }
    }
}

/** The word set in bold where it sits in its sentence. */
private fun emphasized(sentence: String, word: String, strong: Color): AnnotatedString = buildAnnotatedString {
    val quoted = "“$sentence”"
    val at = quoted.indexOf(word, ignoreCase = true)
    if (at < 0) { append(quoted); return@buildAnnotatedString }
    append(quoted.substring(0, at))
    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = strong)) {
        append(quoted.substring(at, at + word.length))
    }
    append(quoted.substring(at + word.length))
}
