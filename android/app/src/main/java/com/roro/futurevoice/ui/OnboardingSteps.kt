package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudQueue
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.PhonelinkLock
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.IosButton as Button

/**
 * The onboarding beats' "seen" flags.
 *
 * The daily-call and weekly-rhythm screens that used to follow the clone were
 * replaced by the routine builder over the Talk tab ([RoutineOnboardingOverlay],
 * iOS 2026-10-18). Their keys stay: [DAILY_CALL] is the builder's gate, so an
 * install that saw the old screens never sees the builder, and both are set
 * when it finishes so nothing that reads them asks again.
 */
object OnboardingFlags {
    private const val PREFS = "futurevoice"
    const val DAILY_CALL = "futurevoice.dailyCall.onboarded"
    /** The old "once a week" step (test day + time). */
    const val WEEKLY_RHYTHM = "futurevoice.weeklyRhythm.onboarded"
    /** "Your practice stays on your phone", new installs only (iOS
     *  `LocalDataOnboardingView`, same key). */
    const val LOCAL_DATA = "futurevoice.localData.onboarded"

    fun seen(c: Context, key: String) =
        c.getSharedPreferences(PREFS, 0).getBoolean(key, false)

    fun markSeen(c: Context, key: String) {
        c.getSharedPreferences(PREFS, 0).edit().putBoolean(key, true).apply()
    }
}

/**
 * iOS `LocalDataOnboardingView`: said once, right after the voice exists —
 * every call, recording and thing studied is kept on THIS phone and nowhere
 * else. Safety first (nothing on our servers, so speak freely), the cost
 * second (it goes with the app). Where iOS points at the learner's iCloud,
 * Android points at their Google Drive (Settings → Devices), which
 * [BackupOfferSheet] also offers once after the third talk.
 */
@Composable
fun LocalDataOnboardingScreen(context: Context, onDone: () -> Unit) {
    BottomActionLayout(
        spacing = 32.dp,
        content = {
            Column(horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Icon(Icons.Outlined.PhonelinkLock, contentDescription = null,
                    modifier = Modifier.size(52.dp), tint = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.your_practice_stays_on_your_phone),
                    style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center)
                Text(stringResource(R.string.calls_recordings_and_every_word_you_study_are_saved_right_he_35bbe7),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            }
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                LocalDataRow(Icons.Outlined.Shield, R.string.not_on_our_servers,
                    R.string.we_don_t_keep_your_talks_so_speak_freely)
                LocalDataRow(Icons.Outlined.Delete, R.string.it_goes_with_the_app,
                    R.string.delete_the_app_or_change_phones_and_it_s_gone_too)
                LocalDataRow(Icons.Outlined.CloudQueue, R.string.want_a_copy_use_your_own_google_drive,
                    R.string.turn_it_on_any_time_in_settings_devices)
            }
        },
        actions = {
            Button(onClick = {
                com.roro.futurevoice.core.Analytics.capture("local_data_onboarding")
                OnboardingFlags.markSeen(context, OnboardingFlags.LOCAL_DATA)
                onDone()
            }, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.continue_))
            }
        },
    )
}

@Composable
private fun LocalDataRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: Int, detail: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(28.dp),
            tint = MaterialTheme.colorScheme.primary)
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(stringResource(title), style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold)
            Text(stringResource(detail), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
