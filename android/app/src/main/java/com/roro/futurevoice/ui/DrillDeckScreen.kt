package com.roro.futurevoice.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.TouchApp
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
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.DrillBin
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * The sentence deck: the learner's own slip on the front — say it out loud,
 * tap to check — the fluent line and the reason on the back, then a drag
 * files it.
 *
 * It files through the SAME four verdicts and the same folders as the
 * word/expression deck. That is the whole reason [DrillBin] exists: the two
 * decks must never disagree about what "Soon" means, and for a while this one
 * offered a plain known/not-yet pair instead, so the same gesture meant
 * different things depending on which sheet you were in.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun DrillDeckScreen(language: String, onBack: () -> Unit) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { DrillStore.shared(context) }

    var deck by remember { mutableStateOf<List<DrillCard>>(emptyList()) }
    var dealt by remember { mutableStateOf(false) }
    var resolved by remember { mutableIntStateOf(0) }
    var revealed by remember { mutableStateOf(false) }
    /** Everything still waiting, bucketed by WHEN it comes back. */
    var scheduled by remember { mutableStateOf<Map<DrillBin, Int>>(emptyMap()) }
    /** "Got it" is session-local here too — a graduated card is not "waiting". */
    var finished by remember { mutableIntStateOf(0) }
    var verdictFor by remember { mutableStateOf<DrillCard?>(null) }

    var dragOffset by remember { mutableStateOf(0f to 0f) }
    var dragging by remember { mutableStateOf(false) }
    var binBounds by remember { mutableStateOf<Map<DrillBin, Rect>>(emptyMap()) }
    var cardOrigin by remember { mutableStateOf(0f to 0f) }
    var pointer by remember { mutableStateOf(0f to 0f) }

    suspend fun refreshFolders() {
        val now = System.currentTimeMillis()
        scheduled = store.load(language)
            .filter { it.nextReviewAt > now && it.box < com.roro.futurevoice.data.DrillIngest.MAX_BOX }
            .groupingBy { DrillBin.folder(it.nextReviewAt - now) }
            .eachCount()
    }

    LaunchedEffect(language) {
        deck = store.due(language)
        dealt = true
        refreshFolders()
    }

    val top = deck.firstOrNull()
    LaunchedEffect(top?.id) { revealed = false }

    fun file(card: DrillCard, bin: DrillBin) {
        scope.launch {
            val manual = bin.manual
            if (manual != null) store.fileInBin(card, manual.first, manual.second, language)
            else { store.markKnown(card, language); finished += 1 }
            refreshFolders()
            StoreEvents.bump()
        }
        deck = deck.drop(1)
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
                        Text(stringResource(R.string.review_cards),
                            style = MaterialTheme.typography.titleMedium)
                        if (deck.isNotEmpty() || resolved > 0) {
                            Text(stringResource(R.string.lld_of_lld,
                                (resolved + 1).coerceAtMost(resolved + deck.size),
                                resolved + deck.size),
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
            val total = resolved + deck.size
            if (total > 0) {
                LinearProgressIndicator(
                    progress = { resolved / total.toFloat() },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }

            if (top == null) {
                if (dealt) {
                    DeckDone(
                        folders = DrillBin.entries.map { bin ->
                            bin to if (bin == DrillBin.GOT_IT) finished else (scheduled[bin] ?: 0)
                        },
                        modifier = Modifier.weight(1f),
                    )
                }
            } else {
                Box(Modifier.weight(1f).padding(horizontal = 16.dp)) {
                    DrillCardFace(
                        card = top,
                        revealed = revealed,
                        modifier = Modifier
                            .fillMaxSize()
                            .onGloballyPositioned {
                                if (!dragging) {
                                    val b = it.boundsInWindow()
                                    cardOrigin = b.left to b.top
                                }
                            }
                            .offset { IntOffset(dragOffset.first.roundToInt(),
                                dragOffset.second.roundToInt()) }
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
                                        val p = Offset(pointer.first, pointer.second)
                                        val hit = binBounds.entries
                                            .firstOrNull { it.value.contains(p) }?.key
                                        if (hit != null) file(top, hit)
                                        else { dragging = false; dragOffset = 0f to 0f }
                                    },
                                ) { change, delta ->
                                    change.consume()
                                    dragOffset = dragOffset.first + delta.x to
                                        dragOffset.second + delta.y
                                    pointer = pointer.first + delta.x to pointer.second + delta.y
                                }
                            }
                            .combinedClickable(
                                onClick = { if (!revealed) revealed = true },
                                onLongClick = { if (revealed) verdictFor = top },
                            ),
                    )
                }

                Text(stringResource(R.string.drag_the_card_into_a_folder),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp))

                VerdictRow(
                    dragging = dragging,
                    counts = { bin ->
                        if (bin == DrillBin.GOT_IT) finished else (scheduled[bin] ?: 0)
                    },
                    onBounds = { bin, rect -> binBounds = binBounds + (bin to rect) },
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
    }

    verdictFor?.let { card ->
        ModalBottomSheet(onDismissRequest = { verdictFor = null }) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(card.targetPhrase, style = MaterialTheme.typography.titleMedium)
                Text(stringResource(R.string.when_should_it_come_back),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                DrillBin.entries.forEach { bin ->
                    Row(
                        Modifier.fillMaxWidth()
                            .clickable { verdictFor = null; file(card, bin) }
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
}

/**
 * The card. The learner's own slip on the front (struck through once the
 * fluent line is showing, so the pair reads as a correction), the fluent line
 * and its reason on the back.
 */
@Composable
private fun DrillCardFace(card: DrillCard, revealed: Boolean, modifier: Modifier = Modifier) {
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
        if (card.sourcePhrase.isNotBlank()) {
            Text(card.sourcePhrase, style = MaterialTheme.typography.titleMedium,
                color = if (revealed) onCardSecondary else onCard,
                textDecoration = if (revealed) TextDecoration.LineThrough else null)
        }

        if (revealed) {
            Column(Modifier.weight(1f, fill = false).clipToBounds(),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(card.targetPhrase, style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold, color = onCard)
                if (card.reason.isNotBlank()) {
                    Text(card.reason, style = MaterialTheme.typography.bodyMedium,
                        color = onCardSecondary)
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

/** The four verdicts — folder counters at rest, drop targets mid-drag. */
@Composable
private fun VerdictRow(
    dragging: Boolean,
    counts: (DrillBin) -> Int,
    onBounds: (DrillBin, Rect) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        DrillBin.entries.forEach { bin ->
            Column(
                Modifier.weight(1f)
                    .onGloballyPositioned { onBounds(bin, it.boundsInWindow()) }
                    .background(
                        bin.tint.copy(alpha = if (dragging) 0.28f else 0.12f),
                        RoundedCornerShape(12.dp))
                    .padding(vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Icon(bin.icon, contentDescription = null, tint = bin.tint,
                    modifier = Modifier.size(18.dp))
                Text(stringResource(if (dragging) bin.titleRes else bin.folderTitleRes),
                    style = MaterialTheme.typography.labelSmall)
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

/** Keeps the folders after the last card — "where did all that go?". */
@Composable
private fun DeckDone(folders: List<Pair<DrillBin, Int>>, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(stringResource(R.string.done_for_today),
            style = MaterialTheme.typography.titleMedium)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            folders.forEach { (bin, n) ->
                Column(
                    Modifier.weight(1f)
                        .background(bin.tint.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
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
