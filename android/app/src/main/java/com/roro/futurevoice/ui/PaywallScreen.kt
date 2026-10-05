package com.roro.futurevoice.ui

import android.app.Activity
import kotlinx.coroutines.launch
import com.roro.futurevoice.ui.brand.ContinuousShape
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.outlined.Circle
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.data.TopUpOffer
import com.android.billingclient.api.ProductDetails
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.BillingGate
import com.roro.futurevoice.data.BillingService
import com.roro.futurevoice.data.PlanChange
import com.roro.futurevoice.data.renewalLabel
import com.roro.futurevoice.data.ConsentStore
import com.roro.futurevoice.ui.brand.AppSurfaces
import java.text.NumberFormat
import java.util.Locale

/**
 * Where the funnel is. The paywall is THREE steps, not one long page: sell
 * the value, de-risk the trial, then show prices last. A screen that opens on
 * prices asks for a decision before it has made the case for one.
 *
 * [RESOLVING] is the state before Play has answered. Without it the screen
 * opened on the pitch and jumped to the plans a beat later, flashing a "Try
 * for free" pitch at an account with no trial left to take.
 */
private enum class PaywallStep { RESOLVING, PITCH, TIMELINE, PLANS }

/** Trial length to speak of while Play hasn't priced anything. */
private const val DEFAULT_TRIAL_DAYS = 7

/**
 * Google Play's own subscriber terms — the Play twin of Apple's standard
 * EULA, and the licence a Play subscription is actually sold under.
 */
private const val PLAY_TERMS_URL = "https://play.google.com/about/play-terms/"

/**
 * systemGreen — a SEMANTIC literal (saving money is good news), the one kind
 * of hardcoded colour the UI rules allow, and the same value `DrillBin` uses
 * for "got it". The accent always comes from the theme instead.
 */
private val SavingsGreen = Color(0xFF34C759)

/**
 * What the app costs, and what you get for it — ONE ladder, smallest first,
 * one line per plan (iOS `PaywallView`, 2026-10-02, founder: "make it easy to
 * compare"). The card layout it replaced spent half of every card on rows that
 * were identical on all of them, and three cards needed two screens to
 * compare. Each row carries its minutes, its scenes on a line of their own,
 * the price and the price PER MINUTE — the one number that says what a bigger
 * plan buys. What every plan shares is said once, under the ladder.
 *
 * The tiers are DATA: whatever `subscription_plans` sells (an inactive row is
 * not fetched at all), in [AccountStatus.TIER_ORDER]. Prices come from Play
 * only; with none the rows still render from the catalog and the CTA waits.
 *
 * The one-time minute pack sits under the ladder in its own group ("Extra
 * minutes", iOS 2026-10-02): a different kind of purchase from the plans,
 * bought before one or on top of one. Selecting it turns the CTA into "Buy N
 * minutes"; the minutes land through `google-topup` before Play's purchase
 * is consumed (master plan 4.0). Drawn only with a live Play price.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallScreen(onDismiss: () -> Unit, preselectTier: String? = null) {
    val context = LocalContext.current
    val billing = remember { BillingService.shared(context) }
    val offers by billing.offers.collectAsStateWithLifecycle()
    // Screenshot harness only: open on the plans over a sample catalog,
    // without asking Play or the server.
    val previewPlans = com.roro.futurevoice.capture.flags.MeCaptureFlags.previewPlans
    val livePlans by billing.plans.collectAsStateWithLifecycle()
    val liveSettled by billing.settled.collectAsStateWithLifecycle()
    val plans = (previewPlans ?: livePlans).filter { it.is_active }
    val settled = liveSettled || previewPlans != null
    val prices = rememberLadderPrices(offers)
    var period by remember { mutableStateOf("monthly") }
    // The tier this screen was OPENED for outranks the held plan below: a
    // learner who tapped "Move to Max" must not land on Plus, which they hold.
    val asked = remember { preselectTier ?: BillingGate.paywallTier.value }
    var tier by remember { mutableStateOf(asked ?: "plus") }
    var account by remember { mutableStateOf<AccountStatus?>(null) }
    /** Which store bills the held plan (`user_subscriptions.source`) — what
     *  decides whether "Change to X" may be a Play change flow at all. */
    var subscriptionSource by remember { mutableStateOf<String?>(null) }
    var step by remember {
        mutableStateOf(if (previewPlans != null) PaywallStep.PLANS else PaywallStep.RESOLVING)
    }
    val pack = rememberTalkPack()
    val packState by billing.packState.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) {
        BillingGate.paywallTier.value = null
        if (previewPlans == null) billing.refresh()
        val loaded = com.roro.futurevoice.capture.flags.MeCaptureFlags.previewAccount
            ?: if (previewPlans != null) AccountStatus() else AccountStatus.load(AuthRepository())
        if (previewPlans == null && loaded.isEntitled) {
            subscriptionSource = runCatching {
                com.roro.futurevoice.data.SubscriptionReceipt.load(AuthRepository()).source
            }.getOrNull()
        }
        account = loaded
        // Open on the plan they hold, so a subscriber starts by seeing their
        // own state rather than a pitch for something else.
        if (loaded.isEntitled) loaded.planId?.let { id ->
            if (asked == null) tier = id.substringBefore('_')
            id.substringAfter('_', "").takeIf { it.isNotEmpty() }?.let { period = it }
        }
    }

    // Trial length and eligibility come from Play's own pricing phases: a
    // trial is a phase priced at zero, and Play only attaches one to an
    // account that can still take it. Nothing loaded = NO trial (iOS reads
    // `trialEligible` the same way): the trial came off sale on 2026-09-26,
    // and a funnel promising "N days free" with nothing behind it is the
    // one screen a tester without Play products would otherwise meet.
    val trialDays = offers.mapNotNull { trialDaysOf(it.details).takeIf { d -> d > 0 } }
        .maxOrNull() ?: DEFAULT_TRIAL_DAYS
    // The trial's SIZE (iOS `StoreKitService.trialTalkMinutes`): a trial is
    // metered at Light's monthly pool pro-rated 7/30, whatever plan it
    // trials — keep the formula in step with `consume_metered_seconds`.
    val trialTalkMinutes = offers.filter { it.plan.tier == "light" }
        .mapNotNull { it.plan.monthly_seconds }.minOrNull()?.let { (it * 7 / 30 / 60).toInt() }
    val isSubscriber = account?.isEntitled == true
    // A subscriber opened this to CHANGE plans: the trial funnel would be wrong.
    val showsTrial = !isSubscriber && offers.any { trialDaysOf(it.details) > 0 }
    var redeemOpen by remember { mutableStateOf(false) }

    LaunchedEffect(settled, showsTrial, account) {
        if (settled && account != null && step == PaywallStep.RESOLVING) {
            step = if (showsTrial) PaywallStep.PITCH else PaywallStep.PLANS
        }
    }

    // Back walks one step UP the funnel; it only leaves the screen from the
    // first step someone was actually shown. Without a trial funnel the plans
    // ARE that first step, so there is nothing behind them to go back to.
    val backExits = when (step) {
        PaywallStep.TIMELINE -> false
        PaywallStep.PLANS -> !showsTrial
        else -> true
    }
    val goBack = {
        when {
            step == PaywallStep.TIMELINE -> step = PaywallStep.PITCH
            step == PaywallStep.PLANS && showsTrial -> step = PaywallStep.TIMELINE
            else -> onDismiss()
        }
    }
    BackHandler(onBack = goBack)

    // Periods in a FIXED order, not the order the server happened to return
    // them in: a segmented control whose segments move between fetches reads
    // as a different control each time. Annual is off sale (an inactive row),
    // so today this is monthly alone and the picker hides itself.
    val catalogPeriods = plans.map { it.period }.distinct()
    val periods = listOf("weekly", "monthly", "annual")
        .filter { it in catalogPeriods }
        .ifEmpty { listOf("monthly") }
    LaunchedEffect(periods) { if (period !in periods) period = periods.first() }
    // Max was picked on the monthly side and has no yearly row: the selection
    // moves to the biggest tier that has one.
    LaunchedEffect(period, plans) {
        if (tier != PACK && plans.isNotEmpty() && plans.none { it.tier == tier && it.period == period }) {
            plans.filter { it.period == period }
                .maxByOrNull { AccountStatus.TIER_ORDER.indexOf(it.tier) }
                ?.let { tier = it.tier }
        }
    }

    val showsPack = TopUpOffer.onPaywall(account, pack?.formattedPrice != null)
    // Opened on the pack (a capture, or a stale pick) with no pack to show:
    // the selection falls back to the plan most people choose.
    LaunchedEffect(settled, showsPack, pack) {
        if (settled && tier == PACK && !showsPack) tier = MOST_CHOSEN_TIER
    }
    val packPicked = tier == PACK
    val currentPlanId = if (isSubscriber) account?.planId else null
    val selectionIsCurrent = currentPlanId == "${tier}_$period"
    val route = PlanChange.route(isSubscriber, subscriptionSource, currentPlanId, tier, period)
    val elsewhere = route as? PlanChange.Route.ManageElsewhere
    // Buying needs a PRICED plan; the rows can render without one.
    val chosen = offers.firstOrNull { it.plan.tier == tier && it.plan.period == period }
    val tierName = stringResource(AccountStatus.tierNameRes(tier))
    val uri = LocalUriHandler.current

    Scaffold(
        containerColor = AppSurfaces.ground,
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = {},
                navigationIcon = {
                    IconButton(onClick = goBack) {
                        Icon(
                            if (backExits) Icons.Filled.Close
                            else Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.close),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
            )
        },
        bottomBar = {
            // The one control the funnel needs must never scroll away with the
            // pitch — on iOS it is a pinned bar, and a CTA that has to be
            // scrolled to is a step people simply don't take.
            PaywallBottomBar(
                step = step,
                trialDays = trialDays,
                trialTalkMinutes = trialTalkMinutes,
                plansTitle = when {
                    packPicked -> stringResource(R.string.topup_buy_minutes, pack?.minutes ?: 50)
                    // A subscriber can't buy what they already have — the
                    // only real action on their own plan is Play's screen.
                    selectionIsCurrent -> stringResource(R.string.manage_subscription)
                    // Billed by the App Store / the web: changed there, never
                    // by a Play purchase on top of it (a second subscription).
                    elsewhere?.source == "apple" -> stringResource(R.string.manage_in_the_app_store)
                    elsewhere != null -> stringResource(R.string.paywall_change_where_subscribed)
                    isSubscriber && route is PlanChange.Route.PlayChange ->
                        stringResource(R.string.paywall_change_to, tierName)
                    // A plan Play attaches no free phase to must not be sold
                    // as a trial, whatever the funnel promised.
                    showsTrial && chosen != null && trialDaysOf(chosen.details) > 0 ->
                        stringResource(R.string.start_my_free_lld_day_trial, trialDays)
                    period == "annual" -> stringResource(R.string.paywall_subscribe_yearly, tierName)
                    else -> stringResource(R.string.paywall_subscribe_monthly, tierName)
                },
                canBuy = if (packPicked)
                    pack?.details != null && packState != BillingService.PackState.Purchasing
                else selectionIsCurrent || elsewhere?.source == "apple" ||
                    (elsewhere == null && chosen != null),
                onCode = { redeemOpen = true },
                onPrimary = {
                    when (step) {
                        PaywallStep.RESOLVING -> Unit
                        PaywallStep.PITCH -> step = PaywallStep.TIMELINE
                        PaywallStep.TIMELINE -> step = PaywallStep.PLANS
                        PaywallStep.PLANS -> {
                            val activity = context as? Activity
                            if (packPicked) {
                                activity?.let { billing.buyPack(it) }
                            } else when (route) {
                                PlanChange.Route.ManageCurrent -> uri.openUri(PLAY_SUBSCRIPTIONS_URL)
                                is PlanChange.Route.ManageElsewhere ->
                                    if (route.source == "apple") uri.openUri(APP_STORE_SUBSCRIPTIONS_URL)
                                is PlanChange.Route.PlayChange -> if (activity != null && chosen != null)
                                    billing.changePlan(activity, chosen, currentPlanId, route.replacement,
                                        onNoPurchase = { uri.openUri(PLAY_SUBSCRIPTIONS_URL) })
                                PlanChange.Route.NewPurchase -> if (activity != null && chosen != null)
                                    billing.purchase(activity, chosen)
                            }
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp).padding(top = 8.dp, bottom = 24.dp),
        ) {
            when (step) {
                // Deliberately quiet: a spinner, not a skeleton of the pitch.
                // Whatever is drawn here is what an account with no trial left
                // sees for a fraction of a second.
                PaywallStep.RESOLVING -> Box(
                    Modifier.fillMaxWidth().padding(top = 120.dp),
                    contentAlignment = Alignment.Center,
                ) { CircularProgressIndicator() }

                PaywallStep.PITCH -> PitchStep()
                PaywallStep.TIMELINE -> TimelineStep(trialDays, trialTalkMinutes)
                PaywallStep.PLANS -> PlansStep(
                    plans = plans,
                    prices = prices,
                    period = period,
                    periods = periods,
                    onPeriod = { period = it },
                    tier = tier,
                    onTier = { tier = it },
                    account = account,
                    currentPlanId = currentPlanId,
                    showUnpriced = settled && chosen == null && !selectionIsCurrent && !packPicked,
                    pack = pack.takeIf { showsPack },
                )
            }
        }
    }
    // The pack is on the account: say so, then the paywall's job is done.
    (packState as? BillingService.PackState.Purchased)?.let { done ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { billing.resetPackState(); onDismiss() },
            title = { Text(stringResource(R.string.lld_minutes_added, done.minutes)) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { billing.resetPackState(); onDismiss() }) {
                    Text(stringResource(R.string.ok))
                }
            },
        )
    }
    (packState as? BillingService.PackState.Failed)?.let { failed ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { billing.resetPackState() },
            title = { Text(stringResource(R.string.purchase_failed)) },
            text = { Text(stringResource(failed.message)) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { billing.resetPackState() }) {
                    Text(stringResource(R.string.ok))
                }
            },
        )
    }
    if (redeemOpen) RedeemCodeDialog(
        onDismiss = { redeemOpen = false },
        // A comp is a plan: the wall this paywall stands for is gone, so the
        // paywall goes with the dialog. Invite minutes leave it up — they
        // are minutes, and the plans are still the answer after them.
        onComp = { redeemOpen = false; onDismiss() },
    )
}

/** The pinned CTA, and the one line that de-risks it. */
@Composable
private fun PaywallBottomBar(
    step: PaywallStep,
    trialDays: Int,
    trialTalkMinutes: Int?,
    /** The CTA's words on the plans step — chosen by the caller, which knows
     *  the selection, the held plan and whether Play offers a trial. */
    plansTitle: String,
    canBuy: Boolean,
    onCode: () -> Unit,
    onPrimary: () -> Unit,
) {
    val resolving = step == PaywallStep.RESOLVING
    Surface(color = AppSurfaces.ground) {
        Column {
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Column(
                Modifier.fillMaxWidth().bottomBarInsets()
                    .padding(horizontal = 24.dp).padding(top = 12.dp, bottom = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Button(
                    onClick = onPrimary,
                    // Held rather than hidden: the bar keeps its height while
                    // Play answers, so the screen doesn't jump under the thumb.
                    enabled = !resolving && (step != PaywallStep.PLANS || canBuy),
                    // iOS paywall CTA: 58 pt (gallery).
                    modifier = Modifier.fillMaxWidth().heightIn(min = 58.dp)
                        .alpha(if (resolving) 0f else 1f),
                ) {
                    Text(
                        when (step) {
                            PaywallStep.RESOLVING -> ""
                            PaywallStep.PITCH -> stringResource(R.string.try_for_free)
                            PaywallStep.TIMELINE -> stringResource(R.string.see_plans)
                            PaywallStep.PLANS -> plansTitle
                        },
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                // iOS's "Have a code?" (Apple's offer-code sheet there). On
                // Android a code is the server's own — comp and invite codes
                // both go through `redeem_referral` — so it opens that field.
                if (step == PaywallStep.PLANS) {
                    androidx.compose.material3.TextButton(onClick = onCode) {
                        Text(stringResource(R.string.have_a_code))
                    }
                }
                if (step == PaywallStep.PITCH || step == PaywallStep.TIMELINE) {
                    Text(
                        trialTalkMinutes?.let {
                            stringResource(R.string.lld_days_free_with_lld_min_of_talk_cancel_anytime, trialDays, it)
                        } ?: stringResource(R.string.lld_days_free_cancel_anytime, trialDays),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}

/** Step 1 — what the thing is, before what it costs. */
@Composable
private fun PitchStep() {
    Column(verticalArrangement = Arrangement.spacedBy(28.dp)) {
        Column(
            Modifier.padding(top = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(stringResource(R.string.you_but_fluent),
                style = MaterialTheme.typography.headlineLarge,
                fontWeight = FontWeight.Bold)
            Text(stringResource(R.string.speak_every_day_and_keep_everything_it_teaches_you),
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        // Ordered by importance: the call is the product, the daily call is
        // what makes "every day" credible, then the two rehearse/review
        // halves, then measurement.
        Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
            PitchRow(Icons.Filled.Forum,
                stringResource(R.string.real_conversations_your_voice),
                stringResource(R.string.talk_with_your_fluent_self_like_a_live_phone_call_every_repl_d69f26))
            PitchRow(Icons.Filled.Phone,
                stringResource(R.string.your_fluent_self_calls_first),
                stringResource(R.string.pick_a_time_and_the_phone_rings_miss_it_and_a_voicemail_with_b83e21))
            PitchRow(Icons.Filled.PlayCircle,
                stringResource(R.string.rehearse_before_it_happens),
                stringResource(R.string.describe_what_s_coming_and_watch_your_fluent_self_handle_it_48f4b8))
            PitchRow(Icons.Filled.AutoAwesome,
                stringResource(R.string.corrections_that_stick),
                stringResource(R.string.inline_fixes_become_spaced_repetition_drills_tuned_to_your_m_00ebe4))
            PitchRow(Icons.Filled.GraphicEq,
                stringResource(R.string.pronunciation_you_can_measure),
                stringResource(R.string.shadow_any_line_get_a_real_score_watch_the_weekly_trend))
        }
    }
}

/** One line of the pitch: a glyph, the promise, and what backs it. */
@Composable
private fun PitchRow(icon: ImageVector, title: String, detail: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.Top) {
        // A fixed glyph column, not a glyph-sized one: the icons differ in
        // width and the titles would otherwise start at five different places.
        Box(Modifier.width(30.dp).padding(top = 2.dp), contentAlignment = Alignment.TopStart) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(24.dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold)
            Text(detail, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * Step 2 — the trial, drawn as a calendar rather than promised in prose. The
 * fear being answered is "I'll forget and get charged", so the reminder is a
 * dated row on the same line as the charge.
 */
@Composable
private fun TimelineStep(trialDays: Int, trialTalkMinutes: Int?) {
    // The reminder's own day (iOS `reminderDay`, `TrialReminder.leadDays`),
    // counting the purchase as day 1 — dropped when it would land on the
    // start or the last day, rows the timeline already draws.
    val reminderDay = (trialDays - (if (trialDays <= 4) 1 else 2)).takeIf { it in 2 until trialDays }
    Column(verticalArrangement = Arrangement.spacedBy(28.dp)) {
        Column(
            Modifier.padding(top = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(stringResource(R.string.lld_days_free_no_surprises, trialDays),
                style = MaterialTheme.typography.headlineLarge,
                fontWeight = FontWeight.Bold)
            Text(stringResource(R.string.we_ll_remind_you_before_it_converts_and_the_date_is_always_i_ff65e1),
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Column {
            // The trial's SIZE goes here, before anyone taps: it is the
            // trial's own pool, not the plan's (iOS, 2026-09-25).
            TimelineRow(Icons.Filled.LockOpen,
                stringResource(R.string.today),
                trialTalkMinutes?.let {
                    stringResource(R.string.your_trial_starts_lld_minutes_of_talk_to_use_across_the_lld_153af7, it, trialDays)
                } ?: stringResource(R.string.your_trial_starts_talk_time_on_us_and_all_the_review_it_prod_1afe94),
                showsLine = true)
            reminderDay?.let { day ->
                TimelineRow(Icons.Filled.NotificationsActive,
                    stringResource(R.string.day_lld, day),
                    stringResource(R.string.a_reminder_that_your_trial_is_about_to_convert_we_ask_to_sen_cd5350),
                    showsLine = true)
            }
            TimelineRow(Icons.Filled.WorkspacePremium,
                stringResource(R.string.day_lld, trialDays),
                stringResource(R.string.your_subscription_starts_cancel_any_time_before_then_in_google_play),
                showsLine = false)
        }
    }
}

@Composable
private fun TimelineRow(icon: ImageVector, title: String, caption: String, showsLine: Boolean) {
    val accent = MaterialTheme.colorScheme.primary
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.Top) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                Modifier.size(40.dp)
                    .background(MaterialTheme.colorScheme.surfaceVariant, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = accent,
                    modifier = Modifier.size(20.dp))
            }
            if (showsLine) {
                // The connector is what makes three rows read as ONE timeline
                // instead of three unrelated facts.
                Box(Modifier.width(4.dp).height(34.dp)
                    .background(accent.copy(alpha = 0.5f)))
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold)
            Text(caption, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 22.dp))
        }
    }
}

/** Play's subscription management page — changing or cancelling a live plan
 *  happens there, never in-app (iOS opens Apple's own). */
private const val PLAY_SUBSCRIPTIONS_URL = "https://play.google.com/store/account/subscriptions"
private const val APP_STORE_SUBSCRIPTIONS_URL = "https://apps.apple.com/account/subscriptions"

/**
 * The tier most people actually bought — a FACT the row can state, which is
 * why it says "most chosen" and never "recommended" (iOS, measured 2026-10-02:
 * Plus was the first paid plan of 6 of 9 subscribers). Text in the accent, not
 * a filled capsule, which reads as an award and makes the others look like
 * less. Never put it on a tier nobody has bought.
 */
private const val MOST_CHOSEN_TIER = "plus"

/** The ladder's selection key for the one-time pack — never a plan tier. */
private const val PACK = "pack"

/** A store price kept as a NUMBER, so the ladder can divide it. */
private data class LadderPrice(val formatted: String, val micros: Long, val currency: String)

/**
 * Play's recurring price per plan id. In a capture build the harness seeds the
 * table instead (iOS does the same: a debug build is never priced by a store).
 */
@Composable
private fun rememberLadderPrices(offers: List<BillingService.Offer>): Map<String, LadderPrice> {
    val flags = com.roro.futurevoice.capture.flags.MeCaptureFlags
    val seeded = flags.previewPrices
    val currency = flags.previewCurrency
    val locale = androidx.compose.ui.platform.LocalConfiguration.current.locales[0]
    return remember(offers, seeded, currency, locale) {
        if (seeded != null && currency != null) {
            seeded.mapValues { (_, micros) ->
                LadderPrice(formatMoney(micros / 1_000_000.0, currency, locale, null), micros, currency)
            }
        } else offers.mapNotNull { o ->
            recurringPhase(o.details)?.let {
                o.plan.id to LadderPrice(it.formattedPrice, it.priceAmountMicros, it.priceCurrencyCode)
            }
        }.toMap()
    }
}

private fun formatMoney(value: Double, currency: String, locale: Locale, fraction: Int?): String =
    NumberFormat.getCurrencyInstance(locale).apply {
        runCatching { this.currency = java.util.Currency.getInstance(currency) }
        if (fraction != null) { minimumFractionDigits = fraction; maximumFractionDigits = fraction }
    }.format(value)

/** Step 3 — the prices, last, as one ladder. */
@Composable
private fun PlansStep(
    plans: List<BillingService.Plan>,
    prices: Map<String, LadderPrice>,
    period: String,
    periods: List<String>,
    onPeriod: (String) -> Unit,
    tier: String,
    onTier: (String) -> Unit,
    account: AccountStatus?,
    currentPlanId: String?,
    /** Play answered and has no price for the selection. */
    showUnpriced: Boolean,
    /** The one-time pack, when it is offered here (priced, not uncapped). */
    pack: BillingService.Pack? = null,
) {
    val locale = androidx.compose.ui.platform.LocalConfiguration.current.locales[0]
    // Every tier the catalog sells, smallest first. A tier with no row in the
    // selected period still shows ("Monthly only") so the ladder keeps its
    // shape when the period flips.
    val shownTiers = AccountStatus.TIER_ORDER.filter { t -> plans.any { it.tier == t } }
        .ifEmpty { listOf("light", "plus") }
    Column(verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(stringResource(if (currentPlanId != null) R.string.your_plan else R.string.paywall_keep_talking),
                style = MaterialTheme.typography.headlineLarge,
                fontWeight = FontWeight.Bold)
            if (currentPlanId != null && account != null) {
                val name = stringResource(AccountStatus.tierNameRes(currentPlanId))
                val label = when {
                    // A trial names the plan it will BECOME, not what it allows.
                    account.isTrialing -> stringResource(R.string.trial, name)
                    else -> "$name · " + stringResource(
                        if (currentPlanId.endsWith("annual")) R.string.annual else R.string.monthly)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.WorkspacePremium, contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(16.dp))
                    Text(
                        when {
                            account.isTrialing && account.cancelAtPeriodEnd -> stringResource(
                                R.string.you_re_on_the_it_ends_on, label, account.renewalLabel(locale))
                            account.isTrialing ->
                                stringResource(R.string.you_re_on_the_it_converts_unless_you_cancel, label)
                            else -> stringResource(R.string.you_re_subscribed_to, label)
                        },
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                Text(stringResource(R.string.paywall_pick_how_much),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        if (periods.size > 1) {
            // The segment says only the period; the saving sits on each row.
            com.roro.futurevoice.ui.brand.IosSegmented(periods.map { p -> stringResource(when (p) {
                "weekly" -> R.string.weekly
                "annual" -> R.string.annual
                else -> R.string.monthly
            }) }, periods.indexOf(period).coerceAtLeast(0), { onPeriod(periods[it]) }, Modifier.fillMaxWidth())
        }

        Column(Modifier.fillMaxWidth().background(AppSurfaces.card, ContinuousShape(14.dp))) {
            shownTiers.forEachIndexed { i, t ->
                if (i > 0) HorizontalDivider(Modifier.padding(start = 52.dp),
                    color = MaterialTheme.colorScheme.outlineVariant)
                LadderRow(
                    tier = t,
                    plans = plans,
                    prices = prices,
                    period = period,
                    selected = tier == t,
                    isCurrent = currentPlanId == "${t}_$period",
                    onSelect = { onTier(t) },
                )
            }
        }

        if (pack != null) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.extra_minutes),
                    Modifier.padding(start = 4.dp),
                    style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Column(Modifier.fillMaxWidth().background(AppSurfaces.card, ContinuousShape(14.dp))) {
                    PackRow(pack, selected = tier == PACK, onSelect = { onTier(PACK) })
                }
            }
        }

        // Play answered and had nothing. Say so once, quietly: a disabled
        // button with no explanation reads as the app being broken.
        if (showUnpriced) {
            Text(stringResource(R.string.google_play_isnt_offering_this_plan_here_yet),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        // What every plan shares, said ONCE — on the cards it was two rows
        // identical on all of them.
        Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            FootnoteRow(Icons.Filled.CheckCircle, stringResource(R.string.paywall_shared_unlimited))
            FootnoteRow(Icons.Filled.Phone, stringResource(R.string.paywall_tutor_call))
        }

        SubscriptionLegal()
    }
}

@Composable
private fun FootnoteRow(icon: ImageVector, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(16.dp).padding(top = 1.dp))
        Text(text, style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * One line of the ladder: name and minutes, scenes, the per-day cue, the
 * price and the price per minute. The selection is the whole row, lit — an
 * accent edge and a tinted fill that ease in and out (iOS slides one shape
 * between rows; the UI rules allow subtle motion only).
 */
@Composable
private fun LadderRow(
    tier: String,
    plans: List<BillingService.Plan>,
    prices: Map<String, LadderPrice>,
    period: String,
    selected: Boolean,
    isCurrent: Boolean,
    onSelect: () -> Unit,
) {
    val accent = MaterialTheme.colorScheme.primary
    val locale = androidx.compose.ui.platform.LocalConfiguration.current.locales[0]
    val plan = plans.firstOrNull { it.tier == tier && it.period == period }
    // A tier with no row in this period is shown so the ladder keeps its
    // shape, but it can't be picked (founder, 2026-10-02).
    val monthlyOnly = plan == null && period == "annual"
    val shown = plan ?: plans.firstOrNull { it.tier == tier && it.period == "monthly" }
    val minutes = ((shown?.monthly_seconds ?: 0L) / 60).toInt()
    val scenes = (shown?.monthly_scenes ?: 0L).toInt()
    val on = selected && !monthlyOnly
    val price = shown?.let { prices[it.id] }
    val fill by androidx.compose.animation.animateColorAsState(
        if (on) accent.copy(alpha = 0.10f) else Color.Transparent,
        androidx.compose.animation.core.tween(280), label = "ladderFill")
    val edge by androidx.compose.animation.animateColorAsState(
        if (on) accent else Color.Transparent,
        androidx.compose.animation.core.tween(280), label = "ladderEdge")
    Row(
        Modifier.fillMaxWidth()
            .background(fill, ContinuousShape(14.dp))
            .border(2.dp, edge, ContinuousShape(14.dp))
            .clickable(enabled = !monthlyOnly, onClick = onSelect)
            .alpha(if (monthlyOnly) 0.55f else 1f)
            .padding(horizontal = 12.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) {
            Icon(
                if (on) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                contentDescription = null,
                tint = if (on) accent else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            // The tag rides ABOVE the name, on a line of its own: beside it,
            // "Am häufigsten gewählt" pushed "Plus 600 Min." onto two lines.
            when {
                isCurrent -> Text(stringResource(R.string.current_plan),
                    style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold,
                    color = accent)
                tier == MOST_CHOSEN_TIER -> Text(stringResource(R.string.paywall_most_chosen),
                    style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold,
                    color = accent)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(AccountStatus.tierNameRes(tier)),
                    style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                    maxLines = 1)
                when {
                    // Kept as a branch so the catalog can sell an uncapped
                    // plan again with no app change — none is on sale.
                    shown?.talk_unlimited == true -> Text(stringResource(R.string.no_limit),
                        style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                        maxLines = 1)
                    minutes > 0 -> Text(stringResource(R.string.min, grouped(minutes)),
                        style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                        maxLines = 1)
                }
            }
            // A SIZE CUE, never a rule: the pool has no daily limit. It reads
            // the minutes it sits under, so it comes right after them (iOS
            // 964bae15); scenes and Speech follow as what the plan includes.
            if (minutes / 30 > 0 && shown?.talk_unlimited != true) {
                Text(stringResource(R.string.about_lld_min_a_day, minutes / 30),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (scenes > 0) {
                Text(stringResource(R.string.paywall_plus_scenes, scenes),
                    style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
            }
            // Writing Speech scripts (AI or your own) is these tiers' alone
            // (iOS 63817b73, the same rule as `canWriteSpeechScripts`).
            if (tier == "plus" || tier == "max") {
                Text(stringResource(R.string.speech_d35aea),
                    style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
            }
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            when {
                monthlyOnly -> Text(stringResource(R.string.paywall_monthly_only),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                // No placeholder when Play hasn't priced it: a dash reads as a
                // broken field, and an absent price says the same more quietly.
                price != null -> {
                    Text(price.formatted, style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold)
                    val saving = if (period == "annual") annualSavingLabel(prices, plans, tier) else null
                    if (saving != null) {
                        Text(saving, style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.SemiBold, color = accent)
                    } else {
                        Text(stringResource(if (period == "annual") R.string.paywall_a_year
                            else R.string.paywall_a_month),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (minutes > 0 && shown?.talk_unlimited != true) {
                        Text(perMinuteLabel(price, if (period == "annual") minutes * 12 else minutes, locale),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.SemiBold, color = SavingsGreen)
                    }
                }
            }
        }
    }
}

/**
 * The pack's rung: its minutes, that it is bought once and never expires,
 * that no plan is needed — and its price per minute, the same comparison the
 * plans carry (priced above Light per minute on purpose).
 */
@Composable
private fun PackRow(pack: BillingService.Pack, selected: Boolean, onSelect: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    val locale = androidx.compose.ui.platform.LocalConfiguration.current.locales[0]
    val fill by androidx.compose.animation.animateColorAsState(
        if (selected) accent.copy(alpha = 0.10f) else Color.Transparent,
        androidx.compose.animation.core.tween(280), label = "packFill")
    val edge by androidx.compose.animation.animateColorAsState(
        if (selected) accent else Color.Transparent,
        androidx.compose.animation.core.tween(280), label = "packEdge")
    Row(
        Modifier.fillMaxWidth()
            .background(fill, ContinuousShape(14.dp))
            .border(2.dp, edge, ContinuousShape(14.dp))
            .clickable(onClick = onSelect)
            .padding(horizontal = 12.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) {
            Icon(
                if (selected) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                contentDescription = null,
                tint = if (selected) accent else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(stringResource(R.string.min, grouped(pack.minutes)),
                style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                maxLines = 1)
            Text(stringResource(R.string.topup_one_time_no_expiry),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(stringResource(R.string.topup_with_or_without_plan),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        pack.formattedPrice?.let { formatted ->
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(formatted, style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold)
                Text(stringResource(R.string.topup_once), style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (pack.priceMicros > 0 && pack.currency.isNotEmpty()) {
                    Text(perMinuteLabel(LadderPrice(formatted, pack.priceMicros, pack.currency),
                        pack.minutes, locale),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold, color = SavingsGreen)
                }
            }
        }
    }
}

/** "₩48 a min" / "$0.04 a min" — whole units where the currency's unit is
 *  already small (won, yen), two decimals where it isn't. */
@Composable
private fun perMinuteLabel(price: LadderPrice, minutes: Int, locale: Locale): String {
    if (minutes <= 0) return ""
    val each = price.micros / 1_000_000.0 / minutes
    val text = formatMoney(each, price.currency, locale, if (each >= 1) 0 else 2)
    return stringResource(R.string.paywall_per_min, text)
}

/**
 * The annual saving, said the way the offer is built: "2 months free" when a
 * year costs a whole number of months less than paying monthly, a percentage
 * otherwise. Both only ever from LIVE prices — a badge worked out from figures
 * the viewer is never shown is a claim they cannot check.
 */
@Composable
private fun annualSavingLabel(
    prices: Map<String, LadderPrice>, plans: List<BillingService.Plan>, tier: String,
): String? {
    fun micros(period: String) = plans.firstOrNull { it.tier == tier && it.period == period }
        ?.let { prices[it.id]?.micros }
    val monthly = micros("monthly") ?: return null
    val annual = micros("annual") ?: return null
    if (monthly <= 0) return null
    val free = (monthly * 12 - annual).toDouble() / monthly
    val whole = Math.round(free).toInt()
    if (whole >= 1 && kotlin.math.abs(free - whole) < 0.2) {
        return stringResource(R.string.lld_months_free, whole)
    }
    val full = monthly * 12
    if (full <= annual) return null
    val pct = Math.round((full - annual).toDouble() / full * 100).toInt()
    return if (pct > 0) stringResource(R.string.save_lld_vs_monthly, pct) else null
}

/**
 * The RECURRING phase of an offer — never the trial's.
 *
 * Play lists a free trial as a pricing phase priced at zero, and it comes
 * FIRST. Reading the first phase therefore printed a "free" price on the card
 * of a plan that costs money.
 */
private fun recurringPhase(details: ProductDetails): ProductDetails.PricingPhase? =
    details.subscriptionOfferDetails?.firstOrNull()
        ?.pricingPhases?.pricingPhaseList?.firstOrNull { it.priceAmountMicros > 0 }

/**
 * Required on any screen that sells an auto-renewing subscription: what
 * renews, when it is billed, how to stop it, and the terms + privacy links.
 * Missing links are the single most common subscription rejection — this
 * block is not decoration.
 */
@Composable
private fun SubscriptionLegal() {
    val uri = LocalUriHandler.current
    val accent = MaterialTheme.colorScheme.primary
    Column(
        Modifier.fillMaxWidth().padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(stringResource(R.string.subscription_legal_google),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(R.string.terms_of_use),
                style = MaterialTheme.typography.labelSmall, color = accent,
                modifier = Modifier.clickable { uri.openUri(PLAY_TERMS_URL) })
            Text("·", style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(stringResource(R.string.privacy_policy),
                style = MaterialTheme.typography.labelSmall, color = accent,
                modifier = Modifier.clickable { uri.openUri(ConsentStore.privacyUrl()) })
        }
    }
}

/**
 * How many free days an offer carries, 0 if none. A trial is a pricing phase
 * priced at zero; Play states its length as ISO-8601.
 */
private fun trialDaysOf(details: ProductDetails): Int {
    val phase = details.subscriptionOfferDetails?.firstOrNull()
        ?.pricingPhases?.pricingPhaseList?.firstOrNull { it.priceAmountMicros == 0L } ?: return 0
    val p = phase.billingPeriod
    val n = p.filter { it.isDigit() }.toIntOrNull() ?: return 0
    return when {
        p.endsWith("D") -> n
        p.endsWith("W") -> n * 7
        p.endsWith("M") -> n * 30
        p.endsWith("Y") -> n * 365
        else -> 0
    }
}

/**
 * A figure grouped in the learner's own language, for any card number that
 * can reach four digits.
 *
 * NEVER interpolate such a number straight into a localized string: it is
 * grouped by the FORMATTING locale, which follows the device region rather
 * than the app language — that is how a German-grouped "1.800" shipped inside
 * a Korean sentence, where it reads as one point eight.
 */
private fun grouped(n: Int): String =
    NumberFormat.getIntegerInstance(Locale.getDefault()).format(n)

/** One field, one button: a code from the server's own table (a tester's
 *  comp, a friend's invite), the same `redeem_referral` Me → Invite calls. */
@Composable
private fun RedeemCodeDialog(onDismiss: () -> Unit, onComp: () -> Unit) {
    val context = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val client = remember { com.roro.futurevoice.net.ReferralClient(com.roro.futurevoice.data.AuthRepository()) }
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf(false) }
    androidx.compose.material3.AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text(stringResource(R.string.have_a_code)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                androidx.compose.material3.OutlinedTextField(
                    value = code, onValueChange = { code = it.uppercase(); note = null },
                    placeholder = { Text(stringResource(R.string.enter_invite_code)) },
                    singleLine = true,
                    textStyle = androidx.compose.material3.LocalTextStyle.current.copy(
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace),
                )
                note?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall,
                        color = if (failed) MaterialTheme.colorScheme.error else Color(0xFF34C759))
                }
            }
        },
        confirmButton = {
            androidx.compose.material3.TextButton(
                enabled = !busy && code.isNotBlank(),
                onClick = {
                    busy = true
                    scope.launch {
                        runCatching { client.redeem(code) }
                            .onSuccess { r ->
                                failed = false
                                if (r.isComp) onComp()
                                else note = context.getString(R.string.redeemed_lld_minutes_added,
                                    com.roro.futurevoice.net.ReferralClient.bonusMinutes)
                            }
                            .onFailure { e -> failed = true; note = context.getString(redeemFailureText(e)) }
                        busy = false
                    }
                },
            ) { Text(stringResource(R.string.redeem)) }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss, enabled = !busy) {
                Text(stringResource(R.string.cancel))
            }
        },
    )
}
