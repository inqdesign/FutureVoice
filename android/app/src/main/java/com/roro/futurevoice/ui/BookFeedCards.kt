package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.MarkChatRead
import androidx.compose.material.icons.filled.PlayCircleOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.ExpressionCatalog
import com.roro.futurevoice.data.ScenarioMastery
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.ShadowAttemptStore
import com.roro.futurevoice.data.TalkCurriculum
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.ScenarioCurriculum
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.Books
import com.roro.futurevoice.ui.brand.ContinuousShape

// The Review tab's Studying page, book-first (iOS `BookFeedCards.swift`,
// 2026-10-03, user decision).
//
// Every word, expression, correction and shadow line on Review came out of a
// talk or a scene — it is a chapter of some book. Studying them as four
// free-floating piles threw away the one thing no word-list app has (this is
// the line YOU stumbled on, in THAT call), so the page is books: newest first,
// each the shelves' own card with one button per chapter under it. The order
// never moves by itself: a sort by "most due" reshuffled the page every time a
// card was cleared.

/**
 * The four kinds of study material, one icon each — the SAME glyph on the
 * library tiles, a book card's chapter buttons and a book page's tabs, and the
 * same ORDER everywhere: words, expressions, grammar, shadowing (iOS
 * `StudyIcon`, `912d6f4`).
 */
object StudyIcon {
    val words: ImageVector get() = Icons.AutoMirrored.Filled.MenuBook
    val expressions: ImageVector get() = Icons.Filled.FormatQuote
    val grammar: ImageVector get() = Icons.Filled.MarkChatRead
    val shadowing: ImageVector get() = Icons.Filled.GraphicEq
}

/** One book as the Studying page shows it — a talk or a scene, flattened. */
data class BookPreview(
    val id: String,
    val session: Session?,
    val scenario: Scenario?,
    /** When it was MADE — the page's one order. */
    val created: Long,
    val tint: Color,
    /** Empty while a talk's chapters could not be derived. */
    val chapters: List<Chapter>,
) {
    enum class Kind(val titleRes: Int) {
        WORDS(R.string.words), EXPRESSIONS(R.string.expressions),
        GRAMMAR(R.string.grammar), SHADOW(R.string.shadowing);

        val icon: ImageVector get() = when (this) {
            WORDS -> StudyIcon.words
            EXPRESSIONS -> StudyIcon.expressions
            GRAMMAR -> StudyIcon.grammar
            SHADOW -> StudyIcon.shadowing
        }
    }

    data class Chapter(val kind: Kind, val items: List<ScenarioCurriculum.Item>) {
        val mastered: Int get() = items.count { it.masteredAt != null }
        val progress: Float get() = if (items.isEmpty()) 0f else mastered / items.size.toFloat()
        /** What the chapter still teaches; a finished chapter studies all of it. */
        val toStudy: List<ScenarioCurriculum.Item>
            get() = items.filter { it.masteredAt == null }.ifEmpty { items }
    }
}

/** How much of each list has been STUDIED (iOS `LibraryStats`): words known or
 *  said in the graded list, expressions known or said, sentence cards reviewed
 *  at least once, lines shadowed at least once (not takes). No bars — only words have a whole. */
data class LibraryStats(val words: Int = 0, val expressions: Int = 0,
                        val sentences: Int = 0, val shadow: Int = 0)

/** Everything the Studying and Finished pages read, built off the main thread
 *  in one pass (a curriculum build per talk). */
data class ReviewShelfData(
    val feed: List<BookPreview> = emptyList(),
    val finished: List<BookPreview> = emptyList(),
    /** Each talk book's mastered / total — the shelf cards' strip. */
    val talkProgress: Map<String, Pair<Int, Int>> = emptyMap(),
    /** Each talk book's last mastery event — today's card says when it was
     *  last worked (iOS `talkSnapshots[id]?.lastStudiedAt`). */
    val talkLastStudied: Map<String, Long> = emptyMap(),
    val stats: LibraryStats = LibraryStats(),
)

/** A scene book is finished when ALL its chapters are — words, expressions
 *  and the Shadow chapter's lines (iOS `refreshScenarioMastery`, ported as
 *  [com.roro.futurevoice.data.ScenarioMastery]). */
internal fun scenarioFinished(sc: Scenario): Boolean = sc.curriculum?.isMastered == true

suspend fun loadReviewShelves(context: Context, language: String, level: CefrLevel): ReviewShelfData {
    val vocab = VocabStore.shared(context)
    val attempts = ShadowAttemptStore.shared(context).load(language)
    val cards = DrillStore.shared(context).load(language)
    val allTalks = SessionStore.shared(context).load(language).filter { it.summary != null }
    val talksForMastery = SessionStore.shared(context).load(language)
    // Mastery is written onto the scene book before the shelves read it —
    // a take or a talk since the last look may have finished a chapter.
    val allScenarios = ScenarioStore.shared(context).load(language).filter { it.isMeeting != true }
        .map { sc -> ScenarioMastery.refresh(context, sc, language, talksForMastery, attempts) }

    val snapshots = allTalks.associate { s ->
        s.id to runCatching { TalkCurriculum.build(s, level, language, vocab, attempts, cards) }.getOrNull()
    }
    fun talkBook(s: Session): BookPreview {
        val snap = snapshots[s.id]
        val chapters = snap?.let {
            listOf(
                BookPreview.Chapter(BookPreview.Kind.WORDS, it.words),
                BookPreview.Chapter(BookPreview.Kind.EXPRESSIONS, it.expressions),
                BookPreview.Chapter(BookPreview.Kind.GRAMMAR, it.corrections),
                BookPreview.Chapter(BookPreview.Kind.SHADOW, it.shadowLines),
            )
        }.orEmpty()
        return BookPreview(s.id, s, null, s.startedAt,
            if (s.origin?.name?.lowercase() == "news") Books.topics else Books.talks, chapters)
    }
    fun sceneBook(sc: Scenario): BookPreview {
        val chapters = sc.curriculum?.let {
            listOf(
                BookPreview.Chapter(BookPreview.Kind.WORDS, it.words),
                BookPreview.Chapter(BookPreview.Kind.EXPRESSIONS, it.expressions),
                // A scene has no grammar: the button stays in its place, dimmed.
                BookPreview.Chapter(BookPreview.Kind.GRAMMAR, emptyList()),
                BookPreview.Chapter(BookPreview.Kind.SHADOW, it.shadowLines),
            )
        }.orEmpty()
        return BookPreview(sc.id, null, sc, sc.createdAt,
            if (sc.isPodcastBook) Books.podcasts else Books.scenarios, chapters)
    }

    // Every unfinished, unarchived book, newest first by when it was MADE —
    // the order never shifts as items are mastered.
    val feed = (allTalks.filter { it.archivedAt == null && snapshots[it.id]?.isMastered != true }.map(::talkBook) +
        allScenarios.filter { it.archivedAt == null && !scenarioFinished(it) }.map(::sceneBook))
        .sortedByDescending { it.created }

    // Books with every item mastered, archived or not, most recently finished first.
    val finished = (allTalks.filter { snapshots[it.id]?.isMastered == true }.map { s ->
        talkBook(s) to (snapshots[s.id]?.lastStudiedAt ?: s.endedAt ?: s.startedAt)
    } + allScenarios.filter(::scenarioFinished).map { sc ->
        val c = sc.curriculum!!
        sceneBook(sc) to (c.allItems.mapNotNull { it.masteredAt }.maxOrNull() ?: sc.createdAt)
    }).sortedByDescending { it.second }.map { it.first }

    val core = CoreVocabulary
    val stats = LibraryStats(
        words = vocab.recordedWords(language).count { core.level(it, language) != null },
        expressions = ExpressionCatalog.all(context, language).count { it.known },
        sentences = cards.count { it.timesSeen > 0 },
        shadow = attempts.map { it.turnId }.toSet().size,
    )
    return ReviewShelfData(
        feed = feed,
        finished = finished,
        talkProgress = snapshots.mapNotNull { (id, snap) -> snap?.let { id to (it.masteredCount to it.totalCount) } }.toMap(),
        talkLastStudied = snapshots.mapNotNull { (id, snap) -> snap?.lastStudiedAt?.let { id to it } }.toMap(),
        stats = stats,
    )
}

/**
 * Under every book's card on the Studying page (the shelves' own card, not
 * redrawn): one button per chapter in a row — words, expressions, grammar,
 * shadowing — each an icon over its progress bar. A tap opens that chapter's
 * own deck, so studying a book is one tap from the shelf (iOS
 * `BookChapterButtons`). All four, always, in the same order — a chapter this
 * book has nothing in stays in its place, dimmed.
 */
@Composable
fun BookChapterButtons(book: BookPreview, onStudy: (BookPreview.Chapter) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, bottom = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        book.chapters.forEach { chapter ->
            val empty = chapter.items.isEmpty()
            val done = !empty && chapter.mastered == chapter.items.size
            val label = stringResource(chapter.kind.titleRes)
            Column(
                Modifier.weight(1f)
                    .alpha(if (empty) 0.4f else 1f)
                    .clip(ContinuousShape(12.dp))
                    .background(com.roro.futurevoice.ui.brand.iosFill())
                    .clickable(enabled = !empty) { onStudy(chapter) }
                    .semantics { contentDescription = "$label ${chapter.mastered}/${chapter.items.size}" }
                    .padding(horizontal = 10.dp, vertical = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // Neutral glyph; colour lives on the bar alone (iOS `912d6f4`).
                Icon(chapter.kind.icon, contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(22.dp))
                LinearProgressIndicator(
                    progress = { chapter.progress },
                    color = if (done) Books.mastery else book.tint,
                    trackColor = MaterialTheme.colorScheme.surfaceVariant,
                    strokeCap = StrokeCap.Round,
                    gapSize = 0.dp,
                    drawStopIndicator = {},
                    modifier = Modifier.fillMaxWidth().height(4.dp),
                )
            }
        }
    }
}

/**
 * The four lists FIRST, each saying how much of it is checked off (iOS
 * `libraryList`): icon, how much was studied, the list's name. No bars — only
 * words have a fixed whole.
 */
@Composable
fun LibraryTiles(
    stats: LibraryStats,
    onWords: () -> Unit,
    onExpressions: () -> Unit,
    onSentences: () -> Unit,
    onShadowing: () -> Unit,
) {
    val locale = java.util.Locale.forLanguageTag(
        com.roro.futurevoice.core.UILanguage.current(androidx.compose.ui.platform.LocalContext.current) ?: "en")
    // Grouped in the APP language — the phone's region printed "8.424" on a
    // Korean screen.
    fun n(v: Int) = java.text.NumberFormat.getIntegerInstance(locale).format(v)
    Row(
        Modifier.fillMaxWidth()
            .background(AppSurfaces.card, ContinuousShape(16.dp))
            .padding(vertical = 12.dp, horizontal = 6.dp),
    ) {
        LibraryTile(StudyIcon.words, n(stats.words), stringResource(R.string.words), onWords, Modifier.weight(1f))
        LibraryTile(StudyIcon.expressions, n(stats.expressions), stringResource(R.string.expressions),
            onExpressions, Modifier.weight(1f))
        LibraryTile(StudyIcon.grammar, n(stats.sentences), stringResource(R.string.sentences),
            onSentences, Modifier.weight(1f))
        LibraryTile(StudyIcon.shadowing, n(stats.shadow), stringResource(R.string.shadowing),
            onShadowing, Modifier.weight(1f))
    }
}

@Composable
private fun LibraryTile(icon: ImageVector, value: String, title: String, onClick: () -> Unit,
                        modifier: Modifier) {
    Column(
        modifier.clip(ContinuousShape(10.dp)).clickable(onClick = onClick).padding(horizontal = 4.dp, vertical = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.size(22.dp))
        Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
            maxLines = 1)
        Text(title, style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1,
            overflow = TextOverflow.Ellipsis)
    }
}

/** A book's whole: every item in its chapters, and how many are mastered. */
val BookPreview.total: Int get() = chapters.sumOf { it.items.size }
val BookPreview.masteredCount: Int get() = chapters.sumOf { it.mastered }

/** The card's floor on a small phone, where the page then scrolls (iOS
 *  `TodayBookCard.minHeight`). */
val TodayBookCardMinHeight = 280.dp

/**
 * Today's review, one book at a time (iOS `TodayBookCard`, 2026-11-11,
 * founder: "one card, and they finish them one by one; swipe sideways for the
 * next book; a bigger card with the key things from the talk's summary; a tap
 * opens the book"). The top is the book — where it came from, its title, the
 * summary's one line, and what it still teaches per chapter — and opens its
 * page. Under it: how much is left, and the four chapter buttons.
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun TodayBookCard(
    book: BookPreview,
    title: String,
    /** The source and the card's one fact: "Free talk · 2 hours ago". */
    meta: String,
    /** The summary's one line: how the talk went, or what the situation is. */
    note: String?,
    icon: ImageVector?,
    photo: androidx.compose.ui.graphics.ImageBitmap? = null,
    initials: String? = null,
    score: Int? = null,
    /** The room the page has left above the tab bar. The card is EXACTLY
     *  this tall, so its chapter buttons never slide under the tab bar; what
     *  the book still teaches gives way instead (2026-11-13, founder). */
    height: androidx.compose.ui.unit.Dp = TodayBookCardMinHeight,
    onOpen: () -> Unit,
    onLongPress: () -> Unit,
    onStudy: (BookPreview.Chapter) -> Unit,
    modifier: Modifier = Modifier,
) {
    val left = book.total - book.masteredCount
    Column(
        modifier.fillMaxWidth()
            .height(height)
            .clip(ContinuousShape(24.dp))
            .background(AppSurfaces.card)
            .combinedClickable(onClick = onOpen, onLongClick = onLongPress),
    ) {
        // The fullest version that fits the room: every row at full length,
        // then one line a row, then no rows (iOS `ViewThatFits`).
        Box(Modifier.fillMaxWidth().weight(1f).clipToBounds().padding(18.dp)) {
            FirstThatFits(
                { TodayTop(book, title, meta, note, icon, photo, initials, score, rowLines = null, noteLines = 3) },
                { TodayTop(book, title, meta, note, icon, photo, initials, score, rowLines = 1, noteLines = 3) },
                { TodayTop(book, title, meta, note, icon, photo, initials, score, rowLines = 1, noteLines = 2) },
                { TodayTop(book, title, meta, note, icon, photo, initials, score, rowLines = 0, noteLines = 2) },
            )
        }
        when {
            // A talk whose chapters could not be derived yet.
            book.chapters.isEmpty() -> androidx.compose.foundation.layout.Box(
                Modifier.fillMaxWidth().padding(bottom = 24.dp), contentAlignment = Alignment.Center) {
                androidx.compose.material3.CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
            }
            book.total == 0 -> Row(
                Modifier.padding(start = 18.dp, end = 18.dp, bottom = 18.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Icons.Filled.PlayCircleOutline, contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                Text(stringResource(R.string.replay_anytime), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            else -> Column {
                Column(Modifier.padding(start = 18.dp, end = 18.dp, bottom = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    LinearProgressIndicator(
                        progress = { if (book.total == 0) 0f else book.masteredCount / book.total.toFloat() },
                        color = if (left == 0) Books.mastery else book.tint,
                        trackColor = com.roro.futurevoice.ui.brand.iosFill(),
                        strokeCap = StrokeCap.Round,
                        gapSize = 0.dp,
                        drawStopIndicator = {},
                        modifier = Modifier.fillMaxWidth().height(4.dp),
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.lld_left, left), style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        Text(stringResource(R.string.lld_lld_mastered, book.masteredCount, book.total),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                BookChapterButtons(book, onStudy)
            }
        }
    }
}

/** The book's half of today's card. `rowLines` null = each row at its own
 *  length, 0 = no rows. */
@Composable
private fun TodayTop(
    book: BookPreview, title: String, meta: String, note: String?, icon: ImageVector?,
    photo: androidx.compose.ui.graphics.ImageBitmap?, initials: String?, score: Int?,
    rowLines: Int?, noteLines: Int,
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            com.roro.futurevoice.ui.brand.BookIconDisc(accent = book.tint, photo = photo) {
                when {
                    initials != null -> Text(initials, style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold, color = book.tint)
                    icon != null -> Icon(icon, contentDescription = null, tint = book.tint,
                        modifier = Modifier.size(22.dp))
                }
            }
            Text(meta, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            score?.let {
                androidx.compose.foundation.layout.Box(
                    Modifier.size(34.dp).border(2.dp, MaterialTheme.colorScheme.outlineVariant, androidx.compose.foundation.shape.CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("$it", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(20.dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold,
                maxLines = 2, overflow = TextOverflow.Ellipsis)
            note?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = noteLines, overflow = TextOverflow.Ellipsis)
            }
        }
        // What each chapter still teaches, one line a chapter: the open
        // items first, so the card shows what finishing this book means.
        val rows = book.chapters.filter { it.items.isNotEmpty() }
        if (rows.isNotEmpty() && rowLines != 0) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                rows.forEach { chapter ->
                    val done = chapter.mastered == chapter.items.size
                    val short = chapter.kind == BookPreview.Kind.WORDS ||
                        chapter.kind == BookPreview.Kind.EXPRESSIONS
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(if (done) Icons.Filled.CheckCircle else chapter.kind.icon, contentDescription = null,
                            tint = if (done) Books.mastery else MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 1.dp).size(18.dp))
                        Text(chapterPreview(chapter), style = MaterialTheme.typography.bodyMedium,
                            color = if (done) MaterialTheme.colorScheme.onSurfaceVariant
                            else MaterialTheme.colorScheme.onSurface,
                            maxLines = rowLines ?: if (short) 2 else 4, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f))
                        Text("${chapter.mastered}/${chapter.items.size}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

/** The first of [variants] whose natural height fits the room, else the last
 *  (SwiftUI's `ViewThatFits(in: .vertical)`). */
@Composable
private fun FirstThatFits(vararg variants: @Composable () -> Unit) {
    androidx.compose.ui.layout.SubcomposeLayout { constraints ->
        val loose = constraints.copy(minHeight = 0, maxHeight = androidx.compose.ui.unit.Constraints.Infinity)
        var chosen: androidx.compose.ui.layout.Placeable? = null
        for ((i, v) in variants.withIndex()) {
            val p = subcompose(i, v).map { it.measure(loose) }.maxByOrNull { it.height } ?: continue
            chosen = p
            if (p.height <= constraints.maxHeight) break
        }
        val p = chosen
        layout(p?.width ?: 0, minOf(p?.height ?: 0, constraints.maxHeight)) { p?.place(0, 0) }
    }
}

private fun chapterPreview(chapter: BookPreview.Chapter): String {
    val texts = chapter.toStudy.map { it.text }
    return when (chapter.kind) {
        BookPreview.Kind.WORDS -> texts.take(8).joinToString(" · ")
        BookPreview.Kind.EXPRESSIONS -> texts.take(4).joinToString(" · ")
        BookPreview.Kind.GRAMMAR, BookPreview.Kind.SHADOW -> texts.take(2).joinToString("\n")
    }
}
