package com.roro.futurevoice.ui

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.clickable
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.ui.graphics.Color
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.net.ReferralClient
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.launch

/**
 * "Invite & talk time": what this account can still speak, the code to share,
 * and — only for an account that never used one — a box to enter a friend's
 * code.
 *
 * A code counts once per account, so the entry box DISAPPEARS once one has
 * been used rather than asking a settled account for something it can no
 * longer do.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InviteScreen(onBack: () -> Unit) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current
    val client = remember { ReferralClient(AuthRepository()) }

    var status by remember { mutableStateOf(ReferralClient.Status()) }
    var account by remember { mutableStateOf(AccountStatus()) }
    var codeInput by remember { mutableStateOf("") }
    var redeeming by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun reload() {
        status = client.status()
        account = AccountStatus.load(AuthRepository())
    }
    LaunchedEffect(Unit) { reload() }

    val bonus = ReferralClient.bonusMinutes

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.invite_talk_time)) },
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
            GroupedCard {
                Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Filled.Bolt, contentDescription = null,
                        modifier = Modifier.size(20.dp),
                        tint = MaterialTheme.colorScheme.primary)
                    Text(stringResource(R.string.talk_time), Modifier.weight(1f))
                    Text(talkTimeLabel(account),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            // Invite minutes are spent BEFORE the plan's monthly pool
            // (20260821100000), so a subscriber sees them come off the top.
            GroupedFooter(stringResource(
                if (account.isEntitled)
                    R.string.invite_minutes_are_used_before_your_monthly_time_so_they_com_41a7e6
                else R.string.minutes_buy_talk_time_with_your_fluent_self_reviewing_is_alw_1b9654))

            GroupedSectionHeader(stringResource(R.string.your_invite_code))
            GroupedCard {
                val code = status.code
                if (code == null) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 14.dp)) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    }
                } else {
                    Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 6.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(code, fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Bold, fontSize = 22.sp,
                            letterSpacing = 3.sp, modifier = Modifier.weight(1f))
                        IconButton(onClick = { clipboard.setText(AnnotatedString(code)) }) {
                            Icon(Icons.Filled.ContentCopy,
                                contentDescription = stringResource(R.string.copy))
                        }
                    }
                    GroupedRowDivider(inset = false)
                    // The store LINK is the payload and the sentence rides
                    // along: shared this way the friend gets something
                    // tappable, not six letters and no way to get the app.
                    Row(
                        Modifier.fillMaxWidth()
                            .clickable {
                                val text = context.getString(
                                    R.string.i_m_practicing_speaking_with_my_own_ai_voice_on_nawana_enter_50926d,
                                    code, bonus) + "\n" + PLAY_URL
                                context.startActivity(Intent.createChooser(
                                    Intent(Intent.ACTION_SEND).apply {
                                        type = "text/plain"
                                        putExtra(Intent.EXTRA_SUBJECT, "nawana")
                                        putExtra(Intent.EXTRA_TEXT, text)
                                    }, null))
                            }
                            .padding(horizontal = 14.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(Icons.Filled.Share, contentDescription = null,
                            modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.primary)
                        Text(stringResource(R.string.share_invite),
                            color = MaterialTheme.colorScheme.primary)
                    }
                    GroupedRowDivider(inset = false)
                    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(Icons.Filled.Group, contentDescription = null,
                            modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.primary)
                        Text(stringResource(R.string.friends_joined), Modifier.weight(1f))
                        Text("${status.invitesUsed} / ${ReferralClient.REWARDED_INVITE_CAP}",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (status.code != null) {
                GroupedFooter(stringResource(
                    R.string.your_friend_enters_this_code_when_they_sign_up_and_you_both_e0ffad,
                    bonus, ReferralClient.REWARDED_INVITE_CAP))
            }

            val joined = status.redeemedCode
            if (joined != null) {
                GroupedCard {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(Icons.Filled.Verified, contentDescription = null,
                            modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.primary)
                        Text(stringResource(R.string.joined_with_a_code), Modifier.weight(1f))
                        Text(joined, fontFamily = FontFamily.Monospace,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                GroupedFooter(stringResource(R.string.a_code_counts_once_per_account_so_this_one_is_done))
            } else {
                GroupedSectionHeader(stringResource(R.string.didn_t_use_a_code_when_you_signed_up))
                GroupedCard {
                    OutlinedTextField(
                        value = codeInput,
                        onValueChange = { codeInput = it.uppercase() },
                        placeholder = { Text(stringResource(R.string.enter_invite_code)) },
                        textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                        singleLine = true,
                        colors = OutlinedTextFieldDefaults.colors(
                            unfocusedBorderColor = Color.Transparent,
                            focusedBorderColor = Color.Transparent),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    GroupedRowDivider(inset = false)
                    // A List-row button, like iOS — not a filled slab, which
                    // would be the only one on the page and read as the
                    // screen's purpose rather than one row's action.
                    Row(
                        Modifier.fillMaxWidth()
                            .clickable(enabled = !redeeming && codeInput.isNotBlank()) {
                                redeeming = true; error = null; message = null
                                scope.launch {
                                    runCatching { client.redeem(codeInput) }
                                        .onSuccess { r ->
                                            message = if (r.isComp)
                                                context.getString(
                                                    R.string.redeemed_is_on_your_account,
                                                    tierName(r.compPlanId))
                                            else context.getString(
                                                R.string.redeemed_lld_minutes_added, bonus)
                                            codeInput = ""
                                            reload()
                                        }
                                        .onFailure { e -> error = context.getString(reasonText(e)) }
                                    redeeming = false
                                }
                            }
                            .padding(horizontal = 14.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(stringResource(R.string.redeem),
                            color = if (!redeeming && codeInput.isNotBlank())
                                MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.outline,
                            modifier = Modifier.weight(1f))
                        if (redeeming) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        }
                    }
                    message?.let {
                        GroupedRowDivider(inset = false)
                        Text(it, style = MaterialTheme.typography.bodySmall,
                            color = Color(0xFF34C759),
                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
                    }
                    error?.let {
                        GroupedRowDivider(inset = false)
                        Text(it, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp))
                    }
                }
                GroupedFooter(stringResource(R.string.enter_it_here_instead_lld_minutes_once, bonus))
            }
        }
    }
}

private const val PLAY_URL = "https://play.google.com/store/apps/details?id=com.roro.futurevoice"

/** Each refusal names the server-side guard that fired, so the learner is
 *  told the actual reason rather than "try again". */
private fun reasonText(e: Throwable): Int = when (
    (e as? ReferralClient.RedeemFailure)?.reason
) {
    ReferralClient.RedeemError.INVALID -> R.string.that_invite_code_isn_t_valid
    ReferralClient.RedeemError.ALREADY_REDEEMED -> R.string.you_ve_already_used_a_code
    ReferralClient.RedeemError.SELF_REFERRAL -> R.string.you_can_t_use_your_own_code
    ReferralClient.RedeemError.ALREADY_SUBSCRIBED -> R.string.you_re_already_subscribed
    else -> R.string.couldn_t_redeem_that_code_try_again
}

/**
 * What this account can still speak. Plus never counts DOWN — a remainder is
 * a monthly receipt for time NOT used, and it reads as money wasted.
 */
@Composable
private fun talkTimeLabel(a: AccountStatus): String = when {
    a.unlimited || a.isPlusPlan ->
        stringResource(R.string.lld_min_talked_this_month, a.secondsUsedPeriod / 60)
    // Light keeps the fraction: 150 minutes is a number that account
    // actually meets, and how they spend it is their business.
    a.monthlyCapSeconds != null -> stringResource(R.string.lld_of_lld_min_talked_this_month,
        a.secondsUsedPeriod / 60, a.monthlyCapSeconds!! / 60)
    else -> stringResource(R.string.lld_min_left, a.secondsBalance / 60)
}

@Composable
private fun Footer(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/**
 * A plan id turned into the name the buyer reads. Tier names say SIZE and
 * never grade the buyer, and the Apple/Play product ids deliberately still
 * carry the old words — so the id is a lookup key, never a label.
 */
private fun tierName(planId: String?): String = when {
    planId == null -> "Plus"
    planId.startsWith("light") || planId.contains("daily") -> "Light"
    else -> "Plus"
}
