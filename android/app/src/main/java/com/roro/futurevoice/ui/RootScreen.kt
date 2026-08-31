package com.roro.futurevoice.ui

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import com.roro.futurevoice.BuildConfig
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.roro.futurevoice.R
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.rememberCoroutineScope
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.NewsTopicStore
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.data.TalkTimeLog
import com.roro.futurevoice.net.NewsClient
import com.roro.futurevoice.talk.SuggestedTopic
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionSummarizer
import com.roro.futurevoice.talk.TurnRole
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@Composable
fun RootScreen() {
    val context = androidx.compose.ui.platform.LocalContext.current
    val app: AppViewModel = viewModel(factory = androidx.lifecycle.viewmodel.viewModelFactory {
        initializer { AppViewModel(context.applicationContext) }
    })
    val state by app.state.collectAsStateWithLifecycle()
    var inCall by remember { mutableStateOf(false) }
    var callTopic by remember { mutableStateOf("") }
    var callFacts by remember { mutableStateOf<List<String>>(emptyList()) }
    var clonePreview by remember { mutableStateOf(false) }
    var welcomeDone by remember { mutableStateOf(false) }
    var welcomePreview by remember { mutableStateOf(false) }

    when {
        welcomePreview -> WelcomeScreen(onGetStarted = { welcomePreview = false })

        // DEBUG-only preview of the clone flow (iOS: `-onboardingPreview`):
        // the dev account already has a voice, so the real gate never shows.
        clonePreview -> CloneFlowScreen(
            targetLanguage = state.targetLanguage,
            onCloned = { clonePreview = false },
        )

        state.resolvingSession -> Loading()
        // The pitch before the ask — the five beats a first-time user must
        // agree with before an account means anything. Returning users
        // (stored session) never see it.
        !state.signedIn && !welcomeDone -> WelcomeScreen(onGetStarted = { welcomeDone = true })
        !state.signedIn -> SignInScreen(
            state,
            onSignIn = app::signIn,
            onDevSignIn = app::devSignIn,
        )
        // First-run answers before anything else — what to teach and how to
        // calibrate. (iOS order puts Welcome before sign-in; Android's
        // account-free entry arrives with the Google-auth work.)
        !state.setupComplete -> SetupFlowScreen(
            initialNative = state.nativeLanguage,
            initialTarget = state.targetLanguage,
            initialLevel = state.level,
            onBackToWelcome = app::signOut,
            onFinish = app::completeSetup,
        )
        // Light taps before the heavy ask (iOS order): persona cards build
        // the investment and the first call's context BEFORE the recording.
        state.personaResolved && state.persona == null -> PersonaIntakeScreen(
            initial = com.roro.futurevoice.talk.UserPersona(),
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onBackToSetup = { app.reopenSetup() },
            onFinish = app::savePersona,
        )

        // No voice on the account: an Android user starts HERE — they clone
        // on Android (roadmap §1.2), they are not sent to an iPhone. Mic
        // permission is asked by the flow's record button via HomeScreen's
        // launcher pattern; the screen itself only records after it.
        !state.restoringVoice && state.voiceId == null -> CloneFlowScreen(
            targetLanguage = state.targetLanguage,
            onCloned = app::onVoiceCloned,
        )

        inCall && state.voiceId != null ->
            TalkScreen(
                voiceId = state.voiceId!!,
                targetLanguage = state.targetLanguage,
                nativeLanguage = state.nativeLanguage,
                level = state.level,
                persona = state.persona,
                topic = callTopic,
                newsFacts = callFacts,
                onExit = { inCall = false; callTopic = ""; callFacts = emptyList() },
            )

        else -> HomeScreen(
            state = state,
            onStartCall = { topic, facts -> callTopic = topic; callFacts = facts; inCall = true },
            onSignOut = app::signOut,
            onClonePreview = { clonePreview = true },
            onWelcomePreview = { welcomePreview = true },
        )
    }
}

@Composable
private fun Loading() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

@Composable
private fun SignInScreen(
    state: AppState,
    onSignIn: () -> Unit,
    onDevSignIn: (String, String) -> Unit,
) {
    var devEmail by remember { mutableStateOf("") }
    var devPassword by remember { mutableStateOf("") }
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Future Voice", style = MaterialTheme.typography.headlineMedium)
            Text(
                "Sign in with the same Apple ID you use on iPhone — your cloned " +
                    "voice comes with you.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Button(onClick = onSignIn, enabled = !state.busy) {
                Text(if (state.busy) "Opening…" else "Continue with Apple")
            }
            state.error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }
            // Emulator escape hatch while Apple web-OAuth setup is pending.
            // Debug builds only — this whole block is compiled out of release,
            // and production accounts are Apple-only so email reaches nothing real.
            if (BuildConfig.DEBUG) {
                OutlinedTextField(
                    value = devEmail,
                    onValueChange = { devEmail = it },
                    label = { Text("Dev email") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = devPassword,
                    onValueChange = { devPassword = it },
                    label = { Text("Dev password") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                TextButton(
                    onClick = { onDevSignIn(devEmail, devPassword) },
                    enabled = devEmail.isNotBlank() && devPassword.isNotBlank() && !state.busy,
                ) { Text("Dev sign-in") }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeScreen(
    state: AppState,
    onStartCall: (topic: String, newsFacts: List<String>) -> Unit,
    onSignOut: () -> Unit,
    onClonePreview: () -> Unit = {},
    onWelcomePreview: () -> Unit = {},
) {
    var micGranted by remember { mutableStateOf(false) }
    var pendingLaunch by remember { mutableStateOf<Pair<String, List<String>>?>(null) }
    val permission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        micGranted = granted
        if (granted) pendingLaunch?.let { onStartCall(it.first, it.second) }
        pendingLaunch = null
    }
    fun launch(topic: String, facts: List<String>) {
        pendingLaunch = topic to facts
        permission.launch(Manifest.permission.RECORD_AUDIO)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Talk") },
                actions = { TextButton(onClick = onSignOut) { Text("Sign out") } },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).padding(24.dp).fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(state.email.orEmpty(), style = MaterialTheme.typography.bodyMedium)
            HorizontalDivider()
            TodayRow()
            when {
                state.restoringVoice -> Text("Restoring your voice…")
                state.voiceId != null -> Text(
                    "Your voice is ready.",
                    style = MaterialTheme.typography.bodyLarge,
                )

                else -> Text(
                    "No voice clone on this account yet. Record one on iPhone " +
                        "first — Android restores it, it never re-clones.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            Button(
                onClick = { launch("", emptyList()) },
                enabled = state.voiceId != null,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Start free talk") }

            NewsSection(
                interests = state.persona?.interests.orEmpty(),
                targetLanguage = state.targetLanguage,
                enabled = state.voiceId != null,
                onTalk = { topic -> launch(topic.title, topic.facts.orEmpty()) },
            )

            RecentTalks(language = state.targetLanguage, nativeLanguage = state.nativeLanguage, level = state.level)

            state.error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }

            if (BuildConfig.DEBUG) {
                TextButton(onClick = onClonePreview) { Text("Clone flow (debug)") }
                TextButton(onClick = onWelcomePreview) { Text("Welcome (debug)") }
            }
        }
    }
}

/**
 * The talks already on this phone — proof the loop persists. Reloads every
 * time Home comes back into composition (i.e. after every call).
 */
@Composable
private fun RecentTalks(language: String, nativeLanguage: String, level: CefrLevel) {
    val context = LocalContext.current
    val store = remember { SessionStore.shared(context) }
    var talks by remember { mutableStateOf<List<Session>>(emptyList()) }
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val inFlight by SessionSummarizer.inFlight.collectAsStateWithLifecycle()
    val progressBySession by SessionSummarizer.progressBySession.collectAsStateWithLifecycle()
    LaunchedEffect(language, revision) { talks = store.load(language) }
    if (talks.isEmpty()) return
    HorizontalDivider()
    Text(stringResource(R.string.talks), style = MaterialTheme.typography.titleMedium)
    val formatter = remember { DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT) }
    talks.take(10).forEach { s ->
        Column {
            Text(
                s.displayTitle ?: stringResource(R.string.conversation),
                style = MaterialTheme.typography.bodyLarge,
            )
            Text(
                formatter.format(Instant.ofEpochMilli(s.rank).atZone(ZoneId.systemDefault())) +
                    " · " + stringResource(R.string.lld_turns, s.turns.count { it.role == TurnRole.USER }) +
                    (s.summary?.scorecard?.let { " · ${it.overall}" } ?: ""),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            s.summary?.scorecard?.topLine?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall)
            }
            // The rescue path (iOS: ConversationDetailView): a talk saved
            // before its analysis finished isn't half a book, it's no book —
            // so it can always be run again from here.
            if (SessionSummarizer.needsSummary(s)) {
                val working = s.id in inFlight
                if (working) {
                    // The rescue path draws the SAME board as the live
                    // wrap-up (`ConversationDetailView` does on iOS).
                    SummaryBoard(progressBySession[s.id] ?: SessionSummarizer.Progress())
                } else {
                    TextButton(
                        onClick = { SessionSummarizer.summarizeInBackground(context, s, nativeLanguage, level) },
                    ) { Text(stringResource(R.string.generate_review_material)) }
                }
            }
        }
    }
}

/** The day's metered talk against the learner's own goal. */
@Composable
private fun TodayRow() {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    val goalMinutes = remember {
        context.getSharedPreferences("futurevoice", 0).getInt("futurevoice.dailyGoalMinutes", 10)
    }
    var seconds by remember { mutableStateOf(0) }
    LaunchedEffect(revision) { seconds = TalkTimeLog.secondsToday(context) }
    Column {
        Text(stringResource(R.string.today), style = MaterialTheme.typography.titleMedium)
        Text(
            stringResource(R.string.lld_of_lld_min_today, seconds / 60, goalMinutes),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        LinearProgressIndicator(
            progress = { (seconds / 60f / goalMinutes).coerceIn(0f, 1f) },
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
        )
    }
}

/**
 * In the news — the platform pool for the learner's interests
 * (`NewsTopicSection`). Cache-first; the server keeps cooking pending
 * categories and each poll paints what landed. A tap talks ABOUT the story:
 * the title becomes the topic, the grounded facts seed the prompt.
 */
@Composable
private fun NewsSection(
    interests: List<String>,
    targetLanguage: String,
    enabled: Boolean,
    onTalk: (SuggestedTopic) -> Unit,
) {
    if (interests.isEmpty()) return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { NewsTopicStore.shared(context) }
    var topics by remember { mutableStateOf<List<SuggestedTopic>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }

    fun displaySelection(pool: List<SuggestedTopic>): List<SuggestedTopic> {
        val seen = store.seenTitles(interests, targetLanguage).toSet()
        val current = topics.map { it.title }.toSet()
        val unseen = pool.filter { it.title !in seen }
        val offscreen = pool.filter { it.title in seen && it.title !in current }
        val onscreen = pool.filter { it.title in seen && it.title in current }
        return (unseen + offscreen + onscreen).take(NewsClient.MAX_SHOWN)
    }

    suspend fun fetchNews(refresh: Boolean) {
        loading = true
        try {
            val client = NewsClient(AuthRepository())
            var pool = client.fetch(interests, targetLanguage, refresh)
            if (pool.topics.isNotEmpty()) {
                store.save(pool.topics, interests, targetLanguage)
                topics = displaySelection(pool.topics)
            }
            var polls = 0
            var target = if (pool.growing) pool.topics.size + 1 else 0
            while (polls < NewsClient.MAX_POLLS && (!pool.isComplete || pool.topics.size < target)) {
                delay(NewsClient.POLL_INTERVAL_MS)
                polls += 1
                pool = client.fetch(interests, targetLanguage)
                if (pool.topics.isNotEmpty()) {
                    store.save(pool.topics, interests, targetLanguage)
                    topics = displaySelection(pool.topics)
                }
                if (pool.topics.size >= target) target = 0
            }
        } catch (_: kotlinx.coroutines.CancellationException) {
        } catch (_: Exception) {
        } finally { loading = false }
    }

    LaunchedEffect(interests, targetLanguage) {
        val cached = store.valid(interests, targetLanguage)
        if (cached != null) topics = displaySelection(cached) else fetchNews(refresh = false)
    }

    Column {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.news), style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f))
            TextButton(onClick = {
                scope.launch {
                    // Rotating the unseen pool is free — only ask the server
                    // once the local pool is exhausted (iOS refresh rule).
                    val cached = store.valid(interests, targetLanguage)
                    if (cached != null && cached.size > topics.size) {
                        store.markSeen(topics.map { it.title }, interests, targetLanguage)
                        val rotated = displaySelection(cached)
                        if (rotated.map { it.title } != topics.map { it.title }) {
                            topics = rotated; return@launch
                        }
                    }
                    store.markSeen(topics.map { it.title }, interests, targetLanguage)
                    fetchNews(refresh = true)
                }
            }) { Text(stringResource(R.string.refresh)) }
        }
        if (loading && topics.isEmpty()) {
            LinearProgressIndicator(Modifier.fillMaxWidth())
        }
        topics.forEach { topic ->
            Column(
                Modifier.fillMaxWidth()
                    .clickable(enabled = enabled) { onTalk(topic) }
                    .padding(vertical = 8.dp),
            ) {
                Text(topic.title, style = MaterialTheme.typography.bodyLarge)
                Text(topic.blurb, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
