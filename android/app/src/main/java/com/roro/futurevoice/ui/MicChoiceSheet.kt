package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.MicPreference

/**
 * The one-time "which mic?" question, asked the first time a mic surface
 * starts with a headset connected. Both buttons are answers; there is no
 * swipe-away, because the caller is waiting on one.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MicChoiceSheet(onChoose: (String) -> Unit) {
    ModalBottomSheet(
        onDismissRequest = { onChoose(MicPreference.EARPHONE) },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 24.dp)
            .padding(bottom = 32.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(stringResource(R.string.which_mic), style = MaterialTheme.typography.titleLarge)
            Text(stringResource(R.string.the_phone_s_mic_hears_more_detail_but_only_when_the_phone_is_3f6c6c),
                style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick = { onChoose(MicPreference.EARPHONE) }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.Headphones, contentDescription = null)
                Text("  " + stringResource(R.string.earphone_mic))
            }
            OutlinedButton(onClick = { onChoose(MicPreference.PHONE) }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.PhoneAndroid, contentDescription = null)
                Text("  " + stringResource(R.string.phone_mic))
            }
        }
    }
}
