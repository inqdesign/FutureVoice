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

    /** Every mode the reference iOS build (1.1.4 (71), `ebf848e`) answers to. */
    val iosModes: List<String> = listOf(
        "activity",
        "activity-cards",
        "activity-unsaved",
        "activity-week",
        "activity-week-edit",
        "app-guide",
        "backup-offer",
        "book",
        "book-lines",
        "book-words",
        "call-coach",
        "call-feed-fade",
        "call-focus",
        "call-focus-sheet",
        "call-goal-sheet",
        "call-goals",
        "call-meter",
        "call-meter-low",
        "call-settings",
        "carryover",
        "composer",
        "credits-out",
        "daily-expressions",
        "daily-words",
        "daily-words-full",
        "daily-words-tray",
        "day-spent",
        "day-spent-invite",
        "day-spent-plus",
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
        "expr-card",
        "feedback",
        "finished",
        "finished-empty",
        "first-call",
        "first-call-check",
        "first-call-check-hard",
        "focus-result",
        "free-minutes-welcome",
        "glow",
        "home",
        "home-light",
        "home-light-fresh",
        "home-plus",
        "home-ring",
        "home-scenarios",
        "intake-people",
        "intro-preview",
        "level-header",
        "level-sheet",
        "me",
        "paywall",
        "paywall-ladder-pack",
        "paywall-plans",
        "people",
        "plan",
        "plan-block",
        "plan-editor",
        "plan-guide",
        "plan-spent",
        "plan-trial",
        "practice-due",
        "practice-review-route",
        "practice-studying",
        "practice-talk",
        "practice-today",
        "practice-watch",
        "practice-week",
        "practice-weekly",
        "profile-name",
        "profile-notes",
        "progress",
        "progress-beginner",
        "progress-beginner-grammar",
        "progress-grammar",
        "review-due",
        "review-item-sentence",
        "review-item-word",
        "routine-new",
        "scene-end",
        "score",
        "setup",
        "shadow",
        "shadow-ja",
        "signup-account",
        "summary-progress",
        "summary-progress-start",
        "sync",
        "sync-other-device",
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
        "transcript",
        "transcript-ja",
        "update",
        "update-required",
        "vocab",
        "vocab-card",
        "vocab-failed",
        "vocab-loading",
        "voice-revival",
        "voice-revival-tune",
        "watch",
        "watchtab",
        "watchtab-empty",
        "week-archive",
        "week-recap",
        "week-recap-quiet",
        "weekly-test-build",
        "weekly-test-build-right",
        "weekly-test-build-wrong",
        "weekly-test-gap",
        "weekly-test-gap-wrong",
        "weekly-test-grammar",
        "weekly-test-grammar-right",
        "weekly-test-grammar-wrong",
        "weekly-test-listen",
        "weekly-test-result",
        "weekly-test-speak",
        "weekly-test-upgrade",
        "weekly-test-upgrade-right",
        "weekly-test-upgrade-wrong",
        "weekly-test-word",
        "weekly-test-word-right",
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
    /** Each area owns its own file, so areas can be wired independently. */
    private val areas = listOf(
        CaptureTalk.wired, CaptureWatch.wired, CapturePractice.wired, CaptureProgress.wired,
        CaptureMe.wired, CaptureOnboarding.wired, CaptureWidgets.wired, CaptureWeeklyTest.wired,
        CaptureShadow.wired, CaptureWeekRecap.wired, CaptureRoutine.wired,
        CaptureGuide.wired,
    )
    private val wired: Map<String, @Composable (Context) -> Unit> = areas.fold(emptyMap()) { a, b -> a + b }
    private val notPorted: Map<String, String> =
        listOf(CaptureTalk.notPorted, CaptureWatch.notPorted, CapturePractice.notPorted,
            CaptureProgress.notPorted, CaptureMe.notPorted, CaptureOnboarding.notPorted,
            CaptureWidgets.notPorted, CaptureWeeklyTest.notPorted).fold(emptyMap()) { a, b -> a + b }

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
        // `--es seed all` runs every sample seed (CaptureSeed) before the
        // screen is built — a way to inspect the seeded stores on their own.
        if (context is android.app.Activity && context.intent.getStringExtra("seed") == "all") {
            kotlinx.coroutines.runBlocking { CaptureSeed.seedAll(context) }
        }
        val screen = wired[m]
        val reason = notPorted[m]
        return when {
            screen != null -> ({ screen(context) })
            reason != null -> ({ NotPorted(m, reason) })
            else -> ({ NotWired(m) })
        }
    }

    /** Orange, not red: the harness is fine, the APP lacks this — and the
     *  reason names the master-plan item that will add it. */
    @Composable
    private fun NotPorted(mode: String, reason: String) {
        Column(
            Modifier.fillMaxSize().background(Color(0xFFE65100)).padding(32.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("NOT PORTED", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Bold)
            Text(mode, color = Color.White, fontSize = 22.sp)
            Text(reason, color = Color.White, fontSize = 14.sp)
        }
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
