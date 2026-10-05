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
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Forum
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
 * Practice — the REVIEW home (`PracticeTab`'s spine). Everything here came out
 * of an activity; nothing is born on this screen. Hosted by the tab shell, so
 * no Scaffold of its own — the week's things (put off, the week, the tests)
 * are in the tab's HEADER (`ReviewHeaderActions`).
 *
 * The Studying page is BOOK-FIRST (iOS `790099d`, 2026-10-03): the four lists
 * on top as one row of tiles, then every unfinished book newest first, each
 * the shelves' own card with four chapter buttons under it. The old Today card
 * is gone — what a day asks for is the routine's.
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
    /** A shadow hand — dealt here, played by the root. */
    onShadowHand: (List<com.roro.futurevoice.data.ShadowPicks.Pick>) -> Unit = {},
    /** Everything shadowable, not today's hand. */
    onShadowAll: () -> Unit = {},
    onOpenWordsAll: () -> Unit = {},
    onOpenExpressionsAll: () -> Unit = {},
    /** The Sentences tile: the sentence-card LIST (iOS `SentencesView`). */
    onOpenSentencesAll: () -> Unit = onOpenDeck,
    onOpenDueReview: () -> Unit = {},
    /** One talk's sentence cards — a book's Grammar chapter (iOS
     *  `DrillView(source: .session)`). */
    onOpenSessionDeck: (String) -> Unit = { onOpenDeck() },
    nativeLanguage: String = "en",
    /** Which shelf the page opens on (iOS `PracticeTab(initialShelf:)`). */
    initialShelf: Shelf = Shelf.STUDYING,
) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var shelf by remember { mutableStateOf(initialShelf) }
    var scenarios by remember { mutableStateOf<List<Scenario>>(emptyList()) }
    val scope = rememberCoroutineScope()
    var talks by remember { mutableStateOf<List<Session>>(emptyList()) }
    /** Finished books. They keep their progress and can come back. */
    var archivedTalks by remember { mutableStateOf<List<Session>>(emptyList()) }
    var archivedScenarios by remember { mutableStateOf<List<Scenario>>(emptyList()) }
    /** The feed, the finished shelf, each talk's strip and the library counts —
     *  one curriculum pass, off the main thread. */
    var data by remember { mutableStateOf<ReviewShelfData?>(null) }
    var counterparts by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    /** A chapter's word/expression deck, over the tab (iOS's sheet). */
    var chapterDeck by remember { mutableStateOf<Pair<String, List<StudyDeckItem>>?>(null) }

    LaunchedEffect(language, revision) {
        // The shelves first: their pass writes each scene book's mastery
        // (`ScenarioMastery`), which the scenario cards below then read.
        data = withContext(Dispatchers.Default) {
            runCatching { loadReviewShelves(context, language, level) }.getOrNull()
        }
        val allScenarios = ScenarioStore.shared(context).load(language).filter { it.isMeeting != true }
        scenarios = allScenarios.filter { it.archivedAt == null }.sortedByDescending { it.createdAt }
        archivedScenarios = allScenarios.filter { it.archivedAt != null }
        val allTalks = SessionStore.shared(context).load(language).filter { it.summary != null }
            .sortedByDescending { it.startedAt }
        talks = allTalks.filter { it.archivedAt == null }
        archivedTalks = allTalks.filter { it.archivedAt != null }
        counterparts = runCatching {
            com.roro.futurevoice.data.CounterpartStore.shared(context).load().associate { it.id to it.name }
        }.getOrDefault(emptyMap())
    }
    val talkProgress = data?.talkProgress.orEmpty()

    fun study(chapter: BookPreview.Chapter, book: BookPreview) {
        val items = chapter.toStudy
        when (chapter.kind) {
            BookPreview.Kind.WORDS ->
                chapterDeck = context.getString(R.string.words) to items.map { StudyDeckItem.word(it.text) }
            BookPreview.Kind.EXPRESSIONS ->
                chapterDeck = context.getString(R.string.expressions) to items.map { StudyDeckItem.expression(it.text) }
            // The talk's own turn where there is one (its audio and attempts
            // are attached to it); a scene line becomes a synthetic turn under
            // the item's id, the way the scene page does it.
            BookPreview.Kind.SHADOW -> onShadowHand(items.map { item ->
                val turn = book.session?.turns?.firstOrNull { it.id == item.id }
                    ?: com.roro.futurevoice.talk.Turn(id = item.id, role = TurnRole.FLUENT_SELF,
                        transcript = item.text)
                com.roro.futurevoice.data.ShadowPicks.Pick(turn, item.note)
            })
            BookPreview.Kind.GRAMMAR -> book.session?.let { onOpenSessionDeck(it.id) }
        }
    }

    @Composable
    fun card(book: BookPreview, tall: Boolean, modifier: Modifier = Modifier) {
        book.session?.let {
            TalkCard(it, onOpenTalk, progress = if (tall) talkProgress[it.id] else null,
                tall = tall, modifier = modifier)
        }
        book.scenario?.let {
            ScenarioCard(it, onOpenScenarioBook, personaName = it.counterpartId?.let(counterparts::get),
                tall = tall, modifier = modifier)
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        ShelfChips(
            selected = shelf,
            counts = { s ->
                when (s) {
                    Shelf.STUDYING -> data?.feed?.size?.takeIf { it > 0 }
                    Shelf.TALK -> talks.size.takeIf { it > 0 }
                    Shelf.WATCH -> scenarios.size.takeIf { it > 0 }
                    Shelf.FINISHED -> data?.finished?.size?.takeIf { it > 0 }
                }
            },
            onSelect = { shelf = it },
        )

        when (shelf) {
            Shelf.STUDYING -> {
                val d = data
                LibraryTiles(
                    stats = d?.stats ?: LibraryStats(),
                    onWords = onOpenWordsAll,
                    onExpressions = onOpenExpressionsAll,
                    onSentences = onOpenSentencesAll,
                    onShadowing = onShadowAll,
                )
                d?.feed?.forEach { book ->
                    // The shelf's own card, with its chapter buttons under it
                    // on the same ground.
                    Column(Modifier.fillMaxWidth().clip(ContinuousShape(18.dp)).background(AppSurfacesCard())) {
                        card(book, tall = false)
                        BookChapterButtons(book) { chapter -> study(chapter, book) }
                    }
                }
                if (d != null && d.feed.isEmpty()) {
                    Text(stringResource(R.string.nothing_here_yet_have_a_talk_or_watch_a_scene),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            Shelf.TALK -> {
                // Two columns, as iOS's `LazyVGrid` — a full-width card per
                // talk made the shelf a list of banners.
                BookGrid(talks) { t, m ->
                    TalkCard(t, onOpenTalk, progress = talkProgress[t.id], modifier = m,
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
                BookGrid(scenarios) { sc, m ->
                    ScenarioCard(sc, onOpenScenarioBook, modifier = m,
                        personaName = sc.counterpartId?.let(counterparts::get),
                        onArchive = { id, on -> scope.launch {
                            ScenarioStore.shared(context).setArchived(id, on, language); StoreEvents.bump() } },
                        onDelete = { id -> scope.launch {
                            ScenarioStore.shared(context).delete(id, language); StoreEvents.bump() } })
                }
                ArchiveSection(archivedScenarios.isNotEmpty()) {
                    archivedScenarios.forEach {
                        ScenarioCard(it, onOpenScenarioBook,
                            personaName = it.counterpartId?.let(counterparts::get),
                            onArchive = { id, on -> scope.launch {
                                ScenarioStore.shared(context).setArchived(id, on, language); StoreEvents.bump() } },
                            onDelete = { id -> scope.launch {
                                ScenarioStore.shared(context).delete(id, language); StoreEvents.bump() } })
                    }
                }
            }
            // Books with every item mastered, as a shelf of their own (iOS
            // 2026-10-03 — it was a page behind a header seal). The same cards
            // as every shelf, most recently finished first.
            Shelf.FINISHED -> {
                val books = data?.finished.orEmpty()
                if (data != null && books.isEmpty()) {
                    Text(stringResource(R.string.master_every_word_and_line_in_a_book_from_a_talk_or_a_scene_ade546),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    BookGrid(books) { b, m -> card(b, tall = true, modifier = m) }
                }
            }
        }
    }

    chapterDeck?.let { (title, items) ->
        androidx.compose.ui.window.Dialog(
            onDismissRequest = { chapterDeck = null; StoreEvents.bump() },
            properties = androidx.compose.ui.window.DialogProperties(
                usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
        ) {
            StudyDeckHost(
                kind = items.firstOrNull()?.kind ?: StudyScheduleStore.Kind.WORD,
                language = language, nativeLanguage = nativeLanguage, level = level,
                hand = items, handTitle = title,
                onBack = { chapterDeck = null; StoreEvents.bump() },
            )
        }
    }
}

@Composable
private fun AppSurfacesCard() = com.roro.futurevoice.ui.brand.AppSurfaces.card

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
                     /** Mastered / total of the talk's book, once counted. */
                     progress: Pair<Int, Int>? = null,
                     modifier: Modifier = Modifier,
                     /** The tall shelf shape; off under the chapter buttons. */
                     tall: Boolean = true,
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
        // iOS `bubble.left.and.bubble.right.fill` — two bubbles, a conversation.
        icon = Icons.Filled.Forum,
        origin = when (t.origin?.name?.lowercase()) {
            "news" -> stringResource(R.string.news)
            "scenario" -> stringResource(R.string.scenarios)
            else -> stringResource(R.string.free_talk)
        },
        accent = if (t.origin?.name?.lowercase() == "news") Books.topics else Books.talks,
        // WHEN it was last worked, said as recency — it keeps advancing as
        // the book is studied, which a fixed date does not.
        detail = stringResource(R.string.studied, Recency.label(t.endedAt ?: t.startedAt)) +
            // Where the score would be, a practice call says what it was.
            (if (t.isPractice) " · " + stringResource(R.string.practice_call) else ""),
        // A practice (coach mode) call has no score to headline.
        score = t.summary?.scorecard?.overall?.takeIf { !t.isPractice },
        // The book's mastery strip, as iOS's TalkBookCard carries it.
        progress = progress?.takeIf { it.second > 0 }?.let { it.first / it.second.toFloat() },
        progressLabel = progress?.takeIf { it.second > 0 }
            ?.let { stringResource(R.string.lld_of_lld_mastered, it.first, it.second) },
        mastered = progress != null && progress.second > 0 && progress.first == progress.second,
        tall = tall,
        modifier = modifier
            .combinedClickable(onClick = { onOpen(t.id) }, onLongClick = { menu = true }),
    )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ScenarioCard(sc: Scenario, onOpen: (String) -> Unit,
                         onTalk: ((Scenario) -> Unit)? = null,
                         modifier: Modifier = Modifier,
                         /** The person this scene is with, if it is linked to one. */
                         personaName: String? = null,
                         tall: Boolean = true,
                         onArchive: ((String, Boolean) -> Unit)? = null,
                         onDelete: ((String) -> Unit)? = null) {
    var menu by remember { mutableStateOf(false) }
    val cur = sc.curriculum
    // All three chapters — words, expressions, shadow lines (`ScenarioMastery`).
    val total = cur?.totalCount ?: 0
    val done = cur?.masteredCount ?: 0
    // A scene with a person shows THAT person — their photo, else their
    // initials on the same disc (iOS `21dd1ac`).
    val photo = if (personaName != null) rememberPersonPhoto(sc.counterpartId) else null
    BookCard(
        title = sc.cardTitle,
        icon = Symbols.icon(sc.categoryIcon),
        photo = photo,
        initials = personaName?.takeIf { photo == null }?.let(::initials),
        tall = tall,
        // WHO the scene is with — a category names the shelf, not the scene.
        origin = sc.role?.takeIf { it.isNotBlank() } ?: sc.category,
        accent = Books.scenarios,
        detail = null,
        progressLabel = if (!tall) null
        else if (cur == null) stringResource(R.string.watch_the_scene_first)
        else if (total > 0 && done == total) stringResource(R.string.mastered_550ec5)
        else stringResource(R.string.lld_of_lld_mastered, done, total),
        mastered = scenarioFinished(sc),
        progress = if (total == 0 || !tall) null else done / total.toFloat(),
        modifier = modifier
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
