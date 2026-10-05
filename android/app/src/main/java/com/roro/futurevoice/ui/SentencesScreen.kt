package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DrillIngest
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.LibraryBadge
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.ui.brand.AppSurfaces

/**
 * Every drill sentence in one flat list — iOS `SentencesView`, the
 * sentence-level twin of the words and expressions pages, reached from the
 * Studying page's Sentences tile. The sentence itself is the row, with the
 * card's own coaching note as its gloss; tapping a row drills exactly that
 * card.
 *
 * Two lenses, as the word and expression lists have: To study (below the top
 * rung) and Known (box 5). "Got it" RETIRES a card — it is still LISTED here
 * under Known; re-filing it from the deck's Known folder is what brings it
 * back. No search and no row menu: iOS's page has neither.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SentencesScreen(
    language: String,
    /** Drill this one card (iOS `DrillView(source: .card(id))`, pushed). */
    onOpenCard: (String) -> Unit,
    onBack: () -> Unit,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var cards by remember(language) { mutableStateOf<List<DrillCard>>(emptyList()) }
    var known by remember { mutableStateOf(com.roro.futurevoice.capture.flags.PracticeCaptureFlags.sentencesKnown) }
    LaunchedEffect(language, revision) { cards = DrillStore.shared(context).load(language) }
    // Newest first — the sentence minted this morning is the one you came for.
    val visible = cards.filter { (it.box >= DrillIngest.MAX_BOX) == known }
        .sortedByDescending { it.createdAt }

    Scaffold(
        topBar = {
            // Pushed from Practice on iOS: back chevron, name centred.
            CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.sentences), style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
            .padding(horizontal = 16.dp)) {
            com.roro.futurevoice.ui.brand.IosSegmented(
                listOf(stringResource(R.string.to_study), stringResource(R.string.known)),
                if (known) 1 else 0, { known = it == 1 },
                Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 12.dp))
            if (visible.isEmpty()) {
                SentencesEmpty(known)
                return@Column
            }
            LazyColumn(Modifier.fillMaxSize()) {
                item { GroupedSectionHeader(stringResource(R.string.lld_sentences, visible.size)) }
                itemsIndexed(visible, key = { _, c -> c.id }) { index, card ->
                    val first = index == 0
                    val last = index == visible.lastIndex
                    val r = com.roro.futurevoice.ui.brand.IosRadius.groupedCard
                    val shape = RoundedCornerShape(
                        topStart = if (first) r else 0.dp, topEnd = if (first) r else 0.dp,
                        bottomStart = if (last) r else 0.dp, bottomEnd = if (last) r else 0.dp)
                    Column(Modifier.fillMaxWidth().clip(shape).background(AppSurfaces.card)) {
                        SentenceRow(card, onClick = { onOpenCard(card.id) })
                        if (!last) HorizontalDivider(
                            Modifier.padding(start = if (card.box >= DrillIngest.MAX_BOX) 44.dp else 16.dp),
                            color = MaterialTheme.colorScheme.outlineVariant)
                    }
                }
                item { GroupedSectionSpacer() }
            }
        }
    }
}

/** Badge (known rung only: plain = "Got it", filled = said in a talk), then
 *  the sentence over its coaching note — or what the learner first said. */
@Composable
private fun SentenceRow(card: DrillCard, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        val top = card.box >= DrillIngest.MAX_BOX
        when (LibraryBadge.of(studying = false, known = top, used = top && card.usedInTalkAt != null)) {
            LibraryBadge.USED -> Icon(Icons.Filled.CheckCircle,
                contentDescription = stringResource(R.string.used_in_a_talk),
                modifier = Modifier.padding(top = 3.dp).size(16.dp), tint = Color(0xFF34C759))
            LibraryBadge.KNOWN -> Icon(Icons.Filled.Check,
                contentDescription = stringResource(R.string.marked_known),
                modifier = Modifier.padding(top = 3.dp).size(16.dp), tint = Color(0xFF34C759))
            else -> {}
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(card.targetPhrase, style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            val gloss = card.reason.ifBlank { card.sourcePhrase }
            if (gloss.isNotBlank()) {
                Text(gloss, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            modifier = Modifier.align(Alignment.CenterVertically),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
    }
}

/** iOS's `ContentUnavailableView` for each lens. */
@Composable
private fun SentencesEmpty(known: Boolean) {
    Column(Modifier.fillMaxSize().padding(30.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically)) {
        Icon(if (known) Icons.Outlined.Inbox else Icons.Outlined.CheckCircle, contentDescription = null,
            modifier = Modifier.size(44.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(stringResource(if (known) R.string.nothing_learned_yet else R.string.nothing_left_to_study),
            style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center)
        Text(stringResource(if (known)
                R.string.a_sentence_lands_here_once_it_reaches_the_top_of_the_review_e78fa1
            else R.string.every_sentence_from_your_talks_is_at_the_top_of_the_ladder_n_0e61ab),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}
