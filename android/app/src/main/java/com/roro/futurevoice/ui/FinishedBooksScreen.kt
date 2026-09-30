package com.roro.futurevoice.ui

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.ShadowAttemptStore
import com.roro.futurevoice.data.TalkCurriculum
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosGlassTextButton

/** iOS `systemGreen` — the green mastery wears on this page. */
private val FinishedGreen = Color(0xFF34C759)

/**
 * The trophy shelf: books where every single word and line is mastered, Talk
 * and Watch together, archived or not (iOS `FinishedBooksSheet`).
 *
 * Archiving is tidying; THIS is the achievement. A full page, opened from the
 * seal in the Practice header — centred title, Done at the right, back closes.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FinishedBooksScreen(books: List<FinishedBook>, onOpen: (FinishedBook) -> Unit, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = {
                    Text(stringResource(R.string.finished), style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Normal)
                },
                actions = {
                    IosGlassTextButton(stringResource(R.string.done), onClick = onBack,
                        modifier = Modifier.padding(end = 12.dp))
                },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        if (books.isEmpty()) {
            EmptyShelf(Modifier.padding(padding))
            return@Scaffold
        }
        Column(
            Modifier.padding(padding).fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(top = 36.dp),
        ) {
            // The count IS the record, so it is said as a number and not as a
            // sentence, in the green mastery wears everywhere else.
            GroupedCard {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text("${books.size}", fontSize = 44.sp, fontWeight = FontWeight.Bold,
                        color = FinishedGreen, style = MaterialTheme.typography.displaySmall)
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(stringResource(
                            if (books.size == 1) R.string.book_finished else R.string.books_finished),
                            style = MaterialTheme.typography.titleMedium, fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold)
                        Text(stringResource(R.string.lld_words_and_lines_mastered_inside_them,
                            books.sumOf { it.itemCount }),
                            style = MaterialTheme.typography.bodySmall, fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            Spacer(Modifier.height(36.dp))
            GroupedCard {
                books.forEachIndexed { i, book ->
                    if (i > 0) GroupedRowDivider(inset = true)
                    FinishedRow(book) { onOpen(book) }
                }
            }
            GroupedFooter(stringResource(R.string.a_book_lands_here_once_every_word_and_line_in_it_is_mastered_d3fa9a))
            Spacer(Modifier.height(32.dp).windowInsetsPadding(WindowInsets.navigationBars))
        }
    }
}

/** icon · title over "Scene · with X · 14 mastered · date" · seal · chevron. */
@Composable
private fun FinishedRow(book: FinishedBook, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick)
        .padding(start = 16.dp, end = 12.dp, top = 12.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) {
            Icon(book.icon, contentDescription = null,
                tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            // iOS subheadline (15) over caption (12).
            Text(book.title, style = MaterialTheme.typography.bodyMedium, fontSize = 15.sp,
                fontWeight = FontWeight.Medium, maxLines = 2)
            Text(stringResource(R.string.lld_mastered, book.subtitle, book.itemCount, book.finishedLabel),
                style = MaterialTheme.typography.bodySmall, fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Icon(Icons.Filled.Verified, contentDescription = null,
            tint = FinishedGreen, modifier = Modifier.size(18.dp))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun EmptyShelf(modifier: Modifier) {
    Column(modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Outlined.Verified, contentDescription = null,
            tint = MaterialTheme.colorScheme.outlineVariant, modifier = Modifier.size(44.dp))
        Text(stringResource(R.string.nothing_finished_yet), style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold)
        Text(stringResource(R.string.master_every_word_and_line_in_a_book_from_a_talk_or_a_scene_ade546),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}

/**
 * The header seal on Practice (iOS `finishedShelfButton`): green seal + the
 * count once anything is finished, an outlined grey seal at zero — shown even
 * then, so the shelf is something to fill rather than a surprise.
 */
@Composable
fun FinishedShelfButton(count: Int, onClick: () -> Unit, modifier: Modifier = Modifier) {
    com.roro.futurevoice.ui.brand.IosGlassButton(onClick, modifier) {
        Icon(if (count > 0) Icons.Filled.Verified else Icons.Outlined.Verified,
            contentDescription = stringResource(R.string.lld_books_finished, count),
            tint = if (count > 0) FinishedGreen else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(22.dp))
        if (count > 0) {
            Text("$count", modifier = Modifier.padding(start = 5.dp),
                style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                color = FinishedGreen)
        }
    }
}

/**
 * Every finished book in [language] — Talk and Watch, archived or not. Heavy
 * (a curriculum build per talk), so callers run it off the main thread.
 */
suspend fun loadFinishedBooks(context: Context, language: String, level: CefrLevel): List<FinishedBook> {
    val allTalks = SessionStore.shared(context).load(language).filter { it.summary != null }
    val allScenarios = ScenarioStore.shared(context).load(language).filter { it.isMeeting != true }
    val vocabStore = VocabStore.shared(context)
    val attempts = ShadowAttemptStore.shared(context).load(language)
    val cards = DrillStore.shared(context).load(language)
    return allTalks.mapNotNull { s ->
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
            // "Scene · with Sarah" — who it was with is part of what the book
            // WAS, and the row is the only place it still shows.
            listOfNotNull(context.getString(R.string.scene),
                sc.role.takeIf { it.isNotBlank() }?.let { context.getString(R.string.with, it) })
                .joinToString(" · "),
            Icons.Filled.Movie, total, isTalk = false,
            finishedLabel = shelfDate(sc.createdAt))
    }
}

/** A finished book, prepared so the page never has to know how Talk and
 *  Watch books compute mastery. */
data class FinishedBook(
    val id: String,
    val title: String,
    val subtitle: String,
    val icon: ImageVector,
    val itemCount: Int,
    val isTalk: Boolean,
    /** The day it was finished, already written the way the row prints it. */
    val finishedLabel: String = "",
)
