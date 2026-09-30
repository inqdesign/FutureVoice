package com.roro.futurevoice.ui

import com.roro.futurevoice.data.Recency
import com.roro.futurevoice.ui.brand.ContinuousShape
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
                .clip(ContinuousShape(999.dp))
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
                    testRows = { WeeklyTestRows(language, level) },
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


/** How many cards a daily deck deals. Mirrors iOS's per-day goal default. */
private const val DAILY_HAND = 10

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

/** The finished shelf's date: a day, abbreviated, in the learner's own
 *  language. A finished book is a record, so it says WHEN, not how long ago. */
internal fun shelfDate(at: Long): String =
    java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM)
        .format(java.util.Date(at))
