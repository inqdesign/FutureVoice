package com.roro.futurevoice.ui

import com.roro.futurevoice.data.Recency
import com.roro.futurevoice.ui.brand.ContinuousShape
import com.roro.futurevoice.data.StudyCollections
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.alpha
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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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

/** Everything the Review tab and All books read, one pass per language and
 *  store revision. */
private data class ReviewBooks(
    val data: ReviewShelfData? = null,
    val talks: List<Session> = emptyList(),
    /** Finished books. They keep their progress and can come back. */
    val archivedTalks: List<Session> = emptyList(),
    val scenarios: List<Scenario> = emptyList(),
    val archivedScenarios: List<Scenario> = emptyList(),
    /** Podcast episodes the learner copied into their books — the Listen
     *  shelf, kept off the Watch one. */
    val listenBooks: List<Scenario> = emptyList(),
    val archivedListenBooks: List<Scenario> = emptyList(),
    val counterparts: Map<String, String> = emptyMap(),
)

@Composable
private fun rememberReviewBooks(language: String, level: CefrLevel): ReviewBooks {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var books by remember { mutableStateOf(ReviewBooks()) }
    LaunchedEffect(language, revision) {
        // The shelves first: their pass writes each scene book's mastery
        // (`ScenarioMastery`), which the scenario cards then read.
        val data = withContext(Dispatchers.Default) {
            runCatching { loadReviewShelves(context, language, level) }.getOrNull()
        }
        val allScenarios = ScenarioStore.shared(context).load(language).filter { it.isMeeting != true }
        val allTalks = SessionStore.shared(context).load(language).filter { it.summary != null }
            .sortedByDescending { it.startedAt }
        books = ReviewBooks(
            data = data,
            talks = allTalks.filter { it.archivedAt == null },
            archivedTalks = allTalks.filter { it.archivedAt != null },
            scenarios = allScenarios.filter { it.archivedAt == null && !it.isPodcastBook }
                .sortedByDescending { it.createdAt },
            archivedScenarios = allScenarios.filter { it.archivedAt != null && !it.isPodcastBook },
            listenBooks = allScenarios.filter { it.archivedAt == null && it.isPodcastBook }
                .sortedByDescending { it.createdAt },
            archivedListenBooks = allScenarios.filter { it.archivedAt != null && it.isPodcastBook }
                .sortedByDescending { it.createdAt },
            counterparts = runCatching {
                com.roro.futurevoice.data.CounterpartStore.shared(context).load().associate { it.id to it.name }
            }.getOrDefault(emptyMap()),
        )
    }
    return books
}

/**
 * Practice — the REVIEW home (`PracticeTab`'s spine). Everything here came out
 * of an activity; nothing is born on this screen. Hosted by the tab shell, so
 * no Scaffold of its own — the week's things (put off, the week, the tests)
 * are in the tab's HEADER (`ReviewHeaderActions`).
 *
 * Today's review, one book at a time (iOS `b43651fa`, 2026-11-11, founder):
 * the four lists on top, then one big card per unfinished book, newest first,
 * swiped sideways. "N of M" at the section's right opens All books — the
 * shelves the chips used to carry.
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
    /** The shelves, as a pushed page (iOS `showingAllBooks`). */
    onOpenAllBooks: () -> Unit = {},
    /** A scenario card's long-press "Talk now" (iOS `scenarioCard` context
     *  menu) — a metered launch, so the host runs it through the gate. */
    onTalkScenario: ((Scenario) -> Unit)? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val books = rememberReviewBooks(language, level)
    val d = books.data
    val feed = d?.feed.orEmpty()
    /** A chapter's word/expression deck, over the tab (iOS's sheet). */
    var chapterDeck by remember { mutableStateOf<Pair<String, List<StudyDeckItem>>?>(null) }

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

    // The card runs down to the tab bar instead of leaving the page's foot
    // empty: the page's height, less what sits above the card.
    val density = androidx.compose.ui.platform.LocalDensity.current
    var viewport by remember { mutableStateOf(0) }
    var aboveCard by remember { mutableStateOf(0) }
    val bottomRoom = IosTabBarClearance + androidx.compose.foundation.layout.WindowInsets.navigationBars
        .asPaddingValues().calculateBottomPadding()
    val cardHeight = if (viewport > 0 && aboveCard > 0) with(density) {
        maxOf(TodayBookCardMinHeight, (viewport - aboveCard).toDp() - 8.dp - 14.dp - bottomRoom)
    } else TodayBookCardMinHeight
    val pager = androidx.compose.foundation.pager.rememberPagerState { feed.size }

    Column(
        Modifier.fillMaxSize()
            .onSizeChanged { viewport = it.height }
            .verticalScroll(rememberScrollState())
            .padding(top = 8.dp),
    ) {
        Column(
            Modifier.onSizeChanged { aboveCard = it.height },
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            val st = d?.stats ?: LibraryStats()
            // Dimmed only while there is nothing anywhere (iOS cd867a2b).
            val bare = d != null && feed.isEmpty() &&
                st.words + st.expressions + st.sentences + st.shadow == 0
            Box(Modifier.padding(horizontal = 20.dp).padding(bottom = 6.dp).alpha(if (bare) 0.45f else 1f)) {
                LibraryTiles(
                    stats = st,
                    onWords = onOpenWordsAll,
                    onExpressions = onOpenExpressionsAll,
                    onSentences = onOpenSentencesAll,
                    onShadowing = onShadowAll,
                )
            }
            // The section's right side opens everything there is to review:
            // the shelves, by the chips this tab used to carry.
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.today_s_review), style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                val allBooks = stringResource(R.string.all_books)
                Row(
                    Modifier.clip(ContinuousShape(8.dp)).clickable(onClick = onOpenAllBooks)
                        .semantics { contentDescription = allBooks }
                        .padding(horizontal = 4.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text(if (feed.isEmpty()) allBooks
                        else stringResource(R.string.lld_of_lld, pager.currentPage + 1, feed.size),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                }
            }
        }
        Spacer(Modifier.height(14.dp))
        // No weekly test banner here (iOS 4f706d92, 2026-10-19): the test
        // lives inside the week's report.
        if (d != null && feed.isEmpty()) {
            Box(Modifier.padding(horizontal = 20.dp)) {
                FirstBookPlaceholder {
                    DeepLinkInbox.requestFreeTalk(com.roro.futurevoice.talk.TalkEntry.PRACTICE_EMPTY)
                }
            }
        } else if (feed.isNotEmpty()) {
            // One book fills the page; the next one's edge shows at the right,
            // so the row reads as something to swipe.
            androidx.compose.foundation.pager.HorizontalPager(
                state = pager,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = 20.dp, end = if (feed.size > 1) 38.dp else 20.dp),
                pageSpacing = 10.dp,
                verticalAlignment = Alignment.Top,
                key = { feed[it].id },
            ) { i ->
                TodayCard(feed[i], books, cardHeight,
                    onOpenTalk = onOpenTalk, onOpenScenarioBook = onOpenScenarioBook,
                    onTalkScenario = onTalkScenario,
                    onStudy = { chapter -> study(chapter, feed[i]) },
                    onArchiveTalk = { id -> scope.launch {
                        SessionStore.shared(context).setArchived(id, true, language); StoreEvents.bump() } },
                    onDeleteTalk = { id -> scope.launch {
                        SessionStore.shared(context).delete(id, language); StoreEvents.bump() } },
                    onArchiveScenario = { id -> scope.launch {
                        ScenarioStore.shared(context).setArchived(id, true, language); StoreEvents.bump() } },
                    onDeleteScenario = { id -> scope.launch {
                        ScenarioStore.shared(context).delete(id, language); StoreEvents.bump() } })
            }
        }
        // Room to scroll the card's foot up past the floating bar.
        Spacer(Modifier.height(bottomRoom))
    }

    chapterDeck?.let { (title, items) ->
        androidx.compose.ui.window.Dialog(
            onDismissRequest = { chapterDeck = null; StoreEvents.bump() },
            properties = androidx.compose.ui.window.DialogProperties(
                usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
        ) {
            DialogSystemBarsLikeActivity()
            StudyDeckHost(
                kind = items.firstOrNull()?.kind ?: StudyScheduleStore.Kind.WORD,
                language = language, nativeLanguage = nativeLanguage, level = level,
                hand = items, handTitle = title,
                onBack = { chapterDeck = null; StoreEvents.bump() },
            )
        }
    }
}

/** One book of today's review: the big card, its tap, and the same
 *  archive / delete menu the shelves' cards carry (iOS `todayCard`). */
@Composable
private fun TodayCard(
    book: BookPreview,
    books: ReviewBooks,
    minHeight: androidx.compose.ui.unit.Dp,
    onOpenTalk: (String) -> Unit,
    onOpenScenarioBook: (String) -> Unit,
    onTalkScenario: ((Scenario) -> Unit)?,
    onStudy: (BookPreview.Chapter) -> Unit,
    onArchiveTalk: (String) -> Unit,
    onDeleteTalk: (String) -> Unit,
    onArchiveScenario: (String) -> Unit,
    onDeleteScenario: (String) -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    val t = book.session
    val sc = book.scenario
    Box {
        if (t != null) {
            val last = listOfNotNull(books.data?.talkLastStudied?.get(t.id), t.endedAt, t.startedAt).max()
            TodayBookCard(
                book = book,
                title = t.displayTitle ?: stringResource(R.string.conversation),
                meta = "${talkOrigin(t)} · ${Recency.label(last)}",
                note = t.summary?.let { s ->
                    s.scorecard?.topLine?.trim().orEmpty().ifEmpty { s.overallNote.trim() }
                }?.takeIf { it.isNotEmpty() },
                icon = Icons.Filled.Forum,
                score = t.summary?.scorecard?.overall?.takeIf { !t.isPractice },
                height = minHeight,
                onOpen = { onOpenTalk(t.id) },
                onLongPress = { menu = true },
                onStudy = onStudy,
            )
            BookMenu(menu, { menu = false }, listOf(
                Triple(stringResource(R.string.archive), Icons.Filled.Inventory2, { onArchiveTalk(t.id) }),
                Triple(stringResource(R.string.delete), Icons.Filled.Delete, { onDeleteTalk(t.id) }),
            ))
        } else if (sc != null) {
            val personaName = sc.counterpartId?.let(books.counterparts::get)
            val photo = if (personaName != null) rememberPersonPhoto(sc.counterpartId) else null
            val role = sc.role.trim().takeIf { it.isNotEmpty() }
            TodayBookCard(
                book = book,
                title = sc.cardTitle,
                meta = listOfNotNull(scenarioOrigin(sc), personaName ?: role).joinToString(" · "),
                note = (if (sc.cardTitle != sc.environment) sc.environment else sc.brief?.summary)
                    ?.trim()?.takeIf { it.isNotEmpty() },
                icon = when {
                    sc.isPodcastBook -> categoryIcon(sc.category)
                    sc.isTopic == true -> Icons.Filled.Newspaper
                    else -> Symbols.icon(sc.categoryIcon)
                },
                photo = photo,
                initials = personaName?.takeIf { photo == null }?.let(::initials),
                height = minHeight,
                onOpen = { onOpenScenarioBook(sc.id) },
                onLongPress = { menu = true },
                onStudy = onStudy,
            )
            BookMenu(menu, { menu = false }, listOfNotNull(
                onTalkScenario?.let { Triple(stringResource(R.string.talk_now), Icons.Filled.Mic, { it(sc) }) },
                Triple(stringResource(R.string.archive), Icons.Filled.Inventory2, { onArchiveScenario(sc.id) }),
                Triple(stringResource(R.string.delete), Icons.Filled.Delete, { onDeleteScenario(sc.id) }),
            ))
        }
    }
}

/**
 * Every book by shelf — Studying · Talk · Watch · Listen · Finished, each with
 * its archive (iOS `allBooksPage`). The Review tab's chips until 2026-11-11;
 * now one page behind today's review's "N of M".
 */
@Composable
fun AllBooksScreen(
    language: String,
    level: CefrLevel,
    onOpenScenarioBook: (String) -> Unit,
    onOpenTalk: (String) -> Unit,
    onBack: () -> Unit,
    initialShelf: Shelf = Shelf.STUDYING,
    onTalkScenario: ((Scenario) -> Unit)? = null,
) {
    NavPageBackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val books = rememberReviewBooks(language, level)
    val data = books.data
    val talkProgress = data?.talkProgress.orEmpty()
    val talks = books.talks
    val scenarios = books.scenarios
    val listenBooks = books.listenBooks
    val counterparts = books.counterparts

    @Composable
    fun card(book: BookPreview, modifier: Modifier = Modifier) {
        book.session?.let { TalkCard(it, onOpenTalk, progress = talkProgress[it.id], modifier = modifier) }
        book.scenario?.let {
            ScenarioCard(it, onOpenScenarioBook, onTalk = onTalkScenario,
                personaName = it.counterpartId?.let(counterparts::get), modifier = modifier)
        }
    }

    fun count(s: Shelf): Int? = when (s) {
        Shelf.STUDYING -> data?.feed?.size?.takeIf { it > 0 }
        Shelf.TALK -> talks.size.takeIf { it > 0 }
        Shelf.WATCH -> scenarios.size.takeIf { it > 0 }
        Shelf.LISTEN -> listenBooks.size.takeIf { it > 0 }
        Shelf.FINISHED -> data?.finished?.size?.takeIf { it > 0 }
    }

    @OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
    androidx.compose.material3.Scaffold(
        topBar = {
            androidx.compose.material3.CenterAlignedTopAppBar(
                colors = com.roro.futurevoice.ui.brand.AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.all_books), style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    androidx.compose.material3.IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        },
        containerColor = com.roro.futurevoice.ui.brand.AppSurfaces.ground,
    ) { padding ->
      Box(Modifier.padding(top = padding.calculateTopPadding()).fillMaxSize()) {
        // The shelves are PAGES (iOS: a paging ScrollView under the chip bar):
        // swipe sideways between them, or tap a chip.
        val pager = androidx.compose.foundation.pager.rememberPagerState(
            initialPage = initialShelf.ordinal) { Shelf.entries.size }
        ChipPager(
            state = pager,
            chip = { i, selected, onClick ->
                val s = Shelf.entries[i]
                // Neutral for every shelf (iOS `912d6f4`): the page keeps colour
                // for its progress bars alone.
                com.roro.futurevoice.ui.brand.IosChip(
                    label = stringResource(s.labelRes),
                    count = count(s),
                    selected = selected,
                    onClick = onClick)
            },
        ) { page ->
            when (Shelf.entries[page]) {
                // Every unfinished book, newest first — today's review as a shelf.
                Shelf.STUDYING -> {
                    val feed = data?.feed.orEmpty()
                    if (data != null && feed.isEmpty()) {
                        Text(stringResource(R.string.finish_a_talk_and_it_lands_here_as_a_book_replay_it_pick_up_f70da1),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } else {
                        BookGrid(feed) { b, m -> card(b, m) }
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
                    ArchiveSection(books.archivedTalks.isNotEmpty()) {
                        books.archivedTalks.forEach {
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
                        ScenarioCard(sc, onOpenScenarioBook, onTalk = onTalkScenario, modifier = m,
                            personaName = sc.counterpartId?.let(counterparts::get),
                            onArchive = { id, on -> scope.launch {
                                ScenarioStore.shared(context).setArchived(id, on, language); StoreEvents.bump() } },
                            onDelete = { id -> scope.launch {
                                ScenarioStore.shared(context).delete(id, language); StoreEvents.bump() } })
                    }
                    ArchiveSection(books.archivedScenarios.isNotEmpty()) {
                        books.archivedScenarios.forEach {
                            ScenarioCard(it, onOpenScenarioBook, onTalk = onTalkScenario,
                                personaName = it.counterpartId?.let(counterparts::get),
                                onArchive = { id, on -> scope.launch {
                                    ScenarioStore.shared(context).setArchived(id, on, language); StoreEvents.bump() } },
                                onDelete = { id -> scope.launch {
                                    ScenarioStore.shared(context).delete(id, language); StoreEvents.bump() } })
                        }
                    }
                }
                Shelf.LISTEN -> {
                    if (listenBooks.isEmpty() && books.archivedListenBooks.isEmpty()) {
                        Text(stringResource(R.string.podcast_listen_shelf_empty),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    BookGrid(listenBooks) { sc, m ->
                        ScenarioCard(sc, onOpenScenarioBook, modifier = m,
                            onArchive = { id, on -> scope.launch {
                                ScenarioStore.shared(context).setArchived(id, on, language); StoreEvents.bump() } },
                            onDelete = { id -> scope.launch {
                                ScenarioStore.shared(context).delete(id, language); StoreEvents.bump() } })
                    }
                    ArchiveSection(books.archivedListenBooks.isNotEmpty()) {
                        books.archivedListenBooks.forEach {
                            ScenarioCard(it, onOpenScenarioBook,
                                onArchive = { id, on -> scope.launch {
                                    ScenarioStore.shared(context).setArchived(id, on, language); StoreEvents.bump() } },
                                onDelete = { id -> scope.launch {
                                    ScenarioStore.shared(context).delete(id, language); StoreEvents.bump() } })
                        }
                    }
                }
                // Books with every item mastered, as a shelf of their own (iOS
                // 2026-10-03). The same cards as every shelf, most recently
                // finished first.
                Shelf.FINISHED -> {
                    val finished = data?.finished.orEmpty()
                    if (data != null && finished.isEmpty()) {
                        Text(stringResource(R.string.master_every_word_and_line_in_a_book_from_a_talk_or_a_scene_ade546),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } else {
                        BookGrid(finished) { b, m -> card(b, m) }
                    }
                }
            }
        }
      }
    }
}

/** A talk's source line — "Free talk", "News · Tutor", "Practice call"
 *  (iOS `OriginTag(session:)`). */
@Composable
private fun talkOrigin(t: Session): String {
    val source = when (t.origin?.name?.lowercase()) {
        "news" -> stringResource(R.string.news)
        "scenario" -> stringResource(R.string.scenarios)
        else -> stringResource(R.string.free_talk)
    }
    // A coach-mode call says so in place of "Free talk" (after "News" /
    // "Scenario"). A practice call (`Session.coached` — tutor mode, or
    // coach mode before 2026-10-14) carries no score, so it is named
    // that (iOS `OriginTag`). A tutor call scored on its final check
    // (`Turn.tutorRole`) says "Tutor"; one that never reached the
    // check is a practice call.
    val coached = t.turns.any { it.coachLine != null }
    val tutored = t.turns.any { it.tutorRole != null }
    if (!t.isPractice && !coached && !tutored) return source
    val coach = stringResource(when {
        t.isPractice -> R.string.practice_call
        tutored -> R.string.tutor
        else -> R.string.coach_mode
    })
    return when (t.origin?.name?.lowercase()) {
        "news", "scenario" -> "$source · $coach"
        else -> coach
    }
}

/** A scene book's source: the podcast episode it was copied from, News, or
 *  Scenario (iOS `OriginTag(scenario:)`). */
@Composable
private fun scenarioOrigin(sc: Scenario): String =
    sc.podcast?.let { "${stringResource(R.string.nawana_podcast)} · EP ${it.number}" }
        ?: stringResource(if (sc.isTopic == true) R.string.news else R.string.scenario)

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
    com.roro.futurevoice.ui.brand.IosDropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        items.forEachIndexed { i, (label, icon, action) ->
            val destructive = destructiveLast && i == items.lastIndex
            com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
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
        origin = talkOrigin(t),
        accent = if (t.origin?.name?.lowercase() == "news") Books.topics else Books.talks,
        // WHEN it was last worked, said as recency — it keeps advancing as
        // the book is studied, which a fixed date does not. It rides after
        // the source on one line ("Free talk · 11 hours ago"); the old
        // "Studied …" wording went (iOS 2026-10-16).
        detail = Recency.label(t.endedAt ?: t.startedAt),
        // A practice call has no score to headline.
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
        icon = if (sc.isPodcastBook) categoryIcon(sc.category) else Symbols.icon(sc.categoryIcon),
        photo = photo,
        initials = personaName?.takeIf { photo == null }?.let(::initials),
        tall = tall,
        // The source, then WHO the scene is with, on one line — "Scenario ·
        // Sarah" (iOS `OriginTag(scenario:).with(partnerLabel)`, 2026-10-16).
        // A Listen book is the podcast episode it was copied from.
        origin = scenarioOrigin(sc),
        accent = if (sc.isPodcastBook) Books.podcasts else Books.scenarios,
        detail = personaName ?: sc.role.trim().takeIf { it.isNotEmpty() },
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

/**
 * Where the first book will sit (iOS `firstBookPlaceholder`, cd867a2b): the
 * card's own shape, dashed, with its four chapters dimmed so the learner sees
 * what a talk turns into before having one.
 */
@Composable
private fun FirstBookPlaceholder(onStartTalk: () -> Unit) {
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    // iOS `separator` / `quaternarySystemFill`.
    val separator = if (dark) Color(0xFF545458).copy(alpha = 0.6f) else Color(0xFF3C3C43).copy(alpha = 0.29f)
    val fill = if (dark) Color(0xFF767680).copy(alpha = 0.18f) else Color(0xFF747480).copy(alpha = 0.08f)
    Column(
        Modifier.fillMaxWidth()
            .drawBehind {
                val w = 1.5.dp.toPx()
                drawRoundRect(separator,
                    topLeft = androidx.compose.ui.geometry.Offset(w / 2, w / 2),
                    size = androidx.compose.ui.geometry.Size(size.width - w, size.height - w),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(18.dp.toPx() - w / 2),
                    style = androidx.compose.ui.graphics.drawscope.Stroke(w,
                        pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(
                            floatArrayOf(6.dp.toPx(), 5.dp.toPx()))))
            }
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(stringResource(R.string.your_first_book_goes_here),
                style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.every_talk_becomes_a_book_of_its_own),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Row(Modifier.fillMaxWidth().alpha(0.6f).clearAndSetSemantics {},
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(StudyIcon.words to R.string.words, StudyIcon.expressions to R.string.expressions,
                StudyIcon.shadowing to R.string.shadowing, StudyIcon.grammar to R.string.grammar,
            ).forEach { (icon, title) ->
                Column(
                    Modifier.weight(1f).clip(ContinuousShape(12.dp)).background(fill)
                        .padding(horizontal = 6.dp, vertical = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(icon, contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(24.dp))
                    Text(stringResource(title), maxLines = 1,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Button(onClick = onStartTalk, modifier = Modifier.fillMaxWidth()) {
            Icon(androidx.compose.material.icons.Icons.Filled.Mic, contentDescription = null,
                modifier = Modifier.size(18.dp))
            androidx.compose.foundation.layout.Spacer(Modifier.size(8.dp))
            Text(stringResource(R.string.start_a_talk))
        }
    }
}
