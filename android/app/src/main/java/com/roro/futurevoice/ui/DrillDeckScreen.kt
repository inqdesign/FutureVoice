package com.roro.futurevoice.ui

import androidx.compose.material.icons.filled.Visibility
import com.roro.futurevoice.ui.brand.ContinuousShape
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.material.icons.filled.Close
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.Animatable
import com.roro.futurevoice.ui.brand.IosButton as Button
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
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
    /** A per-item reminder's card: dealt on its own, whether or not it is due
     *  yet (the learner tapped the notification that named it). */
    focusCardId: String? = null,
    /** One talk's cards, due or not — the book's "Review this talk" (iOS
     *  `DrillView(source: .session)`). Anything left joins the normal queue. */
    sessionId: String? = null,
    onBack: () -> Unit,
    /** The sheet's title — iOS names the deck by where it was opened:
     *  "Review" from Practice and a talk book, "Grammar" from a chapter,
     *  "Sentences" from the old DrillSheet. Null = "Review". */
    title: String? = null,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { DrillStore.shared(context) }

    var deck by remember { mutableStateOf<List<DrillCard>>(emptyList()) }
    var dealt by remember { mutableStateOf(false) }
    var resolved by remember { mutableIntStateOf(0) }
    var revealed by remember { mutableStateOf(false) }
    /** Everything not due now: the three delay windows, plus Known for the
     *  cards that retired there. */
    var scheduled by remember { mutableStateOf<Map<DrillBin, Int>>(emptyMap()) }
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
        // A retired card has no return date, so it belongs in Known rather
        // than in a window on when it comes back (iOS `1ab175d`). It is
        // listed there, and re-filing it from the folder is what brings it
        // back — the learner's call, not the ladder's.
        folderCards = store.load(language)
            .filter { it.nextReviewAt > now }
            .groupBy {
                if (com.roro.futurevoice.data.DrillIngest.isRetired(it)) DrillBin.GOT_IT
                else DrillBin.folder(it.nextReviewAt - now)
            }
        scheduled = folderCards.mapValues { it.value.size }
    }

    suspend fun dealHand() {
        val focused = focusCardId?.let { id -> store.load(language).firstOrNull { it.id == id } }
        val due = when {
            focused != null -> listOf(focused)
            sessionId != null -> store.load(language).filter {
                it.sourceSessionId == sessionId && !com.roro.futurevoice.data.DrillIngest.isRetired(it)
            }
            else -> store.due(language)
        }
        // The routine's review number when today has one (iOS `b905ac2`).
        deck = due.take(com.roro.futurevoice.data.GoalStore.target(context,
            com.roro.futurevoice.data.StudyPlan.Kind.REVIEW) ?: SESSION_CAP)
        remainingDue = (due.size - deck.size).coerceAtLeast(0)
        dealt = true
        refreshFolders()
    }

    LaunchedEffect(language) {
        dealHand()
        if (com.roro.futurevoice.capture.flags.PracticeCaptureFlags.previewDrillFolder) openFolder = DrillBin.TOMORROW
    }

    val top = deck.firstOrNull()
    LaunchedEffect(top?.id) {
        revealed = false
        // Capture seams: the tray is drag-only and a folder is tap-only, so a
        // screenshot can't reach either without being put there.
        if (top != null && com.roro.futurevoice.capture.flags.PracticeCaptureFlags.previewDrillTray) {
            revealed = true; dragging = true; activeBin = DrillBin.TOMORROW
            cardOffset.snapTo(with(density) { Offset(40.dp.toPx(), 150.dp.toPx()) })
        }
    }

    fun apply(card: DrillCard, bin: DrillBin) {
        scope.launch {
            val manual = bin.manual
            if (manual != null) {
                store.fileInBin(card, manual.first, manual.second, language)
                // Filed by hand = a promise about THIS line: it gets its own callback.
                com.roro.futurevoice.data.ReviewQueue.armSentence(context, card,
                    System.currentTimeMillis() + manual.second)
            } else {
                store.markKnown(card, language)
                com.roro.futurevoice.data.ReviewQueue.cancelSentence(context, card.id)
            }
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
            // A sheet, as on iOS: the deck's name centred, Done on the right,
            // no back arrow. The count sits under the bar, in the deck.
            androidx.compose.material3.CenterAlignedTopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = {
                    Text(title ?: stringResource(R.string.review),
                        style = MaterialTheme.typography.titleMedium)
                },
                actions = {
                    androidx.compose.material3.TextButton(onClick = onBack) {
                        Text(stringResource(R.string.done), style = MaterialTheme.typography.titleMedium)
                    }
                },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // No progress bar: iOS draws none — the deck is a pile, not a
            // quiz with a finish line (gallery 4.2).

            // "1 of 20 · 6 waiting" (iOS `counterRow`): the rest of the due
            // pile didn't vanish, it just isn't in this hand.
            if (top != null && (deck.isNotEmpty() || resolved > 0)) {
                Text(
                    stringResource(R.string.lld_of_lld,
                        (resolved + 1).coerceAtMost(resolved + deck.size),
                        resolved + deck.size) +
                        if (remainingDue > 0) stringResource(R.string.lld_waiting, remainingDue) else "",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 12.dp))
            }
            if (top == null) {
                if (dealt) {
                    DeckDone(
                        folders = DrillBin.entries.map { bin ->
                            bin to (scheduled[bin] ?: 0)
                        },
                        // Nothing due at all is a different day from a deck
                        // just finished — one is "come back after a talk",
                        // the other is "nice work".
                        finishedCount = resolved,
                        remainingDue = remainingDue,
                        onNext = if (remainingDue > 0) ({ scope.launch { resolved = 0; dealHand() } }) else null,
                        onOpen = { bin -> openFolder = bin },
                        modifier = Modifier.weight(1f),
                    )
                }
            } else {
                // The panel FLOATS over the bottom of the deck (iOS
                // `cardDeck.overlay`): the card keeps its at-rest size mid-drag,
                // so its own Hear it · Shadow · Examples row still shows under
                // the folders, and the card never moves out from under the finger.
                Box(Modifier.weight(1f).fillMaxWidth()) {
                Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                    contentAlignment = Alignment.Center) {
                    // A peek of the next card, so the hand reads as a DECK.
                    // A recall card stays concealed back here, or the answer
                    // leaks while the one in front is still being graded.
                    deck.getOrNull(1)?.let { next ->
                        DrillCardFace(
                            card = next,
                            revealed = next.sourcePhrase.isBlank(),
                            modifier = Modifier.fillMaxSize()
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
                                            val audio = com.roro.futurevoice.data.cachedSynthesis(
                                                context, voiceId, top.targetPhrase, purpose = "drill")
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
                            .fillMaxSize()
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

                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp)
                    .graphicsLayer { alpha = if (dragging) 0f else 1f },
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.TouchApp, contentDescription = null,
                        modifier = Modifier.size(15.dp),
                        tint = MaterialTheme.colorScheme.outline)
                    Spacer(Modifier.size(6.dp))
                    Text(stringResource(
                        if (revealed) R.string.drag_the_card_into_a_folder
                        else R.string.say_it_out_loud_then_tap_the_card_to_check),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                // At rest the folders are quiet counters; mid-drag the panel
                // takes their place, so these keep their room but go clear.
                VerdictRow(
                    dragging = false,
                    tappable = revealed,
                    counts = { bin -> scheduled[bin] ?: 0 },
                    onOpen = { bin ->
                        if (dragging) Unit
                        else if (revealed && top != null) file(top, bin)
                        else openFolder = bin
                    },
                    onBounds = { _, _ -> },
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                        .graphicsLayer { alpha = if (dragging) 0f else 1f },
                )
                }
                if (dragging) Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
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
                    VerdictRow(
                        dragging = true,
                        active = activeBin.takeIf { !cancelActive },
                        tappable = revealed,
                        counts = { bin -> scheduled[bin] ?: 0 },
                        onBounds = { bin, rect -> binBounds = binBounds + (bin to rect) },
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    // What happens if you let go HERE. Named, so the decision is
                    // readable before it is made.
                    Row(Modifier.fillMaxWidth().padding(bottom = 6.dp),
                        horizontalArrangement = Arrangement.Center) {
                        Text(
                            when {
                                cancelActive -> stringResource(R.string.leave_it_undecided)
                                activeBin != null -> stringResource(activeBin!!.dropHintRes)
                                else -> stringResource(R.string.drop_it_on_a_folder)
                            },
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier
                                .background(MaterialTheme.colorScheme.surface, ContinuousShape(999.dp))
                                .padding(horizontal = 12.dp, vertical = 5.dp),
                        )
                    }
                }
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
                    if (manual == null) {
                        store.markKnown(card, language)
                        com.roro.futurevoice.data.ReviewQueue.cancelSentence(context, card.id)
                    } else {
                        store.fileInBin(card, manual.first, manual.second, language)
                        com.roro.futurevoice.data.ReviewQueue.armSentence(context, card,
                            System.currentTimeMillis() + manual.second)
                    }
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
    Column(
        modifier
            .heightIn(min = 240.dp)
            // The accent IS the card, so it needs its own lift off the page.
            .shadow(10.dp, ContinuousShape(22.dp),
                ambientColor = MaterialTheme.colorScheme.primary,
                spotColor = MaterialTheme.colorScheme.primary)
            .background(MaterialTheme.colorScheme.primary, ContinuousShape(22.dp))
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        if (card.sourcePhrase.isNotBlank()) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                // The LABEL "You said" — `you_said` is the quoting sentence
                // with a %s, which printed its placeholder here.
                Text(stringResource(R.string.you_said_f105ab), style = MaterialTheme.typography.bodyMedium,
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

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                stringResource(
                    if (revealed) R.string.try_saying
                    else R.string.how_would_a_fluent_speaker_say_it),
                style = MaterialTheme.typography.bodyMedium, color = onCardSecondary)
            if (revealed) {
                Text(card.targetPhrase, style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold, color = onCard)
            } else {
                // The ANSWER's shape, greyed: a blank space reads as a card
                // that failed to load, and the line lengths tell the learner
                // how much they are being asked to produce.
                listOf(1f, 1f, 0.55f).forEach { fraction ->
                    Box(
                        Modifier.fillMaxWidth(fraction).height(22.dp)
                            .background(Color.White.copy(alpha = 0.22f), ContinuousShape(6.dp)))
                }
            }
        }

        if (revealed && card.reason.isNotBlank()) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.why_label), style = MaterialTheme.typography.bodyMedium,
                    color = onCardSecondary)
                Text(card.reason, style = MaterialTheme.typography.bodyMedium,
                    color = onCardSecondary)
            }
        }

        Spacer(Modifier.weight(1f))

        if (revealed) {
            actions?.invoke()
        } else {
            // Centred on the floor of the card: the one thing to do with a
            // card whose answer is still hidden.
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Visibility, contentDescription = null,
                    tint = onCard, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(8.dp))
                Text(stringResource(R.string.tap_to_reveal),
                    style = MaterialTheme.typography.bodyLarge, color = onCard)
            }
        }
    }
}


/** The four verdicts — folder counters at rest, drop targets mid-drag.
 *  Shared with the word/expression deck: one drag must mean one thing, so
 *  the two decks cannot draw their folders differently. */
@Composable
internal fun VerdictRow(
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
            val onTarget = bin == active
            val n = counts(bin)
            // At rest these are PLACES — a quiet pill with its count. Mid-drag
            // they are TARGETS, and a target has to look like somewhere a card
            // can land, so it grows a face and says what it would do.
            Column(
                Modifier.weight(1f)
                    .onGloballyPositioned { onBounds(bin, it.boundsInWindow()) }
                    .graphicsLayer {
                        scaleX = if (onTarget) 1.08f else 1f
                        scaleY = if (onTarget) 1.08f else 1f
                    }
                    .background(
                        when {
                            onTarget -> bin.tint
                            dragging -> MaterialTheme.colorScheme.surface
                            else -> MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f)
                        },
                        RoundedCornerShape(if (dragging) 14.dp else 999.dp))
                    .then(if (onOpen != null && !dragging && (tappable || n > 0))
                        Modifier.clickable { onOpen(bin) } else Modifier)
                    .padding(vertical = if (dragging) 12.dp else 7.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                if (dragging) {
                    Icon(bin.icon, contentDescription = null,
                        tint = if (onTarget) Color.White else bin.tint,
                        modifier = Modifier.size(20.dp))
                    Text(stringResource(bin.titleRes),
                        style = MaterialTheme.typography.labelSmall,
                        color = if (onTarget) Color.White else MaterialTheme.colorScheme.onSurface)
                } else {
                    // Icon and count only: the folder's NAME is inside it, and
                    // four labelled boxes at rest read as a button bar.
                    Row(verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        Icon(bin.icon, contentDescription = stringResource(bin.folderTitleRes),
                            tint = bin.tint, modifier = Modifier.size(16.dp))
                        Text(if (n == 0) "—" else "$n",
                            style = MaterialTheme.typography.labelLarge,
                            color = if (n == 0) MaterialTheme.colorScheme.outline else bin.tint)
                    }
                }
            }
        }
    }
}


/**
 * The last card is gone — `DrillSheet.emptyState`.
 *
 * A glyph, then what happened, then the one thing left to do, and the folders
 * stay reachable underneath. Those folders are the SAME row the deck drags
 * onto: "so where did all that go?" is asked here, and answering it with a
 * second, differently-shaped row would make the drag's destination look like
 * somewhere else.
 */
@Composable
private fun DeckDone(
    folders: List<Pair<DrillBin, Int>>,
    finishedCount: Int = 0,
    remainingDue: Int = 0,
    onNext: (() -> Unit)? = null,
    onOpen: (DrillBin) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val finished = finishedCount > 0
    Column(
        modifier.fillMaxWidth().padding(32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        // Nothing due at all is a different day from a deck just finished —
        // one is "come back after a talk", the other is "nice work" — so the
        // glyph differs too.
        Icon(
            if (finished) Icons.Filled.CheckCircle else Icons.Outlined.Lightbulb,
            contentDescription = null,
            tint = if (finished) Color(0xFF34C759) else MaterialTheme.colorScheme.outline,
            modifier = Modifier.size(44.dp),
        )
        Text(stringResource(if (finished) R.string.nice_work else R.string.no_drills_due),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold)
        Text(
            when {
                !finished -> stringResource(R.string.drills_appear_here_after_you_end_a_conversation)
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
            Button(onClick = onNext, modifier = Modifier.padding(top = 4.dp)) {
                Text(stringResource(R.string.next_lld, minOf(remainingDue, SESSION_CAP)))
            }
        }
        VerdictRow(
            dragging = false,
            tappable = true,
            counts = { bin -> folders.firstOrNull { it.first == bin }?.second ?: 0 },
            onBounds = { _, _ -> },
            onOpen = onOpen,
            modifier = Modifier.padding(top = 8.dp),
        )
        Spacer(Modifier.weight(1f))
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
        Modifier.border(1.dp, Color.White.copy(alpha = 0.35f), ContinuousShape(999.dp))
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
