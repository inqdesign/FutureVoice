package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
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
import com.roro.futurevoice.data.WeeklyReport
import com.roro.futurevoice.data.WeeklyReportStore
import com.roro.futurevoice.net.WeeklyReportEngine
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.CircularProgressIndicator
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DailyStudyPick
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.GoalStore
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
    var shelf by remember { mutableStateOf(Shelf.STUDYING) }
    var due by remember { mutableStateOf(0) }
    var wordsDue by remember { mutableStateOf(0) }
    var expressionsDue by remember { mutableStateOf(0) }
    var scenarios by remember { mutableStateOf<List<Scenario>>(emptyList()) }
    var talks by remember { mutableStateOf<List<Session>>(emptyList()) }
    var goals by remember { mutableStateOf(GoalStore.Goals()) }
    var today by remember { mutableStateOf(PracticeLog.Day()) }
    var streak by remember { mutableStateOf(0) }

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
        goals = GoalStore.load(context)
        today = PracticeLog.day(context) ?: PracticeLog.Day()
        streak = GoalStore.streak(context, goals)
    }

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        ShelfChips(
            selected = shelf,
            counts = { s ->
                when (s) {
                    Shelf.STUDYING -> null
                    Shelf.TALK -> talks.size.takeIf { it > 0 }
                    Shelf.WATCH -> scenarios.size.takeIf { it > 0 }
                }
            },
            onSelect = { shelf = it },
        )

        when (shelf) {
            // The cross-cutting page: what today asks for, then the books
            // currently in progress as horizontal rows.
            Shelf.STUDYING -> {
                TodayCard(
                    goals = goals, today = today, streak = streak,
                    dueSentences = due, dueWords = wordsDue, dueExpressions = expressionsDue,
                    onSentences = onOpenDeck, onWords = onOpenWords,
                    onExpressions = onOpenExpressions,
                    // Shadowing is reached through a book's line, so the tile
                    // sends them to the shelf that has the lines in it.
                    onShadowing = { shelf = Shelf.TALK },
                    onEditGoals = {},
                )
                if (talks.isNotEmpty()) {
                    BookRow(stringResource(R.string.talk), talks.size, talks.take(6),
                        onOpenShelf = { shelf = Shelf.TALK }) { TalkCard(it, onOpenTalk) }
                }
                if (scenarios.isNotEmpty()) {
                    BookRow(stringResource(R.string.watch), scenarios.size, scenarios.take(6),
                        onOpenShelf = { shelf = Shelf.WATCH }) {
                        ScenarioCard(it, onOpenScenarioBook)
                    }
                }
                if (talks.isEmpty() && scenarios.isEmpty()) {
                    Text(stringResource(R.string.nothing_here_yet_have_a_talk_or_watch_a_scene),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            Shelf.TALK -> talks.forEach { TalkCard(it, onOpenTalk) }
            Shelf.WATCH -> scenarios.forEach { ScenarioCard(it, onOpenScenarioBook) }
        }
    }
}

@Composable
private fun TalkCard(t: Session, onOpen: (String) -> Unit) {
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
        onClick = { onOpen(t.id) },
        modifier = Modifier.padding(vertical = 4.dp),
    )
}

@Composable
private fun ScenarioCard(sc: Scenario, onOpen: (String) -> Unit) {
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
        onClick = { onOpen(sc.id) },
        modifier = Modifier.padding(vertical = 4.dp),
    )
}

/** Two weeks: long enough to show a habit, short enough to read at a glance. */
private const val EFFORT_DAYS = 14

/** Day-of-month, the only part of a date a fourteen-bar strip has room for. */
private fun dayLabel(at: Long): String =
    java.text.SimpleDateFormat("d", java.util.Locale.US).format(java.util.Date(at))

/** How many cards a daily deck deals. Mirrors iOS's per-day goal default. */
private const val DAILY_HAND = 10


/**
 * Progress — measured, never guessed: the CEFR read comes from the talks
 * themselves (the summary's holistic estimate), the minutes from the meter,
 * and the two strips from the logs.
 *
 * No share card here. The day card's home is the Activity page and only
 * there — that page's day summary already says what the day was, and the card
 * is that summary as a picture.
 */
@Composable
fun ProgressBody(language: String, nativeLanguage: String,
                 onOpenAssessment: () -> Unit, goalMinutes: Int = 10) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var talks by remember { mutableStateOf<List<Session>>(emptyList()) }
    var todaySeconds by remember { mutableStateOf(0) }
    var minutesByDay by remember { mutableStateOf<List<Pair<Long, Int>>>(emptyList()) }
    var effortByDay by remember { mutableStateOf<List<Pair<String, PracticeLog.Day>>>(emptyList()) }
    var report by remember { mutableStateOf<WeeklyReport?>(null) }
    var unlock by remember { mutableStateOf<WeeklyReportEngine.Unlock?>(null) }
    var generating by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(language, revision) {
        talks = SessionStore.shared(context).load(language)
        todaySeconds = TalkTimeLog.secondsToday(context)
        minutesByDay = TalkTimeLog.recentSeconds(context, EFFORT_DAYS)
        effortByDay = PracticeLog.recent(context, EFFORT_DAYS)
        report = WeeklyReportStore.shared(context).latest(language)
        unlock = WeeklyReportEngine.unlockState(talks.filter { it.endedAt != null }, report)
    }
    val scored = talks.mapNotNull { it.summary?.scorecard }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // The pooled read outranks any single talk's: it is judged over the
        // whole window's speech at once, a far larger sample than one
        // conversation. A talk's own read is the fallback.
        val headline = report?.cefrLevel?.uppercase()
            ?: scored.firstOrNull()?.cefrLevel?.uppercase()
        headline?.takeIf { it.isNotEmpty() }?.let { level ->
            Column {
                Text(level,
                    style = com.roro.futurevoice.ui.brand.DisplayFace
                        .style(level, MaterialTheme.typography.displaySmall),
                    color = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.a_level_measured_not_guessed),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                // Never an unexplainable verdict: the judge's own rationale
                // names the evidence it decided from.
                report?.levelRationale?.takeIf { it.isNotBlank() }?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 4.dp))
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            Stat(stringResource(R.string.today), "${todaySeconds / 60}")
            Stat(stringResource(R.string.talks), "${talks.count { it.endedAt != null }}")
            if (scored.isNotEmpty()) {
                Stat(stringResource(R.string.overall), "${scored.map { it.overall }.average().toInt()}")
            }
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

        AssessmentPanel(
            report = report,
            onOpen = onOpenAssessment,
            unlock = unlock,
            working = generating,
            onGenerate = {
                generating = true
                scope.launch {
                    runCatching {
                        WeeklyReportEngine.generate(context, talks.filter { it.endedAt != null },
                            report, language, nativeLanguage)
                    }.getOrNull()?.let {
                        WeeklyReportStore.shared(context).save(it, language)
                        report = it
                        unlock = WeeklyReportEngine.unlockState(
                            talks.filter { s -> s.endedAt != null }, it)
                    }
                    generating = false
                }
            },
        )

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

/**
 * The latest assessment, readable at a glance.
 *
 * Locked, it shows what it is WAITING for and how far along that is — the
 * same number the gate opens on, so the bar can't fill at a different rate
 * than the door opens. Unlocked, it offers the button; generated, it shows
 * the trend line and the counts.
 *
 * The full item lists live on the report's own page: a wall of text at the
 * bottom of Progress was getting skipped, not read.
 */
@Composable
private fun AssessmentPanel(
    report: WeeklyReport?,
    onOpen: () -> Unit,
    unlock: WeeklyReportEngine.Unlock?,
    working: Boolean,
    onGenerate: () -> Unit,
) {
    if (unlock == null) return
    Column(
        Modifier.fillMaxWidth().padding(top = 8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(stringResource(R.string.latest_assessment),
            style = MaterialTheme.typography.titleMedium)

        report?.summary?.takeIf { it.isNotBlank() }?.let {
            // The whole digest is the way in — the counts below are lists,
            // and a number you cannot open is a number you cannot act on.
            Column(Modifier.fillMaxWidth().clickable { onOpen() },
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(it, style = MaterialTheme.typography.bodyMedium)
            Row(Modifier.fillMaxWidth().padding(top = 2.dp),
                horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                Stat(stringResource(R.string.new_expressions),
                    "${report.newExpressions.size}")
                Stat(stringResource(R.string.to_drill), "${report.repeatedMistakes.size}")
                Stat(stringResource(R.string.to_try), "${report.suggestedExpressions.size}")
            }
            }
        }

        when (unlock) {
            is WeeklyReportEngine.Unlock.First -> {
                Text(
                    stringResource(R.string.lld_of_lld_min_of_talking,
                        (unlock.accumulated / 60).toInt(), (unlock.required / 60).toInt()),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                LinearProgressIndicator(
                    progress = { (unlock.accumulated / unlock.required).toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            is WeeklyReportEngine.Unlock.Next -> {
                Text(
                    if (unlock.daysRemaining > 0)
                        stringResource(R.string.next_read_in_lld_days, unlock.daysRemaining)
                    else stringResource(R.string.lld_more_min_of_talking,
                        (unlock.secondsRemaining / 60).toInt() + 1),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            WeeklyReportEngine.Unlock.Ready -> {
                Button(onClick = onGenerate, enabled = !working,
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp)) {
                    if (working) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    } else {
                        Text(stringResource(
                            if (report == null) R.string.read_my_level
                            else R.string.new_assessment))
                    }
                }
            }
        }
    }
}
