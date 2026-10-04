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
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.FilledTonalButton
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
 * On Light the upgrade LEADS, because it is the answer to "I want to keep
 * talking"; review stays one tap away and free either way. On Plus the upgrade
 * half is ABSENT rather than disabled — there is nothing left to offer that
 * account, so for them the answer really is the renewal date.
 *
 * It replaced two alerts on iOS that could state the rule but had nowhere to
 * put the thing to do next.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AllowanceSpentSheet(
    pool: SpentPool,
    canUpgrade: Boolean,
    onReview: () -> Unit,
    onUpgrade: () -> Unit,
    onDismiss: () -> Unit,
) {
    // The pool's own size and its refill date, read live rather than
    // hardcoded: a spent allowance whose size the learner cannot see reads as
    // an arbitrary stop, and the size was on the card before the purchase.
    // Loaded here rather than passed in, so every caller gets the same sheet.
    var account by remember { mutableStateOf<AccountStatus?>(null) }
    var inviteOffer by remember { mutableStateOf<InviteOffer?>(null) }
    LaunchedEffect(Unit) {
        // Screenshot harness only: a sample account instead of the network.
        account = com.roro.futurevoice.capture.flags.MeCaptureFlags.previewAccount
            ?: AccountStatus.load(AuthRepository())
        if (pool == SpentPool.TALK) account?.let { inviteOffer = InviteOffer.load(it) }
    }

    // Same line every billing surface uses, so one date format reaches them all.
    val locale = LocalConfiguration.current.locales[0]
    val allowance = account?.let {
        when (pool) {
            SpentPool.TALK -> it.monthlyCapSeconds?.takeIf { s -> s > 0 }?.div(60)
            SpentPool.SCENES -> it.monthlyScenesCap?.takeIf { s -> s > 0 }
        }
    }
    val renewsOn = account?.renewalLabel(locale).orEmpty()

    ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().bottomBarInsets()
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
                    stringResource(
                        if (pool == SpentPool.TALK) R.string.that_s_this_month_s_talk_time
                        else R.string.that_s_this_month_s_scenes),
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
                    Text(spentLine(pool, allowance),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center)
                    // What to do about it — the whole reason this isn't an alert.
                    Text(
                        stringResource(
                            if (canUpgrade) R.string.review_what_this_month_left_you_or_move_to_plus_to_keep_goin_a63865
                            else R.string.review_stays_free_and_always_did),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center)
                }

                // The one fact a monthly pool needs and a daily one never did:
                // WHEN it comes back. "Tomorrow" explained itself; a date has
                // to be said — and a plan told to stop ENDS on that date
                // instead, which is the same date with the opposite promise.
                if (renewsOn.isNotEmpty()) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.Refresh, contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(16.dp))
                        Text(
                            if (account?.cancelAtPeriodEnd == true)
                                stringResource(R.string.your_plan_ends_on_1352d6, renewsOn)
                            else stringResource(R.string.your_pool_refills_on, renewsOn),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }

            Column(
                Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                // Order is the recommendation.
                if (canUpgrade) {
                    Button(onClick = onUpgrade, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.move_to_plus))
                    }
                    // Tonal, not outlined: iOS's `.bordered` is a filled
                    // capsule, and an outline here reads as the weaker of two
                    // choices rather than the free one.
                    FilledTonalButton(onClick = onReview, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.go_to_practice))
                    }
                } else {
                    Button(onClick = onReview, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.go_to_practice))
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
private fun spentLine(pool: SpentPool, allowance: Int?): String = when {
    pool == SpentPool.TALK && allowance != null ->
        stringResource(R.string.all_lld_minutes_of_talk_are_used_up, allowance)
    pool == SpentPool.TALK -> stringResource(R.string.this_month_s_talk_time_is_used_up)
    allowance != null -> stringResource(R.string.all_lld_scenes_are_used_up, allowance)
    else -> stringResource(R.string.this_month_s_scenes_are_used_up)
}
