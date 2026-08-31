package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DailyStudyPick
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.PracticeLog
import com.roro.futurevoice.ui.brand.BookCard
import com.roro.futurevoice.ui.brand.Books
import com.roro.futurevoice.ui.brand.EffortCharts
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import androidx.compose.material3.TextButton
import com.roro.futurevoice.data.AppUsageLog
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.ui.brand.DayCardData
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.Session

/**
 * Practice — the REVIEW home (`PracticeTab`'s spine): the day's due queue,
 * then the book shelves. Everything here came out of an activity; nothing is
 * born on this screen. Hosted by the tab shell, so no Scaffold of its own.
 */
@Composable
fun PracticeBody(
    language: String,
    level: com.roro.futurevoice.data.CefrLevel,
    onOpenDeck: () -> Unit,
    onOpenWords: () -> Unit,
    onOpenExpressions: () -> Unit,
    onOpenScenarioBook: (String) -> Unit,
    onOpenTalk: (String) -> Unit,
) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var due by remember { mutableStateOf(0) }
    var wordsDue by remember { mutableStateOf(0) }
    var expressionsDue by remember { mutableStateOf(0) }
    var scenarios by remember { mutableStateOf<List<Scenario>>(emptyList()) }
    var talks by remember { mutableStateOf<List<Session>>(emptyList()) }
    LaunchedEffect(language, revision) {
        due = DrillStore.shared(context).dueCount(language)
        // The two library decks say how big TODAY's hand is, not how much is
        // in the notebook: the number has to be the number the deck deals or
        // the row promises work the deck won't hand over.
        wordsDue = DailyStudyPick.words(context, DAILY_HAND, language, level).size
        expressionsDue = DailyStudyPick.expressions(context, DAILY_HAND, language).size
        scenarios = ScenarioStore.shared(context).load(language)
            .filter { it.archivedAt == null && it.isMeeting != true }
        talks = SessionStore.shared(context).load(language).filter { it.summary != null }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (due > 0) {
            Row(Modifier.fillMaxWidth().clickable { onOpenDeck() }.padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.review_cards),
                    style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                Text("$due", style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary)
            }
        }
        // The Library decks — words and expressions, dealt from the notebook,
        // the books and the last talks. Always present, because "nothing due"
        // is an answer the learner is entitled to see.
        StudyRow(stringResource(R.string.words), wordsDue, onOpenWords)
        StudyRow(stringResource(R.string.expressions), expressionsDue, onOpenExpressions)

        if (scenarios.isNotEmpty()) {
            Text(stringResource(R.string.scenarios), style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 8.dp))
            scenarios.forEach { sc ->
                val cur = sc.curriculum
                val total = cur?.let { it.words.size + it.expressions.size + it.shadowLines.size } ?: 0
                val done = cur?.let {
                    it.words.count { w -> w.masteredAt != null } +
                        it.expressions.count { e -> e.masteredAt != null }
                } ?: 0
                BookCard(
                    title = sc.cardTitle,
                    origin = sc.category,
                    accent = Books.scenarios,
                    detail = if (cur == null) stringResource(R.string.watch_the_scene_first)
                    else stringResource(R.string.lld_of_lld_mastered, done, total),
                    progress = if (total == 0) null else done / total.toFloat(),
                    onClick = { onOpenScenarioBook(sc.id) },
                    modifier = Modifier.padding(vertical = 4.dp),
                )
            }
        }
        if (talks.isNotEmpty()) {
            Text(stringResource(R.string.talks), style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 8.dp))
            talks.forEach { t ->
                BookCard(
                    title = t.displayTitle ?: stringResource(R.string.conversation),
                    origin = when (t.origin?.name?.lowercase()) {
                        "news" -> stringResource(R.string.news)
                        "scenario" -> stringResource(R.string.scenarios)
                        else -> stringResource(R.string.free_talk)
                    },
                    accent = if (t.origin?.name?.lowercase() == "news") Books.topics else Books.talks,
                    detail = t.summary?.scorecard?.let {
                        "${it.overall} · ${it.cefrLevel?.uppercase().orEmpty()}"
                    },
                    onClick = { onOpenTalk(t.id) },
                    modifier = Modifier.padding(vertical = 4.dp),
                )
            }
        }
    }
}

/** Two weeks: long enough to show a habit, short enough to read at a glance. */
private const val EFFORT_DAYS = 14

/** Day-of-month, the only part of a date a fourteen-bar strip has room for. */
private fun dayLabel(at: Long): String =
    java.text.SimpleDateFormat("d", java.util.Locale.US).format(java.util.Date(at))

/** How many cards a daily deck deals. Mirrors iOS's per-day goal default. */
private const val DAILY_HAND = 10

/**
 * One library deck's row: what it is, and how many cards are waiting today.
 * A zero is shown as a dash rather than hidden — a row that vanishes when
 * it's empty teaches the learner to stop looking for it.
 */
@Composable
private fun StudyRow(title: String, count: Int, onOpen: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onOpen() }.padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        Text(if (count == 0) "—" else "$count",
            style = MaterialTheme.typography.titleMedium,
            color = if (count == 0) MaterialTheme.colorScheme.onSurfaceVariant
            else MaterialTheme.colorScheme.primary)
    }
}

/**
 * Progress — measured, never guessed: the CEFR read comes from the talks
 * themselves (the summary's holistic estimate), the minutes from the meter.
 * The per-skill pages and the 14-day rep bars arrive with the Progress pass.
 */
@Composable
fun ProgressBody(language: String, goalMinutes: Int = 10) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var talks by remember { mutableStateOf<List<Session>>(emptyList()) }
    var todaySeconds by remember { mutableStateOf(0) }
    var showCard by remember { mutableStateOf(false) }
    var minutesByDay by remember { mutableStateOf<List<Pair<Long, Int>>>(emptyList()) }
    var effortByDay by remember { mutableStateOf<List<Pair<String, PracticeLog.Day>>>(emptyList()) }
    LaunchedEffect(language, revision) {
        talks = SessionStore.shared(context).load(language)
        todaySeconds = TalkTimeLog.secondsToday(context)
        minutesByDay = TalkTimeLog.recentSeconds(context, EFFORT_DAYS)
        effortByDay = PracticeLog.recent(context, EFFORT_DAYS)
    }
    val scored = talks.mapNotNull { it.summary?.scorecard }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        scored.firstOrNull()?.let { card ->
            Column {
                val level = card.cefrLevel?.uppercase().orEmpty()
                Text(level,
                    style = com.roro.futurevoice.ui.brand.DisplayFace
                        .style(level, MaterialTheme.typography.displaySmall),
                    color = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.a_level_measured_not_guessed),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            Stat(stringResource(R.string.today), "${todaySeconds / 60}")
            Stat(stringResource(R.string.talks), "${talks.count { it.endedAt != null }}")
            if (scored.isNotEmpty()) {
                Stat(stringResource(R.string.overall), "${scored.map { it.overall }.average().toInt()}")
            }
        }
        val today = remember(talks, todaySeconds, revision) {
            val startOfDay = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, 0); set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0); set(java.util.Calendar.MILLISECOND, 0)
            }.timeInMillis
            val todays = talks.filter { (it.endedAt ?: it.startedAt) >= startOfDay }
            DayCardData(
                date = System.currentTimeMillis(),
                talkMinutes = todaySeconds / 60,
                // Never less than the talk figure: a call in a pocket is
                // metered but not foregrounded.
                studyMinutes = maxOf(AppUsageLog.secondsOn(context, System.currentTimeMillis()) / 60,
                    todaySeconds / 60),
                streakDays = TalkTimeLog.streakDays(context),
                talks = todays.size,
                topics = todays.sortedByDescending { s ->
                    s.turns.filter { it.role == TurnRole.USER }.sumOf { it.durationMs }
                }.mapNotNull { it.displayTitle }.distinct().take(4),
            )
        }
        // What the last two weeks actually were. Both strips are drawn only
        // when there is something in them: an empty chart is a reproach, and
        // a new learner has done nothing wrong.
        if (minutesByDay.any { it.second > 0 }) {
            Text(stringResource(R.string.talk_time), style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 8.dp))
            EffortCharts.Bars(
                days = minutesByDay.map { (at, secs) ->
                    EffortCharts.DayBar(dayLabel(at),
                        listOf(MaterialTheme.colorScheme.primary to secs / 60f))
                },
                goal = goalMinutes.toFloat(),
            )
            Text(stringResource(R.string.the_dashed_line_is_your_daily_goal),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        if (effortByDay.any { it.second.total > 0 }) {
            val shadow = Color(0xFF34C759)
            val sentences = Color(0xFFFF9500)
            val notebook = Color(0xFF007AFF)
            Text(stringResource(R.string.activity), style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 8.dp))
            // Stacked by KIND, not just totals — a strip that is always one
            // colour is the "I only ever do the comfortable thing" signal,
            // and that is the whole reason to draw it by kind.
            EffortCharts.Bars(
                days = effortByDay.map { (key, d) ->
                    EffortCharts.DayBar(key.takeLast(2), listOf(
                        shadow to d.shadowReps.toFloat(),
                        sentences to d.drillReps.toFloat(),
                        notebook to (d.wordReps + d.expressionReps).toFloat(),
                    ))
                },
            )
            EffortCharts.Legend(listOf(
                stringResource(R.string.shadowing) to shadow,
                stringResource(R.string.sentences) to sentences,
                stringResource(R.string.notebook) to notebook,
            ))
        }

        if (today.hasActivity) {
            TextButton(onClick = { showCard = true }) {
                Text(stringResource(R.string.share_card))
            }
        }
        if (showCard) DayCardSheet(today) { showCard = false }
    }
}

/**
 * The day's share card lives with the ACTIVITY and only there — the day
 * summary already says what the day was, and the card is that summary as a
 * picture. A post-talk button was tried on iOS and removed the same week:
 * the wrap-up flow is the book's, and a share offer inside it read as an
 * interruption.
 */
@Composable
private fun Stat(label: String, value: String) {
    Column {
        Text(value, style = MaterialTheme.typography.headlineMedium)
        Text(label, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
