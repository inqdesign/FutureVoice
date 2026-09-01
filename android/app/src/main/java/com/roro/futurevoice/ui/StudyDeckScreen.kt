package com.roro.futurevoice.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.foundation.border
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.StudyScheduleStore
import com.roro.futurevoice.net.WordLore
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.DrillBin
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * One card in a daily deck: the text plus what kind of thing it is, so a
 * mixed session (words AND expressions, whatever came due) can resolve each
 * card into the right store.
 */
data class StudyDeckItem(val kind: StudyScheduleStore.Kind, val text: String) {
    val id: String get() = kind.raw + "|" + text.lowercase()

    companion object {
        fun word(t: String) = StudyDeckItem(StudyScheduleStore.Kind.WORD, t)
        fun expression(t: String) = StudyDeckItem(StudyScheduleStore.Kind.EXPRESSION, t)
    }
}

/**
 * The word / expression deck (iOS `StudyDeckView`): the item alone on the
 * front — say it out loud, do you know it — a tap flips it to its meaning,
 * then a drag files it into one of the four verdicts.
 *
 * The FOLDERS are a window on the return time, not a tally of this session's
 * drops: they are rebuilt from [StudyScheduleStore] after every verdict, so a
 * card is shown where it actually IS ("3 days" the drop, "Later" the place)
 * and the promise survives closing the sheet. "Got it" is the one folder that
 * stays session-local, and must: marking something known CLEARS its return
 * date, so there is nothing on disk to list.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun StudyDeckScreen(
    title: String,
    items: List<StudyDeckItem>,
    language: String,
    nativeLanguage: String,
    onResolve: suspend (StudyDeckItem, DrillBin) -> Unit,
    onBack: () -> Unit,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val lore = remember { WordLore(AuthRepository()) }

    var queue by remember(items) { mutableStateOf(items) }
    var resolved by remember(items) { mutableIntStateOf(0) }
    var revealed by remember { mutableStateOf(false) }
    var entry by remember { mutableStateOf<WordLore.Entry?>(null) }
    var loading by remember { mutableStateOf(false) }
    /** Where everything still WAITING sits, bucketed by when it comes back. */
    var scheduled by remember { mutableStateOf<Map<DrillBin, List<StudyScheduleStore.DueItem>>>(emptyMap()) }
    /** "Got it" can't come from the schedule — see the class comment. */
    var finished by remember { mutableStateOf<List<StudyDeckItem>>(emptyList()) }
    var openFolder by remember { mutableStateOf<DrillBin?>(null) }
    var verdictFor by remember { mutableStateOf<StudyDeckItem?>(null) }

    var dragOffset by remember { mutableStateOf(0f to 0f) }
    var dragging by remember { mutableStateOf(false) }
    var binBounds by remember { mutableStateOf<Map<DrillBin, Rect>>(emptyMap()) }
    /** Window origin of the card, sampled at rest — the drag moves the node,
     *  so re-reading it mid-drag would chase its own offset. */
    var cardOrigin by remember { mutableStateOf(0f to 0f) }
    /** Where the FINGER is, in window coords. The card's centre is the wrong
     *  probe: a card is taller than a bin, so its centre clears the bins by
     *  hundreds of pixels while the finger is still on one. */
    var pointer by remember { mutableStateOf(0f to 0f) }

    val top = queue.firstOrNull()

    suspend fun refreshFolders() {
        val now = System.currentTimeMillis()
        // Scoped to the KINDS this deck was dealt: a Words session listing
        // expressions under "Later" would answer a question nobody asked.
        val kinds = items.map { it.kind }.toSet()
        scheduled = StudyScheduleStore.shared(context).snapshot(language).upcoming(now)
            .filter { it.kind in kinds }
            .groupBy { DrillBin.folder(it.at - now) }
    }

    LaunchedEffect(items) { refreshFolders() }

    LaunchedEffect(top?.id) {
        revealed = false
        entry = null
        val item = top ?: return@LaunchedEffect
        loading = true
        // A mixed deck holds both kinds; each has to be looked up as what it
        // is, or an expression comes back glossed as one of its words.
        entry = lore.entry(item.text, nativeLanguage, language,
            if (item.kind == StudyScheduleStore.Kind.EXPRESSION) WordLore.Kind.EXPRESSION
            else WordLore.Kind.WORD)
        loading = false
    }

    fun file(item: StudyDeckItem, bin: DrillBin) {
        scope.launch {
            onResolve(item, bin)
            if (bin == DrillBin.GOT_IT && finished.none { it.id == item.id }) {
                finished = finished + item
            }
            refreshFolders()
            StoreEvents.bump()
        }
        queue = queue.drop(1)
        resolved += 1
        dragOffset = 0f to 0f
        dragging = false
    }

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = {
                    Column {
                        Text(title, style = MaterialTheme.typography.titleMedium)
                        if (items.isNotEmpty()) {
                            Text(stringResource(R.string.lld_of_lld,
                                (resolved + 1).coerceAtMost(items.size), items.size),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (items.isNotEmpty()) {
                LinearProgressIndicator(
                    progress = { resolved / items.size.toFloat() },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }

            if (top == null) {
                DeckDoneState(
                    folders = DrillBin.entries.map { bin ->
                        bin to if (bin == DrillBin.GOT_IT) finished.size
                        else (scheduled[bin]?.size ?: 0)
                    },
                    onOpen = { openFolder = it },
                    modifier = Modifier.weight(1f),
                )
            } else {
                Box(Modifier.weight(1f).padding(horizontal = 16.dp)) {
                    StudyCard(
                        text = top.text,
                        revealed = revealed,
                        loading = loading,
                        entry = entry,
                        modifier = Modifier
                            .fillMaxSize()
                            .onGloballyPositioned {
                                if (!dragging) {
                                    val b = it.boundsInWindow()
                                    cardOrigin = b.left to b.top
                                }
                            }
                            .offset { IntOffset(dragOffset.first.roundToInt(), dragOffset.second.roundToInt()) }
                            .pointerInput(top.id, revealed) {
                                if (!revealed) return@pointerInput
                                detectDragGestures(
                                    onDragStart = { start ->
                                        dragging = true
                                        pointer = cardOrigin.first + start.x to
                                            cardOrigin.second + start.y
                                    },
                                    onDragCancel = { dragging = false; dragOffset = 0f to 0f },
                                    onDragEnd = {
                                        val p = androidx.compose.ui.geometry.Offset(
                                            pointer.first, pointer.second)
                                        val hit = binBounds.entries
                                            .firstOrNull { it.value.contains(p) }?.key
                                        if (hit != null) file(top, hit)
                                        else { dragging = false; dragOffset = 0f to 0f }
                                    },
                                ) { change, delta ->
                                    change.consume()
                                    dragOffset = dragOffset.first + delta.x to dragOffset.second + delta.y
                                    pointer = pointer.first + delta.x to pointer.second + delta.y
                                }
                            }
                            .combinedClickable(
                                onClick = { if (!revealed) revealed = true },
                                // Dragging is the gesture; this is the same
                                // four verdicts for anyone who can't make one.
                                onLongClick = { if (revealed) verdictFor = top },
                            ),
                    )
                }

                // The hint keeps its height so the deck doesn't jump when a
                // drag begins — mid-drag the bins take the row below it. It
                // says the DRAG, always: the tap is already written on the
                // card's own face, and saying it twice made the deck look
                // like it was insisting.
                Text(
                    stringResource(R.string.drag_the_card_into_a_folder),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                )

                BinRow(
                    dragging = dragging,
                    counts = { bin ->
                        if (bin == DrillBin.GOT_IT) finished.size else (scheduled[bin]?.size ?: 0)
                    },
                    onBounds = { bin, rect -> binBounds = binBounds + (bin to rect) },
                    onTap = { bin -> openFolder = bin },
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
    }

    verdictFor?.let { item ->
        ModalBottomSheet(onDismissRequest = { verdictFor = null }) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(item.text, style = MaterialTheme.typography.titleMedium)
                Text(stringResource(R.string.when_should_it_come_back),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                DrillBin.entries.forEach { bin ->
                    Row(
                        Modifier.fillMaxWidth()
                            .clickable { verdictFor = null; file(item, bin) }
                            .padding(vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(bin.icon, contentDescription = null, tint = bin.tint,
                            modifier = Modifier.size(20.dp))
                        Text(stringResource(bin.titleRes),
                            style = MaterialTheme.typography.bodyLarge)
                    }
                }
            }
        }
    }

    openFolder?.let { bin ->
        val rows: List<Pair<String, Long?>> =
            if (bin == DrillBin.GOT_IT) finished.map { it.text to null }
            else (scheduled[bin] ?: emptyList()).map { it.text to it.at }
        ModalBottomSheet(onDismissRequest = { openFolder = null }) {
            Column(Modifier.padding(20.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(stringResource(bin.folderTitleRes),
                    style = MaterialTheme.typography.titleMedium)
                if (rows.isEmpty()) {
                    Text(stringResource(
                        if (bin == DrillBin.GOT_IT) R.string.nothing_marked_known_in_this_session
                        else R.string.nothing_waiting_here),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                rows.forEach { (text, at) ->
                    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        Text(text, style = MaterialTheme.typography.bodyMedium)
                        if (at != null) {
                            Text(relativeReturn(at), style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}

/** "in 3 hours" / "tomorrow" — a rough when, never a countdown. */
@Composable
private fun relativeReturn(at: Long): String {
    val ms = at - System.currentTimeMillis()
    val hours = ms / (60 * 60 * 1000)
    return when {
        hours < 1 -> stringResource(R.string.within_the_hour)
        hours < 24 -> stringResource(R.string.in_lld_hours, hours.toInt())
        else -> stringResource(R.string.in_lld_days, (hours / 24).toInt().coerceAtLeast(1))
    }
}

/**
 * The card: the same accent slab the drill card wears. Caption over content,
 * meaning below the fold, and a fixed shape so a long gloss scrolls INSIDE
 * the slab rather than pushing the bins off the screen.
 */
@Composable
private fun StudyCard(
    text: String,
    revealed: Boolean,
    loading: Boolean,
    entry: WordLore.Entry?,
    modifier: Modifier = Modifier,
) {
    val onCard = Color.White
    val onCardSecondary = Color.White.copy(alpha = 0.72f)
    Column(
        modifier
            .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(18.dp))
            .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(18.dp))
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Text(
            stringResource(
                if (revealed) R.string.when_should_it_come_back
                else R.string.say_it_out_loud_do_you_know_it),
            style = MaterialTheme.typography.labelMedium, color = onCardSecondary,
        )
        Text(text, style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold, color = onCard)

        if (revealed) {
            // Cut to fit, never scrolled. An inner scroll would swallow the
            // drag that files the card — the deck's one gesture — so the
            // card is a fixed slab and the gloss is trimmed to it (iOS does
            // the same, via a bounded proposal and ViewThatFits).
            Column(
                Modifier.weight(1f, fill = false).clipToBounds(),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                when {
                    loading -> CircularProgressIndicator(
                        color = onCard, modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    entry == null -> Text("—", color = onCardSecondary)
                    else -> {
                        entry.senses.take(3).forEach { s ->
                            Column {
                                if (s.pos.isNotBlank()) {
                                    Text(s.pos, style = MaterialTheme.typography.labelSmall,
                                        color = onCardSecondary)
                                }
                                Text(s.meaning, style = MaterialTheme.typography.bodyMedium,
                                    color = onCard)
                            }
                        }
                        entry.examples.take(2).forEach { e ->
                            Column {
                                Text(e.text, style = MaterialTheme.typography.bodyMedium,
                                    color = onCard)
                                e.meaning?.takeIf { it.isNotBlank() }?.let {
                                    Text(it, style = MaterialTheme.typography.bodySmall,
                                        color = onCardSecondary)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            Spacer(Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.TouchApp, contentDescription = null,
                    tint = onCardSecondary, modifier = Modifier.size(16.dp))
                Text(stringResource(R.string.tap_to_check_the_meaning),
                    style = MaterialTheme.typography.labelMedium, color = onCardSecondary)
            }
        }
    }
}

/**
 * The four verdicts. At rest they are quiet folder counters; mid-drag they
 * light up as the drop targets — the same row doing both jobs, so nothing on
 * the screen moves when a drag begins.
 */
@Composable
private fun BinRow(
    dragging: Boolean,
    counts: (DrillBin) -> Int,
    onBounds: (DrillBin, Rect) -> Unit,
    onTap: (DrillBin) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        DrillBin.entries.forEach { bin ->
            val emphasis by animateFloatAsState(if (dragging) 1f else 0f, label = "bin")
            Column(
                Modifier.weight(1f)
                    .onGloballyPositioned { onBounds(bin, it.boundsInWindow()) }
                    .background(
                        bin.tint.copy(alpha = 0.12f + 0.16f * emphasis),
                        RoundedCornerShape(12.dp))
                    .clickable { onTap(bin) }
                    .padding(vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Icon(bin.icon, contentDescription = null, tint = bin.tint,
                    modifier = Modifier.size(18.dp))
                Text(stringResource(if (dragging) bin.titleRes else bin.folderTitleRes),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface)
                if (!dragging) {
                    val n = counts(bin)
                    Text(if (n == 0) "—" else "$n",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/**
 * The done state keeps the folders. "Where did all that go?" is asked after
 * the last card, and having to reopen the deck to look is the very thing that
 * made a kept promise look broken.
 */
@Composable
private fun DeckDoneState(
    folders: List<Pair<DrillBin, Int>>,
    onOpen: (DrillBin) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier.fillMaxWidth().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(24.dp))
        Text(stringResource(R.string.done_for_today),
            style = MaterialTheme.typography.titleMedium)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            folders.forEach { (bin, n) ->
                Column(
                    Modifier.weight(1f)
                        .background(bin.tint.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
                        .clickable { onOpen(bin) }
                        .padding(vertical = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(bin.icon, contentDescription = null, tint = bin.tint,
                        modifier = Modifier.size(18.dp))
                    Text(stringResource(bin.folderTitleRes),
                        style = MaterialTheme.typography.labelSmall)
                    Text(if (n == 0) "—" else "$n",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}
