package com.roro.futurevoice.ui

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.StoreEvents
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
    var clonePreview by remember { mutableStateOf(false) }

    when {
        // DEBUG-only preview of the clone flow (iOS: `-onboardingPreview`):
        // the dev account already has a voice, so the real gate never shows.
        clonePreview -> CloneFlowScreen(
            targetLanguage = state.targetLanguage,
            onCloned = { clonePreview = false },
        )

        state.resolvingSession -> Loading()
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
                onExit = { inCall = false },
            )

        else -> HomeScreen(
            state = state,
            onStartCall = { inCall = true },
            onSignOut = app::signOut,
            onClonePreview = { clonePreview = true },
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
    onStartCall: () -> Unit,
    onSignOut: () -> Unit,
    onClonePreview: () -> Unit = {},
) {
    var micGranted by remember { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        micGranted = granted
        if (granted) onStartCall()
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
            Modifier.padding(padding).padding(24.dp).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(state.email.orEmpty(), style = MaterialTheme.typography.bodyMedium)
            HorizontalDivider()
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
                onClick = { permission.launch(Manifest.permission.RECORD_AUDIO) },
                enabled = state.voiceId != null,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Start free talk") }

            RecentTalks(language = state.targetLanguage, nativeLanguage = state.nativeLanguage, level = state.level)

            state.error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }

            if (BuildConfig.DEBUG) {
                TextButton(onClick = onClonePreview) { Text("Clone flow (debug)") }
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
