package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AccountEraser
import com.roro.futurevoice.data.ConsentStore
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

/**
 * Where a consent given during onboarding can be READ BACK and TAKEN AWAY.
 *
 * GDPR Art. 7(3) requires withdrawal to be as easy as giving, and the only
 * honest withdrawal for a voice model is deleting it — so that button does
 * exactly that, upstream at ElevenLabs included.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrivacyScreen(voiceId: String?, onVoiceDeleted: () -> Unit, onBack: () -> Unit) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val uri = LocalUriHandler.current
    var confirming by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    val ageAt = remember { ConsentStore.ageConfirmedAt(context) }
    var voiceAt by remember { mutableStateOf(ConsentStore.voiceConsentAt(context)) }
    val df = remember { DateFormat.getDateInstance(DateFormat.MEDIUM) }

    Scaffold(
        topBar = {
            TopAppBar(
                colors = com.roro.futurevoice.ui.brand.AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.privacy)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        }
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize()
                .background(com.roro.futurevoice.ui.brand.AppSurfaces.ground)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            GroupedSectionHeader(stringResource(R.string.consent))
            voiceAt?.let {
                SettingsRow(
                    icon = Icons.Filled.GraphicEq,
                    title = stringResource(R.string.voice_model_consent),
                    subtitle = stringResource(R.string.given_lld, df.format(Date(it))),
                )
            }
            ageAt?.let {
                SettingsRow(
                    icon = Icons.Filled.VerifiedUser,
                    title = stringResource(R.string.age_confirmed),
                    subtitle = stringResource(R.string.at_least_lld, ConsentStore.MINIMUM_AGE),
                )
            }
            GroupedFooter(stringResource(R.string.your_voice_model_is_biometric_data))

            if (voiceAt != null || voiceId != null) {
                HorizontalDivider(Modifier.padding(vertical = 8.dp))
                if (!confirming) {
                    OutlinedButton(
                        onClick = { confirming = true },
                        enabled = !working,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        if (working) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        } else {
                            Text(stringResource(R.string.withdraw_consent_delete_my_voice),
                                color = MaterialTheme.colorScheme.error)
                        }
                    }
                } else {
                    // The confirmation states the two things that make this
                    // irreversible — it is gone upstream too, and the app
                    // cannot hold a call without a voice.
                    Column(Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(stringResource(R.string.delete_your_voice),
                            style = MaterialTheme.typography.titleSmall)
                        Text(stringResource(R.string.your_voice_model_is_deleted_here_and_at_elevenlabs),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        androidx.compose.foundation.layout.Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            TextButton(onClick = { confirming = false }) {
                                Text(stringResource(R.string.cancel))
                            }
                            TextButton(onClick = {
                                confirming = false
                                working = true
                                scope.launch {
                                    voiceId?.let { AccountEraser.deleteVoice(it) }
                                    ConsentStore.withdrawVoiceConsent(context)
                                    voiceAt = null
                                    working = false
                                    onVoiceDeleted()
                                }
                            }) {
                                Text(stringResource(R.string.delete),
                                    color = MaterialTheme.colorScheme.error)
                            }
                        }
                    }
                }
                GroupedFooter(stringResource(R.string.this_deletes_your_voice_model_here_and_at_elevenlabs))
            }

            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            SettingsRow(
                icon = Icons.Filled.Description,
                title = stringResource(R.string.privacy_policy),
                subtitle = "nawana.app/privacy",
                onClick = { uri.openUri(ConsentStore.privacyUrl()) },
            )
            SettingsRow(
                icon = Icons.Filled.Email,
                title = stringResource(R.string.contact_us),
                subtitle = ConsentStore.CONTACT_EMAIL,
                onClick = { uri.openUri("mailto:${ConsentStore.CONTACT_EMAIL}") },
            )
            GroupedFooter(stringResource(R.string.write_to_us_to_see_or_correct_what_we_hold))
            Column(Modifier.padding(bottom = 32.dp)) {}
        }
    }
}


