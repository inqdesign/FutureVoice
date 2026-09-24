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
import androidx.compose.material3.Button
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
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().bottomBarInsets()
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
 * When the welcome is due. Once per install, only for an account that has
 * free minutes and has never talked — so an existing learner with a few
 * seconds left over is never congratulated on them after an update.
 */
object FreeTalkWelcome {
    private const val SHOWN_KEY = "futurevoice.freeTalkWelcome.shown"

    /** Whole minutes to announce, or null when the sheet shouldn't show. */
    suspend fun minutesToAnnounce(context: Context): Int? {
        val prefs = context.getSharedPreferences("futurevoice", 0)
        if (prefs.getBoolean(SHOWN_KEY, false)) return null
        val account = runCatching { AccountStatus.load(AuthRepository()) }.getOrNull() ?: return null
        if (account.isEntitled || account.unlimited || account.secondsBalance < 60) return null
        val talked = com.roro.futurevoice.data.LanguageScope.enrolled(context)
            .any { SessionStore.shared(context).load(it).isNotEmpty() }
        if (talked) {
            // Already talked: they have met the minutes by using them.
            markShown(context)
            return null
        }
        return account.secondsBalance / 60
    }

    fun markShown(context: Context) {
        context.getSharedPreferences("futurevoice", 0).edit()
            .putBoolean(SHOWN_KEY, true).apply()
    }
}
