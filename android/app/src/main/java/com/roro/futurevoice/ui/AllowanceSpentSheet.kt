package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Refresh
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import com.roro.futurevoice.ui.brand.IosTonalButton as FilledTonalButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.BillingGate
import com.roro.futurevoice.data.TopUpOffer
import com.roro.futurevoice.data.renewalLabel

/** Which pool ran out. They read differently and offer different things. */
enum class SpentPool { TALK, SCENES }

/**
 * systemGreen — a SEMANTIC literal (the period finished, and finishing it is
 * the plan working), the one kind of hardcoded colour the UI rules allow, and
 * the same value `DrillBin` uses for "got it".
 */
private val DoneGreen = Color(0xFF34C759)

/**
 * This period's metered pool is spent — talk minutes, or Watch scenes.
 *
 * Deliberately NOT the error alert and never a bare paywall: this learner
 * already paid, and a pool that runs out is the plan working exactly as sold.
 * So the sheet says the month's talking is done, names the size of what was
 * spent, says when it comes back, and offers the next thing to do.
 *
 * A talk-minute pack leads on a spent TALK pool once it has a price — it is
 * the literal answer to "I want to keep talking" ([TopUpOffer]); then, when a
 * bigger plan is on sale, the upgrade — Light → Plus, Plus → Max
 * (`AccountStatus.upgradeTier`) — because it is the answer to "I want to keep
 * talking"; review stays one tap away and free either way. At the top the
 * upgrade half is ABSENT rather than disabled — there is nothing left to offer
 * that account, so for them the answer really is the renewal date.
 *
 * It replaced two alerts on iOS that could state the rule but had nowhere to
 * put the thing to do next.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AllowanceSpentSheet(
    pool: SpentPool,
    onReview: () -> Unit,
    onUpgrade: () -> Unit,
    onDismiss: () -> Unit,
) {
    // The pool's own size and its refill date, read live rather than
    // hardcoded: a spent allowance whose size the learner cannot see reads as
    // an arbitrary stop, and the size was on the card before the purchase.
    // Loaded here rather than passed in, so every caller gets the same sheet.
    //
    // The sheet waits for both answers before it appears (iOS resolves the
    // account and the invite offer BEFORE raising it, "so no button grows
    // under the learner's thumb"): drawn first and filled in after, the plan
    // move and the invite row arrived a beat late under a finger already
    // reaching for "Go to Review".
    var account by remember { mutableStateOf<AccountStatus?>(null) }
    var inviteOffer by remember { mutableStateOf<InviteOffer?>(null) }
    var resolved by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        // Screenshot harness only: a sample account instead of the network.
        account = com.roro.futurevoice.capture.flags.MeCaptureFlags.previewAccount
            ?: runCatching { AccountStatus.load(AuthRepository()) }.getOrNull()
        if (pool == SpentPool.TALK) account?.let {
            inviteOffer = com.roro.futurevoice.capture.flags.MeCaptureFlags.previewInvite
                ?: runCatching { InviteOffer.load(it) }.getOrNull()
        }
        resolved = true
    }
    if (!resolved) return
    // A bigger plan is on sale for this account (iOS `canUpgradePlan =
    // account.upgradeTier != nil`) — resolved here, never by the caller.
    val canUpgrade = account?.upgradeTier != null

    // Same line every billing surface uses, so one date format reaches them all.
    val locale = LocalConfiguration.current.locales[0]
    val allowance = account?.let {
        when (pool) {
            SpentPool.TALK -> it.monthlyCapSeconds?.takeIf { s -> s > 0 }?.div(60)
            SpentPool.SCENES -> it.monthlyScenesCap?.takeIf { s -> s > 0 }
        }
    }
    val renewsOn = account?.renewalLabel(locale).orEmpty()
    // A TRIAL's pool is the trial's own (pro-rated, whatever plan is being
    // tried): nothing here may say "this month", offer a bigger plan (a
    // bigger plan's trial is metered at the same pool — the button would
    // cost money and change nothing), or call the date a refill — it is the
    // day the subscription starts (iOS `isTrial`, 2026-09-25).
    val isTrial = account?.isTrialing == true
    val planMinutesAfterTrial = account?.planMonthlySeconds?.takeIf { it > 0 }?.div(60)
    val endsInstead = account?.cancelAtPeriodEnd == true
    val showsUpgrade = SpentSheetCopy.showsUpgrade(canUpgrade, isTrial)
    // The tier "Move to …" lands on: the next bigger one ON SALE (Light →
    // Plus, Plus → Max — iOS `upgradeTier`). Plus is the fallback name only
    // while the account is still loading behind a caller that already knows.
    val upgradeTier = account?.upgradeTier ?: "plus"
    val upgradeName = stringResource(AccountStatus.tierNameRes(upgradeTier))
    val upgrade = {
        BillingGate.paywallTier.value = upgradeTier
        onUpgrade()
    }
    // Asked for on the account alone; LEADS only once Play has priced it
    // (iOS `packOffered` / `packLeads`).
    val packOffered = TopUpOffer.onSpentSheet(account, pool == SpentPool.TALK)
    var packOnSale by remember { mutableStateOf(false) }
    val packLeads = TopUpOffer.leads(packOffered, packOnSale)

    ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),onDismissRequest = onDismiss) {
        Column(
            Modifier.sheetBody()
                .padding(horizontal = 20.dp).padding(top = 8.dp, bottom = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Icon(Icons.Filled.CheckCircle, contentDescription = null,
                tint = DoneGreen, modifier = Modifier.size(44.dp))

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(
                    stringResource(SpentSheetCopy.title(pool, isTrial)),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                )
                Column(
                    Modifier.padding(horizontal = 4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    // What ran out — named as the size that was bought, not as
                    // a number sprung on someone.
                    Text(spentLine(pool, allowance, isTrial),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center)
                    // What to do about it — the whole reason this isn't an alert.
                    // Names the pack only when the pack button is THERE — a
                    // line that says "add minutes" over a sheet with no such
                    // button is the wrong promise the lead rule exists for.
                    Text(
                        when (SpentSheetCopy.next(isTrial, endsInstead, renewsOn.isNotEmpty(),
                            planMinutesAfterTrial != null, packLeads, showsUpgrade)) {
                            SpentSheetCopy.Next.TRIAL_STARTS_WITH_MINUTES -> stringResource(
                                R.string.your_plan_starts_on_with_lld_minutes_of_talk_a_month_review_4d9f2b,
                                renewsOn, planMinutesAfterTrial ?: 0)
                            SpentSheetCopy.Next.TRIAL_STARTS -> stringResource(
                                R.string.your_plan_starts_on_review_stays_free_until_then, renewsOn)
                            SpentSheetCopy.Next.ADD_MOVE_OR_REVIEW ->
                                stringResource(R.string.spent_add_minutes_move_or_review, upgradeName)
                            SpentSheetCopy.Next.ADD_OR_REVIEW -> stringResource(
                                R.string.add_minutes_to_keep_going_now_or_review_what_this_month_left_044ece)
                            SpentSheetCopy.Next.REVIEW_OR_MOVE ->
                                stringResource(R.string.spent_review_or_move_to_tier, upgradeName)
                            SpentSheetCopy.Next.REVIEW_FREE ->
                                stringResource(R.string.review_stays_free_and_always_did)
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center)
                }

                // The one fact a monthly pool needs and a daily one never did:
                // WHEN it comes back. "Tomorrow" explained itself; a date has
                // to be said — and a plan told to stop ENDS on that date
                // instead, which is the same date with the opposite promise.
                val renewal = SpentSheetCopy.renewal(isTrial, endsInstead, renewsOn.isNotEmpty())
                if (renewal != SpentSheetCopy.Renewal.NONE) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.Refresh, contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(16.dp))
                        Text(
                            when (renewal) {
                                SpentSheetCopy.Renewal.TRIAL_ENDS ->
                                    stringResource(R.string.your_trial_ends_on_d70dbd, renewsOn)
                                SpentSheetCopy.Renewal.PLAN_ENDS ->
                                    stringResource(R.string.your_plan_ends_on_1352d6, renewsOn)
                                else -> stringResource(R.string.your_pool_refills_on, renewsOn)
                            },
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }

            Column(
                Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                // Order is the recommendation: the pack, the plan move,
                // review. Exactly one of them is prominent — the first one
                // actually drawn.
                if (packOffered) {
                    TalkTopUpButton(onAvailability = { packOnSale = it }, onPurchased = onDismiss)
                }
                if (showsUpgrade) {
                    if (packLeads) {
                        FilledTonalButton(onClick = upgrade, modifier = Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.spent_move_to_tier, upgradeName))
                        }
                    } else {
                        Button(onClick = upgrade, modifier = Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.spent_move_to_tier, upgradeName))
                        }
                    }
                }
                // Tonal, not outlined: iOS's `.bordered` is a filled capsule,
                // and an outline here reads as the weaker of two choices
                // rather than the free one.
                if (packLeads || showsUpgrade) {
                    FilledTonalButton(onClick = onReview, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.go_to_review))
                    }
                } else {
                    Button(onClick = onReview, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.go_to_review))
                    }
                }
                // Last, and on a TALK wall only: an invite can't resume this
                // call (the friend has to join first), and a scene pool can't
                // be topped up with talk minutes at all.
                if (pool == SpentPool.TALK) inviteOffer?.let { InviteShareRow(it) }
                TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.not_now),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/**
 * What ran out. Names the pool's own size when the client knows it — that is
 * what the learner bought. Both tiers print it: Plus is no longer sold as
 * unlimited, so hiding its number would be concealment.
 */
@Composable
private fun spentLine(pool: SpentPool, allowance: Int?, isTrial: Boolean): String = when {
    isTrial && pool == SpentPool.TALK && allowance != null ->
        stringResource(R.string.all_lld_minutes_of_trial_talk_are_used_up, allowance)
    isTrial && pool == SpentPool.TALK -> stringResource(R.string.the_trial_s_talk_time_is_used_up)
    isTrial && allowance != null -> stringResource(R.string.all_lld_trial_scenes_are_used_up, allowance)
    isTrial -> stringResource(R.string.the_trial_s_scenes_are_used_up)
    pool == SpentPool.TALK && allowance != null ->
        stringResource(R.string.all_lld_minutes_of_talk_are_used_up, allowance)
    pool == SpentPool.TALK -> stringResource(R.string.this_month_s_talk_time_is_used_up)
    allowance != null -> stringResource(R.string.all_lld_scenes_are_used_up, allowance)
    else -> stringResource(R.string.this_month_s_scenes_are_used_up)
}

/**
 * The sheet's copy decisions, pure so they can be pinned by a test (iOS
 * `DailyAllowanceSheet.title` / `nextLine` / `renewalLine`).
 */
internal object SpentSheetCopy {
    /** "Move to …" is drawn: a bigger plan is on sale and this is not a trial. */
    fun showsUpgrade(canUpgrade: Boolean, isTrial: Boolean): Boolean = canUpgrade && !isTrial

    fun title(pool: SpentPool, isTrial: Boolean): Int = when {
        isTrial && pool == SpentPool.TALK -> R.string.that_s_your_trial_s_talk_time
        isTrial -> R.string.that_s_your_trial_s_scenes
        pool == SpentPool.TALK -> R.string.that_s_this_month_s_talk_time
        else -> R.string.that_s_this_month_s_scenes
    }

    enum class Next {
        TRIAL_STARTS_WITH_MINUTES, TRIAL_STARTS,
        ADD_MOVE_OR_REVIEW, ADD_OR_REVIEW, REVIEW_OR_MOVE, REVIEW_FREE,
    }

    /**
     * What to do about it. A stopped trialer hears the one thing they need:
     * this was the trial's pool, the plan starts on a date, and it is a
     * different size. A cancelled trial (or no date) has nothing starting.
     */
    fun next(
        isTrial: Boolean, endsInstead: Boolean, hasDate: Boolean,
        knowsPlanMinutes: Boolean, packLeads: Boolean, showsUpgrade: Boolean,
    ): Next = when {
        isTrial && (endsInstead || !hasDate) -> Next.REVIEW_FREE
        isTrial && knowsPlanMinutes -> Next.TRIAL_STARTS_WITH_MINUTES
        isTrial -> Next.TRIAL_STARTS
        packLeads && showsUpgrade -> Next.ADD_MOVE_OR_REVIEW
        packLeads -> Next.ADD_OR_REVIEW
        showsUpgrade -> Next.REVIEW_OR_MOVE
        else -> Next.REVIEW_FREE
    }

    enum class Renewal { NONE, TRIAL_ENDS, PLAN_ENDS, REFILLS }

    /** The date line. On a trial the start date is already in [next]; only a
     *  cancelled trial has a separate thing to say about that day. */
    fun renewal(isTrial: Boolean, endsInstead: Boolean, hasDate: Boolean): Renewal = when {
        !hasDate -> Renewal.NONE
        isTrial -> if (endsInstead) Renewal.TRIAL_ENDS else Renewal.NONE
        endsInstead -> Renewal.PLAN_ENDS
        else -> Renewal.REFILLS
    }
}
