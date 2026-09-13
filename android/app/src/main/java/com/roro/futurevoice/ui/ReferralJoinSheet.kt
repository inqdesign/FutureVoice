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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.ReferralJoins
import com.roro.futurevoice.net.ReferralClient

/** A friend joined with your code — said in the app, not only in a notification. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReferralJoinSheet(join: ReferralJoins.Join, onDismiss: () -> Unit) {
    val headline = when {
        join.friendName != null -> stringResource(R.string.referral_joined_named, join.friendName)
        join.friendsJoined == 1 -> stringResource(R.string.a_friend_joined_with_your_code_975008)
        else -> stringResource(R.string.lld_friends_joined_with_your_code_fe4dfc, join.friendsJoined)
    }
    // Past the cap the friend still got their half, so the line stays warm
    // instead of reading as a rejection.
    val support = if (join.minutesEarned > 0)
        stringResource(R.string.they_got_lld_minutes_too_that_s_lld_of_your_lld_rewarded_inv_9c811c, ReferralClient.bonusMinutes, join.totalJoined, ReferralClient.REWARDED_INVITE_CAP)
    else stringResource(R.string.they_got_lld_minutes_your_lld_rewarded_invites_are_already_u_5cb510, ReferralClient.bonusMinutes, ReferralClient.REWARDED_INVITE_CAP)
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 24.dp).padding(bottom = 32.dp, top = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(headline, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            if (join.minutesEarned > 0) Text(stringResource(R.string.lld_min_7c4bb6, join.minutesEarned),
                style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary)
            Text(support, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.nice)) }
        }
    }
}
