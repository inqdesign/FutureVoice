package com.roro.futurevoice.ui

import androidx.compose.material.icons.filled.DonutLarge
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Contrast
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Pending
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.TheaterComedy
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.talk.TutorCurriculum
import com.roro.futurevoice.talk.TutorLesson
import com.roro.futurevoice.talk.TutorProgressStore
import com.roro.futurevoice.talk.TutorTopicProgress
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
        val inCheck = lesson?.inFinalCheck == true
        Row(
            Modifier.fillMaxWidth().clickable(enabled = lesson != null && !inCheck, onClick = onToggle),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val finished = lesson?.isFinished == true
            Icon(if (finished) Icons.Filled.Verified else Icons.Filled.School, contentDescription = null,
                tint = if (finished) TickGreen else MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp))
            if (lesson != null && inCheck) {
                // The final check: nothing to lean on (iOS 23ce515f). The
                // title and the step, no rows, no way out of it from here.
                Text(lesson.title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                Spacer(Modifier.weight(1f))
                Text(stringResource(R.string.final_check), style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
            } else if (lesson != null) {
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
        if (lesson != null && inCheck) {
            Text(stringResource(R.string.say_it_all_in_your_own_words_in_one_go),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            // What it should cover, as the parts' short names only — never
            // their example lines (iOS 06933043: three or four parts are hard
            // to hold in your head with nothing on screen).
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                lesson.challenges.forEachIndexed { i, c ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        val color = MaterialTheme.colorScheme.onSurfaceVariant
                        Box(Modifier.size(16.dp).border(1.dp, color, CircleShape), contentAlignment = Alignment.Center) {
                            Text("${i + 1}", style = MaterialTheme.typography.labelSmall, color = color)
                        }
                        Text(c.goal, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
        AnimatedVisibility(visible = lesson != null && expanded && !inCheck) {
            if (lesson != null) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (lesson.isFinished) {
                    Text(stringResource(R.string.passed_you_can_say_it_now), style = MaterialTheme.typography.bodySmall,
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
 * The tutor's curriculum, behind the button right of the pill (iOS
 * `TutorTopicSheet`, 23ce515f). One "Next up", the chapters with how many
 * topics are passed, and inside a chapter every topic with its state. A topic
 * above the learner's level reads "Step up" and is still a tap away, after
 * one question (soft unlocking). The learner's own scenarios stay at the
 * bottom; they aren't counted on the map. Picking starts the lesson:
 * [onPick] gets the topic as the planner gets it and its curriculum id (null
 * for the learner's own scenarios).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TutorTopicSheet(language: String, level: CefrLevel, onPick: (String, String?) -> Unit, onDismiss: () -> Unit,
                    /** The lesson running in this call, drawn on top so the page says
                     *  what is being practiced now (iOS cd57f343). */
                    current: com.roro.futurevoice.talk.TutorLesson? = null) {
    val context = LocalContext.current
    // The learner's own goals and the questions each is practiced on — the
    // same questions, and the same lesson ids, as the goal's page.
    var goalQuestions by remember {
        mutableStateOf<List<Pair<com.roro.futurevoice.data.UpcomingGoal, List<com.roro.futurevoice.talk.GoalPrep.Question>>>>(emptyList())
    }
    var lessons by remember { mutableStateOf<List<com.roro.futurevoice.talk.TutorLesson>>(emptyList()) }
    var own by remember { mutableStateOf<List<com.roro.futurevoice.talk.Scenario>>(emptyList()) }
    var progress by remember { mutableStateOf<Map<String, TutorTopicProgress>>(emptyMap()) }
    var chapter by remember { mutableStateOf<TutorCurriculum.Chapter?>(null) }
    var stepUp by remember { mutableStateOf<TutorCurriculum.Topic?>(null) }
    androidx.compose.runtime.LaunchedEffect(language) {
        progress = TutorProgressStore.all(context, language)
        lessons = com.roro.futurevoice.talk.TutorLessonStore.all(context, language)
        goalQuestions = com.roro.futurevoice.data.UpcomingGoalStore.active(context, language).mapNotNull { g ->
            val qs = com.roro.futurevoice.talk.GoalPrep.cachedQuestions(context, g)
            if (qs.isNullOrEmpty()) null else g to qs
        }
        own = runCatching { ScenarioStore.shared(context).load(language) }.getOrDefault(emptyList())
            .filter { it.starterId == null && it.archivedAt == null }.take(12)
    }
    fun start(topic: TutorCurriculum.Topic) {
        stepUp = null
        onPick(context.getString(topic.title), topic.id)
        onDismiss()
    }
    fun pick(topic: TutorCurriculum.Topic) {
        if (progress[topic.id]?.passedAt == null && TutorCurriculum.isStepUp(topic, level)) stepUp = topic
        else start(topic)
    }
    ModalBottomSheet(onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)) {
        // Not sheetBody(): its verticalScroll hands the LazyColumn below an
        // unbounded height, which crashes the moment the sheet opens.
        Column(Modifier.fillMaxWidth().bottomBarInsets()) {
            val open = chapter
            Box(Modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
                if (open != null) {
                    IconButton(onClick = { chapter = null }, modifier = Modifier.align(Alignment.CenterStart)) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.what_to_practice))
                    }
                } else {
                    TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.CenterStart)) {
                        Text(stringResource(R.string.close))
                    }
                }
                Text(if (open != null) stringResource(open.title) else stringResource(R.string.what_to_practice),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.align(Alignment.Center))
            }
            if (open != null) {
                LazyColumn {
                    items(open.topics, key = { it.id }) { topic ->
                        Box(Modifier.fillMaxWidth().clickable { pick(topic) }
                            .padding(horizontal = 20.dp, vertical = 12.dp)) {
                            TopicRow(topic, progress[topic.id], level)
                        }
                    }
                }
            } else {
                LazyColumn {
                    current?.takeIf { it.droppedAt == null && !it.isFinished }?.let { lesson ->
                        item(key = "h-now") { SheetHeader(stringResource(R.string.now)) }
                        item(key = "now") {
                            Row(
                                Modifier.fillMaxWidth().clickable { onDismiss() }
                                    .padding(horizontal = 20.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                Icon(Icons.Filled.School, contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
                                Text(lesson.title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                                Text("${lesson.doneCount}/${lesson.challenges.size}", style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                    goalQuestions.forEach { (goal, questions) ->
                        item(key = "h-goal-${goal.id}") {
                            Row(Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 6.dp),
                                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Icon(goal.kind.icon(), contentDescription = null, modifier = Modifier.size(16.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                Text(goal.title, style = MaterialTheme.typography.titleSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        items(questions, key = { "g-${goal.id}-${it.text}" }) { q ->
                            val state = com.roro.futurevoice.talk.GoalPrep.state(q.text, goal, lessons)
                            val isNow = current?.topicId == com.roro.futurevoice.talk.GoalPrep.topicId(goal, q.text) &&
                                current?.droppedAt == null
                            Row(
                                Modifier.fillMaxWidth().clickable {
                                    // The same lesson the goal's page opens on this question.
                                    com.roro.futurevoice.core.Analytics.capture("tutor_topic_goal_picked", mapOf("kind" to goal.kind.raw))
                                    onPick("\u201C${q.text}\u201D — ${goal.title}. ${goal.drillBlurb}",
                                        com.roro.futurevoice.talk.GoalPrep.topicId(goal, q.text))
                                    onDismiss()
                                }.padding(horizontal = 20.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                when (state) {
                                    com.roro.futurevoice.talk.GoalPrep.QuestionState.READY ->
                                        Icon(Icons.Filled.CheckCircle, null, tint = Color(0xFF34C759), modifier = Modifier.size(24.dp))
                                    com.roro.futurevoice.talk.GoalPrep.QuestionState.PRACTICING ->
                                        Icon(Icons.Filled.DonutLarge, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
                                    com.roro.futurevoice.talk.GoalPrep.QuestionState.UNTOUCHED ->
                                        Icon(Icons.Outlined.Circle, null, tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(24.dp))
                                }
                                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(q.text, style = MaterialTheme.typography.bodyLarge)
                                    if (isNow) Text(stringResource(R.string.now), style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.primary)
                                    else if (state == com.roro.futurevoice.talk.GoalPrep.QuestionState.PRACTICING)
                                        Text(stringResource(R.string.in_progress), style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                    TutorCurriculum.next(progress, level)?.let { next ->
                        item(key = "h-next") { SheetHeader(stringResource(R.string.next_up)) }
                        item(key = "next") {
                            Row(
                                Modifier.fillMaxWidth().clickable { pick(next.topic) }
                                    .padding(horizontal = 20.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                Icon(Icons.Filled.PlayCircle, contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(28.dp))
                                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(stringResource(next.topic.title), style = MaterialTheme.typography.bodyLarge)
                                    Text(if (progress[next.topic.id]?.checkLeft == true) stringResource(R.string.final_check_left)
                                        else stringResource(next.chapter.title),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                    item(key = "h-curriculum") { SheetHeader(stringResource(R.string.curriculum)) }
                    items(TutorCurriculum.chapters, key = { "c-" + it.id }) { c ->
                        ChapterRow(c, progress, onClick = { chapter = c })
                    }
                    item(key = "f-curriculum") {
                        val passed = progress.values.count { it.passedAt != null }
                        val total = TutorCurriculum.chapters.sumOf { it.topics.size }
                        Text(stringResource(R.string.lld_of_lld_topics_passed, passed, total),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 6.dp))
                    }
                    if (own.isNotEmpty()) {
                        item(key = "h-own") { SheetHeader(stringResource(R.string.your_scenarios)) }
                        items(own, key = { "o-" + it.id }) { sc ->
                            Row(
                                Modifier.fillMaxWidth().clickable { onPick(sc.environment, null); onDismiss() }
                                    .padding(horizontal = 20.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(Icons.Filled.TheaterComedy, contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                                Spacer(Modifier.width(14.dp))
                                Text(sc.environment, style = MaterialTheme.typography.bodyLarge)
                            }
                        }
                    }
                }
            }
        }
    }
    stepUp?.let { topic ->
        AlertDialog(
            onDismissRequest = { stepUp = null },
            title = { Text(stringResource(R.string.this_one_is_a_step_up_try_it)) },
            text = { Text(stringResource(R.string.the_tutor_will_keep_it_at_your_level)) },
            confirmButton = { TextButton(onClick = { start(topic) }) { Text(stringResource(R.string.try_it)) } },
            dismissButton = { TextButton(onClick = { stepUp = null }) { Text(stringResource(R.string.not_now)) } },
        )
    }
}

@Composable
private fun SheetHeader(text: String) {
    Text(text, style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 4.dp))
}

@Composable
private fun ChapterRow(chapter: TutorCurriculum.Chapter, progress: Map<String, TutorTopicProgress>, onClick: () -> Unit) {
    val passed = chapter.topics.count { progress[it.id]?.passedAt != null }
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Symbols.icon(chapter.icon), contentDescription = null, tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.width(26.dp).size(22.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(stringResource(chapter.title), style = MaterialTheme.typography.bodyLarge)
            LinearProgressIndicator(
                progress = { passed.toFloat() / chapter.topics.size.coerceAtLeast(1) },
                modifier = Modifier.fillMaxWidth(),
                color = TickGreen,
                drawStopIndicator = {},
            )
        }
        Text("$passed/${chapter.topics.size}", style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f), modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun TopicRow(topic: TutorCurriculum.Topic, p: TutorTopicProgress?, level: CefrLevel) {
    val step = p?.passedAt == null && TutorCurriculum.isStepUp(topic, level)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        val (icon, tint) = when {
            p?.passedAt != null -> Icons.Filled.CheckCircle to TickGreen
            p?.checkLeft == true -> Icons.Filled.Contrast to TickGreen
            p?.inProgress == true -> Icons.Outlined.Pending to MaterialTheme.colorScheme.primary
            else -> Icons.Outlined.Circle to MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
        }
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(topic.title), style = MaterialTheme.typography.bodyLarge,
                color = if (step) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface)
            if (p?.checkLeft == true) {
                Text(stringResource(R.string.final_check_left), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else if (p?.inProgress == true) {
                Text(stringResource(R.string.in_progress), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        val rounds = p?.rounds ?: 0
        if (rounds > 1) {
            Text(stringResource(R.string.lld_rounds, rounds), style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold, color = TickGreen)
        } else if (step) {
            Text(stringResource(R.string.step_up), style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold, color = Color(0xFFFF9500))
        }
    }
}
