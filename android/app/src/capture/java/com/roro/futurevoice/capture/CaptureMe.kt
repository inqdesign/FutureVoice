package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import com.roro.futurevoice.capture.flags.MeCaptureFlags
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.AppUpdateService
import com.roro.futurevoice.data.BillingService
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.PersonaStore
import com.roro.futurevoice.talk.UserPersona
import com.roro.futurevoice.ui.AllowanceSpentSheet
import com.roro.futurevoice.ui.CreditGuideScreen
import com.roro.futurevoice.ui.FeedbackContext
import com.roro.futurevoice.ui.FeedbackSheet
import com.roro.futurevoice.ui.MeScreen
import com.roro.futurevoice.ui.PaywallScreen
import com.roro.futurevoice.ui.PlanPageScreen
import com.roro.futurevoice.ui.SpentPool
import com.roro.futurevoice.ui.UpdateAvailableSheet
import com.roro.futurevoice.ui.brand.AppSurfaces

/**
 * Capture modes for the Me area. This file owns exactly these iOS modes:
 *
 *   me
 *   plan
 *   plan-guide
 *   plan-trial
 *   paywall
 *   paywall-plans
 *   day-spent
 *   day-spent-scenes
 *   day-spent-unlimited
 *   day-spent-trial
 *   day-spent-trial-plus
 *   credits-out
 *   update
 *   update-required
 *   sync
 *   feedback
 *
 * A mode is either WIRED (the real Android screen over `CaptureSeed` data),
 * NOT PORTED (the Android app has no such screen or feature yet — the reason
 * names the master-plan item), or absent (still NOT WIRED in the gallery).
 *
 * Billing screens never touch the network here: they are handed
 * `CaptureSeed.sampleLightAccount` / `sampleTrialAccount` through
 * [MeCaptureFlags], the way iOS passes `account:` into the view. `plan` and
 * `plan-guide` share ONE account on purpose — the two pages quote each other.
 *
 * iOS presents the sheets (`day-spent*`, `update*`, `feedback`) over the Talk
 * home; Android draws them over the plain page ground — the home belongs to
 * the Talk area and needs its own seeded state.
 */
object CaptureMe {
    val wired: Map<String, @Composable (Context) -> Unit> = mapOf(
        "paywall" to { _ -> PaywallScreen(onDismiss = {}) },
        "paywall-plans" to { _ ->
            MeCaptureFlags.previewPlans = samplePlans
            // iOS seeds the storefront a reviewer of the capture would be in:
            // won for a Korean app language, dollars otherwise.
            val korean = java.util.Locale.getDefault().language == "ko"
            MeCaptureFlags.previewCurrency = if (korean) "KRW" else "USD"
            // Micros, as Play states them.
            MeCaptureFlags.previewPrices = if (korean)
                mapOf("light_monthly" to 15_000_000_000L, "plus_monthly" to 29_000_000_000L,
                    "max_monthly" to 58_000_000_000L)
            else mapOf("light_monthly" to 9_990_000L, "plus_monthly" to 24_990_000L,
                "max_monthly" to 49_990_000L)
            PaywallScreen(onDismiss = {})
        },
        "me" to { context -> Me(context) },
        "plan" to { _ ->
            MeCaptureFlags.previewAccount = CaptureSeed.sampleLightAccount
            MeCaptureFlags.previewReceipt = CaptureSeed.sampleLightReceipt
            PlanPageScreen(onOpenCreditGuide = {}, onOpenInvite = {}, onBack = {})
        },
        "plan-trial" to { _ ->
            MeCaptureFlags.previewAccount = CaptureSeed.sampleTrialAccount
            MeCaptureFlags.previewReceipt = CaptureSeed.sampleTrialReceipt
            PlanPageScreen(onOpenCreditGuide = {}, onOpenInvite = {}, onBack = {})
        },
        "plan-guide" to { _ ->
            MeCaptureFlags.previewAccount = CaptureSeed.sampleLightAccount
            CreditGuideScreen(onBack = {})
        },
        "day-spent" to { _ -> DaySpent(SpentPool.TALK, canUpgrade = true, CaptureSeed.sampleLightAccount) },
        "day-spent-scenes" to { _ -> DaySpent(SpentPool.SCENES, canUpgrade = true, CaptureSeed.sampleLightAccount) },
        // iOS: the same sheet with nothing left to sell (Unlimited/Plus) —
        // same numbers, `canUpgrade: false`.
        "day-spent-unlimited" to { _ -> DaySpent(SpentPool.TALK, canUpgrade = false, CaptureSeed.sampleLightAccount) },
        // iOS: a TRIAL meets the Light pool pro-rated 7/30 (35 min), dated at
        // the trial's end (+4 days, already `sampleTrialAccount.periodEnd`).
        "day-spent-trial" to { _ -> DaySpent(SpentPool.TALK, canUpgrade = true, trialAccount) },
        "day-spent-trial-plus" to { _ -> DaySpent(SpentPool.TALK, canUpgrade = false, trialAccount) },
        "update" to { _ -> Update(required = false) },
        "update-required" to { _ -> Update(required = true) },
        "feedback" to { _ ->
            OverGround { FeedbackSheet(context = FeedbackContext.RETURNING_TALK, onDismiss = {}) }
        },
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf(
        "sync" to "Sync between devices (iOS iCloud) not ported — 2.28",
        "credits-out" to "4.6 — No in-call out-of-credits recovery row — Android routes a turn's 402 " +
            "straight to the paywall/allowance sheet (TalkViewModel.hitWall); 4.7",
    )

    /** The trial as the spent sheet meets it: 35 of the Light pool's minutes. */
    private val trialAccount: AccountStatus
        get() = CaptureSeed.sampleTrialAccount.copy(monthlyCapSeconds = 35 * 60)

    /**
     * The `subscription_plans` catalog as it is SOLD today (iOS seeds the
     * same rows): Light 150 min + 10 scenes, Plus 600 + 30, Max 1,200 + 30 —
     * monthly only, the annual rows are off sale. No `google_product_id`; the
     * prices come from [MeCaptureFlags.previewPrices] instead of Play.
     */
    private val samplePlans: List<BillingService.Plan> = listOf(
        BillingService.Plan(id = "light_monthly", tier = "light", period = "monthly",
            monthly_seconds = 9000, monthly_scenes = 10),
        BillingService.Plan(id = "plus_monthly", tier = "plus", period = "monthly",
            monthly_seconds = 36000, monthly_scenes = 30),
        BillingService.Plan(id = "max_monthly", tier = "max", period = "monthly",
            monthly_seconds = 72000, monthly_scenes = 30),
    )

    /** iOS: `MeTab()` over the harness's app state — whatever persona the
     *  sandbox holds (none unless `--es seed all` ran). Not signed in, so the
     *  account and Core reads resolve empty without a request. */
    @Composable
    private fun Me(context: Context) {
        val prefs = context.getSharedPreferences("futurevoice", 0)
        val persona by produceState<UserPersona?>(null) { value = PersonaStore.shared(context).load() }
        MeScreen(
            email = null,
            persona = persona,
            targetLanguage = LanguageScope.active(context),
            nativeLanguage = prefs.getString("futurevoice.nativeLanguage", null)
                ?: LanguageCatalog.defaultNative(),
            onSavePersona = {},
            enrolledLanguages = LanguageScope.enrolled(context),
            onSwitchLanguage = {},
            onAddLanguage = { _, _ -> },
            hasVoice = false,
            onOpenPeople = {},
            onOpenPublicIntro = {},
            onOpenPlanPage = {},
            onEditProfile = {},
            onOpenPaywall = {},
            onSignOut = {},
            onOpenPrivacy = {},
            onRestored = {},
            onBack = {},
        )
    }

    @Composable
    private fun DaySpent(pool: SpentPool, canUpgrade: Boolean, account: AccountStatus) {
        MeCaptureFlags.previewAccount = account
        OverGround {
            AllowanceSpentSheet(pool = pool, canUpgrade = canUpgrade,
                onReview = {}, onUpgrade = {}, onDismiss = {})
        }
    }

    /** iOS `UpdateCaptureHost`: build 99 / 1.1, the real release notes at their
     *  real length (a paragraph and five bullets), none when required. */
    @Composable
    private fun Update(required: Boolean) {
        OverGround {
            UpdateAvailableSheet(
                update = AppUpdateService.AppUpdate(
                    latestBuild = 99, latestVersion = "1.1",
                    notes = if (required) null else RELEASE_NOTES,
                    required = required,
                    fromPlay = true, url = AppUpdateService.PLAY_URL),
                onDismiss = {})
        }
    }

    @Composable
    private fun OverGround(sheet: @Composable () -> Unit) {
        Box(Modifier.fillMaxSize().background(AppSurfaces.ground)) { sheet() }
    }

    /** Verbatim from iOS `UpdateCaptureHost.releaseNotes`. */
    private val RELEASE_NOTES = """
        nawana를 시작합니다.

        말이 늘지 않는 이유는 하나 — 충분히 말하지 않아서예요. 60초 녹음으로 유창해진 미래의 내 목소리를 만들고, 매일 통화하세요. 통화가 끝나면 내가 쓴 단어·표현·문법으로 나만의 교재가 만들어져요.

        - 내 관심사에서 시작하는 매일 통화
        - 매 턴 돌아오는 유창한 버전
        - 통화가 끝나면 자동으로 만들어지는 나만의 교재
        - 내 목소리로 하는 섀도잉, 입으로 답하는 복습
        - 실제로 말한 것들로만 측정되는 레벨
    """.trimIndent()
}
