package com.roro.futurevoice.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AccountStatus
import com.roro.futurevoice.ui.speech.rememberGateAccount
import com.roro.futurevoice.ui.speech.voiceoverPriceLine

/**
 * What the next Watch scene costs, said where the button that starts one is
 * (iOS `SceneCostNote`, 2026-10-19). Since that day a scene costs five
 * minutes of talk time for anyone who subscribes from then on, read before
 * the tap the way the Speech voiceover's price is.
 *
 * Draws nothing until the account is known, and nothing for the admin account.
 */
@Composable
fun SceneCostNote(modifier: Modifier = Modifier) {
    val account = rememberGateAccount()
    val text = sceneCostText(account) ?: return
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Outlined.PlayCircle, contentDescription = null, modifier = Modifier.size(14.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(text, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun sceneCostText(account: AccountStatus?): String? {
    if (account == null || account.unlimited) return null
    if (!account.isEntitled) {
        // A spent sample answers with the plans at the tap; nothing to say.
        val cap = account.freeScenesCap ?: return null
        if (account.freeScenesUsed >= cap) return null
        return stringResource(R.string.your_free_scene_it_takes_no_talk_time)
    }
    if (account.scenesCostTalk) {
        // Short of a whole scene: say what it needs before the tap, which
        // answers with the spent-pool sheet.
        if (account.sceneTalkShort) {
            return listOfNotNull(
                stringResource(R.string.a_scene_needs_lld_min_of_talk_time, account.sceneTalkMinutes),
                com.roro.futurevoice.data.ScriptVoiceover.remainingMinutes(account)
                    ?.let { stringResource(R.string.lld_min_of_talk_time_left, it) },
            ).joinToString(" · ")
        }
        return voiceoverPriceLine(account.sceneTalkMinutes, account)
    }
    val cap = account.monthlyScenesCap ?: return null
    return stringResource(R.string.lld_of_lld_scenes_left,
        maxOf(0, cap - account.scenesUsedPeriod), cap)
}
