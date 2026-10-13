package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.audio.PcmStreamPlayer
import com.roro.futurevoice.audio.WavPcm
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.BillingGate
import com.roro.futurevoice.data.DrillIngest
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.PhraseAudioStore
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.net.CurriculumClient
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.net.ElevenLabsClient
import com.roro.futurevoice.talk.DialogueEngineTurn
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.talk.UserPersona
import com.roro.futurevoice.talk.identityIn
import com.roro.futurevoice.talk.nameIn
import com.roro.futurevoice.ui.brand.ContinuousShape
import com.roro.futurevoice.ui.brand.IosButton as Button
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.gestures.animateScrollBy
import com.roro.futurevoice.talk.ScenarioCurriculum
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

/**
 * The Watch scene — iOS `SceneWatchView` + the scenario-watch half of
 * `WatchView`. The scene STREAMS: each line is on screen the moment the model
 * finishes writing it, playback starts on the first one, and the playback
 * loop waits at the frontier for lines still being written. The scene may
 * only END once the full payload decoded and the book was saved
 * (`feedComplete`); a failed stream is the error state and nothing is saved.
 * The learner's side plays in THEIR OWN cloned voice, the counterpart on its
 * preset voice; every line carries ONE scene_key, so the scene bills a single
 * count and a scene in progress is never cut off. A fresh take absorbs into
 * the book (scene replaces, study items accumulate).
 *
 * A fixed bottom bar (iOS `safeAreaInset`): Restart + Play/Pause while the
 * scene runs, then Watch again + Study this once playback ran out past the
 * last line of a closed scene.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WatchSceneScreen(
    scenarioId: String,
    /** Say this line after the fluent self — the same screen the books open. */
    onShadow: (String) -> Unit = {},
    /** The end handoff: take the scene to its book (iOS `SceneHandoff`). */
    onStudy: (String) -> Unit = {},
    voiceId: String,
    persona: UserPersona?,
    targetLanguage: String,
    proficiency: String,
    onBack: () -> Unit,
    /** The book's Watch (iOS `ScenarioDetailView` → `WatchView(savedDialogue:)`):
     *  replay THE scene the book was extracted from — never a new generation,
     *  no reading, no gate. Every line is on screen at once and it plays
     *  from the first. The Watch tab leaves this off and writes a fresh take. */
    replaySaved: Boolean = false,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mp3 = remember { Mp3Player(context.cacheDir, source = "scene") }
    val pcm = remember { PcmStreamPlayer() }

    /** The scenario this scene belongs to — its who/where/what heads the page. */
    var scene by remember { mutableStateOf<Scenario?>(null) }
    /** The real person behind the scene, when there is one. */
    var other by remember { mutableStateOf<com.roro.futurevoice.data.Counterpart?>(null) }

    // ── Generation (iOS `SceneWatchView`) ──
    /** True while the scenario's attached material is read — the board owns
     *  the screen. Once per change to the material, never per take. */
    var readingBrief by remember { mutableStateOf(false) }
    var briefProgress by remember { mutableStateOf(com.roro.futurevoice.net.ScenarioBriefEngine.Progress()) }
    /** True from the moment the player is up (a stream started, or a saved
     *  scene is being shown) — iOS's `streaming` / saved-scene branch. */
    var playerUp by remember { mutableStateOf(false) }
    var generationError by remember { mutableStateOf<String?>(null) }
    /** Bumped by Try again: reruns the reading, then the scene. */
    var attempt by remember { mutableStateOf(0) }
    /** One take per screen — survives this page being covered (a shadow
     *  line, the book) so coming back never writes a second take. */
    val runKey = rememberSaveable { UUID.randomUUID().toString().take(8) }

    // ── Player (iOS `WatchView`) ──
    val turns = remember { mutableStateListOf<DialogueEngineTurn>() }
    var title by remember { mutableStateOf<String?>(null) }
    /** The scene's own fallback title while the generated one is unwritten. */
    var fallbackTitle by remember { mutableStateOf("") }
    var currentIndex by remember { mutableStateOf<Int?>(null) }
    var isPlaying by remember { mutableStateOf(false) }
    /** "Writing the dialogue…" until the first line lands. */
    var loading by remember { mutableStateOf(true) }
    /** Feed mode: more lines are on the wire until this flips. */
    var feedComplete by remember { mutableStateOf(true) }
    var streamAutoStarted by remember { mutableStateOf(false) }
    /** Parked waiting for a line that hasn't been written yet — gates the
     *  prefetch refill: a line about to be claimed the instant it appears is
     *  streamed by the loop, never turned into a buffered prefetch (that
     *  would bill it twice). */
    var waitingAtFrontier by remember { mutableStateOf(false) }
    /** Playback ran out past the last line of a closed scene at least once. */
    var didFinishScene by rememberSaveable { mutableStateOf(false) }
    var playError by remember { mutableStateOf<String?>(null) }
    /** A spent pool: a sheet, never an error line and never a bare paywall. */
    var spent by remember { mutableStateOf<SpentPool?>(null) }
    /** One key for this whole scene run — every line sends it, so the
     *  scene's count is charged once however many lines play. */
    val sceneRunKey = rememberSaveable(replaySaved) {
        if (replaySaved) "scene:$scenarioId:replay-${UUID.randomUUID().toString().take(8)}"
        else "scene:$scenarioId:$runKey"
    }
    /** The replay already started once on this page — coming back from a
     *  shadow line shows it again without playing it over. */
    var replayStarted by rememberSaveable(replaySaved) { mutableStateOf(false) }
    /** This run has put a scene in `PracticeLog` — once, on the first line heard. */
    var loggedScene by rememberSaveable { mutableStateOf(false) }
    /** Drill targets already on file, keyed as the store dedupes. */
    var savedPhraseKeys by remember { mutableStateOf<Set<String>>(emptySet()) }
    /** Audio for the next lines, fetched while the current one plays. Never
     *  cancelled: a synthesis in flight is already billed. */
    val prefetches = remember { mutableMapOf<Int, Deferred<ByteArray>>() }
    var playJob by remember { mutableStateOf<Job?>(null) }
    val listState = rememberLazyListState()

    // iOS `watchCounterpart(for:)`: the real person, else the scene's stock
    // character (`ScenarioDetailView.syntheticCounterpart`). Read at CALL
    // time — the playback loop outlives the composition that started it.
    fun castVoiceId() = other?.voicePresetId?.takeIf { it.isNotBlank() }
        ?: StockPerson.by(scene?.voicePresetId).voiceId
    fun counterpartName() = other?.name?.takeIf { it.isNotBlank() }
        ?: StockPerson.by(scene?.voicePresetId).nameIn(targetLanguage)
    val counterpartRelationship = other?.relationship ?: scene?.role.orEmpty()

    fun pause() {
        // Gate first, then stop: the stopped line's completion must not
        // carry the loop on to the next one.
        isPlaying = false
        playJob?.cancel()
        mp3.stop()
        pcm.stop()
    }

    NavPageBackHandler(onBack = { pause(); onBack() })

    /** Everything needed to synthesize one line, read before any concurrency
     *  so a prefetch can't race the list growing under a streamed scene. */
    data class SpeechRequest(val text: String, val voiceId: String,
                             val previousText: String?, val nextText: String?)

    fun speechRequest(index: Int): SpeechRequest {
        val turn = turns[index]
        return SpeechRequest(
            text = turn.text,
            voiceId = if (turn.speaker == "user") voiceId else castVoiceId(),
            previousText = if (index > 0) turns[index - 1].text else null,
            nextText = if (index + 1 < turns.size) turns[index + 1].text else null,
        )
    }

    suspend fun loadOrSynthesize(request: SpeechRequest): ByteArray {
        if (request.voiceId.isEmpty()) throw IllegalStateException("No voice id available.")
        com.roro.futurevoice.data.DebugBilling.consume402()?.let { throw it }
        val store = PhraseAudioStore.shared(context)
        store.data(request.text, request.voiceId)?.let { return it }
        val audio = ElevenLabsClient(AuthRepository()).synthesize(
            voiceId = request.voiceId, text = request.text,
            modelId = ElevenLabsClient.CLONE_MODEL_ID,
            purpose = "scene", sceneKey = sceneRunKey,
            previousText = request.previousText, nextText = request.nextText)
        store.save(audio, request.text, request.voiceId)
        return audio
    }

    /** Fetch the next `PREFETCH_DEPTH` lines that aren't already in flight. */
    fun startPrefetch(after: Int) {
        for (offset in 1..PREFETCH_DEPTH) {
            val next = after + offset
            if (next >= turns.size || prefetches.containsKey(next)) continue
            val request = speechRequest(next)
            prefetches[next] = SceneAudioScope.async { loadOrSynthesize(request) }
        }
    }

    /**
     * Speak the line by STREAMING it: audio starts on the first PCM chunk.
     * The request runs outside the playback job, so a pause never throws a
     * billed synthesis away — it still lands in the cache. False when the
     * server answered with a whole file (nothing streamed) — the caller then
     * plays it buffered.
     */
    suspend fun streamAndPlay(request: SpeechRequest): Boolean {
        if (request.voiceId.isEmpty()) return false
        var feeding = true
        var started = false
        val result = SceneAudioScope.async {
            val r = ElevenLabsClient(AuthRepository()).synthesizeStreaming(
                voiceId = request.voiceId, text = request.text,
                modelId = ElevenLabsClient.CLONE_MODEL_ID,
                purpose = "scene", sceneKey = sceneRunKey,
            ) { chunk ->
                if (!feeding) return@synthesizeStreaming
                if (!started) { pcm.start(); started = true }
                pcm.write(chunk)
            }
            val store = PhraseAudioStore.shared(context)
            when (r) {
                is ElevenLabsClient.StreamedAudio.Mp3 -> store.save(r.data, request.text, request.voiceId)
                is ElevenLabsClient.StreamedAudio.Pcm22050 -> {
                    val shorts = ShortArray(r.data.size / 2)
                    ByteBuffer.wrap(r.data).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(shorts)
                    store.save(WavPcm.wav(shorts, ElevenLabsClient.STREAM_SAMPLE_RATE),
                        request.text, request.voiceId)
                }
            }
            r
        }
        try {
            return when (val r = result.await()) {
                is ElevenLabsClient.StreamedAudio.Mp3 -> false
                is ElevenLabsClient.StreamedAudio.Pcm22050 -> {
                    if (!started) false else { pcm.drain(); pcm.stop(); true }
                }
            }
        } finally {
            feeding = false
        }
    }

    suspend fun runPlayback(from: Int) {
        var i = from
        while (true) {
            // Streaming: hold the playhead until the next line lands or the
            // generation closes the scene.
            while (isPlaying && i >= turns.size && !feedComplete) {
                waitingAtFrontier = true
                delay(120)
            }
            waitingAtFrontier = false
            if (!isPlaying || i >= turns.size) break
            currentIndex = i
            val request = speechRequest(i)
            try {
                // Fill the lookahead window BEFORE awaiting this line.
                startPrefetch(i)
                var data: ByteArray? = prefetches.remove(i)?.let { runCatching { it.await() }.getOrNull() }
                if (data == null) data = PhraseAudioStore.shared(context).data(request.text, request.voiceId)
                if (data != null) {
                    mp3.play(data)
                } else if (!streamAndPlay(request)) {
                    // Streaming unavailable — classic fetch-then-play.
                    mp3.play(loadOrSynthesize(request))
                }
                if (!loggedScene) {
                    // A scene the learner sat through keeps a streak alive —
                    // logged ONCE, on the first line actually heard.
                    loggedScene = true
                    com.roro.futurevoice.data.PracticeLog.record(
                        context, com.roro.futurevoice.data.PracticeLog.Kind.SCENE)
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                isPlaying = false
                when (e) {
                    // The free pool is genuinely empty — the paywall IS the answer.
                    is EdgeError.InsufficientCredits -> {
                        BillingGate.invalidate()
                        BillingGate.showPaywall.value = true
                    }
                    // They already paid; the pool refills on its own.
                    is EdgeError.SceneCapReached -> spent = SpentPool.SCENES
                    is EdgeError.DailyCapReached -> spent = SpentPool.TALK
                    else -> playError = e.message ?: e.toString()
                }
                return
            }
            i += 1
        }
        // A pause exits with isPlaying already false; only a natural run-out
        // past the LAST line of a closed scene counts as finishing.
        val reachedEnd = isPlaying && i >= turns.size
        isPlaying = false
        currentIndex = null
        if (reachedEnd) didFinishScene = true
    }

    fun playFrom(index: Int) {
        if (index >= turns.size) return
        playJob?.cancel()
        mp3.stop(); pcm.stop()
        isPlaying = true
        playJob = scope.launch { runPlayback(index) }
    }

    /** A line landed from the stream (iOS `onReceive(feedTurnsPublisher)`). */
    fun appendStreamed(turn: DialogueEngineTurn) {
        turns.add(turn)
        loading = false
        if (!streamAutoStarted) {
            streamAutoStarted = true
            playFrom(0)
        } else if (isPlaying && !waitingAtFrontier) {
            // The scene started with only the first line written, so its
            // prefetch had nothing to reach for; refill the window the moment
            // a new line lands so it synthesizes behind the current one.
            currentIndex?.let { startPrefetch(it) }
        }
    }

    /** The saved scene, every line at once (a replay, or coming back to a
     *  take already written in this visit). */
    fun showSaved(s: Scenario) {
        turns.clear()
        turns.addAll(s.curriculum?.dialogue.orEmpty())
        title = s.curriculum?.dialogueTitle?.trim()
        loading = false
        feedComplete = true
        playerUp = true
    }

    LaunchedEffect(Unit) {
        savedPhraseKeys = DrillStore.shared(context).load(targetLanguage)
            .map { DrillIngest.normalizedForMatch(it.targetPhrase) }.toSet()
    }

    LaunchedEffect(scenarioId, attempt, replaySaved) {
        val store = ScenarioStore.shared(context)
        var scenario = store.load(targetLanguage).firstOrNull { it.id == scenarioId }
            ?: run { onBack(); return@LaunchedEffect }
        scene = scenario
        fallbackTitle = scenario.displayTitle
        other = scenario.counterpartId?.let { id ->
            com.roro.futurevoice.data.CounterpartStore.shared(context).load().firstOrNull { it.id == id }
        }
        if (replaySaved) {
            // The saved scene, as it is in the book: no model call, no
            // reading, no new take — every line up, played from the first.
            if (scenario.curriculum?.dialogue.isNullOrEmpty()) { onBack(); return@LaunchedEffect }
            showSaved(scenario)
            if (!replayStarted) { replayStarted = true; playFrom(0) }
            return@LaunchedEffect
        }
        // Capture only: the scene as it stands once it has played out.
        if (com.roro.futurevoice.capture.flags.WatchCaptureFlags.previewSceneFinished) {
            showSaved(scenario)
            didFinishScene = true
            return@LaunchedEffect
        }
        // Back from a page that covered this one (a shadow line, the book):
        // this visit's take is written (or still being written) — wait for
        // it and show it, never write another.
        val runId = "$scenarioId:$runKey"
        SceneRuns[runId]?.let { run ->
            if (!run.isCompleted) { turns.clear(); loading = true; playerUp = true }
            val ok = runCatching { run.await() }.isSuccess
            if (ok) {
                store.load(targetLanguage).firstOrNull { it.id == scenarioId }?.let { showSaved(it) }
                return@LaunchedEffect
            }
            SceneRuns.remove(runId)
        }
        // Material first. A brief with sources but no reading yet is read
        // here, once, with the board on screen; the scene is then written
        // FROM it. A failed reading is the error state, never a scene
        // quietly written without the material the learner attached.
        val pending = scenario.brief
        if (pending != null && pending.needsReading) {
            readingBrief = true
            briefProgress = com.roro.futurevoice.net.ScenarioBriefEngine.Progress(
                sourcesRead = pending.sources.map { false })
            try {
                val read = com.roro.futurevoice.net.ScenarioBriefEngine.read(
                    context, scenario, persona, targetLanguage,
                    context.getSharedPreferences("futurevoice", android.content.Context.MODE_PRIVATE)
                        .getString("futurevoice.nativeLanguage", null)
                        ?: com.roro.futurevoice.data.LanguageCatalog.defaultNative(),
                    onProgress = { briefProgress = it })
                scenario = scenario.copy(brief = read)
                store.save(scenario, targetLanguage)
                scene = scenario
                StoreEvents.bump()
                com.roro.futurevoice.core.Analytics.capture("scenario_brief_read", mapOf(
                    "sources" to read.sources.size,
                    "links" to read.sources.count { it.kind == com.roro.futurevoice.talk.ScenarioBrief.Kind.LINK },
                    "unread" to read.sources.count { !it.readOK },
                    "questions" to read.likelyQuestions.size,
                    "expressions" to read.keyExpressions.size,
                ))
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                readingBrief = false
                generationError = e.message ?: context.getString(R.string.nothing_to_read_attach_a_link_or_a_file_first)
                return@LaunchedEffect
            }
            readingBrief = false
        }
        // What the two actually share, worked out in code — a scene about a
        // person has to open on the overlap. Builtin seeds have no person.
        val withPerson = other?.takeIf { it.remoteId?.startsWith("builtin:") != true }
        // Plus who a public figure is and how the two address each other.
        val commonGround = withPerson?.let {
            listOf(
                if (it.isPublicFigure == true) ""
                else com.roro.futurevoice.talk.CommonGround.block(persona, com.roro.futurevoice.talk.CommonGround.of(it)),
                com.roro.futurevoice.talk.ConversationCharacter.sceneCounterpartLines(it, targetLanguage),
            ).filter { b -> b.isNotBlank() }.joinToString("\n\n")
        } ?: ""
        val cast = StockPerson.by(other?.voicePresetId?.takeIf { it.isNotBlank() } ?: scenario.voicePresetId)
        // Fresh conduit per attempt, then the player — it starts playing
        // turns the moment the model produces them.
        turns.clear(); prefetches.clear()
        title = null
        loading = true
        feedComplete = false
        streamAutoStarted = false
        didFinishScene = false
        playerUp = true
        val hasScene = !scenario.curriculum?.dialogue.isNullOrEmpty()
        try {
            // The take runs outside this page's composition, as iOS's sheet
            // never stops the scene under it: covering the page with a shadow
            // line mid-stream must not throw the take away. Lines stream to
            // whichever player started it.
            val run = SceneAudioScope.async {
                val fresh = CurriculumClient(AuthRepository()).generate(
                    scenario = scenario, persona = persona, castIdentity = cast.identityIn(targetLanguage),
                    proficiency = proficiency, targetLanguage = targetLanguage,
                    avoidTitles = if (hasScene) listOfNotNull(scenario.curriculum?.dialogueTitle) else emptyList(),
                    commonGround = commonGround,
                    runKey = if (hasScene) runKey else null,
                    onTitle = { title = it.trim() },
                    onTurn = { appendStreamed(it) },
                )
                // The book keeps everything the takes have taught.
                val latest = store.load(targetLanguage).firstOrNull { it.id == scenarioId } ?: scenario
                store.save(latest.copy(
                    curriculum = latest.curriculum?.takeIf { hasScene }?.absorb(fresh) ?: fresh,
                    lastUsedAt = System.currentTimeMillis()), targetLanguage)
                StoreEvents.bump()
                fresh
            }
            SceneRuns[runId] = run
            val fresh = run.await()
            // The book is saved — only now may playback end the scene. The
            // final turns are the truth: a buffered (non-streaming) answer
            // emitted nothing incrementally, and this puts its scene up.
            val final = fresh.dialogue.orEmpty()
            if (final.size > turns.size) final.drop(turns.size).forEach { appendStreamed(it) }
            fresh.dialogueTitle?.let { title = it.trim() }
            loading = false
            feedComplete = true
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            // Off the player: the error state owns the screen (any lines
            // already heard were ephemeral — nothing persisted).
            SceneRuns.remove(runId)
            pause()
            playerUp = false
            generationError = e.message ?: e.toString()
        }
    }

    // The playing line, centred (iOS `.onChange(of: currentIndex)`).
    LaunchedEffect(currentIndex) {
        val idx = (currentIndex ?: return@LaunchedEffect) + 1 + (if (loading) 1 else 0)
        listState.animateScrollToItem(idx)
        val layout = listState.layoutInfo
        val item = layout.visibleItemsInfo.firstOrNull { it.index == idx } ?: return@LaunchedEffect
        val viewport = layout.viewportEndOffset - layout.viewportStartOffset
        listState.animateScrollBy((item.offset + item.size / 2 - viewport / 2).toFloat())
    }

    val otherPhoto = rememberPersonPhoto(scene?.counterpartId)

    Scaffold(
        containerColor = MaterialTheme.colorScheme.surface,
        topBar = {
            CenterAlignedTopAppBar(
                // The plain page, header and feed one surface (iOS
                // `WatchView`: `.background(Color(.systemBackground))`).
                colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    scrolledContainerColor = MaterialTheme.colorScheme.surface),
                title = {
                    // iOS `LevelHeaderTitle("Watching", level)`.
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(stringResource(R.string.watching),
                            style = MaterialTheme.typography.titleMedium, maxLines = 1)
                        Text(proficiency.uppercase(), style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                navigationIcon = {
                    IconButton(onClick = { pause(); onBack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        },
        bottomBar = {
            if (playerUp && generationError == null && !readingBrief) {
                Surface(color = MaterialTheme.colorScheme.surfaceContainer) {  // iOS `.bar`
                    Row(Modifier.fillMaxWidth().navigationBarsPadding()
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        if (didFinishScene) {
                            // Two states, not two extra buttons: after the end,
                            // the study handoff takes the prominent slot.
                            OutlinedButton(onClick = { playFrom(0) }, enabled = !loading,
                                modifier = Modifier.weight(1f)) {
                                ControlLabel(Icons.Filled.Refresh, stringResource(R.string.watch_again))
                            }
                            Button(onClick = { pause(); onStudy(scenarioId) }, modifier = Modifier.weight(1f)) {
                                ControlLabel(Icons.AutoMirrored.Filled.LibraryBooks, stringResource(R.string.study_this))
                            }
                        } else {
                            OutlinedButton(onClick = { playFrom(0) },
                                enabled = turns.isNotEmpty() && !loading,
                                modifier = Modifier.weight(1f)) {
                                ControlLabel(Icons.Filled.SkipPrevious, stringResource(R.string.restart))
                            }
                            Button(onClick = { if (isPlaying) pause() else playFrom(currentIndex ?: 0) },
                                enabled = turns.isNotEmpty() && !loading,
                                modifier = Modifier.weight(1f)) {
                                ControlLabel(
                                    if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                                    stringResource(if (isPlaying) R.string.pause else R.string.play))
                            }
                        }
                    }
                }
            }
        },
    ) { padding ->
        val page = Modifier.padding(padding).fillMaxSize().background(MaterialTheme.colorScheme.surface)
        when {
            playerUp && generationError == null -> {
                LazyColumn(page, state = listState,
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 18.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    item(key = "header") {
                        // iOS `WatchView.header`: who the other side is (name ·
                        // relationship), then the scene's title.
                        Column(Modifier.fillMaxWidth().padding(bottom = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            val who = listOf(counterpartName(), counterpartRelationship)
                                .filter { it.isNotBlank() }.joinToString(" · ")
                            Text(who, style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(title?.takeIf { it.isNotEmpty() } ?: fallbackTitle,
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.SemiBold)
                        }
                    }
                    if (loading) item(key = "loading") {
                        Row(Modifier.padding(vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                            Text(stringResource(R.string.writing_the_dialogue),
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    itemsIndexed(turns, key = { _, t -> t.id }) { i, turn ->
                        val isUser = turn.speaker == "user"
                        val text = turn.text
                        com.roro.futurevoice.ui.brand.DialogueLine(
                            speaker = if (isUser) com.roro.futurevoice.ui.brand.DialogueSpeaker.USER
                            else com.roro.futurevoice.ui.brand.DialogueSpeaker.OTHER,
                            // The learner's side of a watched scene is performed
                            // by the fluent self.
                            name = if (isUser) stringResource(R.string.future_self_1384d5) else counterpartName(),
                            isCurrent = currentIndex == i,
                            avatar = if (isUser) null else otherPhoto,
                            modifier = Modifier.clickable { playFrom(i) },
                            accessory = {
                                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                                    SceneLineAction(Icons.Filled.GraphicEq,
                                        stringResource(R.string.shadow_this)) {
                                        // Shadowing records the mic — stop the
                                        // scene so it doesn't bleed under it.
                                        pause()
                                        onShadow(text)
                                    }
                                    // Same learning loop as Talk: a line worth
                                    // keeping goes into the drill queue.
                                    val key = DrillIngest.normalizedForMatch(text)
                                    if (key in savedPhraseKeys) {
                                        Row(verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                            Icon(Icons.Filled.Check, contentDescription = null,
                                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                                modifier = Modifier.size(16.dp))
                                            Text(stringResource(R.string.saved),
                                                style = MaterialTheme.typography.labelMedium,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    } else if (DrillIngest.isDrillable(text)) {
                                        // Offered only for a line the store can
                                        // read back, or it never turns "Saved".
                                        SceneLineAction(Icons.Filled.AddCircleOutline,
                                            stringResource(R.string.save_phrase)) {
                                            scope.launch {
                                                val trimmed = text.trim()
                                                if (trimmed.isEmpty()) return@launch
                                                val now = System.currentTimeMillis()
                                                val sceneTitle = scene?.displayTitle.orEmpty()
                                                val card = DrillCard(
                                                    sourcePhrase = "", targetPhrase = trimmed,
                                                    reason = "From your dialogue with ${counterpartName()} — $sceneTitle",
                                                    createdAt = now, nextReviewAt = now, box = 0)
                                                if (DrillStore.shared(context).saveIfNew(card, targetLanguage) == null) return@launch
                                                savedPhraseKeys = savedPhraseKeys + DrillIngest.normalizedForMatch(trimmed)
                                                StoreEvents.bump()
                                                HapticEngine.drillCorrect(context)
                                            }
                                        }
                                    }
                                }
                            },
                        ) { Text(text) }
                    }
                }
            }
            generationError != null -> {
                // iOS `ContentUnavailableView`: the reading or the scene
                // failed; Try again reruns both.
                Column(page.padding(30.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically)) {
                    Icon(Icons.Filled.Warning, contentDescription = null,
                        modifier = Modifier.size(44.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(stringResource(R.string.couldn_t_write_the_scene),
                        style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center)
                    Text(generationError.orEmpty(), style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                    Button(onClick = { generationError = null; attempt += 1 },
                        modifier = Modifier.padding(top = 8.dp)) {
                        Text(stringResource(R.string.try_again))
                    }
                }
            }
            readingBrief -> Box(page, contentAlignment = Alignment.Center) {
                BriefProgressBoard(scene?.brief?.sources.orEmpty(), briefProgress)
            }
            else -> Column(page,
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)) {
                CircularProgressIndicator()
                Text(stringResource(R.string.writing_this_scene),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }

    playError?.let { message ->
        AlertDialog(
            onDismissRequest = { playError = null },
            title = { Text(stringResource(R.string.something_went_wrong)) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { playError = null }) { Text(stringResource(R.string.ok)) } },
        )
    }

    spent?.let { pool ->
        // Whether there is anything left to SELL is resolved by the sheet
        // (the 402 body carries no tier). "Go to Review" switches to Review
        // (iOS `pendingPracticeRoute = .studying`); this page has no tab
        // stack to stay pushed on, so it closes on the way.
        AllowanceSpentSheet(
            pool = pool,
            onReview = {
                spent = null; onBack()
                com.roro.futurevoice.data.DeepLinkInbox.pending.value =
                    com.roro.futurevoice.data.DeepLinkInbox.Destination.PRACTICE
            },
            onUpgrade = { spent = null; BillingGate.showPaywall.value = true },
            onDismiss = { spent = null },
        )
    }

    // Leaving the page stops the scene (iOS `onDisappear`): gate, then stop.
    androidx.compose.runtime.DisposableEffect(Unit) {
        onDispose { isPlaying = false; mp3.stop(); pcm.stop() }
    }
}

/** Line audio and the scene's take run here, never in a page's own scope:
 *  a synthesis in flight is already billed and lands in the cache even when
 *  nobody waits for it any more (iOS never cancels a prefetch). */
private val SceneAudioScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

/** This process's takes, by screen run — so a page covered and shown again
 *  waits for its own take instead of writing a second one. */
private val SceneRuns = mutableMapOf<String, Deferred<ScenarioCurriculum>>()

/** iOS `WatchView.prefetchDepth`: two lines ahead, so a slow line has two
 *  lines of speech to hide behind. */
private const val PREFETCH_DEPTH = 2

/** iOS `Scenario.displayTitle` — the scene's name until its own title is written. */
private val Scenario.displayTitle: String
    get() {
        val r = role.trim()
        return if (r.isEmpty()) environment else "$environment · with $r"
    }

@Composable
private fun ControlLabel(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String) {
    Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
    Text("  $label", maxLines = 1)
}

/** One line's offer: a glyph and a word, in the accent — never a button, or
 *  every line would carry two of them. */
@Composable
private fun SceneLineAction(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    Row(
        Modifier.clip(ContinuousShape(999.dp)).clickable(onClick = onClick)
            .padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(16.dp))
        Text(label, style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary)
    }
}
