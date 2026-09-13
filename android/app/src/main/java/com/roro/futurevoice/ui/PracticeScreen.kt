package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import com.roro.futurevoice.ui.brand.Symbols
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.WorkspacePremium
import com.roro.futurevoice.data.TalkCurriculum
import com.roro.futurevoice.data.ShadowAttemptStore
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.DropdownMenu
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import com.roro.futurevoice.data.StudyScheduleStore
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LevelBands
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
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.ui.text.font.FontWeight
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
    /** Today's shadow hand — dealt here, played by the root. */
    onShadowHand: (List<com.roro.futurevoice.data.ShadowPicks.Pick>) -> Unit = {},
    /** Everything shadowable, not today's hand. */
    onShadowAll: () -> Unit = {},
    onOpenWordsAll: () -> Unit = {},
    onOpenExpressionsAll: () -> Unit = {},
    onOpenDueReview: () -> Unit = {},
) {
    var editingGoals by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var shelf by remember { mutableStateOf(Shelf.STUDYING) }
    var due by remember { mutableStateOf(0) }
    var wordsDue by remember { mutableStateOf(0) }
    var expressionsDue by remember { mutableStateOf(0) }
    var scenarios by remember { mutableStateOf<List<Scenario>>(emptyList()) }
    val scope = rememberCoroutineScope()
    var talks by remember { mutableStateOf<List<Session>>(emptyList()) }
    var goals by remember { mutableStateOf(GoalStore.Goals()) }
    var today by remember { mutableStateOf(PracticeLog.Day()) }
    var streak by remember { mutableStateOf(0) }
    var dueBack by remember { mutableStateOf(0) }
    var finished by remember { mutableStateOf<List<FinishedBook>>(emptyList()) }
    var showFinished by remember { mutableStateOf(false) }
    /** Finished books. They keep their progress and can come back. */
    var archivedTalks by remember { mutableStateOf<List<Session>>(emptyList()) }
    var archivedScenarios by remember { mutableStateOf<List<Scenario>>(emptyList()) }

    LaunchedEffect(language, revision) {
        due = DrillStore.shared(context).dueCount(language)
        // The two library decks say how big TODAY's hand is, not how much is
        // in the notebook: the number has to be the number the deck deals or
        // the row promises work the deck won't hand over.
        wordsDue = DailyStudyPick.words(context, DAILY_HAND, language, level).size
        expressionsDue = DailyStudyPick.expressions(context, DAILY_HAND, language).size
        val allScenarios = ScenarioStore.shared(context).load(language).filter { it.isMeeting != true }
        scenarios = allScenarios.filter { it.archivedAt == null }
        archivedScenarios = allScenarios.filter { it.archivedAt != null }
        val allTalks = SessionStore.shared(context).load(language).filter { it.summary != null }
        talks = allTalks.filter { it.archivedAt == null }
        archivedTalks = allTalks.filter { it.archivedAt != null }
        goals = GoalStore.load(context)
        today = PracticeLog.day(context) ?: PracticeLog.Day()
        streak = GoalStore.streak(context, goals)
        // What the learner put away and asked to see again, now due.
        dueBack = StudyScheduleStore.shared(context).snapshot(language).dueItems().size
        // Archiving is tidying; this is the achievement — so archived books
        // count too, and both kinds land on the same shelf.
        val vocabStore = VocabStore.shared(context)
        val attempts = ShadowAttemptStore.shared(context).load(language)
        val cards = DrillStore.shared(context).load(language)
        finished = (allTalks.mapNotNull { s ->
            val snap = runCatching {
                TalkCurriculum.build(s, level, language, vocabStore, attempts, cards)
            }.getOrNull()
            if (snap?.isMastered != true) null
            else FinishedBook(s.id, s.displayTitle ?: "", context.getString(R.string.talk),
                Icons.Filled.Mic, snap.totalCount, isTalk = true)
        } + allScenarios.mapNotNull { sc ->
            val cur = sc.curriculum ?: return@mapNotNull null
            val total = cur.words.size + cur.expressions.size
            val done = cur.words.count { it.masteredAt != null } +
                cur.expressions.count { it.masteredAt != null }
            if (total == 0 || done < total) null
            else FinishedBook(sc.id, sc.cardTitle, context.getString(R.string.watch),
                Icons.Filled.MenuBook, total, isTalk = false)
        })
    }

    if (showFinished) {
        FinishedBooksSheet(
            books = finished,
            onOpen = { book ->
                showFinished = false
                if (book.isTalk) onOpenTalk(book.id) else onOpenScenarioBook(book.id)
            },
            onDismiss = { showFinished = false })
    }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) {
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
            }
            // Books where every word and line is mastered. A pill, shown even
            // at zero, so the shelf is something to fill rather than a
            // surprise the first time it appears.
            Row(Modifier
                .clip(RoundedCornerShape(999.dp))
                .background(MaterialTheme.colorScheme.surface)
                .clickable { showFinished = true }
                .padding(horizontal = 12.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Icon(Icons.Filled.WorkspacePremium, contentDescription = null,
                    modifier = Modifier.size(17.dp),
                    tint = if (finished.isEmpty()) MaterialTheme.colorScheme.outline else Books.mastery)
                Text("${finished.size}", style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = if (finished.isEmpty()) MaterialTheme.colorScheme.outline else Books.mastery)
            }
        }

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
                    onShadowAll = onShadowAll,
                    dueBack = dueBack,
                    onDueBack = onOpenDueReview,
                    onWordsAll = onOpenWordsAll,
                    onExpressionsAll = onOpenExpressionsAll,
                    onShadowing = {
                        // Deal today's hand. With nothing to deal — no talks
                        // yet — the Talk shelf is the honest fallback: the
                        // material comes from conversations, so that is where
                        // the learner has to go first.
                        scope.launch {
                            val picks = com.roro.futurevoice.data.ShadowPicks.pick(
                                sessions = talks,
                                attempts = com.roro.futurevoice.data.ShadowAttemptStore
                                    .shared(context).load(language),
                                level = level,
                                language = language,
                                limit = maxOf(goals.shadows, 1))
                            if (picks.isEmpty()) shelf = Shelf.TALK else onShadowHand(picks)
                        }
                    },
                    onEditGoals = { editingGoals = true },
                )
                if (editingGoals) {
                    StudyGoalsSheet(onDismiss = {
                        editingGoals = false
                        // The card reads the goals it was handed, so the
                        // change has to travel the same way every write does.
                        StoreEvents.bump()
                    })
                }
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

            Shelf.TALK -> {
                talks.forEach {
                    TalkCard(it, onOpenTalk,
                        onArchive = { id, on -> scope.launch {
                            SessionStore.shared(context).setArchived(id, on, language); StoreEvents.bump() } },
                        onDelete = { id -> scope.launch {
                            SessionStore.shared(context).delete(id, language); StoreEvents.bump() } })
                }
                ArchiveSection(archivedTalks.isNotEmpty()) {
                    archivedTalks.forEach {
                        TalkCard(it, onOpenTalk,
                            onArchive = { id, on -> scope.launch {
                                SessionStore.shared(context).setArchived(id, on, language); StoreEvents.bump() } },
                            onDelete = { id -> scope.launch {
                                SessionStore.shared(context).delete(id, language); StoreEvents.bump() } })
                    }
                }
            }
            Shelf.WATCH -> {
                scenarios.forEach {
                    ScenarioCard(it, onOpenScenarioBook,
                        onArchive = { id, on -> scope.launch {
                            ScenarioStore.shared(context).setArchived(id, on, language); StoreEvents.bump() } },
                        onDelete = { id -> scope.launch {
                            ScenarioStore.shared(context).delete(id, language); StoreEvents.bump() } })
                }
                ArchiveSection(archivedScenarios.isNotEmpty()) {
                    archivedScenarios.forEach {
                        ScenarioCard(it, onOpenScenarioBook,
                            onArchive = { id, on -> scope.launch {
                                ScenarioStore.shared(context).setArchived(id, on, language); StoreEvents.bump() } },
                            onDelete = { id -> scope.launch {
                                ScenarioStore.shared(context).delete(id, language); StoreEvents.bump() } })
                    }
                }
            }
        }
    }
}

/** A book's own actions. Long-press, because a tap is for opening it. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BookMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    items: List<Triple<String, ImageVector, () -> Unit>>,
    destructiveLast: Boolean = true,
) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        items.forEachIndexed { i, (label, icon, action) ->
            val destructive = destructiveLast && i == items.lastIndex
            DropdownMenuItem(
                text = {
                    Text(label, color = if (destructive) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurface)
                },
                leadingIcon = {
                    Icon(icon, contentDescription = null,
                        tint = if (destructive) MaterialTheme.colorScheme.error
                        else MaterialTheme.colorScheme.onSurfaceVariant)
                },
                onClick = { onDismiss(); action() })
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TalkCard(t: Session, onOpen: (String) -> Unit,
                     onArchive: ((String, Boolean) -> Unit)? = null,
                     onDelete: ((String) -> Unit)? = null) {
    var menu by remember { mutableStateOf(false) }
    Box {
        BookMenu(menu, { menu = false }, listOfNotNull(
            onArchive?.let {
                Triple(stringResource(if (t.archivedAt == null) R.string.archive else R.string.unarchive),
                    Icons.Filled.Inventory2, { it(t.id, t.archivedAt == null) })
            },
            onDelete?.let { Triple(stringResource(R.string.delete), Icons.Filled.Delete, { it(t.id) }) },
        ))
    BookCard(
        title = t.displayTitle ?: stringResource(R.string.conversation),
        icon = Icons.AutoMirrored.Filled.Chat,
        origin = when (t.origin?.name?.lowercase()) {
            "news" -> stringResource(R.string.news)
            "scenario" -> stringResource(R.string.scenarios)
            else -> stringResource(R.string.free_talk)
        },
        accent = if (t.origin?.name?.lowercase() == "news") Books.topics else Books.talks,
        // WHEN it was last worked, said as recency — it keeps advancing as
        // the book is studied, which a fixed date does not.
        detail = stringResource(R.string.studied,
            android.text.format.DateUtils.getRelativeTimeSpanString(
                t.endedAt ?: t.startedAt, System.currentTimeMillis(),
                android.text.format.DateUtils.MINUTE_IN_MILLIS).toString()),
        score = t.summary?.scorecard?.overall,
        modifier = Modifier.padding(vertical = 4.dp)
            .combinedClickable(onClick = { onOpen(t.id) }, onLongClick = { menu = true }),
    )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ScenarioCard(sc: Scenario, onOpen: (String) -> Unit,
                         onTalk: ((Scenario) -> Unit)? = null,
                         onArchive: ((String, Boolean) -> Unit)? = null,
                         onDelete: ((String) -> Unit)? = null) {
    var menu by remember { mutableStateOf(false) }
    val cur = sc.curriculum
    val total = cur?.let { it.words.size + it.expressions.size + it.shadowLines.size } ?: 0
    val done = cur?.let {
        it.words.count { w -> w.masteredAt != null } +
            it.expressions.count { e -> e.masteredAt != null }
    } ?: 0
    BookCard(
        title = sc.cardTitle,
        icon = Symbols.icon(sc.categoryIcon),
        // WHO the scene is with — a category names the shelf, not the scene.
        origin = sc.role?.takeIf { it.isNotBlank() } ?: sc.category,
        accent = Books.scenarios,
        detail = null,
        progressLabel = if (cur == null) stringResource(R.string.watch_the_scene_first)
        else if (total > 0 && done == total) stringResource(R.string.mastered_550ec5)
        else stringResource(R.string.lld_of_lld_mastered, done, total),
        mastered = total > 0 && done == total,
        progress = if (total == 0) null else done / total.toFloat(),
        modifier = Modifier.padding(vertical = 4.dp)
            .combinedClickable(onClick = { onOpen(sc.id) }, onLongClick = { menu = true }),
    )
    BookMenu(menu, { menu = false }, listOfNotNull(
        Triple(stringResource(R.string.open), Icons.Filled.MenuBook, { onOpen(sc.id) }),
        onTalk?.let { Triple(stringResource(R.string.talk_now), Icons.Filled.Mic, { it(sc) }) },
        onArchive?.let {
            Triple(stringResource(if (sc.archivedAt == null) R.string.archive else R.string.unarchive),
                Icons.Filled.Inventory2, { it(sc.id, sc.archivedAt == null) })
        },
        onDelete?.let { Triple(stringResource(R.string.delete), Icons.Filled.Delete, { it(sc.id) }) },
    ))
}

/**
 * Progress's dimensions. Shadowing is deliberately NOT one: shadow scores
 * measure practice EFFORT, not level, and presenting them as an assessed
 * skill made them read as part of the level estimate. They live in the
 * activity strip and in Practice.
 */
enum class Dim(val labelRes: Int) {
    OVERALL(R.string.overall),
    VOCABULARY(R.string.vocabulary),
    GRAMMAR(R.string.grammar),
    FLUENCY(R.string.fluency),
    EXPRESSIVENESS(R.string.expressiveness),
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
                 onOpenAssessment: () -> Unit, onOpenActivity: () -> Unit,
                 goalMinutes: Int = 10,
                 /** A measured CEFR level from a fresh assessment. */
                 onMeasuredLevel: (String) -> Unit = {}) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var talks by remember { mutableStateOf<List<Session>>(emptyList()) }
    var todaySeconds by remember { mutableStateOf(0) }
    var minutesByDay by remember { mutableStateOf<List<Pair<Long, Int>>>(emptyList()) }
    var effortByDay by remember { mutableStateOf<List<Pair<String, PracticeLog.Day>>>(emptyList()) }
    var report by remember { mutableStateOf<WeeklyReport?>(null) }
    var unlock by remember { mutableStateOf<WeeklyReportEngine.Unlock?>(null) }
    var generating by remember { mutableStateOf(false) }
    var dim by remember { mutableStateOf(Dim.OVERALL) }
    var carryoverTotal by remember { mutableStateOf(0) }
    var carryoverWeek by remember { mutableStateOf(0) }
    var material by remember { mutableStateOf(0 to 0) }
    var streak by remember { mutableStateOf(0) }
    var vocabBands by remember { mutableStateOf<Map<CefrLevel, Int>>(emptyMap()) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(language, revision) {
        talks = SessionStore.shared(context).load(language)
        todaySeconds = TalkTimeLog.secondsToday(context)
        minutesByDay = TalkTimeLog.recentSeconds(context, EFFORT_DAYS)
        effortByDay = PracticeLog.recent(context, EFFORT_DAYS)
        report = WeeklyReportStore.shared(context).latest(language)
        unlock = WeeklyReportEngine.unlockState(talks.filter { it.endedAt != null }, report)
        // Studied, then SAID — the loop closing, which is the one number that
        // proves the app worked. The detector already writes it onto every
        // summary; it had simply never been read back.
        val carries = talks.flatMap { it.summary?.carryovers.orEmpty() }
        carryoverTotal = carries.size
        val weekAgo = System.currentTimeMillis() - 7L * 86_400_000L
        carryoverWeek = carries.count { it.detectedAt >= weekAgo }
        // Whole-library mastery: "how far along am I" is THIS tab's question,
        // which is why it lives here rather than on Practice.
        val books = ScenarioStore.shared(context).load(language)
            .filter { it.archivedAt == null }
        material = books.sumOf { b ->
            b.curriculum?.let { c ->
                c.words.count { it.masteredAt != null } +
                    c.expressions.count { it.masteredAt != null }
            } ?: 0
        } to books.sumOf { b ->
            b.curriculum?.let { it.words.size + it.expressions.size + it.shadowLines.size } ?: 0
        }
        streak = TalkTimeLog.streakDays(context)
        vocabBands = VocabStore.shared(context).usedWordsByLevel(language)
    }
    val scored = talks.mapNotNull { it.summary?.scorecard }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Dim.entries.forEach { d ->
                FilterChip(selected = d == dim, onClick = { dim = d },
                    label = { Text(stringResource(d.labelRes)) })
            }
        }

        if (dim != Dim.OVERALL) {
            // Each skill's own page: its measured number and what the number
            // is. Measurement only — the DOING lives in Practice.
            SkillPage(dim, scored.firstOrNull())
            return@Column
        }

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

        // ONE unit on the level page: the CEFR read per skill, tappable for
        // the measured numbers behind it. The raw figures (WPM, 0-100 score)
        // live on each skill's own page, not here.
        // The recipe made visible, equalizer-style: one column per measured
        // ingredient, lit blocks = that axis's CEFR band. A weak axis is a
        // visibly shorter column, which a row of 0-100 scores can't show.
        if (scored.isNotEmpty() || vocabBands.isNotEmpty()) {
            val userTurns = talks.flatMap { it.turns }.filter { it.role == TurnRole.USER }
            val words = userTurns.sumOf { it.transcript.trim().split(Regex("\\s+")).count { w -> w.isNotEmpty() } }
            val voiced = userTurns.sumOf { it.fluency?.speakingSeconds ?: 0.0 }
            val wallSeconds = userTurns.sumOf { it.durationMs / 1000.0 }
            val wpm = when {
                voiced > 30 -> words / (voiced / 60.0)
                wallSeconds > 30 -> words / (wallSeconds / 60.0)
                else -> 0.0
            }
            val perTurn = if (userTurns.isEmpty()) 0.0 else words.toDouble() / userTurns.size
            val vocabLevel = LevelBands.vocabularyLevel(vocabBands)
            val fluencyLevel = LevelBands.fluencyBand(wpm, fromVoicedSpeech = voiced > 30)
            val grammarLevel = LevelBands.grammarBand(scored.firstOrNull()?.grammar?.score ?: 0)
            val expressLevel = LevelBands.expressionBand(perTurn)
            fun lit(l: CefrLevel?) = l?.let { CoreVocabulary.levelRank(it) + 1 } ?: 0
            fun label(l: CefrLevel?, approx: Boolean) =
                l?.let { (if (approx) "≈" else "") + it.code.uppercase() } ?: "—"
            LevelEqualizer.View(listOf(
                LevelEqualizer.Bar(stringResource(R.string.axis_vocab), label(vocabLevel, false),
                    lit(vocabLevel), Color(0xFF3B82F6)),
                LevelEqualizer.Bar(stringResource(R.string.fluency), label(fluencyLevel, true),
                    lit(fluencyLevel), Color(0xFF22C55E)),
                LevelEqualizer.Bar(stringResource(R.string.grammar), label(grammarLevel, true),
                    lit(grammarLevel), Color(0xFFF59E0B)),
                LevelEqualizer.Bar(stringResource(R.string.axis_express), label(expressLevel, true),
                    lit(expressLevel), Color(0xFFA855F7)),
            ), Modifier.padding(top = 8.dp))
            Text(stringResource(R.string.vocabulary_is_graded_from_the_words_you_actually_use_levels_a3dc6c),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.outline)
        }

        if (scored.isNotEmpty()) {
            val card = scored.first()
            Text(stringResource(R.string.across_skills),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 8.dp))
            SkillRow(stringResource(R.string.vocabulary), card.vocabulary.score) {
                dim = Dim.VOCABULARY
            }
            SkillRow(stringResource(R.string.fluency), card.fluency.score) {
                dim = Dim.FLUENCY
            }
            SkillRow(stringResource(R.string.grammar), card.grammar.score) {
                dim = Dim.GRAMMAR
            }
            SkillRow(stringResource(R.string.expressiveness), card.expressiveness.score) {
                dim = Dim.EXPRESSIVENESS
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

        // Never drawn while zero: a headline "0" on the one number that
        // proves the loop closed reads as a verdict on the learner.
        if (carryoverTotal > 0) {
            BigStat(
                title = stringResource(R.string.studied_then_said),
                value = carryoverTotal,
                caption = stringResource(R.string.things_you_studied_came_out_of_your_mouth),
                trailing = carryoverWeek.takeIf { it > 0 }
                    ?.let { stringResource(R.string.plus_lld_this_week, it) },
            )
        }

        if (material.second > 0) {
            BigStat(
                title = stringResource(R.string.your_material),
                value = material.first,
                caption = stringResource(
                    R.string.mastered_out_of_lld_your_talks_have_made, material.second),
                progress = material.first / material.second.toFloat(),
            )
        }

        // The ONLY way into the activity calendar from this tab. A streak is
        // a claim about a history, so it has to open the record — otherwise
        // it is a number asking to be trusted.
        Row(
            Modifier.fillMaxWidth().clickable { onOpenActivity() }.padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Filled.LocalFireDepartment, contentDescription = null,
                tint = if (streak > 0) Color(0xFFFF9500)
                else MaterialTheme.colorScheme.onSurfaceVariant)
            Column(Modifier.weight(1f)) {
                Text(
                    if (streak == 0) stringResource(R.string.no_streak_yet)
                    else stringResource(R.string.lld_day_streak, streak),
                    style = MaterialTheme.typography.bodyLarge)
                Text(stringResource(R.string.lld_talks_tap_for_calendar,
                    talks.count { it.endedAt != null }),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
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
                        // The MEASURED level replaces the self-reported
                        // setting — from here scoring calibration, pickup-word
                        // difficulty and the talk-card label all track
                        // measurement rather than what someone guessed about
                        // themselves in onboarding. A manual change in Me
                        // still wins until the next assessment.
                        it.cefrLevel?.let { measured -> onMeasuredLevel(measured) }
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

/**
 * One skill's line on the level page: what it is, and the band it measures
 * at. Tappable, because the numbers behind it are on its own page.
 */
@Composable
private fun SkillRow(title: String, score: Int, onOpen: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Text("$score", style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.primary)
    }
}

/**
 * A skill's own page: the measured number, and a plain sentence saying what
 * was measured. Nothing to DO here — Progress is the measurement tab, and
 * the doing lives in Practice.
 */
@Composable
private fun SkillPage(dim: Dim, card: com.roro.futurevoice.talk.SessionScorecard?) {
    val axis = when (dim) {
        Dim.VOCABULARY -> card?.vocabulary
        Dim.GRAMMAR -> card?.grammar
        Dim.FLUENCY -> card?.fluency
        Dim.EXPRESSIVENESS -> card?.expressiveness
        Dim.OVERALL -> null
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("${axis?.score ?: 0}",
            style = MaterialTheme.typography.displaySmall,
            color = MaterialTheme.colorScheme.primary)
        Text(stringResource(dim.labelRes), style = MaterialTheme.typography.titleMedium)
        // The coach's own note about this axis, in the learner's language.
        axis?.note?.takeIf { it.isNotBlank() }?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        } ?: Text(stringResource(R.string.have_a_talk_and_this_gets_measured),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * One big measured number with the sentence that says what it counts.
 *
 * The figure carries the weight and the sentence does the explaining — a
 * label above a number makes the reader assemble the fact from two places.
 */
@Composable
private fun BigStat(
    title: String,
    value: Int,
    caption: String,
    trailing: String? = null,
    progress: Float? = null,
) {
    Column(Modifier.fillMaxWidth().padding(top = 8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f))
            trailing?.let {
                Text(it, style = MaterialTheme.typography.labelMedium,
                    color = Color(0xFF34C759))
            }
        }
        Row(verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("$value", style = MaterialTheme.typography.displaySmall,
                fontWeight = FontWeight.Bold)
            Text(caption, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 10.dp))
        }
        progress?.let {
            LinearProgressIndicator(
                progress = { it.coerceIn(0f, 1f) },
                color = if (it >= 1f) Color(0xFF34C759) else MaterialTheme.colorScheme.primary,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

/** Finished books, under the shelf they left. Collapsed to a header so they
 *  never compete with what is still in progress. */
@Composable
private fun ArchiveSection(hasAny: Boolean, content: @Composable () -> Unit) {
    if (!hasAny) return
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(stringResource(R.string.archive), style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(top = 12.dp))
        content()
        Text(stringResource(R.string.finished_books_they_keep_their_progress_unarchive_anytime),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
