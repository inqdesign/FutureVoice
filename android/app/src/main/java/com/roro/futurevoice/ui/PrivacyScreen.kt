package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.GraphicEq
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material.icons.outlined.VoiceOverOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
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
 * Where a consent given during onboarding can be READ BACK and TAKEN AWAY
 * (iOS `MeTab.privacyPage`): Consent, the withdrawal, then policy + contact,
 * each its own grouped card.
 *
 * GDPR Art. 7(3) requires withdrawal to be as easy as giving, and the only
 * honest withdrawal for a voice model is deleting it — so that button does
 * exactly that, upstream at ElevenLabs included.
 */
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

    MeSubpage(stringResource(R.string.privacy), onBack) {
        GroupedSectionHeader(stringResource(R.string.consent))
        if (voiceAt != null || ageAt != null) {
            GroupedCard {
                voiceAt?.let {
                    MeRow(Icons.Outlined.GraphicEq, stringResource(R.string.voice_model_consent),
                        stringResource(R.string.given_lld, df.format(Date(it))),
                        kind = MeRowKind.PLAIN)
                }
                if (voiceAt != null && ageAt != null) GroupedRowDivider()
                ageAt?.let {
                    MeRow(Icons.Outlined.VerifiedUser, stringResource(R.string.age_confirmed),
                        stringResource(R.string.at_least_lld, ConsentStore.MINIMUM_AGE),
                        kind = MeRowKind.PLAIN)
                }
            }
        }
        GroupedFooter(stringResource(R.string.your_voice_model_is_biometric_data))

        if (voiceAt != null || voiceId != null) {
            GroupedSectionSpacer()
            GroupedCard {
                MeRow(Icons.Outlined.VoiceOverOff,
                    stringResource(R.string.withdraw_consent_delete_my_voice),
                    kind = MeRowKind.DESTRUCTIVE, enabled = !working,
                    trailing = if (working) ({
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    }) else null,
                    onClick = { confirming = true })
            }
            GroupedFooter(stringResource(R.string.this_deletes_your_voice_model_here_and_at_elevenlabs))
        }

        GroupedSectionSpacer()
        GroupedCard {
            MeRow(Icons.Outlined.Description, stringResource(R.string.privacy_policy),
                "nawana.app/privacy", kind = MeRowKind.ACTION,
                onClick = { uri.openUri(ConsentStore.privacyUrl()) })
            GroupedRowDivider()
            MeRow(Icons.Outlined.Email, stringResource(R.string.contact_us),
                ConsentStore.CONTACT_EMAIL, kind = MeRowKind.ACTION,
                onClick = { uri.openUri("mailto:${ConsentStore.CONTACT_EMAIL}") })
        }
        GroupedFooter(stringResource(R.string.write_to_us_to_see_or_correct_what_we_hold))
    }

    // The confirmation states the two things that make this irreversible —
    // it is gone upstream too, and the app cannot hold a call without a voice.
    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(stringResource(R.string.delete_your_voice)) },
            text = { Text(stringResource(R.string.your_voice_model_is_deleted_here_and_at_elevenlabs)) },
            confirmButton = {
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
                    Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirming = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}
