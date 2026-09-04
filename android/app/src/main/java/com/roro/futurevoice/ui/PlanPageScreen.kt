package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material.icons.filled.HelpOutline
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.renewalLabel
import com.roro.futurevoice.net.ReferralClient
import com.roro.futurevoice.ui.brand.AppSurfaces

/**
 * Me → Talk time. What is left this month, the plan and its refill date, then
 * help.
 *
 * It states the refill date exactly ONCE. The rows used to be spread across
 * Me itself, where the same fact was told three times — and where the invite
 * and the transparency page sat at the top level rather than beside the
 * allowance they explain.
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
    LaunchedEffect(Unit) { account = AccountStatus.load(AuthRepository()) }
    val locale = LocalConfiguration.current.locales[0]

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.talk_time)) },
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
            GroupedSectionHeader(stringResource(
                if (a?.isEntitled == true) R.string.this_month else R.string.left_to_spend))
            GroupedCard {
                ValueRow(Icons.Filled.Bolt, stringResource(R.string.talk_time),
                    talkValue(a))
                if (a?.monthlyScenesCap != null) {
                    GroupedRowDivider()
                    ValueRow(Icons.Filled.PlayCircle, stringResource(R.string.watch_scenes),
                        stringResource(R.string.lld_of_lld,
                            a.scenesUsedPeriod, a.monthlyScenesCap!!))
                }
                val renews = a?.renewalLabel(locale).orEmpty()
                if (renews.isNotEmpty()) {
                    GroupedRowDivider()
                    // A plan told to stop ENDS on that date rather than
                    // refilling — the same date, the opposite promise.
                    SubtitleRow(
                        if (a?.cancelAtPeriodEnd == true) Icons.Filled.EventBusy
                        else Icons.Filled.CalendarMonth,
                        if (a?.cancelAtPeriodEnd == true)
                            stringResource(R.string.your_plan_ends_on_lld, renews)
                        else stringResource(R.string.refills_on_7e5745, renews),
                        null,
                    )
                }
            }

            GroupedSectionHeader(stringResource(R.string.help))
            GroupedCard {
                SubtitleRow(Icons.Filled.HelpOutline,
                    stringResource(R.string.what_uses_talk_time),
                    stringResource(R.string.and_what_s_always_free),
                    onClick = onOpenCreditGuide)
                GroupedRowDivider()
                SubtitleRow(Icons.Filled.CardGiftcard,
                    stringResource(R.string.invite_earn_talk_time),
                    stringResource(R.string.lld_minutes_each_per_friend, ReferralClient.bonusMinutes),
                    onClick = onOpenInvite)
            }
            GroupedFooter(stringResource(
                R.string.minutes_buy_talk_time_with_your_fluent_self_reviewing_always_e2be9b))
        }
    }
}

/**
 * Plus never counts anything DOWN. A remainder is a monthly receipt for time
 * NOT used; it reads as money wasted and is the likeliest thing to end the
 * subscription. Light keeps the fraction — 150 minutes is a number that
 * account actually meets.
 */
@Composable
private fun talkValue(a: AccountStatus?): String = when {
    a == null -> ""
    a.unlimited || a.isPlusPlan ->
        stringResource(R.string.lld_min_talked_this_month, a.secondsUsedPeriod / 60)
    a.monthlyCapSeconds != null -> stringResource(R.string.lld_of_lld_min_talked_this_month,
        a.secondsUsedPeriod / 60, a.monthlyCapSeconds!! / 60)
    a.secondsBalance > 0 -> stringResource(R.string.lld_min_left, a.secondsBalance / 60)
    else -> stringResource(R.string.none)
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

@Composable
private fun SubtitleRow(
    icon: ImageVector, title: String, subtitle: String?, onClick: (() -> Unit)? = null,
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
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
