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
        "welcome" to { _ -> WelcomeScreen(onGetStarted = {}, onSignIn = {}) },
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
        // iOS's sign-in step. On Android it is a screen of its own inside the
        // root router; shown here signed out, with the Google button as a
        // fresh install without a client id would draw it.
        "welcome-signin" to { _ ->
            com.roro.futurevoice.ui.SignInScreen(
                state = com.roro.futurevoice.ui.AppState(),
                onSignIn = {}, onDevSignIn = { _, _ -> })
        },
        // The account step after the clone: keep the voice you just heard.
        "signup-account" to { _ ->
            com.roro.futurevoice.ui.AccountScreen(
                googleAvailable = true, onGoogleSignIn = {}, onAppleSignIn = {})
        },
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf()
}
