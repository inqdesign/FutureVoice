package com.roro.futurevoice.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.TheaterComedy
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.DiscoverChip
import com.roro.futurevoice.data.LearningPurposeStore
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.talk.TutorLesson
import com.roro.futurevoice.ui.brand.Symbols

private val TickGreen = Color(0xFF34C759)

/**
 * Tutor mode's checklist, pinned above the transcript (iOS `TutorLessonStrip`).
 *
 * The lesson's 3–4 challenges with what is done, what is being worked on now,
 * and what is left. Tapping the header folds it to one line, so a long lesson
 * doesn't eat the transcript. The ticks are the app's (correction + judge),
 * never the tutor's word.
 */
@Composable
fun TutorLessonStrip(lesson: TutorLesson?, planning: Boolean, expanded: Boolean,
                     onToggle: () -> Unit, onChangeTopic: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            Modifier.fillMaxWidth().clickable(enabled = lesson != null, onClick = onToggle),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val finished = lesson?.isFinished == true
            Icon(if (finished) Icons.Filled.Verified else Icons.Filled.School, contentDescription = null,
                tint = if (finished) TickGreen else MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp))
            if (lesson != null) {
                Text(lesson.title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                Spacer(Modifier.weight(1f))
                Text("${lesson.doneCount}/${lesson.challenges.size}", style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                val angle by animateFloatAsState(if (expanded) 0f else -90f, tween(200), label = "tutorChevron")
                Icon(Icons.Filled.ExpandMore, contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    modifier = Modifier.size(18.dp).rotate(angle))
                var menu by remember { mutableStateOf(false) }
                Box {
                    IconButton(onClick = { menu = true }, modifier = Modifier.size(width = 32.dp, height = 28.dp)) {
                        Icon(Icons.Outlined.MoreHoriz, contentDescription = stringResource(R.string.choose_another_topic),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.choose_another_topic)) },
                            leadingIcon = { Icon(Icons.Outlined.Sync, contentDescription = null) },
                            onClick = { menu = false; onChangeTopic() },
                        )
                    }
                }
            } else {
                Text(stringResource(R.string.preparing_your_lesson), style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.weight(1f))
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
            }
        }
        AnimatedVisibility(visible = lesson != null && expanded) {
            if (lesson != null) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (lesson.isFinished) {
                    Text(stringResource(R.string.all_done_you_can_say_it_now), style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                lesson.challenges.forEachIndexed { i, c -> ChallengeRow(i, c, isNow = lesson.current == i) }
                if (planning) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        CircularProgressIndicator(Modifier.size(12.dp), strokeWidth = 1.5.dp)
                        Text(stringResource(R.string.preparing_your_lesson), style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
private fun ChallengeRow(i: Int, c: TutorLesson.Challenge, isNow: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        val done = c.doneAt != null
        Box(Modifier.size(18.dp), contentAlignment = Alignment.Center) {
            if (done) {
                Icon(Icons.Filled.CheckCircle, contentDescription = stringResource(R.string.done),
                    tint = TickGreen, modifier = Modifier.size(18.dp))
            } else {
                // SF's numbered circle, filled for the one on now.
                val color = if (isNow) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                Box(
                    if (isNow) Modifier.size(16.dp).background(color, CircleShape)
                    else Modifier.size(16.dp).border(1.dp, color, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("${i + 1}", style = MaterialTheme.typography.labelSmall,
                        color = if (isNow) MaterialTheme.colorScheme.onPrimary else color)
                }
            }
        }
        Text(c.goal, style = MaterialTheme.typography.bodySmall,
            fontWeight = if (isNow) FontWeight.SemiBold else FontWeight.Normal,
            color = if (done) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
            textDecoration = if (done) TextDecoration.LineThrough else null,
            modifier = Modifier.weight(1f))
    }
}

/**
 * Topics to practice, for a learner who has no idea (the button right of the
 * pill, iOS `TutorTopicSheet`). The Talk tab's own ready-made situations, by
 * the learner's purposes, plus the situations they built themselves — nothing
 * new to make or fetch. Picking one starts the lesson.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TutorTopicSheet(language: String, level: CefrLevel, onPick: (String) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    data class TopicRow(val icon: ImageVector, val title: String)
    data class Group(val id: String, val title: String, val rows: List<TopicRow>)
    val chips = remember(level) { LearningPurposeStore.chips(context, level) }
    var own by remember { mutableStateOf<List<com.roro.futurevoice.talk.Scenario>>(emptyList()) }
    androidx.compose.runtime.LaunchedEffect(language) {
        own = runCatching { ScenarioStore.shared(context).load(language) }.getOrDefault(emptyList())
            .filter { it.starterId == null && it.archivedAt == null }.take(12)
    }
    val groups = buildList {
        val seen = mutableSetOf<String>()
        val ordered = chips.filter { it.starters != null } +
            (if (DiscoverChip.EVERYDAY in chips) emptyList() else listOf(DiscoverChip.EVERYDAY))
        for (chip in ordered) {
            val rows = chip.starters.orEmpty().filter { seen.add(it.id) }
                .map { TopicRow(Symbols.icon(it.icon), stringResource(it.title)) }
            if (rows.isNotEmpty()) add(Group(chip.raw, stringResource(chip.label), rows))
        }
        if (own.isNotEmpty()) add(Group("own", stringResource(R.string.your_scenarios),
            own.map { TopicRow(Icons.Filled.TheaterComedy, it.environment) }))
    }
    ModalBottomSheet(onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)) {
        Column(Modifier.sheetBody()) {
            Box(Modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
                TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.CenterStart)) {
                    Text(stringResource(R.string.close))
                }
                Text(stringResource(R.string.what_to_practice), style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.align(Alignment.Center))
            }
            LazyColumn {
                groups.forEach { g ->
                    item(key = "h-" + g.id) {
                        Text(g.title, style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 4.dp))
                    }
                    items(g.rows) { row ->
                        Row(
                            Modifier.fillMaxWidth().clickable { onPick(row.title); onDismiss() }
                                .padding(horizontal = 20.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(row.icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(22.dp))
                            Spacer(Modifier.width(14.dp))
                            Text(row.title, style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                }
            }
        }
    }
}
