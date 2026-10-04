package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.talk.GrammarFocus
import com.roro.futurevoice.talk.GrammarFocusRecord

/** iOS `.orange` — a reminder, not a failure (red is never used here). */
private val FocusOrange = Color(0xFFFF9500)
private val FocusGreen = Color(0xFF34C759)

@Composable
private fun cameBack(id: Int, n: Int): String =
    LocalContext.current.resources.getQuantityString(id, n, n)

/**
 * The call's grammar focus, pinned above the transcript beside the studying
 * chips (iOS `GrammarFocusStrip`). The name the learner thinks in and their
 * own slip beside its fix, so the rule never stands without the example.
 * Once the slip comes back, the trailing counter says so — orange, not red.
 */
@Composable
fun GrammarFocusStrip(label: String, mistake: String, correction: String, repeats: Int,
                      onTap: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onTap)
            .padding(horizontal = 20.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Filled.TrackChanges, contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(30.dp)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), CircleShape)
                .padding(7.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(label, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                Text(stringResource(R.string.cm_this_calls_focus), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            }
            GrammarFocusPair(mistake, correction, maxLines = 1)
        }
        if (repeats > 0) {
            val a11y = cameBack(R.plurals.cm_came_back_times, repeats)
            Row(
                Modifier.background(FocusOrange.copy(alpha = 0.14f), CircleShape)
                    .padding(horizontal = 8.dp, vertical = 4.dp)
                    .androidSemantics(a11y),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Icon(Icons.Filled.Replay, contentDescription = null, tint = FocusOrange,
                    modifier = Modifier.size(13.dp))
                Text("$repeats", style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold, color = FocusOrange)
            }
        } else {
            Icon(Icons.Filled.ChevronRight, contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                modifier = Modifier.size(18.dp))
        }
    }
}

private fun Modifier.androidSemantics(label: String): Modifier =
    clearAndSetSemantics { contentDescription = label }

/**
 * The learner's slip and its fix on one line: what they say, struck through
 * and quiet; what to say, plain. Only the part that CHANGED, with a word of
 * context either side ([GrammarFocus.compact]). Target-language material.
 */
@Composable
fun GrammarFocusPair(mistake: String, correction: String, maxLines: Int = 1) {
    val (was, now) = GrammarFocus.compact(mistake, correction)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(was, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textDecoration = TextDecoration.LineThrough,
            maxLines = maxLines, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false))
        Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            modifier = Modifier.size(12.dp))
        Text(now, style = MaterialTheme.typography.bodySmall,
            maxLines = maxLines, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false))
    }
}

/**
 * What the focus strip opens: the point, when it applies, the learner's own
 * example, and what the call will do about it. The call is still running
 * underneath, so it stays one screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GrammarFocusSheet(focus: GrammarFocus, repeats: Int, onDismiss: () -> Unit) {
    ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.cm_this_calls_focus), style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f))
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.done), style = MaterialTheme.typography.titleMedium)
                }
            }
            Text(focus.label, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            if (focus.tip.isNotEmpty()) {
                Text(focus.tip, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            HorizontalDivider(Modifier.padding(vertical = 6.dp))
            LabeledRow(stringResource(R.string.you_said_f105ab)) {
                Text(focus.pattern.mistake, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textDecoration = TextDecoration.LineThrough)
            }
            LabeledRow(stringResource(R.string.cm_say)) {
                Text(focus.pattern.correction, fontWeight = FontWeight.SemiBold)
            }
            Text(stringResource(R.string.cm_focus_sheet_footer), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (repeats > 0) {
                HorizontalDivider(Modifier.padding(vertical = 6.dp))
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(Icons.Filled.Replay, contentDescription = null, tint = FocusOrange,
                        modifier = Modifier.size(20.dp))
                    Text(cameBack(R.plurals.cm_came_back_in_this_call, repeats),
                        style = MaterialTheme.typography.bodyLarge)
                }
            }
            Spacer(Modifier.size(16.dp))
        }
    }
}

@Composable
private fun LabeledRow(label: String, value: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(0.35f))
        Column(Modifier.weight(0.65f), horizontalAlignment = Alignment.End) { value() }
    }
}

/** On a correction card whose slip is the focus coming back. Sits above the
 *  rewrite so the learner reads WHY this card matters before the card. */
@Composable
fun GrammarFocusRepeatBadge(label: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(Icons.Filled.Replay, contentDescription = null, tint = FocusOrange, modifier = Modifier.size(14.dp))
        Text(stringResource(R.string.again) + " · " + label, style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold, color = FocusOrange,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** The book page's line for a talk that had a focus: what it was and how the
 *  call went on it. Counted in code; the wording never scolds. */
@Composable
fun GrammarFocusResultRow(record: GrammarFocusRecord, modifier: Modifier = Modifier) {
    val clean = record.repeats == 0
    Row(modifier.padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(if (clean) Icons.Filled.Verified else Icons.Filled.TrackChanges, contentDescription = null,
            tint = if (clean) FocusGreen else MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(24.dp))
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(record.label, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            GrammarFocusPair(record.mistake, record.correction, maxLines = 2)
            Text(
                if (clean) stringResource(R.string.cm_didnt_come_back)
                else cameBack(R.plurals.cm_came_back_stays_focus, record.repeats),
                style = MaterialTheme.typography.bodySmall,
                color = if (clean) FocusGreen else MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * Coach mode's hint: the word, and a tick once it has been said (iOS
 * `CoachHintLabel`). Worded so the item never needs a particle or an article
 * attached to it ("Try using · rest").
 */
@Composable
fun CoachHintLabel(item: TalkGoalItem, used: Boolean, onTap: () -> Unit) {
    Row(Modifier.clickable(onClick = onTap).padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(if (used) Icons.Filled.CheckCircle else Icons.Outlined.Lightbulb, contentDescription = null,
            tint = if (used) FocusGreen else MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(18.dp))
        Text(stringResource(if (used) R.string.cm_used_it else R.string.cm_try_using),
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("·", style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
        Text(item.text, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
    }
}

/**
 * Coach mode's "try saying" (iOS `CoachReplyLabel`): one easy answer to the
 * line just spoken, its blanks the learner's to fill, and what it means in
 * their own language. Centred above the pill, like the hint line under it; no
 * icon — the label says what it is, and the sentence is what the eye should
 * land on.
 */
@Composable
fun CoachReplyLabel(reply: com.roro.futurevoice.talk.CoachReply, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(stringResource(R.string.try_saying), style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(coachLine(reply.say, MaterialTheme.colorScheme.onSurface),
            style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        if (reply.meaning.isNotEmpty()) {
            Text(coachLine(reply.meaning, MaterialTheme.colorScheme.onSurfaceVariant),
                style = MaterialTheme.typography.bodyMedium,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
}

/** The bracketed example faded and underlined (iOS `.tertiaryLabel`). */
@Composable
private fun coachLine(line: String, color: androidx.compose.ui.graphics.Color) =
    androidx.compose.ui.text.buildAnnotatedString {
        val faded = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f)
        for ((text, example) in com.roro.futurevoice.talk.CoachReply.segments(line)) {
            withStyle(if (example) androidx.compose.ui.text.SpanStyle(color = faded,
                textDecoration = androidx.compose.ui.text.style.TextDecoration.Underline)
            else androidx.compose.ui.text.SpanStyle(color = color)) { append(text) }
        }
    }
