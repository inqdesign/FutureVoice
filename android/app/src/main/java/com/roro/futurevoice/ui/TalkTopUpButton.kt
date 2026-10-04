package com.roro.futurevoice.ui

import android.app.Activity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.BillingService
import com.roro.futurevoice.ui.brand.IosButton
import com.roro.futurevoice.ui.brand.IosTonalButton

/**
 * The live pack, or the capture build's seeded one. Null until the catalog
 * row AND Play's price have both answered — a button with no price is a
 * promise nobody priced.
 */
@Composable
fun rememberTalkPack(): BillingService.Pack? {
    val context = LocalContext.current
    val billing = remember { BillingService.shared(context) }
    val live by billing.pack.collectAsStateWithLifecycle()
    return com.roro.futurevoice.capture.flags.MeCaptureFlags.previewPack ?: live
}

/**
 * "Add 50 minutes · ₩5,900" — the one button that sells a talk-minute pack
 * (iOS `TalkTopUpButton`, master plan 4.0). Drawn where a spent pool is met
 * ([AllowanceSpentSheet]) and on Usage, so the number and the price come from
 * one place: the pack from `talk_topups`, the price from Play.
 *
 * [prominent] picks the style: the sheet leads with it, Usage lists it.
 * [onAvailability] reports whether anything was drawn — a host that ORDERS its
 * buttons has to know, or it reserves the lead slot for a button that isn't
 * there. [onPurchased] runs once the minutes are on the account.
 */
@Composable
fun TalkTopUpButton(
    modifier: Modifier = Modifier,
    prominent: Boolean = true,
    onAvailability: (Boolean) -> Unit = {},
    onPurchased: () -> Unit = {},
) {
    val context = LocalContext.current
    val billing = remember { BillingService.shared(context) }
    val pack = rememberTalkPack()
    val state by billing.packState.collectAsStateWithLifecycle()
    val price = pack?.formattedPrice

    LaunchedEffect(price != null) { onAvailability(price != null) }
    LaunchedEffect(state) {
        if (state is BillingService.PackState.Purchased) onPurchased()
    }
    // The flow is one per app; a finished purchase must not greet the next
    // screen that draws this button as already done.
    DisposableEffect(Unit) {
        onDispose {
            if (billing.packState.value is BillingService.PackState.Purchased) billing.resetPackState()
        }
    }
    if (pack == null || price == null) return

    val busy = state == BillingService.PackState.Purchasing
    val done = state is BillingService.PackState.Purchased
    val onClick = { (context as? Activity)?.let { billing.buyPack(it) }; Unit }
    val label: @Composable () -> Unit = {
        when {
            busy -> CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            done -> Row(horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(stringResource(R.string.lld_minutes_added, pack.minutes))
            }
            else -> Text(stringResource(R.string.add_lld_minutes, pack.minutes, price))
        }
    }
    if (prominent) {
        IosButton(onClick = onClick, enabled = !busy && !done,
            modifier = modifier.fillMaxWidth()) { label() }
    } else {
        IosTonalButton(onClick = onClick, enabled = !busy && !done,
            modifier = modifier.fillMaxWidth()) { label() }
    }

    val failed = state as? BillingService.PackState.Failed
    if (failed != null) {
        AlertDialog(
            onDismissRequest = { billing.resetPackState() },
            title = { Text(stringResource(R.string.purchase_failed)) },
            text = { Text(stringResource(failed.message)) },
            confirmButton = {
                TextButton(onClick = { billing.resetPackState() }) { Text(stringResource(R.string.ok)) }
            },
        )
    }
}
