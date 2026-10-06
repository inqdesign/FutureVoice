package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CardGiftcard
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.SessionStore

/**
 * "Here is time to talk with your fluent self." Shown once, the first time a
 * new account reaches the Talk home with free talk time on it.
 *
 * It exists because the grant is otherwise invisible: onboarding's paywall
 * steps aside for any account with a balance, so without this the learner is
 * never told the minutes exist, how many, or what happens after them.
 *
 * The minutes are READ off the account, never written here — the grant is a
 * server constant, and a sheet quoting its own number would drift the day
 * that constant moves.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FreeTalkWelcomeSheet(minutes: Int, onStart: () -> Unit, onDismiss: () -> Unit) {
    var revealed by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { revealed = true }
    val reveal by animateFloatAsState(if (revealed) 1f else 0f, tween(500), label = "reveal")
    ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),onDismissRequest = onDismiss) {
        Column(
            Modifier.sheetBody()
                .padding(horizontal = 24.dp).padding(top = 12.dp, bottom = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Filled.CardGiftcard, contentDescription = null,
                modifier = Modifier.size(44.dp).alpha(reveal),
                tint = MaterialTheme.colorScheme.primary)
            Text(stringResource(R.string.congratulations),
                style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            Text(stringResource(R.string.lld_min_b61908, minutes),
                style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold,
                modifier = Modifier.alpha(reveal).scale(0.85f + 0.15f * reveal))
            Text(
                stringResource(R.string.you_can_talk_with_your_fluent_self_for_lld_minutes_once_they_357104, minutes),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center)
            Spacer(Modifier.size(8.dp))
            Button(onClick = onStart, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.start_talking))
            }
        }
    }
}

/**
 * When the welcome is due. It remembers the LAST BALANCE SEEN rather than
 * "was it shown" (iOS `f04015b`): a free account's balance only rises when
 * minutes are granted, so a rise of a minute or more announces the grant —
 * a once-per-install flag kept a later top-up silent forever. The first pass
 * on an install only records the baseline if they have already talked or
 * been welcomed; it never congratulates leftover seconds after an update.
 */
object FreeTalkWelcome {
    private const val SHOWN_KEY = "futurevoice.freeTalkWelcome.shown"
    private const val SEEN_KEY = "futurevoice.freeTalkWelcome.seenSeconds"
    private const val RISE_SECONDS = 60
    private const val DEBUG_MINUTES_KEY = "futurevoice.debug.welcomeMinutes"

    /** Whole minutes to announce, or null when the sheet shouldn't show. */
    suspend fun minutesToAnnounce(context: Context): Int? {
        val prefs = context.getSharedPreferences("futurevoice", 0)
        // Debug only: a stand-in grant, so the sheet's ORDER can be checked
        // on an account that has nothing to announce. Used once.
        if (com.roro.futurevoice.BuildConfig.DEBUG && prefs.contains(DEBUG_MINUTES_KEY)) {
            val m = prefs.getInt(DEBUG_MINUTES_KEY, 0)
            prefs.edit().remove(DEBUG_MINUTES_KEY).apply()
            markShown(context)
            return m
        }
        val account = runCatching { AccountStatus.load(AuthRepository()) }.getOrNull() ?: return null
        if (account.isEntitled || account.unlimited) return null
        val balance = account.secondsBalance
        val seen = if (prefs.contains(SEEN_KEY)) prefs.getInt(SEEN_KEY, 0) else null
        // Every pass records what it saw — the baseline must exist before a
        // grant can beat it.
        prefs.edit().putInt(SEEN_KEY, balance).apply()
        if (balance < 60) return null
        if (seen == null) {
            val talked = com.roro.futurevoice.data.LanguageScope.enrolled(context)
                .any { SessionStore.shared(context).load(it).isNotEmpty() }
            if (prefs.getBoolean(SHOWN_KEY, false) || talked) { markShown(context); return null }
            markShown(context)
            return balance / 60
        }
        if (balance < seen + RISE_SECONDS) return null
        markShown(context)
        return balance / 60
    }

    /** Whether this install has been congratulated before — the caller logs
     *  a first welcome and a top-up as one event with different kinds. */
    fun hasBeenShown(context: Context): Boolean =
        context.getSharedPreferences("futurevoice", 0).getBoolean(SHOWN_KEY, false)

    fun markShown(context: Context) {
        context.getSharedPreferences("futurevoice", 0).edit()
            .putBoolean(SHOWN_KEY, true).apply()
    }
}
