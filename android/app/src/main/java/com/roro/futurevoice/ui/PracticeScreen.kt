package com.roro.futurevoice.ui

import com.roro.futurevoice.data.Recency
import com.roro.futurevoice.data.StudyCollections
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
import com.roro.futurevoice.data.DeepLinkInbox
import com.roro.futurevoice.data.LanguageCatalog
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Schedule
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
    /** Which shelf the page opens on (iOS `PracticeTab(initialShelf:)`). */
    initialShelf: Shelf = Shelf.STUDYING,
) {
    var editingGoals by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var shelf by remember { mutableStateOf(initialShelf) }
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
    /** How big the collection behind each tile's footer is. */
    var wordsAll by remember { mutableStateOf<Int?>(null) }
    var expressionsAll by remember { mutableStateOf<Int?>(null) }
    var shadowAll by remember { mutableStateOf<Int?>(null) }
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
        wordsAll = StudyCollections.wordsToStudy(context, language)
        expressionsAll = StudyCollections.expressionsToStudy(context, language)
        shadowAll = StudyCollections.shadowToStudy(context, language)
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
                Icons.AutoMirrored.Filled.Chat, snap.totalCount, isTalk = true,
                finishedLabel = shelfDate(s.endedAt ?: s.startedAt))
        } + allScenarios.mapNotNull { sc ->
            val cur = sc.curriculum ?: return@mapNotNull null
            val total = cur.words.size + cur.expressions.size
            val done = cur.words.count { it.masteredAt != null } +
                cur.expressions.count { it.masteredAt != null }
            if (total == 0 || done < total) null
            else FinishedBook(sc.id, sc.cardTitle,
                // "Scene · with Sarah" — who it was with is part of what the
                // book WAS, and the row is the only place it still shows.
                listOfNotNull(context.getString(R.string.scene),
                    sc.role.takeIf { it.isNotBlank() }
                        ?.let { context.getString(R.string.with, it) })
                    .joinToString(" · "),
                Icons.Filled.Movie, total, isTalk = false,
                finishedLabel = shelfDate(sc.createdAt))
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
                    wordsToStudy = wordsAll,
                    expressionsToStudy = expressionsAll,
                    shadowToStudy = shadowAll,
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
        detail = stringResource(R.string.studied, Recency.label(t.endedAt ?: t.startedAt)),
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
 * Progress — measured, never guessed. Every number here is computed in code
 * from the talks themselves (`ProgressMath`); the only thing an LLM writes on
 * this tab is the qualitative note beside a figure it did not invent.
 *
 * The overall level is ONE pooled judgment over everything said since the
 * last assessment — never a single talk's read, which is too small a sample
 * to publish. The per-skill pages behind the chips lean on the deterministic
 * measurements (CEFR-graded vocabulary, articulation pace, verified slip
 * density, words per turn). Shadowing and drill reps are PRACTICE, not
 * assessment: they appear as effort and never move the level.
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
                 onMeasuredLevel: (String) -> Unit = {},
                 /**
                  * Pace and turn length only move by speaking, so the way out
                  * of those pages is a call. Null hides the button rather
                  * than offering a door that opens nowhere — the words and
                  * slips pages route themselves through `DeepLinkInbox`.
                  */
                 onStartTalk: (() -> Unit)? = null) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var talks by remember { mutableStateOf<List<Session>>(emptyList()) }
    var todaySeconds by remember { mutableStateOf(0) }
    var minutesByDay by remember { mutableStateOf<List<Pair<Long, Int>>>(emptyList()) }
    var effortByDay by remember { mutableStateOf<List<Pair<String, PracticeLog.Day>>>(emptyList()) }
    var report by remember { mutableStateOf<WeeklyReport?>(null) }
    /** The newest report that actually CARRIES a level — reports written
     *  before the pooled read existed have none, and the latest report is
     *  not always one of them. */
    var levelReport by remember { mutableStateOf<WeeklyReport?>(null) }
    var unlock by remember { mutableStateOf<WeeklyReportEngine.Unlock?>(null) }
    var generating by remember { mutableStateOf(false) }
    var dim by remember { mutableStateOf(Dim.OVERALL) }
    var carryoverTotal by remember { mutableStateOf(0) }
    var carryoverWeek by remember { mutableStateOf(0) }
    var material by remember { mutableStateOf(0 to 0) }
    var streak by remember { mutableStateOf(0) }
    var avgShadowScore by remember { mutableStateOf(0) }
    // False until the first pass has landed. Every number below starts at
    // zero, and a zero is a CLAIM here ("nothing measured, 0/15 min") — so
    // the pages must not be drawn from it before the archive has been read.
    var loaded by remember { mutableStateOf(false) }
    var metrics by remember { mutableStateOf(ProgressMetrics()) }
    var showHowAssessed by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(language, revision) {
        talks = SessionStore.shared(context).load(language)
        todaySeconds = TalkTimeLog.secondsToday(context)
        minutesByDay = TalkTimeLog.recentSeconds(context, EFFORT_DAYS)
        effortByDay = PracticeLog.recent(context, EFFORT_DAYS)
        val reports = WeeklyReportStore.shared(context).load(language)
        report = reports.firstOrNull()
        levelReport = reports.firstOrNull { it.cefrLevel != null }
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
        val bands = VocabStore.shared(context).usedWordsByLevel(language)
        val expressions = VocabStore.shared(context).expressionEntries(language).size
        val attempts = ShadowAttemptStore.shared(context).load(language)
        avgShadowScore = attempts.sortedByDescending { it.createdAt }.take(10)
            .map { it.matchScore }.takeIf { it.isNotEmpty() }?.average()?.toInt() ?: 0
        // The walk is several passes over every ended talk plus a scorecard
        // recomputation each — off the main thread, or the tab opens on the
        // still-empty state and a learner with a year of talks reads zeroes.
        val loadedTalks = talks
        metrics = withContext(Dispatchers.Default) {
            ProgressMath.compute(loadedTalks, reports, bands, expressions)
        }
        loaded = true
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Dim.entries.forEach { d ->
                PillChip(label = stringResource(d.labelRes), selected = d == dim) { dim = d }
            }
        }

        // Deliberately NOT the empty state: it says nothing has been
        // measured, which is a lie for anyone with a history, and it is what
        // the tab showed on every entry while the archive was still being
        // read.
        if (!loaded) {
            CircularProgressIndicator(Modifier.padding(top = 32.dp))
            return@Column
        }

        val seeWords = { DeepLinkInbox.pending.value = DeepLinkInbox.Destination.VOCABULARY }
        val browseExpressions = { DeepLinkInbox.pending.value = DeepLinkInbox.Destination.EXPRESSIONS }
        val reviewSlips = { DeepLinkInbox.pending.value = DeepLinkInbox.Destination.REVIEW }

        if (dim != Dim.OVERALL) {
            // Each skill's own page: its measured number, the sentence saying
            // what was measured, the trend over its CEFR bands, and the way
            // to improve it — which always leaves this tab, because Progress
            // measures and the doing lives in Talk and Practice.
            ProgressSkillPage(dim, metrics,
                onSeeWords = seeWords,
                onReviewSlips = reviewSlips,
                onStartTalk = onStartTalk,
                onBrowseExpressions = browseExpressions)
            return@Column
        }

        // A level shows ONLY once a pooled read exists. No early guess from a
        // single talk: if the sample is not big enough yet, the honest
        // display is the recipe plus how far along the unlock is.
        val level = levelReport?.cefrLevel?.let { raw ->
            CefrLevel.entries.firstOrNull { it.code.equals(raw, true) }
        }
        val assessedAt = levelReport?.generatedAt
        val stale = assessedAt != null &&
            System.currentTimeMillis() - assessedAt > LEVEL_STALE_DAYS * 86_400_000L

        ProgressPanel {
            Text(stringResource(R.string.estimated_level),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (level != null) {
                val code = level.code.uppercase()
                // A level assessed 4+ weeks ago dims instead of posing as
                // today's truth.
                Text(code,
                    style = com.roro.futurevoice.ui.brand.DisplayFace
                        .style(code, MaterialTheme.typography.displayMedium),
                    color = if (stale) MaterialTheme.colorScheme.onSurfaceVariant
                    else MaterialTheme.colorScheme.primary)
                // Korean learners orient by TOPIK, Japanese by JLPT — the
                // official equivalence under the big number.
                LanguageCatalog.levelLabel(level, language).takeIf { it != code }?.let {
                    Text(it, style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                // What the level MEANS, before where it came from: a bare
                // letter is a grade, and this is a measurement.
                Text(canDoAt(code), style = MaterialTheme.typography.bodyMedium)
                assessedAt?.let { at ->
                    Text(
                        if (stale) stringResource(
                            R.string.assessed_a_while_back_your_next_talks_feed_a_fresh_assessmen_2febb6,
                            Recency.label(at))
                        else stringResource(
                            R.string.assessed_from_your_recent_talk_vocabulary_grammar_fluency_an_688dda,
                            Recency.label(at)),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                GroupedRowDivider(inset = false)
                NextAssessmentStatus(unlock, generating)
            } else {
                // The recipe made visible, equalizer-style: one bar per
                // measured ingredient, lit LED blocks = that axis's CEFR
                // band. A weak axis is a visibly shorter column.
                fun lit(l: CefrLevel?) = l?.let { CoreVocabulary.levelRank(it) + 1 } ?: 0
                fun label(l: CefrLevel?, approx: Boolean) =
                    l?.let { (if (approx) "≈" else "") + it.code.uppercase() } ?: "—"
                LevelEqualizer.View(listOf(
                    LevelEqualizer.Bar(stringResource(R.string.axis_vocab),
                        label(metrics.vocabLevel, false), lit(metrics.vocabLevel), Color(0xFF3B82F6)),
                    LevelEqualizer.Bar(stringResource(R.string.fluency),
                        label(metrics.fluencyLevel, true), lit(metrics.fluencyLevel), Color(0xFF22C55E)),
                    LevelEqualizer.Bar(stringResource(R.string.grammar),
                        label(metrics.grammarLevel, true), lit(metrics.grammarLevel), Color(0xFFF59E0B)),
                    LevelEqualizer.Bar(stringResource(R.string.axis_express),
                        label(metrics.expressionLevel, true), lit(metrics.expressionLevel), Color(0xFFA855F7)),
                ), Modifier.padding(top = 8.dp))
                Text(stringResource(R.string.vocabulary_is_graded_from_the_words_you_actually_use_levels_a3dc6c),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.outline)
                GroupedRowDivider(inset = false)
                BuildingStatus(unlock, generating)
            }
            TextButton(onClick = { showHowAssessed = true },
                modifier = Modifier.padding(top = 2.dp)) {
                Text(stringResource(R.string.how_this_is_assessed))
            }
        }
        if (showHowAssessed) {
            HowAssessedSheet(
                level = level,
                rationale = levelReport?.levelRationale,
                firstReportMinutes = (WeeklyReportEngine.FIRST_REPORT_MIN_SECONDS / 60).toInt(),
                m = metrics,
                onDismiss = { showHowAssessed = false })
        }

        // THE growth graph: the level, one point per assessment. Present from
        // the first assessment on — with one point it says the curve starts
        // at the second, instead of hiding entirely.
        if (metrics.levelHistory.isNotEmpty()) {
            ProgressPanel {
                Text(stringResource(R.string.growth), style = MaterialTheme.typography.titleMedium)
                if (metrics.levelHistory.size >= 2) {
                    LevelHistoryChart(metrics.levelHistory)
                    Text(stringResource(
                        R.string.your_level_one_point_per_assessment_this_line_is_what_growin_5b1e84),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    Text(stringResource(
                        R.string.your_growth_curve_starts_at_your_second_assessment_every_ass_e7099b),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        GroupedCard {
            Row(Modifier.fillMaxWidth().padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                Stat(stringResource(R.string.today), "${todaySeconds / 60}")
                Stat(stringResource(R.string.talks), "${talks.count { it.endedAt != null }}")
            }
        }

        // ONE unit on the level page: the CEFR band per skill, tappable for
        // the measured numbers behind it. Each row reads its OWN axis's band
        // — the raw figures (WPM, slips/100, words per turn) live on the
        // skill's own page, never beside a CEFR letter as a second scale.
        if (metrics.scoredCount > 0 || metrics.vocabLevel != null) {
            GroupedSectionHeader(stringResource(R.string.across_skills))
            GroupedCard {
                SkillRow(stringResource(R.string.vocabulary),
                    metrics.vocabLevel?.code?.uppercase()) { dim = Dim.VOCABULARY }
                GroupedRowDivider(inset = false)
                SkillRow(stringResource(R.string.fluency),
                    metrics.fluencyLevel?.let { "≈" + it.code.uppercase() }) { dim = Dim.FLUENCY }
                GroupedRowDivider(inset = false)
                SkillRow(stringResource(R.string.grammar),
                    metrics.grammarLevel?.let { "≈" + it.code.uppercase() }) { dim = Dim.GRAMMAR }
                GroupedRowDivider(inset = false)
                SkillRow(stringResource(R.string.expressiveness),
                    metrics.expressionLevel?.let { "≈" + it.code.uppercase() }) {
                    dim = Dim.EXPRESSIVENESS
                }
            }
            Text(stringResource(R.string.same_bands_as_how_this_is_assessed_tap_a_skill_for_its_measu_19d33d),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.outline,
                modifier = Modifier.padding(horizontal = 4.dp))
        }

        // What to do next, from the SAME per-axis measurements the sheet
        // shows: only an axis measuring BELOW the target level appears, each
        // anchored to its live number. An unmeasured axis stays silent.
        level?.let { ProgressBands.next(it) }?.let { next ->
            ProgressPanel {
                Text(stringResource(R.string.to_reach, next.code.uppercase()),
                    style = MaterialTheme.typography.titleMedium)
                Text(canDoAt(next.code.uppercase()), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                FocusTips(metrics, next, seeWords, reviewSlips, onStartTalk)
            }
        }

        // What the last two weeks actually were. Both strips are drawn only
        // when there is something in them: an empty chart is a reproach, and
        // a new learner has done nothing wrong.
        if (minutesByDay.any { it.second > 0 }) {
            Row(Modifier.fillMaxWidth().padding(top = 8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.time_speaking),
                    style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                Text(stringResource(R.string.lld_min_this_week,
                    minutesByDay.takeLast(7).sumOf { it.second } / 60),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            EffortCharts.Bars(
                days = minutesByDay.map { (at, secs) ->
                    EffortCharts.DayBar(dayLabel(at),
                        listOf(MaterialTheme.colorScheme.primary to secs / 60f))
                },
                goal = goalMinutes.toFloat(),
            )
            Text(stringResource(
                R.string.minutes_you_actually_spoke_per_day_the_dashed_line_is_your_l_b779b3,
                goalMinutes),
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
                        if (it.cefrLevel != null) levelReport = it
                        // The MEASURED level replaces the self-reported
                        // setting — from here scoring calibration, pickup-word
                        // difficulty and the talk-card label all track
                        // measurement rather than what someone guessed about
                        // themselves in onboarding. A manual change in Me
                        // still wins until the next assessment.
                        it.cefrLevel?.let { measured -> onMeasuredLevel(measured) }
                        unlock = WeeklyReportEngine.unlockState(
                            talks.filter { s -> s.endedAt != null }, it)
                        val fresh = WeeklyReportStore.shared(context).load(language)
                        val bands = VocabStore.shared(context).usedWordsByLevel(language)
                        val seen = talks
                        val expressions = metrics.expressionCount
                        metrics = withContext(Dispatchers.Default) {
                            ProgressMath.compute(seen, fresh, bands, expressions)
                        }
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
            // Reps stay what they have always meant here — REVIEW work.
            // Talk time is counted in minutes, in its own strip above.
            val week = effortByDay.takeLast(7)
            val reps = week.sumOf { it.second.total }
            val daysActive = week.count { it.second.total > 0 }
            Row(Modifier.fillMaxWidth().padding(top = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                Stat(stringResource(R.string.reps_this_week), "$reps")
                Stat(stringResource(R.string.days_active), "$daysActive")
                if (avgShadowScore > 0) {
                    Stat(stringResource(R.string.avg_shadow_score), "$avgShadowScore")
                }
            }
        }
    }
}

/** A level assessed longer ago than this reads as stale — dimmed, with a
 *  "talk again and it refreshes" line, rather than posing as today's truth. */
private const val LEVEL_STALE_DAYS = 28L

/**
 * When and how the level actually gets assessed — the weekly read's REAL
 * unlock rules, never a vague progress bar. Shown INSTEAD of a level, while
 * there isn't one.
 */
@Composable
private fun BuildingStatus(unlock: WeeklyReportEngine.Unlock?, working: Boolean) {
    if (working) {
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            Text(stringResource(R.string.assessing_your_level_from_everything_you_ve_said),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }
    when (unlock) {
        is WeeklyReportEngine.Unlock.First -> {
            Text(stringResource(
                R.string.your_level_is_graded_at_your_first_assessment_one_pooled_jud_873e14),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            UnlockBar(unlock.accumulated, unlock.required)
        }
        is WeeklyReportEngine.Unlock.Next -> {
            Text(stringResource(
                R.string.your_level_is_re_assessed_regularly_the_next_assessment_need_a344c5),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            UnlockConditionRow(unlock.daysRemaining == 0, daysRemainingText(unlock.daysRemaining))
            UnlockConditionRow(unlock.secondsRemaining == 0.0,
                newTalkRemainingText(unlock.secondsRemaining))
        }
        WeeklyReportEngine.Unlock.Ready -> Text(
            stringResource(R.string.ready_assessing_your_level_now),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        null -> Unit
    }
}

/**
 * Shown UNDER an existing level: when the next re-assessment happens and
 * exactly how much more talk gets you there — the part the learner can go and
 * do right now.
 */
@Composable
private fun NextAssessmentStatus(unlock: WeeklyReportEngine.Unlock?, working: Boolean) {
    if (working) {
        Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            Text(stringResource(R.string.re_assessing_your_level_now),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }
    when (unlock) {
        is WeeklyReportEngine.Unlock.Next -> {
            Text(stringResource(R.string.next_assessment),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            val required = WeeklyReportEngine.RECURRING_MIN_SECONDS
            val done = (required - unlock.secondsRemaining).coerceIn(0.0, required)
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                LinearProgressIndicator(
                    progress = { (done / required).toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier.weight(1f))
                Text(stringResource(R.string.lld_lld_min_new_talk,
                    (done / 60).toInt(), (required / 60).toInt()),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            UnlockConditionRow(unlock.daysRemaining == 0, daysRemainingText(unlock.daysRemaining))
            if (unlock.secondsRemaining > 0) {
                Text(stringResource(
                    R.string.talk_lld_more_minutes_and_this_level_gets_re_read_from_every_b72704,
                    minutesUp(unlock.secondsRemaining)),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        WeeklyReportEngine.Unlock.Ready -> Text(
            stringResource(R.string.ready_re_assessing_your_level_now),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        // Can't happen once a level exists; nothing to show.
        else -> Unit
    }
}

@Composable
private fun UnlockBar(accumulated: Double, required: Double) {
    Row(verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        LinearProgressIndicator(
            progress = { (accumulated / required).toFloat().coerceIn(0f, 1f) },
            modifier = Modifier.weight(1f))
        Text(stringResource(R.string.lld_of_lld_min_of_talking,
            (accumulated / 60).toInt(), (required / 60).toInt()),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun UnlockConditionRow(met: Boolean, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(if (met) Icons.Filled.CheckCircle else Icons.Filled.Schedule,
            contentDescription = null,
            tint = if (met) Color(0xFF34C759) else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(18.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium,
            color = if (met) MaterialTheme.colorScheme.onSurfaceVariant
            else MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
private fun daysRemainingText(days: Int): String = when {
    days == 0 -> stringResource(R.string.a_week_since_the_last_assessment)
    days == 1 -> stringResource(R.string.one_more_day)
    else -> stringResource(R.string.lld_more_days, days)
}

@Composable
private fun newTalkRemainingText(secondsRemaining: Double): String =
    if (secondsRemaining <= 0.0) stringResource(R.string.enough_new_conversation)
    else stringResource(R.string.lld_more_min_of_new_talk, minutesUp(secondsRemaining))

/** Minutes, rounded UP and never zero — "0 more min" is not a condition. */
private fun minutesUp(seconds: Double): Int =
    kotlin.math.ceil(seconds / 60.0).toInt().coerceAtLeast(1)

/**
 * The lagging axes, each with its live number and the one place that axis is
 * actually worked on. Capped at three so it reads as focus, not a checklist;
 * two axes that want the same door keep their line and drop the duplicate
 * button rather than showing it twice.
 */
@Composable
private fun FocusTips(
    m: ProgressMetrics,
    next: CefrLevel,
    onSeeWords: () -> Unit,
    onReviewSlips: () -> Unit,
    onStartTalk: (() -> Unit)?,
) {
    val targetRank = CoreVocabulary.levelRank(next)
    fun lags(l: CefrLevel?) = l != null && CoreVocabulary.levelRank(l) < targetRank
    val tips = mutableListOf<Pair<String, ProgressAction?>>()
    if (lags(m.vocabLevel)) {
        tips += stringResource(R.string.use_more_level_words_in_your_talks, next.code.uppercase()) to
            ProgressAction(stringResource(R.string.see_words, next.code.uppercase()), onSeeWords)
    }
    if (lags(m.grammarLevel)) {
        val hint = m.grammarNextThreshold?.let { t ->
            m.grammarLevel?.let { ProgressBands.next(it) }?.let { up ->
                stringResource(R.string.get_under_1f_and_this_reads, t, up.code.uppercase())
            }
        }.orEmpty()
        tips += stringResource(R.string.you_re_at_1f_verified_slips_per_100_words,
            m.slipsPer100Words, hint) to
            ProgressAction(stringResource(R.string.review_your_slips), onReviewSlips)
    }
    if (lags(m.fluencyLevel)) {
        tips += stringResource(R.string.your_pace_is_lld_words_min_talk_more_often_and_a_little_long_608384,
            m.effectivePace) to
            onStartTalk?.let { ProgressAction(stringResource(R.string.start_a_talk), it) }
    }
    if (lags(m.expressionLevel)) {
        tips += stringResource(R.string.your_turns_average_lld_words_add_detail_how_things_felt_not_b4c918,
            m.wordsPerTurn) to
            onStartTalk?.let { ProgressAction(stringResource(R.string.start_a_talk), it) }
    }
    if (tips.isEmpty()) {
        tips += stringResource(R.string.every_measured_skill_already_reads_at_or_above_keep_talking_24170a,
            next.code.uppercase()) to null
    }
    val offered = mutableSetOf<String>()
    tips.take(3).forEach { (text, action) ->
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(text, style = MaterialTheme.typography.bodyMedium)
            if (action != null && offered.add(action.title)) ProgressActionLink(action)
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
 *
 * It is handed the band its OWN axis measured — vocabulary is graded from
 * the word list, the other three from their own deterministic proxies. A row
 * that ran every axis's 0-100 score through the grammar table said something
 * different about the same skill than the equalizer directly above it.
 */
@Composable
private fun SkillRow(title: String, band: String?, onOpen: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onOpen)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        // The band, not the 0-100 score: the number is calibrated to the
        // learner's own level setting, so beside a CEFR letter it reads as a
        // second, contradicting scale. The score lives on the skill's page.
        Text(band ?: "—",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(18.dp))
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

/** What a level can actually DO, in one line (iOS `canDo`). */
@Composable
private fun canDoAt(level: String): String = stringResource(
    when (level.uppercase()) {
        "A1" -> R.string.simple_words_and_phrases_about_immediate_familiar_things
        "A2" -> R.string.everyday_topics_in_simple_terms_routines_plans_basic_needs
        "B1" -> R.string.familiar_topics_fluently_enough_to_get_by_and_tell_a_simple_fa6cea
        "B2" -> R.string.clear_detailed_talk_on_many_topics_including_some_abstract_o_933630
        "C1" -> R.string.fluent_flexible_and_precise_even_on_complex_topics
        else -> R.string.effortless_and_nuanced_close_to_native
    })

/** The finished shelf's date: a day, abbreviated, in the learner's own
 *  language. A finished book is a record, so it says WHEN, not how long ago. */
internal fun shelfDate(at: Long): String =
    java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM)
        .format(java.util.Date(at))
