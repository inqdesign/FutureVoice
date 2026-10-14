package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.union
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.GpsFixed
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.input.pointer.pointerInput
import com.roro.futurevoice.talk.GreetingEngine
import com.roro.futurevoice.talk.VoicePreset
import kotlin.math.max
import androidx.compose.foundation.border
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.People
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.graphics.graphicsLayer
import com.roro.futurevoice.ui.brand.ContinuousShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.PlayCircleFilled
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.CounterpartStore
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.Symbols

/**
 * A situation idea tapped on a person's page (iOS `ComposerConfig.situation`,
 * 2026-09-30): the People page closes and the Watch tab opens the writing door
 * with that person and that line written in. Parked here because the page and
 * the tab are different branches of the root.
 */
internal object WatchComposeRequest {
    val pending = kotlinx.coroutines.flow.MutableStateFlow<Pair<Counterpart, String>?>(null)
}

/**
 * The Watch header's half of the map (iOS `WatchTab` toolbar): the lens and
 * the saved-situations sheet are chosen up there and drawn down here.
 */
internal object WatchSky {
    val lens = kotlinx.coroutines.flow.MutableStateFlow(PeopleSky.Lens.ALL)
    val showingSaved = kotlinx.coroutines.flow.MutableStateFlow(false)
}

/**
 * Whether the Watch tab is writing a new situation (iOS `WatchCreation`): the
 * tab bar steps aside, the box shows under the map, Cancel takes the title's
 * place in the header. Lives outside the tab because the header and the tab
 * bar are drawn by the home shell.
 */
internal object WatchCreation {
    val creating = kotlinx.coroutines.flow.MutableStateFlow(false)
    /** The header's Cancel, handed to the tab (the keyboard goes down first). */
    val cancelTick = kotlinx.coroutines.flow.MutableStateFlow(0)
    /** Who the open box is with. Kept here, beside [creating], because the
     *  tab leaves composition while a scene plays (iOS keeps WatchTab alive
     *  under the cover): coming back found the box still open but with the
     *  composer's default person instead of the one the scene was with. */
    var dockPerson: com.roro.futurevoice.data.Counterpart? = null
}

/**
 * Watch — simulate a specific situation BEFORE it happens (iOS `WatchTab`).
 * Since 1.1.8 (iOS fe83c0f1) the tab IS the people map ([PeopleSkyMap]): a
 * saved situation is almost never played again, but the people in a
 * learner's life come back. With the situation dock (iOS 418314a0, on in
 * release): whoever comes to the middle of the screen greets the learner in
 * their own voice; a tap on someone floats their card over the map; "New
 * situation" (or the card's "Make a situation", or a tap on their greeting)
 * lifts the situation box under the map, the tab bar steps aside and the
 * header gets Cancel. Every situation made before the map lives in the
 * header's list sheet.
 *
 * Minting a scenario PLAYS it. A saved scenario is a reusable TEMPLATE:
 * tapping its card opens it in edit mode, whose CTA writes a fresh take.
 */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
internal fun WatchTabBody(
    language: String,
    enabled: Boolean,
    /** This tab is the one on screen. A hidden tab stays composed, so its
     *  onDispose never runs on a tab switch — iOS stops the voice in
     *  `.onDisappear`, and this is that moment. */
    visible: Boolean = true,
    onWatch: (String) -> Unit,
    meName: String = "",
    /** The learner in the middle — their page. */
    onOpenProfile: () -> Unit = {},
    /** The card's Talk: a call with them (already gated by the caller). */
    onTalkWith: (Counterpart) -> Unit = {},
    /** The card's Watch: a scene of the two of them (gated by the caller). */
    onWatchWith: (Counterpart) -> Unit = {},
    /** A talk on the card's "Your talks together". */
    onOpenTalk: (String) -> Unit = {},
) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val store = remember { ScenarioStore.shared(context) }
    var scenarios by remember { mutableStateOf<List<Scenario>>(emptyList()) }
    /** Which door the composer opens on, when it is open. */
    var composing by remember { mutableStateOf<ComposerMode?>(null) }
    /** The person a composed scene is scoped to, if any. */
    var withPerson by remember { mutableStateOf<Counterpart?>(null) }
    /** Everyone on file — own people and strangers met. */
    var people by remember { mutableStateOf<List<Counterpart>>(emptyList()) }
    /** The saved scenario open in the composer's EDIT mode, if any. */
    var editingScenario by remember { mutableStateOf<Scenario?>(null) }
    /** The line the writing door opens with — an idea picked on a person's page. */
    var situationPrefill by remember { mutableStateOf("") }
    val lens by WatchSky.lens.collectAsStateWithLifecycle()
    val showingSaved by WatchSky.showingSaved.collectAsStateWithLifecycle()
    /** Find-people strangers, for the map's outer ring. */
    var poolRows by remember { mutableStateOf<List<com.roro.futurevoice.net.PublicPersonaClient.PublicPersona>>(emptyList()) }
    /** Talks per person (sessions aren't published). */
    var talksByPerson by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    /** The map is drawn once the pool is in, so nobody shifts when it lands. */
    var skyReady by remember { mutableStateOf(false) }

    // MARK: The situation dock (iOS 2026-10-12, release from 418314a0)
    val creating by WatchCreation.creating.collectAsStateWithLifecycle()
    fun setCreating(on: Boolean) { WatchCreation.creating.value = on }
    /** Who the box's situation is with — shared both ways with its person chip. */
    var dockPerson by remember { mutableStateOf(WatchCreation.dockPerson) }
    LaunchedEffect(dockPerson) { WatchCreation.dockPerson = dockPerson }
    /** The box was opened from a person's card: no category chips. */
    var dockNoChips by remember { mutableStateOf(false) }
    /** The person whose card floats over the map (a tap on them). */
    var skyCard by remember { mutableStateOf<Counterpart?>(null) }
    /** Panned away from me: "Back to me" shows (drawn here, over the fade). */
    var skyAway by remember { mutableStateOf(false) }
    var backToMeTick by remember { mutableStateOf(0) }
    var dockBubble by remember { mutableStateOf<String?>(null) }
    var dockFill by remember { mutableStateOf("") }
    /** Who is in the middle of the screen, and the pan a pick asks for. */
    var skyCentred by remember { mutableStateOf<Counterpart?>(null) }
    var skyScroll by remember { mutableStateOf<SkyScroll?>(null) }
    var scrollNonce by remember { mutableStateOf(0) }
    /** A pick is panning the map: the people it passes on the way are not
     *  "in the middle", so their bubbles stay down until it lands. */
    var panningUntil by remember { mutableStateOf(0L) }
    var bubbleJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    var previewJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    val isVisible by androidx.compose.runtime.rememberUpdatedState(visible)
    /** Greetings written this visit for strangers (people on file keep theirs). */
    val strangerGreetings = remember { mutableMapOf<String, String>() }
    val previewPlayer = remember { com.roro.futurevoice.audio.Mp3Player(context.cacheDir, source = "voice_preview") }
    LaunchedEffect(visible) { if (!visible) { previewJob?.cancel(); previewPlayer.stop() } }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { previewPlayer.stop() } }
    val imeVisible = WindowInsets.isImeVisible
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    val focusManager = androidx.compose.ui.platform.LocalFocusManager.current

    val composeRequest by WatchComposeRequest.pending.collectAsStateWithLifecycle()
    LaunchedEffect(composeRequest) {
        val (person, line) = composeRequest ?: return@LaunchedEffect
        WatchComposeRequest.pending.value = null
        editingScenario = null
        withPerson = person; situationPrefill = line; composing = ComposerMode.CUSTOM
    }
    val scope = rememberCoroutineScope()
    LaunchedEffect(language, revision) {
        scenarios = store.load(language)
        people = CounterpartStore.shared(context).load()
        talksByPerson = com.roro.futurevoice.data.SessionStore.shared(context).load(language)
            .mapNotNull { it.counterpartId }.groupingBy { it }.eachCount()
    }
    // The map is shown once the pool is IN (or truly failed).
    LaunchedEffect(language) {
        val rows = com.roro.futurevoice.capture.flags.WatchCaptureFlags.samplePool
            ?: runCatching {
                com.roro.futurevoice.net.PublicPersonaClient(com.roro.futurevoice.data.AuthRepository())
                    .fetchPool(language)
            }.getOrNull()
        if (rows != null) {
            poolRows = rows
            val ownStore = CounterpartStore.shared(context)
            if (syncOwnVoices(ownStore, rows)) people = ownStore.load()
        }
        skyReady = true
    }
    LaunchedEffect(Unit) {
        // A pool that never answers must not leave the tab blank.
        kotlinx.coroutines.delay(2500)
        skyReady = true
    }
    val live = scenarios
        .filter { it.archivedAt == null && it.isMeeting != true && it.isTopic != true }
        .sortedByDescending { it.lastUsedAt ?: it.createdAt }

    val metLabel = stringResource(R.string.met_on_nawana)
    val nodes = remember(people, poolRows, scenarios, talksByPerson) {
        skyNodes(people, poolRows, scenarios, talksByPerson, metLabel)
    }
    /** The pool's people not met yet, as they stand on the map. */
    val skyPool = remember(people, poolRows) {
        val met = people.mapNotNull { it.remoteId }.toSet()
        poolRows.filter { it.id !in met }.map { it.asCounterpart(metLabel) }
    }
    fun personFor(id: String): Counterpart? =
        people.firstOrNull { it.id == id } ?: skyPool.firstOrNull { it.id == id }

    /** Put the keyboard away, then do the next thing once it is down. */
    fun afterKeyboard(then: () -> Unit) {
        if (!imeVisible) { then(); return }
        keyboard?.hide(); focusManager.clearFocus()
        scope.launch { kotlinx.coroutines.delay(300); then() }
    }

    /** Their voice as their bubble rises. A person from the pool reads the
     *  start of their own intro in their own voice — clips that ship with the
     *  app (`assets/people_voices`, the files iOS bundles), so scrolling past
     *  people spends nothing. Your own people fall back to their preset's
     *  sample; a voice with no clip stays silent rather than paying for one. */
    fun playVoicePreview(person: Counterpart) {
        previewJob?.cancel(); previewPlayer.stop()
        if (!isVisible) return
        val lang = language.substringBefore('-')
        fun asset(path: String) = runCatching { context.assets.open(path).use { it.readBytes() } }.getOrNull()
        var bytes: ByteArray? = null
        val rid = person.remoteId
        if (rid != null && !rid.startsWith("builtin:")) bytes = asset("people_voices/intro-${rid.lowercase()}.mp3")
        if (bytes == null && person.voicePresetId.isNotEmpty()) {
            bytes = asset("voice_previews/preview-$lang-${person.voicePresetId}.mp3")
        }
        val audio = bytes ?: return
        previewJob = scope.launch { runCatching { previewPlayer.play(audio) } }
    }

    /** Their greeting, over their face: the line written for them (in the
     *  person form, or at publish for someone from the pool), else one written
     *  now — kept on a person on file, remembered this visit for a stranger. */
    suspend fun sayGreeting(person: Counterpart) {
        val lang = language
        val people0 = CounterpartStore.shared(context)
        val onFile = people0.load().firstOrNull { it.id == person.id }
        // A person on file whose line came from an older prompt is written
        // again before it is shown (the learner's own line never is).
        if (onFile != null && onFile.greetingNeedsWriting(lang, GreetingEngine.PROMPT_VERSION)
            && onFile.greeting(lang).isNotEmpty()) {
            GreetingEngine.ensure(context, onFile, lang)
        }
        var line = (people0.load().firstOrNull { it.id == person.id } ?: person).greeting(lang)
        if (line.isEmpty()) line = strangerGreetings[person.id].orEmpty()
        if (line.isEmpty()) {
            if (onFile != null) {
                GreetingEngine.ensure(context, onFile, lang)
                line = people0.load().firstOrNull { it.id == person.id }?.greeting(lang).orEmpty()
            } else {
                val fresh = runCatching {
                    GreetingEngine.write(person, com.roro.futurevoice.data.PersonaStore.shared(context).load(), lang)
                }.getOrNull()
                if (fresh != null) { strangerGreetings[person.id] = fresh; line = fresh }
            }
        }
        if (line.isEmpty() || skyCentred?.id != person.id) return
        dockBubble = line
        // Felt as they speak: one firm tap as the bubble rises.
        HapticEngine.medium(context)
        playVoicePreview(person)
    }

    /** Someone came to the middle of the screen (or nobody is there now).
     *  Their bubble rises once they have settled there. */
    fun centre(id: String?, force: Boolean = false) {
        if (!force && System.currentTimeMillis() < panningUntil) return
        // Already the one in the middle: their greeting and voice stand.
        // Tapping them again, or opening the box with them, must not say it
        // all a second time.
        if (id == skyCentred?.id) return
        bubbleJob?.cancel()
        dockBubble = null
        previewJob?.cancel(); previewPlayer.stop()
        val person = id?.let { personFor(it) }
        skyCentred = person
        if (person == null) return
        bubbleJob = scope.launch {
            kotlinx.coroutines.delay(450)
            sayGreeting(person)
        }
    }

    /** Pan to someone; once there, they are the one in the middle. */
    fun panTo(id: String) {
        panningUntil = System.currentTimeMillis() + 700
        scrollNonce += 1
        skyScroll = SkyScroll(id, scrollNonce)
        scope.launch { kotlinx.coroutines.delay(750); centre(id, force = true) }
    }

    /** A tap on someone: their card floats up over the bottom of the map and
     *  they come to the middle, above it, where their greeting rises. */
    fun openSkyCard(c: Counterpart) {
        skyCard = c
        panTo(c.id)
    }

    /** Out of the box and back to a person's card, in one motion — the step
     *  before "Make a situation", never the old full sheet. One thing at a
     *  time: the keyboard goes down first, then the box gives way. */
    fun leaveBoxForCard(c: Counterpart) {
        afterKeyboard {
            setCreating(false)
            dockFill = ""
            openSkyCard(c)
        }
    }

    /** With the box or a card up, a tap on the map is only "put it away" —
     *  even one that lands on someone. Picking a person happens from the bare map. */
    fun putAway(): Boolean {
        if (creating) {
            val p = dockPerson
            if (p != null) leaveBoxForCard(p) else afterKeyboard { setCreating(false) }
            return true
        }
        if (skyCard != null) { skyCard = null; return true }
        return false
    }

    /** The card's "Make a situation": the card goes down as the box comes up,
     *  in one motion, with them already the person it's with. */
    fun composeFromCard(c: Counterpart) {
        skyCard = null
        dockNoChips = true
        setCreating(true)
        dockPerson = c
    }

    /** Meeting someone from the pool files them, like the full card does. */
    suspend fun savedFromCard(c: Counterpart): Counterpart {
        val ownStore = CounterpartStore.shared(context)
        ownStore.load().firstOrNull { it.id == c.id }?.let { return it }
        ownStore.save(c)
        StoreEvents.bump()
        return ownStore.load().firstOrNull { it.id == c.id } ?: c
    }

    /** Tapping their greeting answers it: the box opens with them as the
     *  person the situation is with. */
    fun tapBubble() {
        val person = skyCentred ?: return
        setCreating(true)
        dockPerson = person
    }

    /** A chip in the box picks the person that situation is with — someone of
     *  the learner's own first, then a stranger already met, then one from the
     *  pool. No match leaves the box's person as it was. */
    fun pickDockCategory(title: String) {
        val jobs = poolRows.associate { it.id to it.occupation }
        val candidates = people.filter { it.remoteId == null } +
            people.filter { it.remoteId != null } + skyPool
        val match = candidates.firstOrNull { watchFits(it, title, it.remoteId?.let { r -> jobs[r] }) } ?: return
        dockPerson = match
    }

    LaunchedEffect(creating) {
        if (!creating) dockNoChips = false else skyCard = null
    }
    LaunchedEffect(dockPerson?.id) {
        // Picked in the box (its person chip, or a category chip): bring them
        // to the middle. Picked BY the middle: already there.
        val id = dockPerson?.id ?: return@LaunchedEffect
        if (!creating) return@LaunchedEffect
        panTo(id)
    }
    // The header's Cancel.
    val cancelTick by WatchCreation.cancelTick.collectAsStateWithLifecycle()
    var seenCancel by remember { mutableStateOf(cancelTick) }
    LaunchedEffect(cancelTick) {
        if (cancelTick == seenCancel) return@LaunchedEffect
        seenCancel = cancelTick
        afterKeyboard { setCreating(false); dockFill = "" }
    }
    // Android's back steps out of the box or the card, as the tap on the map does.
    androidx.activity.compose.BackHandler(enabled = creating || skyCard != null) { putAway() }

    Box(Modifier.fillMaxSize()) {
        val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
        // Level with the floating tab bar's top, plus iOS's 16 pt.
        val tabBarTop = navBottom + 76.dp
        val floatBottom = tabBarTop + 16.dp
        Box(Modifier.fillMaxSize().graphicsLayer { alpha = if (skyReady) 1f else 0f }) {
            PeopleSkyMap(
                nodes = nodes,
                meName = meName,
                lens = lens,
                onTap = { n ->
                    // A tap is for who they are; the middle of the screen is
                    // for what to talk about.
                    if (!putAway()) openSkyCard(people.firstOrNull { it.id == n.person.id } ?: n.person)
                },
                // iOS 2c153cdd: the one-page profile (`MyProfileView`).
                onTapMe = onOpenProfile,
                focusedId = if (creating) dockPerson?.id else null,
                bubbleId = skyCentred?.id,
                bubble = dockBubble,
                onTapBubble = { tapBubble() },
                scrollTarget = skyScroll,
                onCenterChange = { centre(it) },
                softenOthers = creating,
                onAwayChange = { skyAway = it },
                backToMeRequest = backToMeTick,
                // A tap on the empty map while writing goes back a step: to
                // the card of the person the box was with.
                onTapEmpty = { putAway() },
            )
        }

        // The "Your situation" box itself — chips, attach, the person,
        // dictation — exactly as its sheet draws it, rising with the keyboard
        // while the map stays put.
        androidx.compose.animation.AnimatedVisibility(
            visible = creating,
            enter = androidx.compose.animation.slideInVertically(tween(300)) { it } +
                androidx.compose.animation.fadeIn(tween(300)),
            exit = androidx.compose.animation.slideOutVertically(tween(300)) { it } +
                androidx.compose.animation.fadeOut(tween(300)),
            modifier = Modifier.align(Alignment.BottomCenter)
                .windowInsetsPadding(WindowInsets.ime.union(WindowInsets.navigationBars)),
        ) {
            ScenarioComposer(
                targetLanguage = language,
                existingCategories = scenarios.mapNotNull { it.category }.distinct(),
                host = ComposerHost.WATCH,
                mode = ComposerMode.CUSTOM,
                onCommitted = { sc -> if (enabled) onWatch(sc.id) },
                onDismiss = {},
                embedded = true,
                partnerSync = dockPerson,
                onPartnerSync = { dockPerson = it },
                situationSync = dockFill,
                onSituationTaken = { dockFill = "" },
                onPickCategory = { pickDockCategory(it) },
                showsCategoryChips = !dockNoChips,
                focusOnAppear = dockNoChips,
            )
        }

        // Writing your own situation is its own button, not a tap on "me":
        // tapping a person opens that person, so tapping me opens me.
        val card = skyCard
        androidx.compose.animation.AnimatedVisibility(
            visible = !creating && card != null,
            enter = androidx.compose.animation.slideInVertically(tween(300)) { it } +
                androidx.compose.animation.fadeIn(tween(300)),
            exit = androidx.compose.animation.slideOutVertically(tween(300)) { it } +
                androidx.compose.animation.fadeOut(tween(300)),
            modifier = Modifier.align(Alignment.BottomCenter)
                .padding(start = 12.dp, end = 12.dp, bottom = tabBarTop + 8.dp),
        ) {
            // Held while it slides away, so the card doesn't empty mid-exit.
            var shown by remember { mutableStateOf(card) }
            if (card != null) shown = card
            shown?.let { c ->
                SkyPersonCard(
                    person = people.firstOrNull { it.id == c.id } ?: c,
                    language = language,
                    onClose = { skyCard = null },
                    onCompose = { composeFromCard(c) },
                    onWatch = {
                        scope.launch {
                            val p = savedFromCard(c)
                            onWatchWith(p)
                        }
                    },
                    onTalk = {
                        scope.launch {
                            val p = savedFromCard(c)
                            onTalkWith(p)
                        }
                    },
                    onOpenTalk = onOpenTalk,
                )
            }
        }
        androidx.compose.animation.AnimatedVisibility(
            visible = !creating && card == null,
            enter = androidx.compose.animation.fadeIn(tween(300)),
            exit = androidx.compose.animation.fadeOut(tween(300)),
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = floatBottom),
        ) {
            com.roro.futurevoice.ui.brand.IosGlassButton(
                onClick = {
                    // Whoever is in the middle is who it's with — the box
                    // never starts on a default the map would fly to.
                    setCreating(true)
                    skyCentred?.let { dockPerson = it }
                },
                modifier = Modifier.height(50.dp),
            ) {
                Icon(Icons.Filled.EditNote, contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.new_situation), style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
            }
        }

        // Back to me, in the tab's own layer: inside the map it sat in the
        // faded bottom edge and showed at a third of its strength. Level with
        // "New situation"; above the box while writing; out of the way of a
        // person's card.
        androidx.compose.animation.AnimatedVisibility(
            visible = skyAway && card == null,
            enter = androidx.compose.animation.fadeIn(tween(300)),
            exit = androidx.compose.animation.fadeOut(tween(300)),
            modifier = Modifier.align(Alignment.BottomEnd)
                .padding(end = 16.dp, bottom = if (creating) navBottom + 216.dp else floatBottom),
        ) {
            val label = stringResource(R.string.watch_sky_backtome)
            // Same size as "New situation" beside it (50 high, the same 22-dp
            // glyph): a 48 against its 50 read as two different buttons.
            com.roro.futurevoice.ui.brand.IosGlassButton(onClick = { backToMeTick += 1 }, circle = true,
                modifier = Modifier.size(50.dp).semantics { contentDescription = label }) {
                Icon(Icons.Filled.GpsFixed, contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
            }
        }
    }

    if (showingSaved) {
        SavedScenariosSheet(
            scenarios = live,
            people = people,
            onDismiss = { WatchSky.showingSaved.value = false },
            // Two sheets can't be up at once: the list goes first.
            onOpen = { sc ->
                WatchSky.showingSaved.value = false
                scope.launch { kotlinx.coroutines.delay(450); editingScenario = sc }
            },
        )
    }

    composing?.let { mode ->
        ScenarioComposer(
            targetLanguage = language,
            existingCategories = scenarios.mapNotNull { it.category }.distinct(),
            prefill = situationPrefill,
            person = withPerson,
            // A scene always needs an other person, so this host opens on a
            // character rather than on the fluent self.
            host = ComposerHost.WATCH,
            mode = mode,
            // Minting it plays it — the composer's CTA IS "Watch".
            onCommitted = { sc -> if (enabled) onWatch(sc.id) },
            onDismiss = { composing = null; withPerson = null; situationPrefill = "" },
        )
    }

    editingScenario?.let { sc ->
        ScenarioComposer(
            targetLanguage = language,
            existingCategories = scenarios.mapNotNull { it.category }.distinct(),
            host = ComposerHost.WATCH,
            editing = sc,
            // Saved in place, then a FRESH take into the same book — the
            // scene screen writes a new take whenever the scenario already
            // has one.
            onCommitted = { edited -> if (enabled) onWatch(edited.id) },
            onDelete = {
                scope.launch { store.delete(sc.id, language); StoreEvents.bump() }
            },
            onDismiss = { editingScenario = null },
        )
    }
}

/** Who a common situation is with, read off what the learner wrote about
 *  their people and what a stranger does (iOS `WatchTab.fits`). */
internal fun watchFits(c: Counterpart, category: String, job: String?): Boolean {
    val text = listOf(c.relationship, c.relationshipKind.orEmpty(), c.intro, c.background, job.orEmpty())
        .joinToString(" ").lowercase()
    val words = when (category) {
        "Work" -> listOf("coworker", "manager", "boss", "colleague", "team", "상사", "팀장", "동료", "부장", "과장", "上司", "同僚", "kollege")
        "Social" -> listOf("friend", "친구", "友達", "freund")
        "School" -> listOf("teacher", "fellow parent", "parent", "선생님", "학부모", "先生", "lehrer")
        "Cafe" -> listOf("barista", "cafe", "café", "coffee", "바리스타", "카페", "カフェ")
        "Travel" -> listOf("flight", "airline", "hotel", "travel", "guide", "승무원", "호텔", "여행", "ホテル")
        "Health" -> listOf("nurse", "doctor", "pharmac", "간호", "의사", "약사", "看護", "医師", "arzt")
        "Shopping" -> listOf("shop", "store", "retail", "sales", "점원", "가게", "店")
        "Phone" -> listOf("support", "call center", "customer service", "상담", "コールセンター")
        else -> emptyList()
    }
    return words.any { text.contains(it) }
}

/**
 * A person, as a card floating over the bottom of the map (iOS
 * `SkyPersonCard`). Closed, it is who they are in a line or three and one row
 * of actions — less than half the screen, so the map and them in its middle
 * stay in view. Opened (tap the text), it grows upward like an accordion into
 * everything the old full page held. No close button: it goes like a sheet —
 * pulled down, or a tap on the map.
 */
@Composable
internal fun SkyPersonCard(
    person: Counterpart,
    language: String,
    onClose: () -> Unit,
    onCompose: () -> Unit,
    onWatch: () -> Unit,
    onTalk: () -> Unit,
    onOpenTalk: (String) -> Unit,
) {
    val context = LocalContext.current
    val density = androidx.compose.ui.platform.LocalDensity.current
    /** How far the card is being pulled down; past 90 pt it goes. */
    val pull = remember { androidx.compose.animation.core.Animatable(0f) }
    val scope = rememberCoroutineScope()
    var expanded by remember(person.id) { mutableStateOf(false) }
    val about = if (person.personaKind == "user") "" else person.intro.ifEmpty { person.background }
    val voiceName = VoicePreset.known(person.voicePresetId)?.let { VoicePreset.name(it.voiceId, it.name, language) }
        ?: stringResource(R.string.their_own)
    var talks by remember(person.id) { mutableStateOf<List<com.roro.futurevoice.talk.Session>>(emptyList()) }
    LaunchedEffect(person.id, language) {
        talks = com.roro.futurevoice.data.SessionStore.shared(context).load(language)
            .filter { it.counterpartId == person.id && it.endedAt != null }
            .sortedByDescending { it.startedAt }
    }
    val dismissPx = with(density) { 90.dp.toPx() }
    Column(
        Modifier
            .fillMaxWidth()
            .graphicsLayer { translationY = pull.value }
            .shadow(24.dp, ContinuousShape(34.dp), clip = false,
                ambientColor = Color.Black.copy(alpha = 0.08f), spotColor = Color.Black.copy(alpha = 0.08f))
            .background(MaterialTheme.colorScheme.surface, ContinuousShape(34.dp))
            .pointerInput(Unit) {
                val tracker = androidx.compose.ui.input.pointer.util.VelocityTracker()
                detectVerticalDragGestures(
                    onDragStart = { tracker.resetTracking() },
                    onDragEnd = {
                        val v = tracker.calculateVelocity().y
                        // Predicted end: where the flick would carry it.
                        if (pull.value > dismissPx || pull.value + v * 0.25f > dismissPx * 2) onClose()
                        else scope.launch { pull.animateTo(0f, tween(250)) }
                    },
                    onDragCancel = { scope.launch { pull.animateTo(0f, tween(250)) } },
                ) { change, dy ->
                    tracker.addPosition(change.uptimeMillis, change.position)
                    change.consume()
                    scope.launch { pull.snapTo(max(0f, pull.value + dy)) }
                }
            }
            .padding(start = 18.dp, end = 18.dp, top = 14.dp, bottom = 16.dp)
            .animateContentSize(tween(300)),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // A sheet's grabber: it says the card can be pulled away.
        Box(Modifier.fillMaxWidth().offset(y = (-6).dp), contentAlignment = Alignment.Center) {
            Box(Modifier.size(36.dp, 5.dp).clip(CircleShape)
                .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.45f)))
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            PersonBubble(person.name, person.id, size = 44.dp)
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(person.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                val cap = partnerCaptionOf(person)
                if (cap.isNotEmpty()) {
                    Text(cap, style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }

        // The accordion: two lines and a chevron, or everything, scrolling
        // inside the card once it would pass ~half the screen.
        if (expanded) {
            Column(
                Modifier.fillMaxWidth().heightIn(max = 340.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                if (about.isNotEmpty()) Text(about, style = MaterialTheme.typography.bodyMedium)
                if (person.commonTopics.isNotEmpty()) {
                    CardSection(stringResource(R.string.topics)) {
                        Text(person.commonTopics, style = MaterialTheme.typography.bodyMedium)
                    }
                }
                CardSection(stringResource(R.string.voice)) {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(voiceName, style = MaterialTheme.typography.bodyMedium)
                        Text(stringResource(R.string.their_own_voice_chosen_with_their_introduction_not_a_recordi_ac2731),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                if (talks.isNotEmpty()) {
                    CardSection(stringResource(R.string.your_talks_together)) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            talks.forEach { s ->
                                Row(Modifier.fillMaxWidth().clickable(remember { MutableInteractionSource() },
                                    indication = null) { onOpenTalk(s.id) },
                                    verticalAlignment = Alignment.CenterVertically) {
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                                        Text(s.displayTitle ?: stringResource(R.string.conversation),
                                            style = MaterialTheme.typography.bodyMedium,
                                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        Text(java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM,
                                            java.text.DateFormat.SHORT).format(java.util.Date(s.startedAt)),
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                                        tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(18.dp))
                                }
                            }
                        }
                    }
                }
            }
            CardToggle(open = false) { expanded = false }
        } else {
            if (about.isNotEmpty()) {
                Text(about, style = MaterialTheme.typography.bodyMedium,
                    maxLines = 2, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.clickable(remember { MutableInteractionSource() },
                        indication = null) { expanded = true })
            }
            CardToggle(open = true) { expanded = true }
        }

        // One row: the situation keeps its words (it is the card's point),
        // Watch and Talk are their glyphs alone — a label in every language
        // would not fit three across.
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(
                Modifier.weight(1f).height(50.dp).clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary).clickable(onClick = onCompose)
                    .padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.EditNote, contentDescription = null, tint = Color.White,
                    modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.make_a_situation), color = Color.White,
                    style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            CardIconButton(Icons.Filled.PlayArrow, stringResource(R.string.watch), onWatch)
            CardIconButton(Icons.Filled.Phone, stringResource(R.string.talk), onTalk)
        }
    }
}

@Composable
private fun CardIconButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Box(
        Modifier.size(width = 58.dp, height = 50.dp).clip(CircleShape)
            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f))
            .clickable(onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(22.dp))
    }
}

@Composable
private fun CardToggle(open: Boolean, onClick: () -> Unit) {
    // A real tap target, with air above and a clear gap before the row of actions.
    Row(
        Modifier.offset(y = (-2).dp).padding(bottom = 8.dp)
            .clickable(remember { MutableInteractionSource() }, indication = null, onClick = onClick)
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(stringResource(if (open) R.string.more else R.string.show_less),
            style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Icon(if (open) Icons.Filled.KeyboardArrowDown else Icons.Filled.KeyboardArrowUp,
            contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(16.dp))
    }
}

@Composable
private fun CardSection(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        content()
    }
}

/**
 * The Watch header (iOS `WatchTab` toolbar): the lens — an occasional choice,
 * so a menu rather than a row the map gives up space to, its icon filled
 * while the map is narrowed — the saved situations, and the ONE people page.
 * iOS groups the three in one glass capsule.
 */
@Composable
internal fun WatchHeaderActions(onOpenPeople: () -> Unit) {
    val lens by WatchSky.lens.collectAsStateWithLifecycle()
    var menu by remember { mutableStateOf(false) }
    val accent = MaterialTheme.colorScheme.primary
    val lensLabel = with(PeopleSky) { lens.title() }
    val options = PeopleSky.Lens.entries.map { it to with(PeopleSky) { it.title() } }
    Box(Modifier.padding(end = 12.dp)) {
        GlassCapsule {
            Box {
                androidx.compose.material3.IconButton(onClick = { menu = true },
                    modifier = Modifier.size(40.dp).semantics { contentDescription = lensLabel }) {
                    // line.3.horizontal.decrease.circle(.fill)
                    val narrowed = lens != PeopleSky.Lens.ALL
                    Box(Modifier.size(22.dp).clip(CircleShape)
                        .then(if (narrowed) Modifier.background(accent)
                            else Modifier.border(1.5.dp, accent, CircleShape)),
                        contentAlignment = Alignment.Center) {
                        Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = null,
                            tint = if (narrowed) Color.White else accent, modifier = Modifier.size(14.dp))
                    }
                }
                com.roro.futurevoice.ui.brand.IosPickerMenu(
                    expanded = menu, onDismissRequest = { menu = false },
                    options = options, selected = lens,
                    onPick = { WatchSky.lens.value = it })
            }
            androidx.compose.material3.IconButton(onClick = { WatchSky.showingSaved.value = true },
                modifier = Modifier.size(40.dp)) {
                // Every situation made before the map still has a home.
                Icon(Icons.Outlined.Layers, contentDescription = stringResource(R.string.your_scenarios),
                    tint = accent, modifier = Modifier.size(22.dp))
            }
            androidx.compose.material3.IconButton(onClick = onOpenPeople, modifier = Modifier.size(40.dp)) {
                // iOS draws `person.2` as an OUTLINE here.
                Icon(Icons.Outlined.People, contentDescription = stringResource(R.string.people),
                    tint = accent, modifier = Modifier.size(24.dp))
            }
        }
    }
}

/**
 * Everyone on the map (iOS `skyNodes`): every person on file, then the pool's
 * strangers not met yet. Seats are dealt in this order, so it must not follow
 * the store's — saving a person reorders it, and the whole map would
 * reshuffle under the learner's finger.
 */
private fun skyNodes(
    people: List<Counterpart>,
    pool: List<com.roro.futurevoice.net.PublicPersonaClient.PublicPersona>,
    scenarios: List<Scenario>,
    talks: Map<String, Int>,
    metLabel: String,
): List<PeopleSky.Node> {
    val practiced = talks.toMutableMap()
    val kept = mutableSetOf<String>()
    for (s in scenarios) {
        val id = s.counterpartId ?: continue
        practiced[id] = (practiced[id] ?: 0) + 1
        val meeting = s.isMeeting == true || s.category == "Meeting"
        if (!meeting && s.isTopic != true) kept += id
    }
    val jobs = pool.associate { it.id to it.occupation }
    val nodes = people.map { c ->
        val job = c.remoteId?.let { jobs[it] }
        PeopleSky.Node(
            id = c.id, name = c.name, person = c, pooled = false,
            ring = PeopleSky.ring(c), isMine = c.remoteId == null,
            practiced = practiced[c.id] ?: 0, hasKept = c.id in kept,
            symbol = PeopleSky.symbol(c, job), eyebrow = PeopleSky.eyebrow(c, job),
        )
    }.toMutableList()
    val metRemote = people.mapNotNull { it.remoteId }.toSet()
    for (row in pool) {
        if (row.id in metRemote) continue
        val c = row.asCounterpart(metLabel)
        nodes += PeopleSky.Node(
            id = c.id, name = c.name, person = c, pooled = true, ring = 2,
            isMine = false, practiced = 0, hasKept = false,
            symbol = PeopleSky.symbol(c, row.occupation), eyebrow = PeopleSky.eyebrow(c, row.occupation),
        )
    }
    return nodes.sortedBy { it.id }
}

/**
 * Every situation made before the map (iOS `savedScenariosPage`): category
 * tabs on top — only the categories the saved situations carry, most used
 * first — and the cards below.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun SavedScenariosSheet(
    scenarios: List<Scenario>,
    people: List<Counterpart>,
    onDismiss: () -> Unit,
    onOpen: (Scenario) -> Unit,
) {
    var category by remember { mutableStateOf<String?>(null) }
    val categories = remember(scenarios) {
        val count = mutableMapOf<String, Int>()
        val icon = mutableMapOf<String, String?>()
        for (s in scenarios) {
            val c = s.category?.trim()?.takeIf { it.isNotEmpty() } ?: continue
            count[c] = (count[c] ?: 0) + 1
            if (icon[c] == null) icon[c] = s.categoryIcon
        }
        count.entries.sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .map { it.key to icon[it.key] }
    }
    val shown = category?.let { c -> scenarios.filter { it.category == c } } ?: scenarios
    androidx.compose.material3.ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = com.roro.futurevoice.ui.rememberModalBottomSheetState(skipPartiallyExpanded = true),
        dragHandle = null,
        containerColor = AppSurfaces.ground,
    ) {
        Column(Modifier.fillMaxSize()) {
            SheetHeader(
                title = stringResource(R.string.your_scenarios),
                leading = {
                    com.roro.futurevoice.ui.brand.IosGlassTextButton(stringResource(R.string.done),
                        onClick = onDismiss)
                },
                modifier = Modifier.padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 4.dp),
            )
            if (categories.size > 1) {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    SoftChip(stringResource(R.string.all), selected = category == null) { category = null }
                    categories.forEach { (name, icon) ->
                        SoftChip(categoryTitle(name), icon = icon, selected = category == name) { category = name }
                    }
                }
            }
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                shown.chunked(2).forEach { pair ->
                    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        pair.forEach { sc ->
                            WatchScenarioCard(sc,
                                Modifier.weight(1f).fillMaxHeight(),
                                person = sc.counterpartId?.let { id -> people.firstOrNull { it.id == id } },
                                // Settings sheet first, not straight to
                                // generation: check, tweak or delete, then
                                // Watch a fresh take from there.
                                onClick = { onOpen(sc) })
                        }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
                Spacer(Modifier.height(24.dp).windowInsetsPadding(WindowInsets.navigationBars))
            }
        }
    }
}

/**
 * One saved scenario, as a card in the Watch grid. A scenario is a reusable
 * TEMPLATE — a tap writes a FRESH take — so the card shows what the situation
 * IS, not when it last ran.
 */
@Composable
private fun WatchScenarioCard(
    sc: Scenario,
    modifier: Modifier = Modifier,
    person: Counterpart?,
    onClick: () -> Unit,
) {
    val personName = person?.name
    val partner = personName ?: sc.role.trim().takeIf { it.isNotEmpty() }
    val env = sc.environment.trim()
    val blurb = env.takeIf { it.isNotEmpty() && !it.equals(sc.cardTitle.trim(), ignoreCase = true) }
    Column(
        modifier
            .clip(ContinuousShape(16.dp))
            .background(AppSurfaces.card)
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            if (person != null) {
                PersonBubble(person.name, person.id, size = 32.dp)
            } else {
                Icon(Symbols.icon(sc.categoryIcon), contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
            }
            Spacer(Modifier.weight(1f))
            Icon(Icons.Filled.PlayCircleFilled, contentDescription = null,
                tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            if (personName == null) sc.category?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Text(sc.cardTitle, style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            blurb?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
        Spacer(Modifier.weight(1f))
        val footer = listOfNotNull(
            partner?.let { stringResource(R.string.with, it) },
            sc.lastUsedAt?.let { com.roro.futurevoice.data.Recency.label(it) },
        ).joinToString(" · ")
        if (footer.isNotEmpty()) {
            Text(footer, style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.outline,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}
