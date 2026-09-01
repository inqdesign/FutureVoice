package com.roro.futurevoice.ui

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.BillingService
import com.roro.futurevoice.ui.brand.AppSurfaces
import java.text.NumberFormat
import java.util.Locale

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
    androidx.activity.compose.BackHandler(onBack = onDismiss)
    val context = LocalContext.current
    val billing = remember { BillingService.shared(context) }
    val offers by billing.offers.collectAsStateWithLifecycle()
    val plans by billing.plans.collectAsStateWithLifecycle()
    val settled by billing.settled.collectAsStateWithLifecycle()
    var period by remember { mutableStateOf("monthly") }
    var tier by remember { mutableStateOf("plus") }

    LaunchedEffect(Unit) { billing.refresh() }

    val forPeriod = plans.filter { it.period == period }
    // Periods come from the CATALOG, not from what Play priced: a period
    // whose product hasn't been created yet is still a real plan, and hiding
    // it would leave the picker with nothing on a device Play can't reach.
    val periods = plans.map { it.period }.distinct().ifEmpty { listOf("monthly", "annual") }
    LaunchedEffect(periods) { if (period !in periods) period = periods.first() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close))
                    }
                },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Text(stringResource(R.string.choose_your_plan),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold)

            if (periods.size > 1) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    periods.forEach { p ->
                        FilterChip(
                            selected = period == p,
                            onClick = { period = p },
                            label = {
                                Text(stringResource(
                                    if (p == "annual") R.string.annual else R.string.monthly))
                            },
                        )
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                PlanCard(
                    plan = forPeriod.firstOrNull { it.tier == "plus" },
                    price = priceOf(offers, "plus", period),
                    name = stringResource(R.string.plus),
                    audience = stringResource(R.string.as_much_as_you_want_whenever_you_want),
                    selected = tier == "plus",
                    onSelect = { tier = "plus" },
                )
                PlanCard(
                    plan = forPeriod.firstOrNull { it.tier == "light" },
                    price = priceOf(offers, "light", period),
                    name = stringResource(R.string.light),
                    audience = stringResource(R.string.keep_it_up_as_a_habit),
                    selected = tier == "light",
                    onSelect = { tier = "light" },
                )
            }

            // Buying needs a PRICED plan; the cards can render without one.
            val chosen = offers.firstOrNull { it.plan.tier == tier && it.plan.period == period }
            Button(
                onClick = {
                    val activity = context as? Activity ?: return@Button
                    chosen?.let { billing.purchase(activity, it) }
                },
                enabled = chosen != null,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (!settled) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Text(stringResource(R.string.subscribe))
                }
            }
            // Play answered and had nothing. Say so once, quietly: a disabled
            // button with no explanation reads as the app being broken.
            if (settled && chosen == null) {
                Text(stringResource(R.string.google_play_isnt_offering_this_plan_here_yet),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            // Required on any screen that sells an auto-renewing subscription.
            // Not decoration: a missing statement of what renews and how to
            // stop it is a standard store rejection.
            Text(stringResource(R.string.subscription_legal_google),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
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
    name: String,
    audience: String,
    selected: Boolean,
    onSelect: () -> Unit,
) {
    val accent = MaterialTheme.colorScheme.primary
    Column(
        Modifier.fillMaxWidth()
            .background(AppSurfaces.card, RoundedCornerShape(16.dp))
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = if (selected) accent
                else MaterialTheme.colorScheme.outlineVariant,
                shape = RoundedCornerShape(16.dp))
            .clickable(onClick = onSelect)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(name, style = MaterialTheme.typography.titleMedium,
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
                // none is printed.
                plan?.talk_unlimited == true -> {
                    SpecRow(stringResource(R.string.talking), stringResource(R.string.no_limit))
                    plan.monthly_scenes?.let {
                        SpecRow(stringResource(R.string.watch_scenes), "$it/mo")
                    }
                }
                plan != null -> {
                    val minutes = ((plan.monthly_seconds ?: 0L) / 60).toInt()
                    SpecRow(
                        stringResource(R.string.talking),
                        stringResource(R.string.lls_min_mo, grouped(minutes)),
                        // A SIZE CUE, never a rule: the pool has no daily
                        // limit, so this sits under the monthly figure as an
                        // aside rather than replacing it.
                        note = stringResource(R.string.about_lld_min_a_day, minutes / 30),
                    )
                    plan.monthly_scenes?.let {
                        SpecRow(stringResource(R.string.watch_scenes), "$it/mo")
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
            Text(it, style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold)
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
 * A figure grouped in the learner's own language, for any card number that
 * can reach four digits.
 *
 * NEVER interpolate such a number straight into a localized string: it is
 * grouped by the FORMATTING locale, which follows the device region rather
 * than the app language — that is how a German-grouped "1.800" shipped inside
 * a Korean sentence, where it reads as one point eight.
 */
/** Play's formatted price for a tier+period, when it has one. */
private fun priceOf(offers: List<BillingService.Offer>, tier: String, period: String): String? =
    offers.firstOrNull { it.plan.tier == tier && it.plan.period == period }
        ?.details?.subscriptionOfferDetails?.firstOrNull()
        ?.pricingPhases?.pricingPhaseList?.firstOrNull()?.formattedPrice

private fun grouped(n: Int): String =
    NumberFormat.getIntegerInstance(Locale.getDefault()).format(n)
