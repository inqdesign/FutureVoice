package com.roro.futurevoice.ui

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
import com.roro.futurevoice.net.EdgeError
import com.roro.futurevoice.net.ElevenLabsClient
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.StockPerson
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
    voiceId: String,
    persona: UserPersona?,
    targetLanguage: String,
    proficiency: String,
    onBack: () -> Unit,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val mp3 = remember { Mp3Player(context.cacheDir) }
    var title by remember { mutableStateOf<String?>(null) }
    var shown by remember { mutableStateOf<List<Turn>>(emptyList()) }
    var playingIndex by remember { mutableIntStateOf(-1) }
    var generating by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    val listState = rememberLazyListState()

    LaunchedEffect(scenarioId) {
        val store = ScenarioStore.shared(context)
        val scenario = store.load(targetLanguage).firstOrNull { it.id == scenarioId }
            ?: run { onBack(); return@LaunchedEffect }
        val cast = StockPerson.by(scenario.voicePresetId)
        try {
            val auth = AuthRepository()
            val runKey = UUID.randomUUID().toString().take(8)
            val fresh = CurriculumClient(auth).generate(
                scenario = scenario, persona = persona, castIdentity = cast.identity,
                proficiency = proficiency, targetLanguage = targetLanguage,
                avoidTitles = listOfNotNull(scenario.curriculum?.dialogueTitle),
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
            for (turn in fresh.dialogue.orEmpty()) {
                val isUser = turn.speaker == "user"
                shown = shown + Turn(
                    id = turn.id,
                    role = if (isUser) TurnRole.USER else TurnRole.FLUENT_SELF,
                    transcript = turn.text)
                playingIndex = shown.lastIndex
                val audio = runCatching {
                    eleven.synthesize(
                        voiceId = if (isUser) voiceId else cast.voiceId,
                        text = turn.text,
                        // The learner's own lines on the fidelity model —
                        // similarity IS the product here; preset lines don't
                        // need it (server allowlists fidelity per purpose).
                        modelId = if (isUser) ElevenLabsClient.FIDELITY_MODEL_ID
                        else ElevenLabsClient.CONVERSATION_MODEL_ID,
                        purpose = "scene",
                        sceneKey = sceneKey,
                    )
                }.getOrElse { e ->
                    if (e is EdgeError.DailyCapReached || e is EdgeError.InsufficientCredits) {
                        error = e.message; return@LaunchedEffect
                    }
                    null   // one failed line must not kill the scene
                }
                audio?.let { mp3.play(it) }
            }
            playingIndex = -1
        } catch (e: Exception) {
            generating = false
            error = e.message
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title ?: stringResource(R.string.watch)) },
                navigationIcon = {
                    IconButton(onClick = { mp3.stop(); onBack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
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
            }
            LazyColumn(state = listState, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                items(shown.size, key = { shown[it].id }) { i ->
                    DialogueLine(shown[i], isCurrent = i == playingIndex)
                }
            }
            LaunchedEffect(shown.size) {
                if (shown.isNotEmpty()) listState.animateScrollToItem(shown.lastIndex)
            }
        }
    }
}
