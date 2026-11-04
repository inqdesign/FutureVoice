package com.roro.futurevoice.ui

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SpaceBar
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.talk.PronunciationCourse
import com.roro.futurevoice.talk.PronunciationJudge
import com.roro.futurevoice.talk.PronunciationProgressStore
import com.roro.futurevoice.talk.PronunciationResult
import com.roro.futurevoice.talk.PronunciationRound
import com.roro.futurevoice.talk.PronunciationTopicProgress

private val PronGreen = Color(0xFF34C759)
private val PronOrange = Color(0xFFFF9500)
private val PronRed = Color(0xFFFF3B30)

/** The course's chapter icons (iOS SF Symbols mouth.fill · waveform · text.word.spacing). */
internal fun pronChapterIcon(name: String): ImageVector = when (name) {
    "waveform" -> Icons.Filled.GraphicEq
    "spacing" -> Icons.Filled.SpaceBar
    else -> Icons.Filled.RecordVoiceOver
}

/**
 * The pronunciation call's card, pinned above the transcript (iOS
 * `PronunciationCard`, ffaf0c58): today's sound, the sentences as dots, and
 * the sentence to read in big letters. The words that carry the sound are in
 * the accent colour until a take is judged; after a take, a word that wasn't
 * clear yet is underlined in red (or orange), the same marks the shadow
 * screen uses. The tip under it is in the learner's own language.
 */
@Composable
fun PronunciationCard(
    round: PronunciationRound?,
    topic: PronunciationCourse.Topic?,
    planning: Boolean,
    onSkip: () -> Unit,
    onLeaveWord: () -> Unit,
) {
    val accent = MaterialTheme.colorScheme.primary
    Column(
        Modifier.fillMaxWidth().animateContentSize().padding(horizontal = 20.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Header(round, topic)
        val i = round?.current
        when {
            planning || round == null -> Row(
                Modifier.fillMaxWidth().padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                Text(stringResource(R.string.preparing_your_sentences), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            i != null -> {
                val line = round.lines[i]
                round.carried?.let { c ->
                    // What the last sentence left, and when it comes back.
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = null, tint = PronOrange,
                            modifier = Modifier.size(14.dp))
                        Text(c.word?.let { w -> c.sound?.let { "$w /$it/" } ?: w } ?: stringResource(R.string.flow),
                            style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, color = PronOrange)
                        Text(stringResource(if (c.laterInRound) R.string.again_at_the_end_of_this_round
                            else R.string.again_in_the_next_round),
                            style = MaterialTheme.typography.bodySmall, color = PronOrange)
                    }
                }
                val drill = line.drillWord
                if (drill != null) {
                    // The word on its own; the sentence waits below it.
                    Text(stringResource(if (drill.contains(" ")) R.string.say_just_this_part else R.string.say_just_this_word),
                        style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = accent)
                    Text(drill, fontWeight = FontWeight.Bold, maxLines = 1,
                        softWrap = false, overflow = TextOverflow.Visible,
                        style = MaterialTheme.typography.displayMedium.copy(fontSize = autoSize(drill)))
                    Text(line.text, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    Text(marked(line, accent), style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.fillMaxWidth().semantics { contentDescription = line.text })
                }
                line.feedback?.let { PronunciationFeedbackPill(it) }
                val heardWord = line.heardWord; val heardAs = line.heardAs
                if (heardWord != null && heardAs != null) {
                    Text(stringResource(R.string.sounded_like, heardWord, heardAs),
                        style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = PronRed)
                }
                if (line.notSmooth) {
                    Text(stringResource(R.string.read_it_in_one_go_without_stopping),
                        style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = PronOrange)
                }
                // Nothing moves on by itself: these are the learner's ways on.
                if (drill != null) {
                    OutlinedButton(onClick = onLeaveWord) {
                        Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.size(6.dp))
                        Text(stringResource(R.string.back_to_the_sentence), fontWeight = FontWeight.SemiBold)
                    }
                } else if (line.tries > 0) {
                    OutlinedButton(onClick = onSkip) {
                        Icon(Icons.Filled.SkipNext, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.size(6.dp))
                        Text(stringResource(R.string.next_sentence), fontWeight = FontWeight.SemiBold)
                    }
                }
                if (round.tip.isNotEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Outlined.Lightbulb, contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                        Text(round.tip, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            else -> Column(Modifier.padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Filled.Verified, contentDescription = null, tint = PronGreen, modifier = Modifier.size(20.dp))
                    Text(stringResource(R.string.round_done), style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold, color = PronGreen)
                }
                Text(stringResource(R.string.lld_of_lld_sentences_passed, round.passedCount, round.sentenceCount),
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** A long word shrinks rather than wrapping (iOS `minimumScaleFactor(0.5)`). */
private fun autoSize(word: String) = when {
    word.length <= 10 -> 52.sp
    word.length <= 16 -> 40.sp
    else -> 30.sp
}

@Composable
private fun Header(round: PronunciationRound?, topic: PronunciationCourse.Topic?) {
    val accent = MaterialTheme.colorScheme.primary
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Filled.RecordVoiceOver, contentDescription = null, tint = accent, modifier = Modifier.size(18.dp))
        if (topic != null) {
            Text(topic.symbol, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(topic.examples, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false))
        }
        Spacer(Modifier.weight(1f))
        if (round != null) {
            val label = stringResource(R.string.lld_of_lld, round.doneCount, round.lines.size)
            Row(Modifier.semantics { contentDescription = label },
                horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                round.lines.forEachIndexed { j, line ->
                    val current = round.current == j
                    val fill = when {
                        line.passed -> PronGreen
                        line.skipped -> MaterialTheme.colorScheme.outline
                        current -> accent
                        else -> MaterialTheme.colorScheme.surfaceContainerHighest
                    }
                    Box(Modifier.size(12.dp), contentAlignment = Alignment.Center) {
                        if (current) Box(Modifier.size(12.dp).border(2.dp, accent, CircleShape))
                        Box(Modifier.size(8.dp).background(fill, CircleShape))
                    }
                }
            }
        }
    }
}

/** The sentence with its sound words in the accent colour, or — once a take
 *  has been judged — the words Azure marked underlined (iOS `marked`). */
private fun marked(line: PronunciationRound.Line, accent: Color): AnnotatedString = buildAnnotatedString {
    val plain = line.text
    append(plain)
    val heard = line.heardWord
    if (heard != null) {
        val r = PronunciationJudge.indexOf(plain, heard, 0)
        if (r >= 0) addStyle(SpanStyle(color = PronRed, textDecoration = TextDecoration.Underline),
            r, r + PronunciationJudge.matchLength(plain, heard, r))
    }
    val result = line.lastResult
    if (result != null) {
        var from = 0
        for (word in result.referenceWords) {
            val r = PronunciationJudge.indexOf(plain, word.word, from)
            if (r < 0) continue
            val end = r + PronunciationJudge.matchLength(plain, word.word, r)
            from = end
            val grade = PronunciationResult.grade(word)
            if (grade >= 2) continue
            addStyle(SpanStyle(color = if (grade == 0) PronRed else PronOrange,
                textDecoration = TextDecoration.Underline), r, end)
        }
    } else {
        for (focus in line.focus) {
            var from = 0
            while (true) {
                val r = PronunciationJudge.indexOf(plain, focus, from)
                if (r < 0) break
                val end = r + PronunciationJudge.matchLength(plain, focus, r)
                addStyle(SpanStyle(color = accent), r, end)
                from = end
            }
        }
    }
}

/** The last take's verdict on the card: the word and its sound, the score
 *  that decided it, and "Nice" / "Not yet" (iOS `PronunciationFeedbackPill`). */
@Composable
fun PronunciationFeedbackPill(feedback: PronunciationRound.Feedback) {
    val color = if (feedback.ok) PronGreen else if (feedback.score < 50) PronRed else PronOrange
    Row(
        Modifier.background(color.copy(alpha = 0.12f), RoundedCornerShape(50))
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        val style = MaterialTheme.typography.bodyMedium
        if (feedback.word != null) {
            Text(feedback.word, style = style, fontWeight = FontWeight.SemiBold)
            feedback.sound?.let { sound ->
                Text("/$sound/", style = style, color = MaterialTheme.colorScheme.onSurfaceVariant)
                when (val h = feedback.heardAs) {
                    is PronunciationJudge.HeardAs.Sound -> Text("→ /${h.phoneme}/", style = style, color = color)
                    PronunciationJudge.HeardAs.VowelAdded -> Text(stringResource(R.string.vowel), style = style, color = color)
                    null -> {}
                }
            }
        } else {
            Text(stringResource(R.string.flow), style = style, fontWeight = FontWeight.SemiBold)
        }
        Text("${feedback.score}", style = style, fontWeight = FontWeight.Bold, color = color)
        Text(stringResource(if (feedback.ok) R.string.nice else R.string.not_yet), style = style,
            fontWeight = FontWeight.SemiBold, color = color)
    }
}

/**
 * The pronunciation course ("교재", iOS `PronunciationTopicSheet`): every
 * sound of the target language by chapter, with how each went last time.
 * Picking one starts a round on it in the running call.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PronunciationTopicSheet(
    language: String,
    level: CefrLevel,
    currentId: String?,
    onPick: (PronunciationCourse.Topic) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    var progress by remember { mutableStateOf<Map<String, PronunciationTopicProgress>>(emptyMap()) }
    LaunchedEffect(language) { progress = PronunciationProgressStore.all(context, language) }
    val next = remember(language, progress) { PronunciationCourse.next(context, language, level, excluding = currentId) }
    fun pick(t: PronunciationCourse.Topic) { onPick(t); onDismiss() }
    ModalBottomSheet(onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)) {
        Column(Modifier.fillMaxWidth().bottomBarInsets()) {
            Box(Modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
                TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.CenterStart)) {
                    Text(stringResource(R.string.close))
                }
                Text(stringResource(R.string.sounds_to_practice), style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.align(Alignment.Center))
            }
            LazyColumn {
                if (next != null) {
                    item(key = "h-next") { PronSheetHeader(stringResource(R.string.next_up), null) }
                    item(key = "next") { PronTopicRow(next, progress[next.id], currentId, leading = true) { pick(next) } }
                }
                PronunciationCourse.chapters(language).forEach { chapter ->
                    item(key = "h-" + chapter.id) { PronSheetHeader(stringResource(chapter.title), pronChapterIcon(chapter.icon)) }
                    items(chapter.topics, key = { chapter.id + it.id }) { topic ->
                        PronTopicRow(topic, progress[topic.id], currentId, leading = false) { pick(topic) }
                    }
                }
            }
        }
    }
}

@Composable
private fun PronSheetHeader(text: String, icon: ImageVector?) {
    Row(Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        icon?.let { Icon(it, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(16.dp)) }
        Text(text, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun PronTopicRow(topic: PronunciationCourse.Topic, p: PronunciationTopicProgress?, currentId: String?,
                         leading: Boolean, onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (leading) Icon(Icons.Filled.PlayCircle, contentDescription = null, tint = accent, modifier = Modifier.size(28.dp))
        Text(topic.symbol, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold,
            modifier = Modifier.widthIn(min = 64.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(topic.examples, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
            val missed = p?.missedWords
            if (!missed.isNullOrEmpty()) {
                Text(stringResource(R.string.to_redo, missed.joinToString(", ")),
                    style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                    color = PronOrange, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        val score = p?.lastScore
        when {
            topic.id == currentId -> Icon(Icons.Filled.Check, contentDescription = null, tint = accent)
            score != null && score > 0 -> Text("$score", style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = if (score >= PronunciationJudge.PASS_BAR) PronGreen else PronOrange)
            p != null && p.rounds > 0 -> Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = PronGreen)
        }
    }
}
