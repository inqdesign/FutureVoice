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
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel

@Composable
fun RootScreen(app: AppViewModel = viewModel()) {
    val state by app.state.collectAsStateWithLifecycle()
    var inCall by remember { mutableStateOf(false) }

    when {
        state.resolvingSession -> Loading()
        !state.signedIn -> SignInScreen(state, onSignIn = app::signIn)
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
private fun SignInScreen(state: AppState, onSignIn: () -> Unit) {
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
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeScreen(
    state: AppState,
    onStartCall: () -> Unit,
    onSignOut: () -> Unit,
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

            state.error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }
        }
    }
}
