package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.PriceConsent
import com.roro.futurevoice.ui.brand.IosButton as Button
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** What the consent is, before Play asks for it (iOS `PriceConsentSheet`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PriceConsentSheet(pending: PriceConsent.Pending, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    ModalBottomSheet(
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        onDismissRequest = onDismiss,
    ) {
        Column(
            Modifier.sheetBody().padding(horizontal = 24.dp).padding(bottom = 32.dp, top = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Outlined.Verified, contentDescription = null,
                tint = MaterialTheme.colorScheme.primary)
            Text(stringResource(R.string.price_consent_title),
                style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            Text(stringResource(if (pending.isTrial) R.string.price_consent_body_trial
                                else R.string.price_consent_body_plan),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            pending.dueOn?.let { day ->
                Text(stringResource(if (pending.isTrial) R.string.price_consent_plan_starts
                                    else R.string.price_consent_renews) + " · " +
                    day.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale)),
                    style = MaterialTheme.typography.bodyMedium)
            }
            Text(stringResource(R.string.price_consent_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick = { PriceConsent.confirm(context); onDismiss() },
                modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.price_consent_confirm_play))
            }
            TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.later))
            }
        }
    }
}
