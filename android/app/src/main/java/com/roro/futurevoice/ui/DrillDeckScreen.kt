package com.roro.futurevoice.ui

import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.material.icons.filled.Close
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.layout.heightIn
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.Animatable
import androidx.compose.material3.Button
import com.roro.futurevoice.data.DrillIngest
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.ElevenLabsClient
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.AssistChip
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
import androidx.compose.foundation.layout.navigationBarsPadding
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
import androidx.compose.material3.TextButton
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
fun DrillDeckScreen(
    language: String,
    persona: com.roro.futurevoice.talk.UserPersona? = null,
    nativeLanguage: String = "en",
    /** The clone, for "Hear it" — blank means no voice yet, and the chip says so by staying off. */
    voiceId: String = "",
    /** Shadowing runs its own screen; the deck hands it one line. */
    onShadow: (String) -> Unit = {},
    onBack: () -> Unit,
) {
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
    /** The card opened up — examples, variants, a hook to remember it by. */
    var enrichFor by remember { mutableStateOf<DrillCard?>(null) }
    /** Due cards this hand didn't take. Short enough to finish in one sitting. */
    var remainingDue by remember { mutableIntStateOf(0) }
    /** One line of the card, in the learner's own cloned voice. */
    var hearing by remember { mutableStateOf(false) }
    val player = remember { com.roro.futurevoice.audio.Mp3Player(context.cacheDir, source = "drill") }

    // The card's own position, animated: a drag writes it directly, a release
    // springs it back, and a commit flies it into the folder.
    val cardOffset = remember { Animatable(Offset.Zero, Offset.VectorConverter) }
    val flyScale = remember { Animatable(1f) }
    val flyAlpha = remember { Animatable(1f) }
    var dragging by remember { mutableStateOf(false) }
    var binBounds by remember { mutableStateOf<Map<DrillBin, Rect>>(emptyMap()) }
    /** Where the card sits when nothing is dragging — the origin every
     *  distance is measured from. */
    var deckCentre by remember { mutableStateOf(Offset.Zero) }
    /** The folder the card is over, or CANCEL when pulled up. Nearest-centre,
     *  never containment: the gap between two chips still has to resolve to
     *  one of them, or a release there reads as the app ignoring you. */
    var activeBin by remember { mutableStateOf<DrillBin?>(null) }
    var cancelActive by remember { mutableStateOf(false) }
    val haptics = androidx.compose.ui.platform.LocalHapticFeedback.current
    val density = androidx.compose.ui.platform.LocalDensity.current

    /** The cards themselves, so a folder can be opened and not just counted. */
    var folderCards by remember { mutableStateOf<Map<DrillBin, List<DrillCard>>>(emptyMap()) }
    var openFolder by remember { mutableStateOf<DrillBin?>(null) }

    suspend fun refreshFolders() {
        val now = System.currentTimeMillis()
        folderCards = store.load(language)
            .filter { it.nextReviewAt > now && it.box < com.roro.futurevoice.data.DrillIngest.MAX_BOX }
            .groupBy { DrillBin.folder(it.nextReviewAt - now) }
        scheduled = store.load(language)
            .filter { it.nextReviewAt > now && it.box < com.roro.futurevoice.data.DrillIngest.MAX_BOX }
            .groupingBy { DrillBin.folder(it.nextReviewAt - now) }
            .eachCount()
    }

    suspend fun dealHand() {
        val due = store.due(language)
        deck = due.take(SESSION_CAP)
        remainingDue = (due.size - deck.size).coerceAtLeast(0)
        dealt = true
        refreshFolders()
    }

    LaunchedEffect(language) { dealHand() }

    val top = deck.firstOrNull()
    LaunchedEffect(top?.id) { revealed = false }

    fun apply(card: DrillCard, bin: DrillBin) {
        scope.launch {
            val manual = bin.manual
            if (manual != null) store.fileInBin(card, manual.first, manual.second, language)
            else { store.markKnown(card, language); finished += 1 }
            refreshFolders()
            StoreEvents.bump()
        }
        deck = deck.drop(1)
        resolved += 1
    }

    /** Fly into the folder, shrink out of existence, THEN write. */
    fun file(card: DrillCard, bin: DrillBin) {
        val target = binBounds[bin]?.center?.minus(deckCentre) ?: Offset.Zero
        scope.launch {
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            listOf(
                launch { cardOffset.animateTo(target, tween(280)) },
                launch { flyScale.animateTo(0.12f, tween(280)) },
                launch { flyAlpha.animateTo(0f, tween(280)) },
            ).forEach { it.join() }
            apply(card, bin)
            cardOffset.snapTo(Offset.Zero); flyScale.snapTo(1f); flyAlpha.snapTo(1f)
            dragging = false; activeBin = null; cancelActive = false
        }
    }

    /** Back where it was, ungraded. A short drag and an explicit cancel end
     *  the same way on purpose: nothing is written either time. */
    fun springBack() {
        scope.launch {
            cardOffset.animateTo(Offset.Zero, spring(dampingRatio = 0.75f, stiffness = 400f))
            dragging = false; activeBin = null; cancelActive = false
        }
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
                            Text(
                                stringResource(R.string.lld_of_lld,
                                    (resolved + 1).coerceAtMost(resolved + deck.size),
                                    resolved + deck.size) +
                                    // The rest of the due pile didn't vanish, it
                                    // just isn't in this hand.
                                    if (remainingDue > 0)
                                        stringResource(R.string.lld_waiting, remainingDue) else "",
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
                        // Nothing due at all is a different day from a deck
                        // just finished — one is "come back after a talk",
                        // the other is "nice work".
                        finishedCount = resolved,
                        remainingDue = remainingDue,
                        onNext = if (remainingDue > 0) ({ scope.launch { resolved = 0; dealHand() } }) else null,
                        modifier = Modifier.weight(1f),
                    )
                }
            } else {
                Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp),
                    contentAlignment = Alignment.Center) {
                    // A peek of the next card, so the hand reads as a DECK.
                    // A recall card stays concealed back here, or the answer
                    // leaks while the one in front is still being graded.
                    deck.getOrNull(1)?.let { next ->
                        DrillCardFace(
                            card = next,
                            revealed = next.sourcePhrase.isBlank(),
                            modifier = Modifier.fillMaxWidth()
                                .graphicsLayer {
                                    scaleX = 0.95f; scaleY = 0.95f; alpha = 0.45f
                                    translationY = 14.dp.toPx()
                                },
                        )
                    }
                    DrillCardFace(
                        card = top,
                        revealed = revealed,
                        actions = {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                CardPill(
                                    icon = if (hearing) null else Icons.AutoMirrored.Filled.VolumeUp,
                                    label = stringResource(if (hearing) R.string.loading else R.string.hear_it),
                                    enabled = voiceId.isNotBlank() && !hearing,
                                ) {
                                    hearing = true
                                    scope.launch {
                                        runCatching {
                                            val audio = ElevenLabsClient(AuthRepository()).synthesize(
                                                voiceId, top.targetPhrase, purpose = "drill")
                                            player.play(audio)
                                        }
                                        hearing = false
                                    }
                                }
                                CardPill(Icons.Filled.GraphicEq, stringResource(R.string.shadow)) {
                                    onShadow(top.targetPhrase)
                                }
                                CardPill(Icons.Filled.MenuBook, stringResource(R.string.examples)) {
                                    enrichFor = top
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .onGloballyPositioned {
                                if (!dragging) deckCentre = it.boundsInWindow().center
                            }
                            .graphicsLayer {
                                translationX = cardOffset.value.x
                                translationY = cardOffset.value.y
                                // Tilts with the pull, the way a held card does.
                                rotationZ = cardOffset.value.x / 20f
                                scaleX = flyScale.value; scaleY = flyScale.value
                                alpha = flyAlpha.value
                            }
                            .pointerInput(top.id, revealed) {
                                // No grading before recall: the card doesn't
                                // move until it has been turned over.
                                if (!revealed) return@pointerInput
                                val deadZone = with(density) { 24.dp.toPx() }
                                val commit = with(density) { 48.dp.toPx() }
                                val cancelPull = with(density) { 90.dp.toPx() }
                                val hysteresis = with(density) { 20.dp.toPx() }
                                detectDragGestures(
                                    onDragStart = { dragging = true },
                                    onDragCancel = { springBack() },
                                    onDragEnd = {
                                        val moved = cardOffset.value.getDistance()
                                        val bin = activeBin
                                        if (!cancelActive && bin != null && moved > commit) file(top, bin)
                                        else springBack()
                                    },
                                ) { change, delta ->
                                    change.consume()
                                    scope.launch { cardOffset.snapTo(cardOffset.value + delta) }
                                    val o = cardOffset.value
                                    // Direction decides the KIND of target before
                                    // position decides which folder: the folders are
                                    // at the bottom, so pulling up already means
                                    // "away from all of them".
                                    when {
                                        o.getDistance() <= deadZone -> {
                                            if (activeBin != null || cancelActive) {
                                                activeBin = null; cancelActive = false
                                            }
                                        }
                                        o.y < -cancelPull -> {
                                            if (!cancelActive) {
                                                cancelActive = true; activeBin = null
                                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                            }
                                        }
                                        else -> {
                                            cancelActive = false
                                            val x = deckCentre.x + o.x
                                            val candidate = binBounds.entries
                                                .minByOrNull { kotlin.math.abs(it.value.center.x - x) }?.key
                                            val current = activeBin
                                            val currentDist = current?.let {
                                                binBounds[it]?.let { r -> kotlin.math.abs(r.center.x - x) }
                                            }
                                            val candidateDist = candidate?.let {
                                                binBounds[it]?.let { r -> kotlin.math.abs(r.center.x - x) }
                                            }
                                            // Sticky between two FOLDERS only, so a
                                            // wobble doesn't flicker the target.
                                            val sticky = current != null && currentDist != null &&
                                                candidateDist != null && currentDist - candidateDist <= hysteresis
                                            if (candidate != null && candidate != current && !sticky) {
                                                activeBin = candidate
                                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                            }
                                        }
                                    }
                                }
                            }
                            .clickable(indication = null,
                                interactionSource = remember { MutableInteractionSource() }) {
                                if (!revealed) revealed = true
                            },
                    )
                }

                if (!revealed) {
                    Text(stringResource(R.string.drag_the_card_into_a_folder),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp))
                }

                if (dragging) {
                    // Above the row and centred: the folders are a decision,
                    // and this is the way past it, so it sits on the path back
                    // to the card rather than at the end of the row where it
                    // would read as a fifth folder.
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                        Box(
                            Modifier.size(44.dp)
                                .background(
                                    if (cancelActive) MaterialTheme.colorScheme.onSurfaceVariant
                                    else MaterialTheme.colorScheme.surfaceVariant, CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Filled.Close, contentDescription = null,
                                modifier = Modifier.size(20.dp),
                                tint = if (cancelActive) MaterialTheme.colorScheme.surface
                                else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                VerdictRow(
                    dragging = dragging,
                    active = activeBin.takeIf { dragging && !cancelActive },
                    tappable = revealed,
                    counts = { bin ->
                        if (bin == DrillBin.GOT_IT) finished else (scheduled[bin] ?: 0)
                    },
                    // "Got it" has nothing to list: marking a card known
                    // CLEARS its return date, so there is no waiting to show.
                    onOpen = { bin ->
                        if (revealed && top != null) file(top, bin)
                        else if (bin != DrillBin.GOT_IT) openFolder = bin
                    },
                    onBounds = { bin, rect -> binBounds = binBounds + (bin to rect) },
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
                // What happens if you let go HERE. Named, so the decision is
                // readable before it is made.
                if (dragging) {
                    Text(
                        when {
                            cancelActive -> stringResource(R.string.leave_it_undecided)
                            activeBin != null -> stringResource(activeBin!!.dropHintRes)
                            else -> stringResource(R.string.drop_it_on_a_folder)
                        },
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.fillMaxWidth().padding(bottom = 6.dp),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                }
            }
        }
    }

    openFolder?.let { bin ->
        DrillFolderSheet(
            bin = bin,
            cards = folderCards[bin].orEmpty(),
            onRefile = { card, target ->
                scope.launch {
                    val manual = target.manual
                    if (manual == null) store.markKnown(card, language)
                    else store.fileInBin(card, manual.first, manual.second, language)
                    refreshFolders()
                    StoreEvents.bump()
                }
                openFolder = null
            },
            onDismiss = { openFolder = null })
    }

    enrichFor?.let { card ->
        DrillEnrichmentSheet(
            card = card,
            persona = persona,
            targetLanguage = language,
            nativeLanguage = nativeLanguage,
            onDismiss = { enrichFor = null },
        )
    }

}

/**
 * The card. The learner's own slip on the front (struck through once the
 * fluent line is showing, so the pair reads as a correction), the fluent line
 * and its reason on the back.
 */
@Composable
private fun DrillCardFace(
    card: DrillCard,
    revealed: Boolean,
    modifier: Modifier = Modifier,
    /** Hear it · Shadow · Examples — on the card, as on iOS, so a dragged
     *  card carries them instead of sliding under them. */
    actions: (@Composable () -> Unit)? = null,
) {
    val onCard = Color.White
    val onCardSecondary = Color.White.copy(alpha = 0.72f)
    Box(
        modifier
            .heightIn(min = 240.dp)
            // The accent IS the card, so it needs its own lift off the page.
            .shadow(8.dp, RoundedCornerShape(18.dp),
                ambientColor = MaterialTheme.colorScheme.primary,
                spotColor = MaterialTheme.colorScheme.primary)
            .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(18.dp))
            .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(18.dp))
            .padding(24.dp),
    ) {
    Column(
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Text(
            stringResource(
                if (revealed) R.string.when_should_it_come_back
                else R.string.say_it_out_loud_do_you_know_it),
            style = MaterialTheme.typography.labelMedium, color = onCardSecondary,
        )
        if (card.sourcePhrase.isNotBlank()) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.you_said), style = MaterialTheme.typography.labelSmall,
                    color = onCardSecondary)
                // Cards minted before the fragment trim carry the WHOLE turn,
                // so trim at render too — a minute-long transcript struck
                // through reads as "everything you said was wrong".
                Text(DrillIngest.relevantFragment(card.sourcePhrase, card.targetPhrase),
                    style = MaterialTheme.typography.titleMedium,
                    color = if (revealed) onCardSecondary else onCard,
                    textDecoration = if (revealed) TextDecoration.LineThrough else null)
            }
        }

        if (revealed) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.try_saying), style = MaterialTheme.typography.labelSmall,
                    color = onCardSecondary)
                Text(card.targetPhrase, style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold, color = onCard)
                if (card.reason.isNotBlank()) {
                    Text(stringResource(R.string.why_label), style = MaterialTheme.typography.labelSmall,
                        color = onCardSecondary, modifier = Modifier.padding(top = 4.dp))
                    Text(card.reason, style = MaterialTheme.typography.bodyMedium,
                        color = onCardSecondary)
                }
            }
        }
        if (revealed && actions != null) actions()
    }
    // Pinned to the floor of the card, not pushed there by a spacer that
    // would stretch the card itself.
    if (!revealed) {
        Row(Modifier.align(Alignment.BottomStart),
            verticalAlignment = Alignment.CenterVertically,
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
    /** The folder the card is over. Only this one lights up. */
    active: DrillBin? = null,
    /** A revealed card is in hand, so every folder is a target. */
    tappable: Boolean = false,
    counts: (DrillBin) -> Int,
    onBounds: (DrillBin, Rect) -> Unit,
    onOpen: ((DrillBin) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        DrillBin.entries.forEach { bin ->
            Column(
                Modifier.weight(1f)
                    .onGloballyPositioned { onBounds(bin, it.boundsInWindow()) }
                    .then(if (onOpen != null && !dragging && (tappable || counts(bin) > 0))
                        Modifier.clickable { onOpen(bin) } else Modifier)
                    .graphicsLayer {
                        val on = bin == active
                        scaleX = if (on) 1.08f else 1f; scaleY = if (on) 1.08f else 1f
                    }
                    .background(
                        if (bin == active) bin.tint
                        else bin.tint.copy(alpha = if (dragging) 0.20f else 0.12f),
                        RoundedCornerShape(12.dp))
                    .padding(vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                val onTarget = bin == active
                Icon(bin.icon, contentDescription = null,
                    tint = if (onTarget) Color.White else bin.tint,
                    modifier = Modifier.size(18.dp))
                Text(stringResource(if (dragging) bin.titleRes else bin.folderTitleRes),
                    style = MaterialTheme.typography.labelSmall,
                    color = if (onTarget) Color.White else MaterialTheme.colorScheme.onSurface)
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
private fun DeckDone(
    folders: List<Pair<DrillBin, Int>>,
    finishedCount: Int = 0,
    remainingDue: Int = 0,
    onNext: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier.fillMaxWidth().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(stringResource(
            if (finishedCount == 0) R.string.no_drills_due else R.string.nice_work),
            style = MaterialTheme.typography.titleMedium)
        Text(
            when {
                finishedCount == 0 -> stringResource(R.string.drills_appear_here_after_you_end_a_conversation)
                remainingDue > 0 -> stringResource(
                    R.string.you_finished_lld_cards_lld_more_are_waiting_when_you_re_read_985087,
                    finishedCount, remainingDue)
                else -> stringResource(
                    R.string.you_finished_lld_card_they_ll_surface_again_on_the_leitner_s_38019a,
                    finishedCount, "")
            },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        if (onNext != null) {
            Button(onClick = onNext) {
                Text(stringResource(R.string.next_lld, minOf(remainingDue, SESSION_CAP)))
            }
        }
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

/** One sitting's worth. A 399-card queue dealt in full is not a review, it
 *  is a wall (iOS `DrillSheet.sessionCap`). */
private const val SESSION_CAP = 20

/** A pill ON the accent card: outlined in the card's own white, never a
 *  system chip, which would bring the page's surface onto the card. */
@Composable
private fun CardPill(
    icon: androidx.compose.ui.graphics.vector.ImageVector?,
    label: String,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val tint = Color.White.copy(alpha = if (enabled) 1f else 0.5f)
    Row(
        Modifier.border(1.dp, Color.White.copy(alpha = 0.35f), RoundedCornerShape(999.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        if (icon == null) CircularProgressIndicator(Modifier.size(13.dp), strokeWidth = 2.dp, color = tint)
        else Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(15.dp))
        Text(label, style = MaterialTheme.typography.labelMedium, color = tint)
    }
}
