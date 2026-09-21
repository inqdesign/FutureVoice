package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * The screenshot harness — Android's `DebugCaptureHarness` (capture build type
 * only). Launch with:
 *
 *     adb shell am start -n com.roro.futurevoice.capture/com.roro.futurevoice.MainActivity --es capture <mode>
 *
 * Mode names are iOS's, character for character, so the gallery can put the
 * two platforms side by side by name. A mode that isn't wired yet renders a
 * loud placeholder instead of silently falling through to the app — the
 * gallery must SHOW a gap, never hide one behind the home screen.
 */
object CaptureRouter {

    /** Every mode the reference iOS build (1.0.7, `4a5e8df`) answers to. */
    val iosModes: List<String> = listOf(
        "activity",
        "activity-cards",
        "activity-unsaved",
        "book",
        "book-lines",
        "book-words",
        "call-feed-fade",
        "call-goal-sheet",
        "call-goals",
        "call-meter",
        "call-meter-low",
        "carryover",
        "composer",
        "credits-out",
        "daily-expressions",
        "daily-words",
        "daily-words-full",
        "daily-words-tray",
        "day-spent",
        "day-spent-scenes",
        "day-spent-trial",
        "day-spent-trial-plus",
        "day-spent-unlimited",
        "daycard",
        "deepen",
        "deepen-full",
        "drills",
        "drills-folder",
        "drills-tray",
        "expr",
        "feedback",
        "finished",
        "finished-empty",
        "first-call",
        "free-minutes-welcome",
        "glow",
        "home",
        "home-light",
        "home-light-fresh",
        "home-plus",
        "home-ring",
        "intake-people",
        "intro-preview",
        "level-header",
        "level-sheet",
        "me",
        "paywall",
        "paywall-plans",
        "people",
        "plan",
        "plan-guide",
        "plan-trial",
        "practice-due",
        "practice-review-route",
        "practice-studying",
        "practice-talk",
        "practice-watch",
        "profile-notes",
        "progress",
        "review-due",
        "review-item-sentence",
        "review-item-word",
        "scene-end",
        "score",
        "setup",
        "shadow",
        "shadow-ja",
        "signup-account",
        "summary-progress",
        "summary-progress-start",
        "sync",
        "tabs",
        "talk-alt",
        "talk-alt-call",
        "talk-alt-demo",
        "talkdetail",
        "talkdetail-cards",
        "talkdetail-expressions",
        "talkdetail-ja",
        "talkdetail-lines",
        "talkdetail-low",
        "talkdetail-mid",
        "talkdetail-words",
        "themes",
        "transcript-ja",
        "update",
        "update-required",
        "vocab",
        "vocab-card",
        "vocab-failed",
        "vocab-loading",
        "watch",
        "watchtab",
        "watchtab-empty",
        "welcome",
        "welcome-signin",
        "widget",
        "widget-book",
        "widget-freetalk",
        "widget-freetalk-themes",
        "widget-progress",
        "widget-streak",
        "wordcard-ja",
    )

    /** Wired so far. Grows mode by mode; the gallery reports the rest. */
    private val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        "paywall" to { _ -> com.roro.futurevoice.ui.PaywallScreen(onDismiss = {}) },
    )

    /**
     * `--es lang ko` picks the app language for the shot. The language is read
     * when the activity's context is built, so a change is written and the
     * activity recreated once; the second pass renders in it.
     */
    fun content(context: Context, mode: String?, lang: String? = null): (@Composable () -> Unit)? {
        val m = mode?.takeIf { it.isNotBlank() } ?: return null
        if (lang != null && context is android.app.Activity) {
            val prefs = context.getSharedPreferences("futurevoice", 0)
            if (prefs.getString("futurevoice.nativeLanguage", null) != lang) {
                prefs.edit().putString("futurevoice.nativeLanguage", lang).commit()
                context.recreate()
                return {}
            }
        }
        val screen = wired[m]
        return if (screen != null) ({ screen(context) }) else ({ NotWired(m) })
    }

    @Composable
    private fun NotWired(mode: String) {
        Column(
            Modifier.fillMaxSize().background(Color(0xFFB00020)).padding(32.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("NOT WIRED", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Bold)
            Text(mode, color = Color.White, fontSize = 22.sp)
            Text(if (mode in iosModes) "iOS has this mode" else "not an iOS mode",
                color = Color.White, fontSize = 14.sp)
        }
    }
}
