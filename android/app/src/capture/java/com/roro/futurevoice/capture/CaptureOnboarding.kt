package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
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
    val wired: Map<String, @Composable (Context) -> Unit> = mapOf<String, @Composable (Context) -> Unit>(
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
        // Not iOS mode names: the bottom-inset survey's own shots (master
        // plan "Bottom insets survey"). The two steps after the voice, and the
        // retroactive age check over an empty page.
        "daily-call-onboarding" to { c ->
            com.roro.futurevoice.ui.DailyCallOnboardingScreen(c, onDone = {})
        },
        "weekly-rhythm-onboarding" to { c ->
            com.roro.futurevoice.ui.WeeklyRhythmOnboardingScreen(c, onDone = {})
        },
        // The voice act, one stage each (the debug app's `--es cloneStage`,
        // which only answers on an install that isn't set up yet).
    ) + listOf("intro", "consent", "mic", "spot", "script", "recording", "reviewing", "uploading", "meet")
        .associate<String, String, @Composable (Context) -> Unit> { st ->
            "clone-$st" to @Composable { _: Context ->
                com.roro.futurevoice.ui.CloneFlowScreen(
                    targetLanguage = "en", onCloned = {}, googleAvailable = true,
                    onGoogleSignIn = {}, onAppleSignIn = {}, debugStage = st)
            }
        } + mapOf<String, @Composable (Context) -> Unit>(
        // Sheets no iOS mode reaches, for the same survey: each over an empty
        // page, no network.
        "sheet-interests" to { _ -> SheetPage { com.roro.futurevoice.ui.InterestsEditorSheet(
            com.roro.futurevoice.talk.UserPersona(), onSave = {}, onDismiss = {}) } },
        "sheet-level-info" to { _ -> SheetPage { com.roro.futurevoice.ui.LevelInfoSheet(
            com.roro.futurevoice.data.CefrLevel.B1, onDismiss = {}) } },
        "sheet-level-up" to { _ -> SheetPage { com.roro.futurevoice.ui.LevelUpSheet(
            com.roro.futurevoice.data.CefrLevel.A2, com.roro.futurevoice.data.CefrLevel.B1, onDismiss = {}) } },
        "sheet-mic-choice" to { _ -> SheetPage { com.roro.futurevoice.ui.MicChoiceSheet(onChoose = {}) } },
        "sheet-referral-join" to { _ -> SheetPage { com.roro.futurevoice.ui.ReferralJoinSheet(
            com.roro.futurevoice.data.ReferralJoins.Join("x", "Jiwoo", 1, 1, 30), onDismiss = {}) } },
        "sheet-study-goals" to { _ -> SheetPage { com.roro.futurevoice.ui.StudyGoalsSheet(onDismiss = {}) } },
        "age-check" to { _ ->
            androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.fillMaxSize()
                .background(com.roro.futurevoice.ui.brand.AppSurfaces.ground))
            com.roro.futurevoice.ui.AgeCheckSheet(onDismiss = {})
        },
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf()
}

@Composable
private fun SheetPage(sheet: @Composable () -> Unit) {
    androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.fillMaxSize()
        .background(com.roro.futurevoice.ui.brand.AppSurfaces.ground))
    sheet()
}
