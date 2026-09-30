package com.roro.futurevoice.ui

import android.content.Context
import com.roro.futurevoice.ui.brand.ContinuousShape
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.net.ReferralClient

/**
 * Inviting a friend is the third answer to a spent pool, and the only free
 * one (iOS `InviteMinutesCard.swift`, 2026-09-27): invite minutes land in the
 * balance, which is spent BEFORE the plan's pool, so a subscriber whose month
 * ran out talks again the moment a friend joins. Three clauses, each a way the
 * offer would otherwise be a lie: an ENTITLED account (a free one's answer is
 * the plans), a COUNTED pool (an uncapped plan never spends the balance), and
 * rewards left.
 */
data class InviteOffer(val code: String, val invitesUsed: Int) {
    val bonusMinutes: Int get() = ReferralClient.bonusMinutes

    companion object {
        suspend fun load(account: AccountStatus): InviteOffer? {
            if (!account.isEntitled || account.monthlyCapSeconds == null) return null
            val status = runCatching { ReferralClient(com.roro.futurevoice.data.AuthRepository()).status() }
                .getOrNull() ?: return null
            val code = status.code ?: return null
            if (status.invitesUsed >= ReferralClient.REWARDED_INVITE_CAP) return null
            return InviteOffer(code, status.invitesUsed)
        }
    }
}

private const val PLAY_URL = "https://play.google.com/store/apps/details?id=com.roro.futurevoice"

internal fun shareInvite(context: Context, offer: InviteOffer) {
    val text = context.getString(
        R.string.i_m_practicing_speaking_with_my_own_ai_voice_on_nawana_enter_50926d,
        offer.code, offer.bonusMinutes) + "\n" + PLAY_URL
    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, "nawana")
        putExtra(Intent.EXTRA_TEXT, text)
    }, null))
}

/** The spent-talk sheet's last line. */
@Composable
fun InviteShareRow(offer: InviteOffer) {
    val context = LocalContext.current
    TextButton(onClick = { shareInvite(context, offer) }, modifier = Modifier.fillMaxWidth()) {
        Icon(Icons.Filled.CardGiftcard, contentDescription = null, modifier = Modifier.size(18.dp))
        Text("  " + stringResource(R.string.invite_a_friend_lld_min_each, offer.bonusMinutes),
            style = MaterialTheme.typography.bodyMedium)
    }
}

/** Usage page, directly under the spent pool it answers. */
@Composable
fun InviteMinutesCard(offer: InviteOffer, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var copied by remember { mutableStateOf(false) }
    Column(modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.CardGiftcard, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Text(stringResource(R.string.lld_minutes_each_together, offer.bonusMinutes),
                style = MaterialTheme.typography.titleMedium)
        }
        Text(stringResource(R.string.when_a_friend_joins_with_your_code_you_both_get_lld_minutes_de6e19, offer.bonusMinutes),
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.weight(1f).height(40.dp)
                .background(MaterialTheme.colorScheme.surfaceVariant, ContinuousShape(10.dp))
                .padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(offer.code, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f))
                IconButton(onClick = {
                    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    cm.setPrimaryClip(android.content.ClipData.newPlainText("nawana", offer.code))
                    copied = true
                }) {
                    Icon(if (copied) Icons.Filled.Check else Icons.Filled.ContentCopy,
                        contentDescription = stringResource(R.string.copy_code), modifier = Modifier.size(18.dp))
                }
            }
            Button(onClick = { shareInvite(context, offer) }) { Text(stringResource(R.string.share_invite)) }
        }
        Text(stringResource(R.string.rewarded_for_your_first_lld_friends, ReferralClient.REWARDED_INVITE_CAP),
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
