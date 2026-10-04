package com.roro.futurevoice.ui

import androidx.compose.material.icons.filled.MenuBook
import com.roro.futurevoice.ui.brand.ContinuousShape
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Alignment
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.foundation.layout.Row
import com.roro.futurevoice.data.VocabStore
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.clickable
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.audio.Mp3Player
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.net.CurriculumClient
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.BillingGate
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.net.ElevenLabsClient
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.talk.identityIn
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.UserPersona
import java.util.UUID

/**
 * The Watch scene — `SceneWatchView`'s spine: generate the scene (one call,
 * study material in the same payload), then play it line by line — the
 * learner's side in THEIR OWN cloned voice (fidelity model: the whole point
 * of Watch is hearing yourself fluent), the counterpart on a preset voice.
 * Every line carries ONE scene_key, so the scene bills a single count and a
 * scene in progress is never cut off. A fresh take absorbs into the book
 * (scene replaces, study items accumulate).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WatchSceneScreen(
    scenarioId: String,
    /** Say this line after the fluent self — the same screen the books open. */
    onShadow: (String) -> Unit = {},
    /** Take the scene to its book, where its words and lines are studied. */
    onStudy: (String) -> Unit = {},
    voiceId: String,
    persona: UserPersona?,
    targetLanguage: String,
    proficiency: String,
    onBack: () -> Unit,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    var feedback by remember { mutableStateOf<FeedbackContext?>(null) }
    feedback?.let { FeedbackSheet(it, onDismiss = { feedback = null }) }
    val mp3 = remember { Mp3Player(context.cacheDir, source = "scene") }
    var title by remember { mutableStateOf<String?>(null) }
    var shown by remember { mutableStateOf<List<Turn>>(emptyList()) }
    val scope = rememberCoroutineScope()
    /** Bumped to play the same take again without writing a new one. */
    var replayKey by remember { mutableIntStateOf(0) }
    var playingIndex by remember { mutableIntStateOf(-1) }
    /** The scenario this scene belongs to — its who/where/what heads the page. */
    var scene by remember { mutableStateOf<com.roro.futurevoice.talk.Scenario?>(null) }
    var generating by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    /** A spent pool: a sheet, never an error line and never a bare paywall. */
    var spent by remember { mutableStateOf<SpentPool?>(null) }
    /** True while the scenario's attached material is read — the board owns
     *  the screen, and the scene is written only once the brief is on the
     *  scenario. Once per change to the material, never per take. */
    var readingBrief by remember { mutableStateOf(false) }
    var briefProgress by remember { mutableStateOf(com.roro.futurevoice.net.ScenarioBriefEngine.Progress()) }
    /** The counterpart's photo, for their speaker label. */
    var otherId by remember { mutableStateOf<String?>(null) }
    val listState = rememberLazyListState()

    LaunchedEffect(scenarioId, replayKey) {
        val store = ScenarioStore.shared(context)
        error = null
        var scenario = store.load(targetLanguage).firstOrNull { it.id == scenarioId }
            ?.also { scene = it; otherId = it.counterpartId }
            ?: run { onBack(); return@LaunchedEffect }
        // Material first (iOS `59c6481`). A brief with sources but no reading
        // yet is read here, once, with the board on screen; the scene below
        // is then written FROM it. A failed reading is the error state (Try
        // again reruns both), never a scene quietly written without the
        // material the learner attached.
        val pending = scenario.brief
        if (pending != null && pending.needsReading &&
            !com.roro.futurevoice.capture.flags.WatchCaptureFlags.previewSceneFinished) {
            readingBrief = true
            generating = false
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
                error = e.message ?: context.getString(R.string.nothing_to_read_attach_a_link_or_a_file_first)
                return@LaunchedEffect
            }
            readingBrief = false
            generating = true
        }
        // Capture only: the scene as it stands once it has played out, from
        // the saved take — no model call, no TTS.
        if (com.roro.futurevoice.capture.flags.WatchCaptureFlags.previewSceneFinished) {
            title = scenario.curriculum?.dialogueTitle
            shown = scenario.curriculum?.dialogue.orEmpty().map {
                Turn(id = it.id, role = if (it.speaker == "user") TurnRole.USER else TurnRole.FLUENT_SELF,
                    transcript = it.text)
            }
            generating = false; playingIndex = -1
            return@LaunchedEffect
        }
        val cast = StockPerson.by(scenario.voicePresetId)
        // What the two actually share, worked out in code — a scene about a
        // person has to open on the overlap, not on a fact plucked from one
        // side. Builtin seeds have no real person behind them.
        val withPerson = scenario.counterpartId?.let { id ->
            com.roro.futurevoice.data.CounterpartStore.shared(context).load().firstOrNull { it.id == id }
        }?.takeIf { it.remoteId?.startsWith("builtin:") != true }
        // Plus who a public figure is and how the two address each other
        // (iOS `ede039e`), which rides in the same verbatim block.
        val commonGround = withPerson?.let {
            listOf(
                // A public figure's old profile fields are never read: the
                // identity is the whole person.
                if (it.isPublicFigure == true) ""
                else com.roro.futurevoice.talk.CommonGround.block(persona, com.roro.futurevoice.talk.CommonGround.of(it)),
                com.roro.futurevoice.talk.ConversationCharacter.sceneCounterpartLines(it, targetLanguage),
            ).filter { b -> b.isNotBlank() }.joinToString("\n\n")
        } ?: ""
        try {
            val auth = AuthRepository()
            val runKey = UUID.randomUUID().toString().take(8)
            val fresh = CurriculumClient(auth).generate(
                scenario = scenario, persona = persona, castIdentity = cast.identityIn(targetLanguage),
                proficiency = proficiency, targetLanguage = targetLanguage,
                avoidTitles = listOfNotNull(scenario.curriculum?.dialogueTitle),
                commonGround = commonGround,
                runKey = if (scenario.curriculum == null) null else runKey,
            )
            generating = false
            title = fresh.dialogueTitle
            // The book keeps everything the takes have taught.
            store.save(scenario.copy(
                curriculum = scenario.curriculum?.absorb(fresh) ?: fresh,
                lastUsedAt = System.currentTimeMillis()), targetLanguage)
            StoreEvents.bump()

            // ── Play the scene: one scene_key for every line = ONE count.
            val eleven = ElevenLabsClient(auth)
            val sceneKey = "scene:${scenario.id}:$runKey"
            var sceneCounted = false
            for (turn in fresh.dialogue.orEmpty()) {
                val isUser = turn.speaker == "user"
                shown = shown + Turn(
                    id = turn.id,
                    role = if (isUser) TurnRole.USER else TurnRole.FLUENT_SELF,
                    transcript = turn.text)
                playingIndex = shown.lastIndex
                val audio = runCatching {
                    // Cache first — a scene replayed from Practice must not
                    // re-bill lines the learner already owns.
                    com.roro.futurevoice.data.cachedSynthesis(
                        context,
                        voiceId = if (isUser) voiceId else cast.voiceId,
                        text = turn.text,
                        // The learner's own lines on the fidelity model —
                        // similarity IS the product here; preset lines don't
                        // need it (server allowlists fidelity per purpose).
                        modelId = if (isUser) ElevenLabsClient.CLONE_MODEL_ID
                        else ElevenLabsClient.CONVERSATION_MODEL_ID,
                        purpose = "scene",
                        sceneKey = sceneKey,
                    )
                }.getOrElse { e ->
                    when (e) {
                        // The free pool is genuinely empty — this account has
                        // nothing to spend, so the paywall IS the answer.
                        is EdgeError.InsufficientCredits -> {
                            BillingGate.invalidate()
                            BillingGate.showPaywall.value = true
                            return@LaunchedEffect
                        }
                        // They already paid; the pool refills on its own.
                        is EdgeError.SceneCapReached -> {
                            spent = SpentPool.SCENES; return@LaunchedEffect
                        }
                        is EdgeError.DailyCapReached -> {
                            spent = SpentPool.TALK; return@LaunchedEffect
                        }
                        else -> null   // one failed line must not kill the scene
                    }
                }
                audio?.let {
                    // A scene the learner sat through is effort, so it keeps
                    // a streak alive — logged ONCE, when its first line is
                    // actually heard. Out of the daily goal: the goal counts
                    // work they did, and a scene plays itself.
                    if (!sceneCounted) {
                        sceneCounted = true
                        com.roro.futurevoice.data.PracticeLog.record(
                            context, com.roro.futurevoice.data.PracticeLog.Kind.SCENE)
                    }
                    mp3.play(it)
                }
            }
            playingIndex = -1
            // No ask here any more. The one feedback moment is after a
            // returning TALK: a scene just played is a poor place to stop
            // someone, and two asks competing meant whichever fired first
            // silenced the other.
        } catch (e: Exception) {
            generating = false
            error = e.message
        }
    }

    val otherPhoto = rememberPersonPhoto(otherId)
    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = {
                    Column {
                        Text(stringResource(R.string.watching),
                            style = MaterialTheme.typography.titleMedium)
                        Text(proficiency.uppercase(), style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                navigationIcon = {
                    IconButton(onClick = { mp3.stop(); onBack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        if (readingBrief) {
            val sources = scene?.brief?.sources.orEmpty()
            androidx.compose.foundation.layout.Box(
                Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground),
                contentAlignment = Alignment.Center,
            ) { BriefProgressBoard(sources, briefProgress) }
            return@Scaffold
        }
        Column(Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground).padding(16.dp)) {
            if (generating) {
                LinearProgressIndicator(Modifier.fillMaxWidth())
                Text(stringResource(R.string.writing_the_scene),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp))
            }
            error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
                // Reruns the whole thing — the reading, then the scene.
                if (shown.isEmpty()) {
                    OutlinedButton(onClick = { replayKey += 1 }, modifier = Modifier.padding(top = 8.dp)) {
                        Text(stringResource(R.string.try_again))
                    }
                }
            }
            LazyColumn(state = listState, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item {
                    Column(Modifier.padding(bottom = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        val who = listOfNotNull(
                            scene?.role?.takeIf { it.isNotBlank() },
                            scene?.environment?.takeIf { it.isNotBlank() },
                        ).joinToString(" · ")
                        if (who.isNotEmpty()) {
                            Text(who, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        title?.let {
                            Text(it, style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.SemiBold)
                        }
                        scene?.notes?.takeIf { it.isNotBlank() }?.let {
                            Text(it, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                items(shown.size, key = { shown[it].id }) { i ->
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        val isUser = shown[i].role == TurnRole.USER
                        com.roro.futurevoice.ui.brand.DialogueLine(
                            speaker = if (isUser) com.roro.futurevoice.ui.brand.DialogueSpeaker.USER
                            else com.roro.futurevoice.ui.brand.DialogueSpeaker.OTHER,
                            name = if (isUser) stringResource(R.string.future_self_1384d5)
                            else scene?.role?.takeIf { it.isNotBlank() }?.substringBefore(" —")?.trim()
                                ?: stringResource(R.string.future_self_1384d5),
                            isCurrent = i == playingIndex,
                            // The same face the stories row shows.
                            avatar = if (isUser) null else otherPhoto,
                        ) { Text(shown[i].transcript) }
                        // Every line is material: say it after them, or keep
                        // it. Offered per LINE, as on iOS — a bar at the
                        // bottom would ask which line it meant.
                        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            SceneLineAction(Icons.Filled.GraphicEq,
                                stringResource(R.string.shadow_this_line)) { onShadow(shown[i].transcript) }
                            SceneLineAction(Icons.Filled.AddCircleOutline,
                                stringResource(R.string.save_expression)) {
                                scope.launch {
                                    VocabStore.shared(context)
                                        .setStudyingExpression(shown[i].transcript, true, targetLanguage)
                                    StoreEvents.bump()
                                }
                            }
                        }
                    }
                }
            }
            LaunchedEffect(shown.size) {
                if (shown.isNotEmpty()) listState.animateScrollToItem(shown.lastIndex)
            }
            // Once the scene has played itself out: hear it again, or go
            // study what it taught. Nothing else belongs at the end of a
            // scene — the book is where the material lives.
            if (!generating && playingIndex < 0 && shown.isNotEmpty()) {
                Row(Modifier.fillMaxWidth().padding(top = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = { replayKey += 1 }, modifier = Modifier.weight(1f)) {
                        Icon(Icons.Filled.Refresh, contentDescription = null,
                            modifier = Modifier.size(18.dp))
                        Text("  " + stringResource(R.string.watch_again))
                    }
                    Button(onClick = { onStudy(scenarioId) }, modifier = Modifier.weight(1f)) {
                        Icon(Icons.Filled.MenuBook, contentDescription = null,
                            modifier = Modifier.size(18.dp))
                        Text("  " + stringResource(R.string.study_this))
                    }
                }
            }
        }
    }

    spent?.let { pool ->
        // Whether there is anything left to SELL is resolved client-side: the
        // 402 body carries no tier, and on Plus the upgrade half must be
        // absent rather than disabled.
        var canUpgrade by remember { mutableStateOf(false) }
        LaunchedEffect(Unit) { canUpgrade = AccountStatus.load(AuthRepository()).isLightPlan }
        AllowanceSpentSheet(
            pool = pool,
            canUpgrade = canUpgrade,
            onReview = { spent = null; onBack() },
            onUpgrade = { spent = null; BillingGate.showPaywall.value = true },
            onDismiss = { spent = null },
        )
    }
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
