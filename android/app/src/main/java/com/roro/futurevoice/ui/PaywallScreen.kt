package com.roro.futurevoice.ui

import android.app.Activity
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
import androidx.compose.material3.Button
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
import com.android.billingclient.api.ProductDetails
import com.roro.futurevoice.R
import com.roro.futurevoice.data.BillingService
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
 * What the app costs, and what you get for it.
 *
 * The card IS the offer. Three rules hold it together, all learned the hard
 * way on iOS and none of them cosmetic:
 *
 * 1. **Same unit on both tiers.** Plus once printed "30 hours" beside Light's
 *    "150 min", which made the two cards non-comparable at the exact moment
 *    the reader is comparing them — nobody divides 30 by 2.5 in their head.
 * 2. **The period rides on the figure** (`/mo`), which retired a footnote
 *    under the cards that nobody read and that left the figures period-less.
 * 3. **The free half lives ON the card.** Split into an "Always free" box
 *    underneath, the offer had to be assembled from two places and the free
 *    half read as a consolation prize rather than part of the purchase.
 *
 * And the one prose line describes what the plan LETS YOU DO, never who you
 * are: the tiers are feature-identical, so "for experts / for beginners"
 * promises a difference that isn't there and misroutes — someone prepping one
 * interview needs ~90 minutes total and belongs on Light.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallScreen(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val billing = remember { BillingService.shared(context) }
    val offers by billing.offers.collectAsStateWithLifecycle()
    // Screenshot harness only: open on the plans over a sample catalog,
    // without asking Play or the server.
    val previewPlans = com.roro.futurevoice.capture.flags.MeCaptureFlags.previewPlans
    val livePlans by billing.plans.collectAsStateWithLifecycle()
    val liveSettled by billing.settled.collectAsStateWithLifecycle()
    val plans = previewPlans ?: livePlans
    val settled = liveSettled || previewPlans != null
    var period by remember { mutableStateOf("monthly") }
    var tier by remember { mutableStateOf("plus") }
    var step by remember {
        mutableStateOf(if (previewPlans != null) PaywallStep.PLANS else PaywallStep.RESOLVING)
    }

    LaunchedEffect(Unit) { if (previewPlans == null) billing.refresh() }

    // Trial length and eligibility come from Play's own pricing phases: a
    // trial is a phase priced at zero, and Play only attaches one to an
    // account that can still take it. With NOTHING loaded the funnel still
    // runs on the default — there is nothing purchasable either way, and
    // guessing "no trial" would strip the whole pitch off the screen on a
    // device that simply cannot reach Play.
    val trialDays = offers.mapNotNull { trialDaysOf(it.details).takeIf { d -> d > 0 } }
        .maxOrNull() ?: DEFAULT_TRIAL_DAYS
    val showsTrial = offers.isEmpty() || offers.any { trialDaysOf(it.details) > 0 }

    LaunchedEffect(settled, showsTrial) {
        if (settled && step == PaywallStep.RESOLVING) {
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
    // as a different control each time.
    val catalogPeriods = plans.map { it.period }.distinct()
    val periods = listOf("weekly", "monthly", "annual")
        .filter { it in catalogPeriods }
        .ifEmpty { listOf("monthly", "annual") }
    LaunchedEffect(periods) { if (period !in periods) period = periods.first() }

    val forPeriod = plans.filter { it.period == period }
    // Buying needs a PRICED plan; the cards can render without one.
    val chosen = offers.firstOrNull { it.plan.tier == tier && it.plan.period == period }

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
                showsTrial = showsTrial,
                canBuy = chosen != null,
                chosenTrialDays = chosen?.let { trialDaysOf(it.details) } ?: 0,
                onPrimary = {
                    when (step) {
                        PaywallStep.RESOLVING -> Unit
                        PaywallStep.PITCH -> step = PaywallStep.TIMELINE
                        PaywallStep.TIMELINE -> step = PaywallStep.PLANS
                        PaywallStep.PLANS -> {
                            val activity = context as? Activity
                            if (activity != null && chosen != null) {
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
                PaywallStep.TIMELINE -> TimelineStep(trialDays)
                PaywallStep.PLANS -> PlansStep(
                    plansForPeriod = forPeriod,
                    offers = offers,
                    period = period,
                    periods = periods,
                    onPeriod = { period = it },
                    tier = tier,
                    onTier = { tier = it },
                    settled = settled,
                    hasPricedPlan = chosen != null,
                )
            }
        }
    }
}

/** The pinned CTA, and the one line that de-risks it. */
@Composable
private fun PaywallBottomBar(
    step: PaywallStep,
    trialDays: Int,
    showsTrial: Boolean,
    canBuy: Boolean,
    chosenTrialDays: Int,
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
                    modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)
                        .alpha(if (resolving) 0f else 1f),
                ) {
                    Text(
                        when (step) {
                            PaywallStep.RESOLVING -> ""
                            PaywallStep.PITCH -> stringResource(R.string.try_for_free)
                            PaywallStep.TIMELINE -> stringResource(R.string.see_plans)
                            // A plan Play attaches no free phase to must not be
                            // sold as a trial, whatever the funnel promised.
                            PaywallStep.PLANS ->
                                if (showsTrial && chosenTrialDays > 0)
                                    stringResource(R.string.start_my_free_lld_day_trial, trialDays)
                                else stringResource(R.string.subscribe)
                        },
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                if (step == PaywallStep.PITCH || step == PaywallStep.TIMELINE) {
                    Text(
                        stringResource(R.string.lld_days_free_cancel_anytime, trialDays),
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
private fun TimelineStep(trialDays: Int) {
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
            TimelineRow(Icons.Filled.LockOpen,
                stringResource(R.string.today),
                stringResource(R.string.your_trial_starts_a_week_s_worth_of_talk_and_all_the_review_18afb8),
                showsLine = true)
            TimelineRow(Icons.Filled.NotificationsActive,
                stringResource(R.string.day_lld, maxOf(1, trialDays - 2)),
                stringResource(R.string.a_reminder_that_your_trial_is_about_to_convert_we_ask_to_sen_cd5350),
                showsLine = true)
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

/** Step 3 — the prices, last. */
@Composable
private fun PlansStep(
    plansForPeriod: List<BillingService.Plan>,
    offers: List<BillingService.Offer>,
    period: String,
    periods: List<String>,
    onPeriod: (String) -> Unit,
    tier: String,
    onTier: (String) -> Unit,
    settled: Boolean,
    hasPricedPlan: Boolean,
) {
    Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Text(stringResource(R.string.choose_your_plan),
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(top = 12.dp))

        if (periods.size > 1) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                periods.forEachIndexed { index, p ->
                    SegmentedButton(
                        selected = period == p,
                        onClick = { onPeriod(p) },
                        shape = SegmentedButtonDefaults.itemShape(index, periods.size),
                    ) {
                        Text(stringResource(when (p) {
                            "weekly" -> R.string.weekly
                            "annual" -> R.string.annual
                            else -> R.string.monthly
                        }))
                    }
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            PlanCard(
                plan = plansForPeriod.firstOrNull { it.tier == "plus" },
                price = priceOf(offers, "plus", period),
                savings = annualSavingsPercent(offers, "plus", period),
                period = period,
                name = stringResource(R.string.plan_tier_plus),
                audience = stringResource(R.string.as_much_as_you_want_whenever_you_want),
                selected = tier == "plus",
                onSelect = { onTier("plus") },
            )
            PlanCard(
                plan = plansForPeriod.firstOrNull { it.tier == "light" },
                price = priceOf(offers, "light", period),
                savings = annualSavingsPercent(offers, "light", period),
                period = period,
                name = stringResource(R.string.plan_tier_light),
                audience = stringResource(R.string.keep_it_up_as_a_habit),
                selected = tier == "light",
                onSelect = { onTier("light") },
            )
        }

        // Play answered and had nothing. Say so once, quietly: a disabled
        // button with no explanation reads as the app being broken.
        if (settled && !hasPricedPlan) {
            Text(stringResource(R.string.google_play_isnt_offering_this_plan_here_yet),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        SubscriptionLegal()
    }
}

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
 * One plan. Both cards carry the SAME four rows in the SAME order and units,
 * so the eye compares down the column instead of parsing two sentences.
 */
@Composable
private fun PlanCard(
    plan: BillingService.Plan?,
    /** Play's formatted price, when Play has one. Absent is not an error. */
    price: String?,
    /** Percent saved against paying monthly for a year, on the annual cycle. */
    savings: Int?,
    period: String,
    name: String,
    audience: String,
    selected: Boolean,
    onSelect: () -> Unit,
) {
    val accent = MaterialTheme.colorScheme.primary
    Column(
        Modifier.fillMaxWidth()
            .background(AppSurfaces.card, ContinuousShape(16.dp))
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = if (selected) accent
                else MaterialTheme.colorScheme.outlineVariant,
                shape = ContinuousShape(16.dp))
            .clickable(onClick = onSelect)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(name, style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold)
                // A quiet line about what the plan lets you do — never a
                // filled capsule, which reads as an award and ranks the plans
                // on one axis, making the smaller one look like less.
                Text(audience, style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(
                if (selected) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                contentDescription = null,
                tint = if (selected) accent else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            when {
                // Plus does not cap TALKING at all: talking costs the learner
                // effort, and effort is a better limiter than any ceiling —
                // nobody speaks for six hours. There is no figure to print and
                // none is printed. WATCH still counts, because a scene plays
                // itself — that is a real limit, and hiding a real limit is
                // how you ambush someone.
                plan?.talk_unlimited == true -> {
                    SpecRow(stringResource(R.string.talking), stringResource(R.string.no_limit))
                    plan.monthly_scenes?.let {
                        SpecRow(stringResource(R.string.watch_scenes),
                            stringResource(R.string.lld_mo, it.toInt()))
                    }
                }
                // A card with no numbers beats a card with guessed ones: a
                // catalog row missing its pool would otherwise print "0 min/mo
                // · about 0 min a day", which is a figure nobody sells.
                plan != null && (plan.monthly_seconds ?: 0L) > 0 -> {
                    val minutes = (plan.monthly_seconds!! / 60).toInt()
                    SpecRow(
                        stringResource(R.string.talking),
                        stringResource(R.string.lls_min_mo, grouped(minutes)),
                        // A SIZE CUE, never a rule: the pool has no daily
                        // limit, so this sits under the monthly figure as an
                        // aside rather than replacing it.
                        note = stringResource(R.string.about_lld_min_a_day, minutes / 30),
                    )
                    plan.monthly_scenes?.let {
                        SpecRow(stringResource(R.string.watch_scenes),
                            stringResource(R.string.lld_mo, it.toInt()))
                    }
                }
            }
            SpecRow(stringResource(R.string.your_own_review_book),
                stringResource(R.string.unlimited))
            SpecRow(stringResource(R.string.shadowing_words_replays_drills),
                stringResource(R.string.unlimited))
        }

        // No placeholder when Play hasn't priced it: a dash reads as a broken
        // field, and an absent price says the same thing more quietly. The
        // whole row goes with it.
        price?.let {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.price_per_cycle, it, stringResource(when (period) {
                        "weekly" -> R.string.week
                        "annual" -> R.string.year_4ff0b1
                        else -> R.string.month_021710
                    })),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                // Only ever computed from LIVE prices: a savings badge worked
                // out from figures the viewer is never shown is a claim they
                // cannot check.
                if (period == "annual" && savings != null) {
                    Text(stringResource(R.string.save_lld_vs_monthly, savings),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = SavingsGreen)
                }
            }
        }
    }
}

/**
 * One line of a card's spec block. Label left, figure right — the same labels
 * in the same order on both cards.
 */
@Composable
private fun SpecRow(label: String, value: String, note: String? = null) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        Text(label, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.End) {
            Text(value, style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold)
            note?.let {
                Text(it, style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
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

/** Play's formatted price for a tier+period, when it has one. */
private fun priceOf(offers: List<BillingService.Offer>, tier: String, period: String): String? =
    offers.firstOrNull { it.plan.tier == tier && it.plan.period == period }
        ?.let { recurringPhase(it.details)?.formattedPrice }

/** Micros for a tier+period, for the savings arithmetic only. */
private fun microsOf(offers: List<BillingService.Offer>, tier: String, period: String): Long? =
    offers.firstOrNull { it.plan.tier == tier && it.plan.period == period }
        ?.let { recurringPhase(it.details)?.priceAmountMicros }

/**
 * Percentage the annual plan saves versus paying monthly for a year, for one
 * tier. Null when either price is unknown or annual isn't actually cheaper —
 * a badge is a claim, and an unbacked one is worse than none.
 */
private fun annualSavingsPercent(
    offers: List<BillingService.Offer>, tier: String, period: String,
): Int? {
    if (period != "annual") return null
    val monthly = microsOf(offers, tier, "monthly") ?: return null
    val annual = microsOf(offers, tier, "annual") ?: return null
    val full = monthly * 12
    if (monthly <= 0 || full <= annual) return null
    val pct = Math.round((full - annual).toDouble() / full * 100).toInt()
    return pct.takeIf { it > 0 }
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
