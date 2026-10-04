package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.net.ScenarioBriefEngine
import com.roro.futurevoice.talk.ScenarioBrief
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/**
 * The board shown while a situation's attached material is read (iOS
 * `BriefProgressView`) — the wrap-up board's shape, for the same reason: the
 * one call IS the whole wait, it streams, and a row ticks the moment the
 * model closes that section. Every number is the count the book shows after.
 */
@Composable
fun BriefProgressBoard(sources: List<ScenarioBrief.Source>, progress: ScenarioBriefEngine.Progress,
                       modifier: Modifier = Modifier) {
    data class Step(val title: String, val done: Boolean, val count: Int?)
    val steps = buildList {
        sources.forEachIndexed { i, src ->
            val title = when (src.kind) {
                ScenarioBrief.Kind.LINK -> stringResource(R.string.reading_the_link)
                ScenarioBrief.Kind.FILE -> stringResource(R.string.reading, src.label)
                ScenarioBrief.Kind.IMAGE -> stringResource(R.string.reading_the_photo)
            }
            add(Step(title, progress.sourcesRead.getOrElse(i) { false }, null))
        }
        add(Step(stringResource(R.string.what_this_is_about), progress.summary, null))
        add(Step(stringResource(R.string.what_they_will_ask), progress.likelyQuestions != null, progress.likelyQuestions))
        add(Step(stringResource(R.string.what_to_have_ready), progress.learnerFacts != null, progress.learnerFacts))
        add(Step(stringResource(R.string.key_expressions), progress.keyExpressions != null, progress.keyExpressions))
    }
    val doneCount = steps.count { it.done }
    /** The row being written now — the first one not yet closed. */
    val current = steps.indexOfFirst { !it.done }
    Column(modifier.widthIn(max = 440.dp).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(stringResource(R.string.reading_your_material), style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold)
        LinearProgressIndicator(
            progress = { doneCount.toFloat() / steps.size.coerceAtLeast(1) },
            modifier = Modifier.fillMaxWidth())
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            steps.forEachIndexed { i, step ->
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    when {
                        step.done -> Icon(Icons.Filled.CheckCircle, contentDescription = null,
                            tint = androidx.compose.ui.graphics.Color(0xFF34C759), modifier = Modifier.size(20.dp))
                        i == current -> CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        else -> Icon(Icons.Outlined.Circle, contentDescription = null,
                            tint = MaterialTheme.colorScheme.outlineVariant, modifier = Modifier.size(20.dp))
                    }
                    Text(step.title, style = MaterialTheme.typography.bodyMedium,
                        color = if (step.done) MaterialTheme.colorScheme.onSurface
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    val n = step.count
                    if (step.done && n != null && n > 0) {
                        Text("$n", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        Text(stringResource(R.string.read_once_the_files_stay_where_they_are_on_your_phone_only_w_ef71a3),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Icon for one attached source — a link, a document, a photo. */
internal fun briefSourceIcon(src: ScenarioBrief.Source): ImageVector = when (src.kind) {
    ScenarioBrief.Kind.LINK -> Icons.Filled.Link
    ScenarioBrief.Kind.FILE -> Icons.Filled.Description
    ScenarioBrief.Kind.IMAGE -> Icons.Filled.Image
}

/** A link shows its host and path, never the scheme; a file its name. */
internal fun briefChipLabel(src: ScenarioBrief.Source): String {
    if (src.kind != ScenarioBrief.Kind.LINK) return src.label
    val uri = runCatching { java.net.URI(src.label) }.getOrNull() ?: return src.label
    val host = uri.host ?: return src.label
    val path = uri.path?.takeIf { it != "/" }.orEmpty()
    return host + path
}

/**
 * The book's Brief section (iOS `ScenarioDetailView.briefRows`): what the
 * reading produced, in the two halves it sorted them into, then the sources
 * with their read date and "Read again". Nothing here is the file — the file
 * is still wherever the learner keeps it.
 */
@Composable
fun BriefSection(
    brief: ScenarioBrief,
    rereading: Boolean,
    progress: ScenarioBriefEngine.Progress,
    error: String?,
    onReadAgain: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(stringResource(R.string.brief), style = MaterialTheme.typography.titleMedium)
        if (rereading) {
            BriefProgressBoard(brief.sources, progress)
            return@Column
        }
        if (brief.summary.isNotBlank()) {
            Text(brief.summary, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
        }
        if (brief.likelyQuestions.isNotEmpty())
            BriefList(stringResource(R.string.what_they_ll_ask), brief.likelyQuestions, material = true)
        if (brief.counterpartFacts.isNotEmpty())
            BriefList(stringResource(R.string.who_you_re_talking_to), brief.counterpartFacts, material = false)
        if (brief.learnerFacts.isNotEmpty())
            BriefList(stringResource(R.string.what_to_have_ready), brief.learnerFacts, material = false)
        if (brief.keyExpressions.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.key_expressions), style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(brief.keyExpressions.joinToString(" · "), style = MaterialTheme.typography.bodyMedium)
            }
        }
        if (brief.needsReading && !brief.hasContent) {
            Text(stringResource(R.string.not_read_yet_it_s_read_the_first_time_you_watch_this_scene),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
        brief.sources.forEach { src ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(briefSourceIcon(src), contentDescription = null,
                    tint = if (src.readOK) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp))
                Column(Modifier.weight(1f)) {
                    Text(briefChipLabel(src), style = MaterialTheme.typography.bodyMedium,
                        maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
                    val d = src.detail?.takeIf { it.isNotBlank() }
                    if (d != null) {
                        Text(d, style = MaterialTheme.typography.bodySmall,
                            color = if (src.readOK) MaterialTheme.colorScheme.onSurfaceVariant
                            else MaterialTheme.colorScheme.error)
                    } else if (!src.readOK) {
                        Text(stringResource(R.string.couldn_t_read_this_one), style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            brief.readAt?.let { at ->
                val date = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
                    .withLocale(Locale.getDefault())
                    .format(Instant.ofEpochMilli(at).atZone(ZoneId.systemDefault()))
                Text(stringResource(R.string.read, date), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.weight(1f))
            OutlinedButton(onClick = onReadAgain) {
                Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.size(6.dp))
                Text(stringResource(R.string.read_again), style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

@Composable
private fun BriefList(title: String, items: List<String>, material: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        items.forEach { line ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("·", color = MaterialTheme.colorScheme.outline)
                Text(line, style = MaterialTheme.typography.bodyMedium,
                    color = if (material) MaterialTheme.colorScheme.onSurface
                    else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
