package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.ConsentStore
import com.roro.futurevoice.ui.brand.IosButton as Button

/**
 * Retroactive age check (iOS `AgeCheckSheet`) for a learner who holds a voice
 * but has no age on record on this device — a voice made before the consent
 * step existed, or on another device. They never pass back through the clone
 * flow, so the declaration comes to them.
 *
 * It asks for the AGE and nothing else; the voice consent stays on the clone
 * flow. A sheet, not a gate, and dismissable — it comes back on the next
 * visit to the tabs instead. An undismissable sheet with no "no" would trap
 * anyone it's meant to stop.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgeCheckSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    /** Starts OFF, always. A pre-ticked age box confirms nothing. */
    var declared by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().bottomBarInsets().padding(horizontal = 24.dp).padding(bottom = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            Icon(Icons.Outlined.VerifiedUser, contentDescription = null,
                modifier = Modifier.padding(top = 16.dp).size(40.dp),
                tint = MaterialTheme.colorScheme.primary)
            Text(stringResource(R.string.one_quick_thing), fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
            Text(stringResource(R.string.your_voice_model_counts_as_biometric_data_so_there_are_rules_298305),
                fontSize = 16.sp, lineHeight = 22.sp, textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.widthIn(max = 320.dp))
            Row(Modifier.widthIn(max = 320.dp).fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.i_m_lld_or_older, ConsentStore.MINIMUM_AGE),
                    style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                com.roro.futurevoice.ui.brand.IosSwitch(checked = declared, onCheckedChange = { declared = it })
            }
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = {
                    ConsentStore.confirmAge(context)
                    onDismiss()
                }, enabled = declared, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.continue_))
                }
                val uri = LocalUriHandler.current
                Text(stringResource(R.string.privacy_policy), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.clickable { uri.openUri(ConsentStore.privacyUrl()) }.padding(4.dp))
            }
        }
    }
}
