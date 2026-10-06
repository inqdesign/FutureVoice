package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.runtime.Composable
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.ui.SetupFlowScreen
import com.roro.futurevoice.ui.WelcomeScreen

/**
 * Capture modes for the Onboarding area. This file owns exactly these iOS modes:
 *
 *   welcome
 *   welcome-signin
 *   setup
 *   signup-account
 *
 * A mode is either WIRED (the real Android screen over `CaptureSeed` data),
 * NOT PORTED (the Android app has no such screen or feature yet — the reason
 * names the master-plan item), or absent (still NOT WIRED in the gallery).
 */
object CaptureOnboarding {
    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        // The first screen, primary path — with the sign-in link RootScreen
        // gives it (no invite path on Android, so that button is absent there too).
        // `--es welcomePage <n>` holds on one beat of the film, as iOS's
        // `-welcomePage <n>` does (n = 9 is the closing frame with the button).
        "welcome" to { c ->
            val page = (c as? android.app.Activity)?.intent?.getStringExtra("welcomePage")?.toIntOrNull() ?: 0
            WelcomeScreen(onGetStarted = {}, onGoogleSignIn = {}, onAppleSignIn = {}, initialBeat = page)
        },
        // The first-run pickers, from the same starting values the app state
        // opens a fresh install with.
        "setup" to { context ->
            val prefs = context.getSharedPreferences("futurevoice", 0)
            SetupFlowScreen(
                initialNative = prefs.getString("futurevoice.nativeLanguage", null)
                    ?: LanguageCatalog.defaultNative(),
                initialTarget = prefs.getString("futurevoice.targetLanguage", null) ?: "en",
                initialLevel = CefrLevel.from(null),
                onBackToWelcome = {},
                onFinish = { _, _, _, _ -> },
            )
        },
        // iOS `-welcomeSignIn 1`: the film's closing frame with the account
        // buttons in the Get started button's place.
        "welcome-signin" to { _ ->
            WelcomeScreen(onGetStarted = {}, onGoogleSignIn = {}, onAppleSignIn = {}, initialSignIn = true)
        },
        // The account step after the clone: keep the voice you just heard —
        // the voice act's own last stage, as iOS's `-cloneStatus account`.
        "signup-account" to { _ ->
            com.roro.futurevoice.ui.CloneFlowScreen(
                targetLanguage = "en", onCloned = {}, googleAvailable = true,
                onGoogleSignIn = {}, onAppleSignIn = {}, debugStage = "account")
        },
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf()
}
