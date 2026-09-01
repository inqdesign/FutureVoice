package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
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
    fun finish(enable: Boolean) {
        if (enable) DailyCallStore.set(context, true, time.hour, time.minute)
        OnboardingFlags.markSeen(context, OnboardingFlags.DAILY_CALL)
        onDone()
    }
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        Icon(Icons.Filled.Call, contentDescription = null, modifier = Modifier.size(40.dp),
            tint = MaterialTheme.colorScheme.primary)
        Text(stringResource(R.string.your_future_self_can_call_you),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold)
        Text(stringResource(R.string.pick_a_time_answer_and_youre_already_talking),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        TimePicker(state = time)
        Spacer(Modifier.weight(1f))
        Button(onClick = { finish(enable = true) }, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.call_me))
        }
        // Skipping still sets the flag: a screen you cannot get past is a
        // wall, and this one is an offer.
        TextButton(onClick = { finish(enable = false) }) {
            Text(stringResource(R.string.not_now))
        }
    }
}
