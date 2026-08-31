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
import com.roro.futurevoice.net.TopicClient
import com.roro.futurevoice.data.DrillStore
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.talk.Scenario
import androidx.compose.material3.AlertDialog
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
    var callScenarioId by remember { mutableStateOf<String?>(null) }
    var clonePreview by remember { mutableStateOf(false) }
    var welcomeDone by remember { mutableStateOf(false) }
    var showMe by remember { mutableStateOf(false) }
    var showDeck by remember { mutableStateOf(false) }
    var detailSessionId by remember { mutableStateOf<String?>(null) }
    var watchScenarioId by remember { mutableStateOf<String?>(null) }
    var editProfile by remember { mutableStateOf(false) }
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
        !state.signedIn && !welcomeDone -> WelcomeScreen(onGetStarted = {
            welcomeDone = true
            // Account-free entry (iOS order): the server needs a session, not
            // an account — the sign-up asks to KEEP the voice, after Meet.
            app.startAnonymous()
        })
        !state.signedIn -> SignInScreen(
            state,
            googleAvailable = app.isGoogleConfigured,
            onGoogleSignIn = app::signInWithGoogle,
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
        editProfile -> PersonaIntakeScreen(
            initial = state.persona ?: com.roro.futurevoice.talk.UserPersona(),
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onBackToSetup = { editProfile = false },
            onFinish = { app.savePersona(it); editProfile = false },
        )

        watchScenarioId != null -> WatchSceneScreen(
            scenarioId = watchScenarioId!!,
            voiceId = state.voiceId ?: "",
            persona = state.persona,
            targetLanguage = state.targetLanguage,
            proficiency = state.level.code,
            onBack = { watchScenarioId = null },
        )

        detailSessionId != null -> TalkDetailScreen(
            sessionId = detailSessionId!!,
            language = state.targetLanguage,
            onBack = { detailSessionId = null },
        )

        showDeck -> DrillDeckScreen(
            language = state.targetLanguage,
            onBack = { showDeck = false },
        )

        showMe -> MeScreen(
            email = state.email,
            persona = state.persona,
            targetLanguage = state.targetLanguage,
            nativeLanguage = state.nativeLanguage,
            onSavePersona = app::savePersona,
            onEditProfile = { editProfile = true },
            onSignOut = { showMe = false; app.signOut() },
            onBack = { showMe = false },
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

        // The crash/kill guard (iOS `resumeUnclaimedVoice`): an anonymous
        // session with a voice must not reach the tabs — its data dies with
        // the install. The flow reopens on the account step.
        state.signedIn && state.isAnonymous && state.voiceId != null && !state.restoringVoice ->
            AccountScreen(
                googleAvailable = app.isGoogleConfigured,
                onGoogleSignIn = app::signInWithGoogle,
                onAppleSignIn = app::signIn,
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
                scenarioId = callScenarioId,
                onExit = { inCall = false; callTopic = ""; callFacts = emptyList(); callScenarioId = null },
            )

        else -> HomeScreen(
            state = state,
            onStartCall = { topic, facts, scenarioId ->
                callTopic = topic; callFacts = facts; callScenarioId = scenarioId; inCall = true
            },
            onOpenMe = { showMe = true },
            onOpenDeck = { showDeck = true },
            onOpenTalk = { detailSessionId = it },
            onWatch = { watchScenarioId = it },
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
    googleAvailable: Boolean = false,
    onGoogleSignIn: (android.content.Context) -> Unit = {},
    onSignIn: () -> Unit,
    onDevSignIn: (String, String) -> Unit,
) {
    val activityContext = LocalContext.current
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
            // Google first — the PRIMARY provider on Android; Apple stays for
            // iPhone switchers (their clone follows the account).
            if (googleAvailable) {
                Button(onClick = { onGoogleSignIn(activityContext) }, enabled = !state.busy,
                    modifier = Modifier.fillMaxWidth()) {
                    Text(if (state.busy) "Opening…" else "Continue with Google")
                }
            }
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
    onStartCall: (topic: String, newsFacts: List<String>, scenarioId: String?) -> Unit,
    onOpenMe: () -> Unit,
    onOpenDeck: () -> Unit = {},
    onOpenTalk: (String) -> Unit = {},
    onWatch: (String) -> Unit = {},
    onClonePreview: () -> Unit = {},
    onWelcomePreview: () -> Unit = {},
) {
    var micGranted by remember { mutableStateOf(false) }
    var pendingLaunch by remember { mutableStateOf<PendingLaunch?>(null) }
    val permission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        micGranted = granted
        if (granted) pendingLaunch?.let { onStartCall(it.topic, it.facts, it.scenarioId) }
        pendingLaunch = null
    }
    fun launch(topic: String, facts: List<String>, scenarioId: String? = null) {
        pendingLaunch = PendingLaunch(topic, facts, scenarioId)
        permission.launch(Manifest.permission.RECORD_AUDIO)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Talk") },
                actions = { TextButton(onClick = onOpenMe) { Text(stringResource(R.string.me)) } },
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

            ReviewRow(
                language = state.targetLanguage,
                onOpen = onOpenDeck,
            )

            ScenariosSection(
                targetLanguage = state.targetLanguage,
                enabled = state.voiceId != null,
                onTalk = { sc -> launch(sc.promptBlurb, emptyList(), sc.id) },
                onWatch = onWatch,
            )

            NewsSection(
                interests = state.persona?.interests.orEmpty(),
                targetLanguage = state.targetLanguage,
                enabled = state.voiceId != null,
                onTalk = { topic -> launch(topic.title, topic.facts.orEmpty()) },
            )

            RecentTalks(language = state.targetLanguage, nativeLanguage = state.nativeLanguage,
                level = state.level, onOpen = onOpenTalk)

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
private fun RecentTalks(language: String, nativeLanguage: String, level: CefrLevel,
                        onOpen: (String) -> Unit = {}) {
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
        Column(Modifier.fillMaxWidth().clickable { onOpen(s.id) }) {
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

/**
 * "Make it yours" — the sign-up AFTER the clone (`VoiceCloneOnboardingView`
 * .account): keep a voice already in the learner's ears. No skip: a session
 * is not an account, and data on one dies with the install.
 */
@Composable
private fun AccountScreen(
    googleAvailable: Boolean,
    onGoogleSignIn: (android.content.Context) -> Unit,
    onAppleSignIn: () -> Unit,
) {
    val context = LocalContext.current
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(stringResource(R.string.make_it_yours), style = MaterialTheme.typography.headlineSmall)
        Text(
            stringResource(R.string.your_voice_is_ready_sign_in_to_keep_it),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(vertical = 12.dp),
        )
        if (googleAvailable) {
            Button(onClick = { onGoogleSignIn(context) }, modifier = Modifier.fillMaxWidth()) {
                Text("Continue with Google")
            }
        }
        Button(onClick = onAppleSignIn, modifier = Modifier.fillMaxWidth()) {
            Text("Continue with Apple")
        }
    }
}

private data class PendingLaunch(val topic: String, val facts: List<String>, val scenarioId: String?)

/**
 * Your scenarios — saved situations as reusable templates, plus the
 * composer ("Make your own situation" — describe the real upcoming thing).
 * v1 is the free-text half of `ScenarioComposerSheet`: categorize is a
 * nicety and never blocks a commit.
 */
@Composable
private fun ScenariosSection(
    targetLanguage: String,
    enabled: Boolean,
    onTalk: (Scenario) -> Unit,
    onWatch: (String) -> Unit = {},
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { ScenarioStore.shared(context) }
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var scenarios by remember { mutableStateOf<List<Scenario>>(emptyList()) }
    var composing by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf("") }
    var committing by remember { mutableStateOf(false) }
    LaunchedEffect(targetLanguage, revision) { scenarios = store.load(targetLanguage) }

    Column {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.your_scenarios), style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f))
            TextButton(onClick = { composing = true }) { Text("+") }
        }
        if (scenarios.isEmpty()) {
            Text(stringResource(R.string.make_your_own_situation),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.clickable { composing = true }.padding(vertical = 6.dp))
        }
        scenarios.filter { it.archivedAt == null && it.isMeeting != true }.take(5).forEach { sc ->
            Column(
                Modifier.fillMaxWidth()
                    .clickable(enabled = enabled) {
                        scope.launch { store.touch(sc.id, targetLanguage); StoreEvents.bump() }
                        onTalk(sc)
                    }
                    .padding(vertical = 8.dp),
            ) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(sc.cardTitle, style = MaterialTheme.typography.bodyLarge)
                        sc.category?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    TextButton(onClick = { onWatch(sc.id) }) {
                        Text(stringResource(R.string.watch))
                    }
                }
            }
        }
    }

    if (composing) {
        AlertDialog(
            onDismissRequest = { if (!committing) composing = false },
            title = { Text(stringResource(R.string.make_your_own_situation)) },
            text = {
                OutlinedTextField(value = draft, onValueChange = { draft = it },
                    minLines = 3, modifier = Modifier.fillMaxWidth())
            },
            confirmButton = {
                TextButton(enabled = draft.isNotBlank() && !committing, onClick = {
                    committing = true
                    val text = draft.trim()
                    scope.launch {
                        // Categorize is a nicety — a failure just leaves the
                        // free text as the scenario (iOS rule).
                        val result = runCatching {
                            TopicClient(AuthRepository()).categorize(
                                text = text,
                                existing = scenarios.mapNotNull { it.category }.distinct(),
                                iconOptions = TopicClient.ICON_PALETTE,
                                targetLanguage = targetLanguage)
                        }.getOrNull()
                        store.save(Scenario(
                            environment = text,
                            category = result?.category?.takeIf { it.isNotBlank() },
                            categoryIcon = result?.icon,
                            summary = result?.summary?.takeIf { it.isNotBlank() },
                        ), targetLanguage)
                        StoreEvents.bump()
                        committing = false; composing = false; draft = ""
                    }
                }) { Text(stringResource(if (committing) R.string.working else R.string.create)) }
            },
            dismissButton = {
                TextButton(enabled = !committing, onClick = { composing = false }) {
                    Text(stringResource(R.string.back_b52b36))
                }
            },
        )
    }
}

/** Review cards · N due — the SRS queue's front door. Hidden while empty. */
@Composable
private fun ReviewRow(language: String, onOpen: () -> Unit) {
    val context = LocalContext.current
    val revision by StoreEvents.revision.collectAsStateWithLifecycle()
    var due by remember { mutableStateOf(0) }
    LaunchedEffect(language, revision) { due = DrillStore.shared(context).dueCount(language) }
    if (due == 0) return
    Row(
        Modifier.fillMaxWidth().clickable { onOpen() }.padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(stringResource(R.string.review_cards), style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.weight(1f))
        Text("$due", style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.primary)
    }
}
