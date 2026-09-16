package com.roro.futurevoice.ui

import android.content.Context
import com.roro.futurevoice.data.PersonaStore
import com.roro.futurevoice.data.LearnerAddress
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.material.icons.filled.PhoneCallback
import android.os.Build
import android.content.pm.PackageManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DailyCallStore

/**
 * The two onboarding beats that come after the voice exists.
 *
 * Both set their "seen" flag on EVERY exit — taken and skipped alike — or the
 * screen becomes a wall the learner cannot get past. Existing installs see
 * each once; that is how they find out the feature is there.
 */
object OnboardingFlags {
    private const val PREFS = "futurevoice"
    const val DAILY_CALL = "futurevoice.dailyCall.onboarded"
    const val PAYWALL = "futurevoice.onboardingPaywall.seen"

    fun seen(c: Context, key: String) =
        c.getSharedPreferences(PREFS, 0).getBoolean(key, false)

    fun markSeen(c: Context, key: String) {
        c.getSharedPreferences(PREFS, 0).edit().putBoolean(key, true).apply()
    }
}

/**
 * The daily call, introduced.
 *
 * Placed AFTER the clone deliberately: the call is the clone's first real
 * job, so here it reads as a promise rather than a permissions request.
 *
 * Nobody opens a language app because a streak asks them to; they answer a
 * phone that rings. That is the whole pitch, and it is made in one line.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DailyCallOnboardingScreen(context: Context, onDone: () -> Unit) {
    val time = rememberTimePickerState(initialHour = 8, initialMinute = 0, is24Hour = true)
    // By NAME when there is one: everything on this screen is the future self
    // speaking, and being called by name is what separates that from an app
    // announcing a feature (`DailyCallOnboardingView`).
    var name by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        name = LearnerAddress.vocative(context, PersonaStore.shared(context).load()?.displayName)
    }
    /** They said yes and the system said no. The screen has to say so, or they
     *  leave believing a call is coming that never will. */
    var denied by remember { mutableStateOf(false) }
    fun finish(enable: Boolean) {
        com.roro.futurevoice.core.Analytics.capture("daily_call_onboarding",
            mapOf("enabled" to enable, "hour" to time.hour))
        DailyCallStore.set(context, enable, time.hour, time.minute)
        OnboardingFlags.markSeen(context, OnboardingFlags.DAILY_CALL)
        onDone()
    }
    val permission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> if (granted) finish(enable = true) else denied = true }

    Column(
        // A full-screen step of its own: the app draws edge to edge, so this
        // is the only thing keeping the buttons off the gesture pill.
        Modifier.fillMaxSize().systemBarsPadding().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        Icon(Icons.Filled.PhoneCallback, contentDescription = null,
            modifier = Modifier.size(52.dp), tint = MaterialTheme.colorScheme.primary)
        // The title is the FUTURE SELF talking, in the first person — not a
        // feature name. "A call every day" described the mechanism and sold
        // nothing.
        Text(name?.let { stringResource(R.string.i_ll_help_you_keep_it_up_d1116e, it) }
                ?: stringResource(R.string.i_ll_help_you_keep_it_up_fe0fae),
            style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center)
        Text(stringResource(R.string.speaking_once_is_easy_every_day_is_the_hard_part_so_i_ll_cal_ce0232),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        Text(stringResource(R.string.it_rings_even_on_silent_and_i_remember_how_the_last_call_wen_b28e80),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.outline, textAlign = TextAlign.Center)
        // The dial, not the compact field: TimeInput takes focus and raises
        // the keyboard over the very button this screen exists to offer.
        TimePicker(state = time)
        if (denied) {
            Text(stringResource(R.string.android_is_blocking_the_call),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
        }
        Spacer(Modifier.weight(1f))
        Button(onClick = {
            denied = false
            if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(
                    android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                permission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
            } else finish(enable = true)
        }, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.call_me_every_day))
        }
        // Skipping still sets the flag: a screen you cannot get past is a
        // wall, and this one is an offer.
        TextButton(onClick = { finish(enable = false) }) {
            Text(stringResource(R.string.not_now))
        }
    }
}
