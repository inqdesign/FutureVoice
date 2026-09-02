package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R

/** Which pool ran out. They read differently and offer different things. */
enum class SpentPool { TALK, SCENES }

/**
 * A spent allowance is a SHEET, never an error and never a bare paywall.
 *
 * It replaced two alerts on iOS that could state the rule but had nowhere to
 * put the thing to do next. The day ending on schedule is the plan working,
 * not a failure — and the word "credits" is wrong for an account that has
 * already paid.
 *
 * The free review is offered FIRST, because it is the thing they can do right
 * now. Plus appears only where there is something to sell: on Plus itself the
 * upgrade half is ABSENT, not disabled — there is nothing left to offer that
 * account, so for them the answer really is next period.
 *
 * Plan SIZES stay out of this copy. The client doesn't know Plus's numbers,
 * and a hardcoded "120 scenes" goes stale silently.
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
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                stringResource(
                    if (pool == SpentPool.TALK) R.string.thats_your_talk_time_for_this_period
                    else R.string.thats_your_watch_scenes_for_this_period),
                style = MaterialTheme.typography.titleLarge,
            )
            Text(stringResource(R.string.it_refills_when_the_period_does_meanwhile_review_is_free),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)

            Button(onClick = onReview, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.review_cards))
            }
            if (canUpgrade) {
                OutlinedButton(onClick = onUpgrade, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.keep_going_today))
                }
            }
        }
    }
}
