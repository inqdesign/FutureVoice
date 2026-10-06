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
import com.roro.futurevoice.ui.InviteOffer
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
 *   plan-spent
 *   paywall
 *   paywall-plans
 *   paywall-ladder-pack
 *   day-spent
 *   day-spent-scenes
 *   day-spent-invite
 *   day-spent-plus
 *   day-spent-pack   (Android only — the pack priced, leading)
 *   day-spent-unlimited
 *   day-spent-trial
 *   day-spent-trial-plus
 *   credits-out
 *   update
 *   update-required
 *   sync
 *   sync-other-device
 *   backup-offer
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
            seedLadder()
            PaywallScreen(onDismiss = {})
        },
        // iOS: the ladder with the one-time pack's rung picked — the CTA
        // reads "Buy 50 minutes".
        "paywall-ladder-pack" to { _ ->
            seedLadder()
            PaywallScreen(onDismiss = {}, preselectTier = "pack")
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
        // iOS: the same page once the month's minutes are gone — the invite
        // row has grown into the card, and nothing else moves.
        "plan-spent" to { _ ->
            MeCaptureFlags.previewAccount = CaptureSeed.sampleLightAccount.copy(
                secondsUsedPeriod = CaptureSeed.sampleLightAccount.monthlyCapSeconds ?: 9000)
            MeCaptureFlags.previewReceipt = CaptureSeed.sampleLightReceipt
            MeCaptureFlags.previewInvite = sampleInvite
            PlanPageScreen(onOpenCreditGuide = {}, onOpenInvite = {}, onBack = {})
        },
        "plan-guide" to { _ ->
            MeCaptureFlags.previewAccount = CaptureSeed.sampleLightAccount
            CreditGuideScreen(onBack = {})
        },
        "day-spent" to { _ -> DaySpent(SpentPool.TALK, onSale(CaptureSeed.sampleLightAccount)) },
        "day-spent-scenes" to { _ -> DaySpent(SpentPool.SCENES, onSale(CaptureSeed.sampleLightAccount)) },
        // iOS: the same sheet with nothing left to sell (Unlimited/Plus) —
        // same numbers, `canUpgrade: false`.
        // iOS: the talk sheet with the invite line, which only a subscriber
        // on a counted pool with rewards left ever sees.
        "day-spent-invite" to { _ ->
            DaySpent(SpentPool.TALK, onSale(CaptureSeed.sampleLightAccount), sampleInvite)
        },
        // iOS: what a Plus subscriber meets today — the month's pool (300 min
        // in iOS's sample) spent, nothing to upgrade to, no minute pack on
        // sale, so the invite is the only free way forward.
        "day-spent-plus" to { _ -> DaySpent(SpentPool.TALK, plusSpentAccount, sampleInvite) },
        // Android only: the Plus sheet once the pack HAS a price — the pack
        // takes the lead slot, review steps back to tonal, and the line above
        // names the pack (iOS shows this state only with a live ASC price).
        "day-spent-pack" to { _ ->
            seedPack()
            DaySpent(SpentPool.TALK, plusSpentAccount, sampleInvite)
        },
        "day-spent-unlimited" to { _ -> DaySpent(SpentPool.TALK, CaptureSeed.sampleLightAccount) },
        // iOS: a TRIAL meets the Light pool pro-rated 7/30 (35 min), dated at
        // the trial's end (+4 days, already `sampleTrialAccount.periodEnd`).
        // The sheet says when the plan starts and, where the client knows it,
        // with how many minutes (`planMinutesAfterTrial`: 150 on the Light
        // trial, unknown on iOS's Plus sample). A trialer sees the invite line
        // too — the one free way forward besides review.
        "day-spent-trial" to { _ ->
            DaySpent(SpentPool.TALK,
                onSale(trialAccount.copy(planMonthlySeconds = 150 * 60)), sampleInvite)
        },
        "day-spent-trial-plus" to { _ ->
            DaySpent(SpentPool.TALK,
                trialAccount.copy(planId = "plus_monthly"), sampleInvite)
        },
        "update" to { _ -> Update(required = false) },
        "update-required" to { _ -> Update(required = true) },
        "feedback" to { _ ->
            OverGround { FeedbackSheet(context = FeedbackContext.RETURNING_TALK, onDismiss = {}) }
        },
    )

    /** mode → why Android can't show it yet (name the master-plan item). */
    val notPorted: Map<String, String> = mapOf(
        "sync" to "Sync between devices (iOS iCloud) not ported — 2.28",
        "sync-other-device" to "2.28 — No device sync, so no second-device hint screen " +
            "(iOS SyncOtherDeviceHintView) — Android has nothing to turn on over there",
        "backup-offer" to "2.28 — No iCloud-backup offer after the third talk (iOS BackupOfferSheet); " +
            "Android has only Me's manual backup export/import",
        "credits-out" to "4.6 — No in-call out-of-credits recovery row — Android routes a turn's 402 " +
            "straight to the paywall/allowance sheet (TalkViewModel.hitWall); 4.7",
    )

    /** iOS seeds the storefront a reviewer of the capture would be in: won
     *  for a Korean app language, dollars otherwise. Micros, as Play states them. */
    private fun seedLadder() {
        MeCaptureFlags.previewPlans = samplePlans
        val korean = java.util.Locale.getDefault().language == "ko"
        MeCaptureFlags.previewCurrency = if (korean) "KRW" else "USD"
        MeCaptureFlags.previewPrices = if (korean)
            mapOf("light_monthly" to 15_000_000_000L, "plus_monthly" to 29_000_000_000L,
                "max_monthly" to 58_000_000_000L)
        else mapOf("light_monthly" to 9_990_000L, "plus_monthly" to 24_990_000L,
            "max_monthly" to 49_990_000L)
        seedPack()
    }

    /** The 50-minute pack as `20261002110000_fifty_minute_pack` sells it:
     *  ₩5,900 / $4.99 (iOS `PaywallView.packPrice` seeds the same). */
    private fun seedPack() {
        val korean = java.util.Locale.getDefault().language == "ko"
        val (micros, currency) = if (korean) 5_900_000_000L to "KRW" else 4_990_000L to "USD"
        val formatted = java.text.NumberFormat.getCurrencyInstance(java.util.Locale.getDefault()).apply {
            this.currency = java.util.Currency.getInstance(currency)
        }.format(micros / 1_000_000.0)
        MeCaptureFlags.previewPack = BillingService.Pack(productId = "talk_50", seconds = 3000,
            formattedPrice = formatted, priceMicros = micros, currency = currency)
    }

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

    /** iOS `InviteOffer(code: "K3MQ9F", invitesUsed: 2)`. */
    private val sampleInvite = InviteOffer(code = "K3MQ9F", invitesUsed = 2)

    /** A Plus subscriber whose month (300 min, iOS's sample) is spent. */
    private val plusSpentAccount: AccountStatus
        get() = CaptureSeed.sampleLightAccount.copy(
            planId = "plus_monthly", secondsUsedPeriod = 300 * 60, monthlyCapSeconds = 300 * 60,
            monthlyScenesCap = 30)

    /** The sheet resolves "anything to sell?" from the account's own
     *  `upgradeTier` now, so a sample that should offer Plus says Plus is on
     *  sale (iOS's samples predate Max: Light → Plus, Plus at the top). */
    private fun onSale(a: AccountStatus) = a.copy(tiersOnSale = setOf("light", "plus"))

    @Composable
    private fun DaySpent(pool: SpentPool, account: AccountStatus,
                         invite: InviteOffer? = null) {
        MeCaptureFlags.previewAccount = account
        MeCaptureFlags.previewInvite = invite
        OverGround {
            AllowanceSpentSheet(pool = pool,
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
