package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CallSplit
import androidx.compose.material.icons.filled.PlayCircleOutline
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.DrillCardEnrichment
import com.roro.futurevoice.data.DrillEnrichmentStore
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.net.EnrichmentClient
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.UserPersona
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.ContinuousShape
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import kotlinx.coroutines.launch

/**
 * iOS `DrillEnrichmentSheet`: examples set in the learner's OWN life, other
 * ways to say the same thing, and a hook to remember it by — under "Examples
 * & variants" with Done, the card's line on top as "Try saying".
 *
 * Generated once per PHRASE and kept ([DrillEnrichmentStore], also mirrored
 * onto the card the way iOS does), so the second open is instant and free —
 * the first version regenerated on every open and sat on a bare spinner each
 * time, which read as broken.
 *
 * [onEnriched] tells the deck the card now carries a payload, so its
 * "Examples" pill can fill in (iOS `refreshTopCard`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DrillEnrichmentSheet(
    card: DrillCard,
    persona: UserPersona?,
    targetLanguage: String,
    nativeLanguage: String,
    /** The clone, for an example's play button. Blank = resolved here. */
    voiceId: String = "",
    onEnriched: (DrillCard) -> Unit = {},
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { DrillEnrichmentStore.shared(context) }

    var enrichment by remember(card.id) { mutableStateOf(DrillEnrichmentStore.fromCard(card)) }
    var loading by remember(card.id) { mutableStateOf(enrichment == null) }
    var error by remember(card.id) { mutableStateOf<String?>(null) }
    var playingExample by remember { mutableStateOf<Int?>(null) }
    /** In-flight synthesis — a second tap must not fire a duplicate request. */
    var synthesizing by remember { mutableStateOf(false) }
    var voice by remember { mutableStateOf(voiceId.ifBlank { null }) }
    val player = remember { com.roro.futurevoice.audio.Mp3Player(context.cacheDir, source = "drill") }
    DisposableEffect(Unit) { onDispose { player.stop() } }

    /** Keep the card's own copy in step — only for a card the store holds. */
    suspend fun mirrorIntoCard(value: DrillCardEnrichment) {
        val drills = DrillStore.shared(context)
        val stored = drills.load(targetLanguage).firstOrNull { it.id == card.id } ?: return
        if (DrillEnrichmentStore.fromCard(stored) == value) return
        val updated = stored.copy(enrichment = DrillEnrichmentStore.toJson(value))
        drills.upsertMany(listOf(updated), targetLanguage)
        onEnriched(updated)
    }

    suspend fun reload() {
        loading = true
        error = null
        try {
            val fresh = EnrichmentClient(AuthRepository())
                .generate(card, persona, targetLanguage, nativeLanguage)
            enrichment = fresh
            store.save(fresh, card.targetPhrase, targetLanguage, nativeLanguage)
            mirrorIntoCard(fresh)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            android.util.Log.w("DrillEnrichment", "generate failed", e)
            error = e.message ?: e.toString()
        } finally {
            loading = false
        }
    }

    LaunchedEffect(card.id) {
        DrillEnrichmentStore.fromCard(card)?.let { cached ->
            // Lift what the card carries into the phrase-keyed store, so a
            // re-analysis clearing that card no longer takes it along.
            store.save(cached, card.targetPhrase, targetLanguage, nativeLanguage)
            return@LaunchedEffect
        }
        store.enrichment(card.targetPhrase, targetLanguage, nativeLanguage)?.let { cached ->
            enrichment = cached
            loading = false
            mirrorIntoCard(cached)
            return@LaunchedEffect
        }
        reload()
    }
    LaunchedEffect(Unit) {
        if (voice != null) return@LaunchedEffect
        val uid = AuthRepository().userId ?: return@LaunchedEffect
        voice = runCatching { com.roro.futurevoice.data.VoiceCloneRepository().activeVoiceId(uid) }.getOrNull()
    }
    // Sentences already on file, read once — an example's long-press says
    // "Saved" instead of offering it again (iOS 71c5e2da).
    var savedSentences by remember { mutableStateOf<Set<String>>(emptySet()) }
    LaunchedEffect(Unit) { savedSentences = DrillStore.shared(context).sentenceKeys(targetLanguage) }
    val exampleReason = stringResource(R.string.example_for, card.targetPhrase)

    fun playExample(idx: Int, text: String) {
        val id = voice ?: return
        if (synthesizing) return
        synthesizing = true
        scope.launch {
            runCatching {
                val audio = com.roro.futurevoice.data.cachedSynthesis(context, id, text, purpose = "drill")
                synthesizing = false
                playingExample = idx
                player.play(audio)
            }.onFailure { e ->
                // A parked voice / spent pool: the plans, not a dead button.
                if (e === com.roro.futurevoice.net.EdgeError.InsufficientCredits)
                    com.roro.futurevoice.data.BillingGate.showPaywall.value = true
            }
            synthesizing = false
            playingExample = null
        }
    }

    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val tint = MaterialTheme.colorScheme.primary

    ModalBottomSheet(
        // iOS `.fittingDetents([.medium, .large])`: opens at half height
        // with a grabber, drags up to full.
        sheetState = com.roro.futurevoice.ui.rememberModalBottomSheetState(skipPartiallyExpanded = false),
        containerColor = AppSurfaces.card,
        onDismissRequest = onDismiss,
    ) {
        SheetHeader(stringResource(R.string.examples_variants),
            trailing = { IosGlassTextButton(stringResource(R.string.done), onClick = onDismiss) },
            modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 4.dp))
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).bottomBarInsets()
                .padding(horizontal = 20.dp, vertical = 20.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            // Target header.
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.try_saying), style = MaterialTheme.typography.labelSmall,
                    color = secondary)
                Text(card.targetPhrase,
                    style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold))
                if (card.reason.isNotBlank()) {
                    Text(card.reason, style = MaterialTheme.typography.bodySmall, color = secondary,
                        modifier = Modifier.padding(top = 2.dp))
                }
            }

            val e = enrichment
            when {
                loading -> Row(Modifier.padding(vertical = 20.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp,
                        color = secondary)
                    Text(stringResource(R.string.pulling_examples_from_your_life),
                        style = MaterialTheme.typography.bodyLarge, color = secondary)
                }
                e != null -> {
                    // Memory hook card.
                    EnrichCard {
                        Row(verticalAlignment = Alignment.Top,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = tint,
                                modifier = Modifier.width(24.dp).size(22.dp))
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(stringResource(R.string.remember_this_when),
                                    style = MaterialTheme.typography.labelSmall, color = secondary)
                                Text(e.memoryHook, style = MaterialTheme.typography.bodyLarge)
                            }
                        }
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        SectionHeader(stringResource(R.string.in_your_life), Icons.Filled.TrackChanges)
                        e.examples.forEachIndexed { idx, item ->
                            // Long-press: keep this example as a sentence card
                            // of its own.
                            ExampleMenu(item.sentence, targetLanguage, exampleReason, savedSentences,
                                onSavedSentence = { savedSentences = savedSentences + it }) {
                                EnrichCard {
                                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Text(item.situation, style = MaterialTheme.typography.labelSmall,
                                            color = secondary)
                                        Row(verticalAlignment = Alignment.Top,
                                            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                            Text(item.sentence, style = MaterialTheme.typography.bodyLarge,
                                                modifier = Modifier.weight(1f))
                                            Icon(
                                                if (playingExample == idx) Icons.AutoMirrored.Filled.VolumeUp
                                                else Icons.Filled.PlayCircleOutline,
                                                contentDescription = null, tint = tint,
                                                modifier = Modifier.size(24.dp)
                                                    .clickable(
                                                        interactionSource = remember { MutableInteractionSource() },
                                                        indication = null,
                                                    ) { playExample(idx, item.sentence) },
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        SectionHeader(stringResource(R.string.variants), Icons.Filled.CallSplit)
                        e.variants.forEach { item ->
                            EnrichCard {
                                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text(item.phrase, style = MaterialTheme.typography.bodyLarge
                                        .copy(fontWeight = FontWeight.Medium))
                                    Text(item.note, style = MaterialTheme.typography.bodySmall,
                                        color = secondary)
                                }
                            }
                        }
                    }
                }
                error != null -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.Top,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Outlined.WarningAmber, contentDescription = null,
                            tint = Color(0xFFFF3B30), modifier = Modifier.size(20.dp))
                        Text(error.orEmpty(), style = MaterialTheme.typography.bodyLarge,
                            color = Color(0xFFFF3B30))
                    }
                    // A retry, not a dead end.
                    Text(stringResource(R.string.try_again), style = MaterialTheme.typography.bodyLarge,
                        color = tint,
                        modifier = Modifier.clickable { scope.launch { reload() } }
                            .padding(vertical = 4.dp))
                }
            }
        }
    }
}

/** iOS: padding 14, `secondarySystemBackground`, 12 pt corners. */
@Composable
private fun EnrichCard(content: @Composable () -> Unit) {
    androidx.compose.foundation.layout.Box(
        Modifier.fillMaxWidth().clip(ContinuousShape(12.dp)).background(cardFill()).padding(14.dp),
    ) { content() }
}

/** iOS `sectionHeader(_:icon:)`: tinted icon, subheadline semibold. */
@Composable
private fun SectionHeader(title: String, icon: ImageVector) {
    Row(Modifier.fillMaxWidth().padding(top = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(17.dp))
        Text(title, style = MaterialTheme.typography.titleSmall)
    }
}
