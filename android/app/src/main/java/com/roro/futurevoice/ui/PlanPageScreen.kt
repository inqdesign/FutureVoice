package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Redeem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.SubscriptionReceipt
import com.roro.futurevoice.data.dayLabel
import com.roro.futurevoice.data.renewalLabel
import com.roro.futurevoice.net.ReferralClient
import com.roro.futurevoice.ui.brand.AppSurfaces

/**
 * Me → Usage. "Usage", not "Talk time": the page reports Watch scenes and the
 * subscription too, and the talk figure is one row of it.
 *
 * Three sections and nothing else — what this billing period holds, the
 * subscription as the store bills it, then help. Everything is scoped to the
 * BILLING period rather than the calendar month, and the date that period ends
 * on is stated exactly ONCE.
 *
 * Two rules the numbers rest on:
 *
 *  · **The headline minutes are the server's pool figure**, never a re-sum of
 *    the usage ledger. The ledger is capped and truncates its oldest rows, so
 *    a second count of the same period can only drift from the one the meter
 *    actually enforces.
 *  · **Plus never counts anything DOWN.** A remainder is a monthly receipt for
 *    time NOT used; it reads as money wasted and is the likeliest thing to end
 *    a subscription. The uncapped tier is told what it SPENT. Light keeps the
 *    fraction, because 150 minutes is a number that account actually meets.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlanPageScreen(
    onOpenCreditGuide: () -> Unit,
    onOpenInvite: () -> Unit,
    onBack: () -> Unit,
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    var account by remember { mutableStateOf<AccountStatus?>(null) }
    var inviteOffer by remember { mutableStateOf<InviteOffer?>(null) }
    var receipt by remember { mutableStateOf<SubscriptionReceipt?>(null) }
    LaunchedEffect(Unit) {
        // Screenshot harness only: a sample account instead of the network.
        com.roro.futurevoice.capture.flags.MeCaptureFlags.previewAccount?.let {
            account = it
            receipt = com.roro.futurevoice.capture.flags.MeCaptureFlags.previewReceipt
            inviteOffer = com.roro.futurevoice.capture.flags.MeCaptureFlags.previewInvite
            return@LaunchedEffect
        }
        val auth = AuthRepository()
        val loaded = AccountStatus.load(auth)
        account = loaded
        // Only an entitled account has a subscription to describe, and the
        // read is a nicety — the section simply has less to say when it fails.
        if (loaded.isEntitled) receipt = SubscriptionReceipt.load(auth)
        val cap = loaded.monthlyCapSeconds
        val poolIsSpent = cap != null && loaded.secondsUsedPeriod >= cap && loaded.secondsBalance < 60
        if (poolIsSpent) inviteOffer = InviteOffer.load(loaded)
    }
    val locale = LocalConfiguration.current.locales[0]
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.usage)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp).padding(bottom = 32.dp),
        ) {
            val a = account
            val uncapped = a != null && a.isUncappedTalk

            GroupedSectionHeader(stringResource(
                if (a?.isEntitled == true) R.string.this_month else R.string.left_to_spend))
            GroupedCard {
                ValueRow(Icons.Filled.Bolt, stringResource(R.string.talk_time), talkValue(a))
                // Invite minutes are time ON TOP of the pool, so they are
                // their own row and never folded into the figure above —
                // added in, the fraction would stop adding up. Only where
                // there is a pool for them to sit on top of: an uncapped plan
                // cannot run out, so nothing is waiting to be topped up, and
                // an account with no plan is already being shown this very
                // balance as its talk time.
                if (a != null && a.isEntitled && !uncapped && a.secondsBalance >= 60) {
                    GroupedRowDivider()
                    ValueRow(Icons.Filled.Redeem, stringResource(R.string.invite_minutes),
                        stringResource(R.string.lld_min_7c4bb6, a.secondsBalance / 60))
                }
                // Scenes are capped on EVERY tier — a scene plays itself, so a
                // count is the only limit there is. A real limit is never
                // hidden, not even from the tier sold as "no limit".
                if (a?.monthlyScenesCap != null) {
                    GroupedRowDivider()
                    ValueRow(Icons.Filled.PlayCircle, stringResource(R.string.watch_scenes),
                        stringResource(R.string.scene_fraction,
                            a.scenesUsedPeriod, a.monthlyScenesCap!!))
                }
                val renews = a?.renewalLabel(locale).orEmpty()
                if (a?.isEntitled == true && renews.isNotEmpty()) {
                    GroupedRowDivider()
                    // The same date, three different promises. A trial's date
                    // is not a refill — it is the day it starts costing money;
                    // and a plan told to stop does not refill on that date
                    // either, it ends on it.
                    LineRow(
                        icon = when {
                            // A trial told to stop is not becoming paid; it
                            // ENDS on that date, and saying otherwise to
                            // someone who already cancelled is the app
                            // getting their own decision wrong.
                            a.cancelAtPeriodEnd -> Icons.Filled.EventBusy
                            a.isTrialing -> Icons.Filled.CalendarToday
                            else -> Icons.Filled.CalendarMonth
                        },
                        title = when {
                            a.cancelAtPeriodEnd ->
                                stringResource(R.string.your_plan_ends_on_e00f74, renews)
                            a.isTrialing ->
                                stringResource(R.string.your_trial_becomes_paid_on, renews)
                            else -> stringResource(R.string.refills_on_7e5745, renews)
                        },
                        subtitle = if (a.isTrialing && !a.cancelAtPeriodEnd)
                            stringResource(R.string.cancel_any_time_before_then_in_google_play)
                        else null,
                    )
                }
            }

            // The pool is spent: the one free way back, directly under the
            // pool it answers — and standing in for the ordinary invite row
            // below, never both (iOS `InviteMinutesCard`).
            if (inviteOffer != null) {
                GroupedSectionSpacer()
                GroupedCard { InviteMinutesCard(inviteOffer!!) }
            }

            // The subscription itself, as the store bills it: since when, what
            // the last charge was, whether the launch code is still pricing
            // it. READ only — changing or cancelling is the store's screen,
            // linked at the bottom; an in-app copy of that could only disagree
            // with the store's own.
            val r = receipt
            if (a?.isEntitled == true && r?.source != null) {
                // Collected first, drawn second: which rows a receipt has to
                // offer varies by store and by how far into the subscription
                // it is, and a divider belongs BETWEEN rows — deciding that
                // inline is how a card ends up with a hairline above nothing.
                val rows = mutableListOf<@Composable () -> Unit>()
                r.startedAt?.let { since ->
                    rows += {
                        LineRow(Icons.Filled.CalendarToday,
                            stringResource(R.string.since, since.dayLabel(locale)))
                    }
                }
                if (r.source == "comp") {
                    rows += {
                        LineRow(Icons.Filled.CardGiftcard, stringResource(
                            R.string.provided_by_nawana_until, a.renewalLabel(locale)))
                    }
                } else {
                    val charge = r.lastChargeLabel(locale)
                    val on = r.lastChargeDate
                    if (charge != null && on != null) {
                        rows += {
                            ValueRow(Icons.Filled.CreditCard,
                                stringResource(R.string.last_charge, charge),
                                on.dayLabel(locale))
                        }
                    }
                    // What the store will charge NEXT, and when — but only
                    // where it is news. In a trial it is the whole question:
                    // nothing has been charged, so there is no last-charge row
                    // and the date above says the day it starts costing money.
                    // Otherwise only when the amount is about to CHANGE.
                    val next = r.renewalLabel(locale)
                    if (next != null && r.nextChargeIsNews(a.isTrialing) &&
                        a.renewalLabel(locale).isNotBlank()) {
                        rows += {
                            ValueRow(Icons.Filled.CreditCard,
                                stringResource(
                                    if (a.isTrialing) R.string.first_charge
                                    else R.string.next_charge, next),
                                a.renewalLabel(locale))
                        }
                    }
                    // Nor the launch code's discount: a cancelled trial is not
                    // going to be charged at all, half price or otherwise.
                    r.offerCodeUntil?.takeIf { !a.cancelAtPeriodEnd }?.let { until ->
                        rows += {
                            LineRow(Icons.Filled.LocalOffer,
                                stringResource(R.string.half_price_with_your_launch_code),
                                stringResource(R.string.until_then_the_regular_price,
                                    until.dayLabel(locale)))
                        }
                    }
                    storeManageUrl(r.source)?.let { url ->
                        rows += {
                            LineRow(
                                icon = Icons.AutoMirrored.Filled.OpenInNew,
                                title = stringResource(storeManageTitle(r.source)),
                                subtitle = stringResource(R.string.change_or_cancel_your_plan),
                                onClick = {
                                    runCatching {
                                        context.startActivity(android.content.Intent(
                                            android.content.Intent.ACTION_VIEW,
                                            android.net.Uri.parse(url)))
                                    }
                                },
                            )
                        }
                    }
                }
                // A header over an empty card would announce a section that
                // has nothing to say — which is exactly what a store whose
                // webhook files no transaction leaves behind.
                if (rows.isNotEmpty()) {
                    GroupedSectionHeader(stringResource(R.string.subscription))
                    GroupedCard {
                        rows.forEachIndexed { i, row ->
                            if (i > 0) GroupedRowDivider()
                            row()
                        }
                    }
                }
            }

            GroupedSectionSpacer()
            GroupedCard {
                LineRow(Icons.Filled.HelpOutline,
                    stringResource(R.string.what_uses_talk_time),
                    stringResource(R.string.and_what_s_always_free),
                    onClick = onOpenCreditGuide)
                if (inviteOffer == null) GroupedRowDivider()
                if (inviteOffer == null) LineRow(Icons.Filled.CardGiftcard,
                    stringResource(R.string.invite_earn_talk_time),
                    stringResource(R.string.lld_minutes_each_per_friend, ReferralClient.bonusMinutes),
                    onClick = onOpenInvite)
            }
            // Only where minutes actually run down. On an uncapped plan nothing
            // is being spent, so this would describe a meter that account
            // does not have.
            if (a != null && !uncapped) {
                GroupedFooter(stringResource(
                    R.string.minutes_buy_talk_time_with_your_fluent_self_reviewing_always_e2be9b))
            }
        }
    }
}

/**
 * Uncapped talk is the SUBSCRIPTION's stamp as `talk_allowance` reports it
 * (nil cap on an entitled account), never the tier: since 2026-09-26 a Plus
 * bought today is a 300-minute pool (`20260926110000_bounded_plans_and_topups`)
 * and only the rows sold before keep no ceiling. (Until then this read the
 * plan id, because a deployed `talk_allowance` once lacked the unlimited
 * branch; the server has had it since `20260904130000`.) Everything that
 * hung off `isPlusPlan` — no ring, "N min talked", no invite row — hangs
 * off this now, because those were rules about an UNCOUNTED pool.
 */
val AccountStatus.isUncappedTalk: Boolean
    get() = isEntitled && monthlyCapSeconds == null

/**
 * The one number this tier is owed.
 *
 *  · uncapped plan — what was TALKED this period. There is no pool to count
 *    down and no cap to count against, so a remainder would be meaningless
 *    even before it was demoralizing. The fair-use line is never printed here:
 *    a tier sold as "no limit" must never be shown an allowance, and a real
 *    stop raises its own error saying the account is being checked.
 *  · a pool — BOTH halves of it. "55 of 150" made the reader do the
 *    subtraction, and under a row titled Talk time the single figure was read
 *    as whichever one the reader expected.
 *  · no plan — what is left of the one-time balance.
 */
@Composable
private fun talkValue(a: AccountStatus?): String = when {
    a == null -> ""
    a.isUncappedTalk ->
        stringResource(R.string.lld_min_talked, a.secondsUsedPeriod / 60)
    a.isEntitled && a.monthlyCapSeconds != null -> {
        val cap = a.monthlyCapSeconds!! / 60
        val used = a.secondsUsedPeriod / 60
        stringResource(R.string.lld_min_used_lld_min_left, used, maxOf(0, cap - used))
    }
    a.unlimited || a.secondsBalance > 0 ->
        stringResource(R.string.lld_min_b61908, a.secondsBalance / 60)
    else -> stringResource(R.string.none)
}

/** Where a live subscription is actually managed. Null for a source with no
 *  screen of its own to send anyone to. */
private fun storeManageUrl(source: String?): String? = when (source) {
    "google" -> "https://play.google.com/store/account/subscriptions"
    "apple" -> "https://apps.apple.com/account/subscriptions"
    else -> null
}

private fun storeManageTitle(source: String?): Int = when (source) {
    "apple" -> R.string.manage_in_the_app_store
    else -> R.string.manage_in_google_play
}

@Composable
private fun ValueRow(icon: ImageVector, title: String, value: String) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary)
        Text(title, Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * A row whose title is the whole fact. `subtitle` is optional: a row that has
 * already said everything must not be given a line of prose to fill the slot.
 */
@Composable
private fun LineRow(
    icon: ImageVector, title: String, subtitle: String? = null,
    onClick: (() -> Unit)? = null,
) {
    Row(
        Modifier.fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f)) {
            Text(title)
            subtitle?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (onClick != null) {
            Spacer(Modifier.width(2.dp))
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
