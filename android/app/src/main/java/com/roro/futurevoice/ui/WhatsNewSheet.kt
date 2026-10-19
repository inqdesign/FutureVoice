package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.MicExternalOn
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import com.roro.futurevoice.ui.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosButton
import com.roro.futurevoice.ui.brand.IosOutlinedButton

/**
 * "What's new" (iOS `WhatsNew`) — shown once, on the first open after an
 * update, to someone who used the app before it. A fresh install has just
 * been through onboarding, where all of it was already new.
 */
object WhatsNew {
    /** Bump with each release that has something to say; the card shows
     *  once per value. iOS's value, so one release says one thing. */
    const val RELEASE = "1.1.8"
    private const val SHOWN_KEY = "futurevoice.whatsNew.shown"

    suspend fun isDue(context: Context, setupComplete: Boolean): Boolean {
        if (!setupComplete) return false
        val prefs = context.getSharedPreferences("futurevoice", 0)
        if (prefs.getString(SHOWN_KEY, null) == RELEASE) return false
        // Someone who has talked before is someone this is news to.
        return com.roro.futurevoice.data.WeekRecapBuilder.sessionsAcrossLanguages(context).isNotEmpty()
    }

    fun markShown(context: Context) {
        context.getSharedPreferences("futurevoice", 0).edit().putString(SHOWN_KEY, RELEASE).apply()
    }
}

/**
 * The card itself (iOS `WhatsNewSheet`). The goal row carries a button
 * because an existing learner never sees the onboarding step that asks why
 * they're learning: this card is the only place they would find out the
 * Talk tab can follow it. [onChooseGoal] opens the talk settings there.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WhatsNewSheet(onChooseGoal: () -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    LaunchedEffect(Unit) {
        WhatsNew.markShown(context)
        com.roro.futurevoice.core.Analytics.capture("whats_new_shown", mapOf("release" to WhatsNew.RELEASE))
    }
    ModalBottomSheet(
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        onDismissRequest = onDismiss,
        containerColor = AppSurfaces.ground,
    ) {
        Column(Modifier.sheetBody().padding(horizontal = 16.dp).padding(bottom = 8.dp)) {
            Text(stringResource(R.string.what_s_new),
                style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(bottom = 20.dp))
            GroupedCard {
                Item(Icons.Filled.MicExternalOn, stringResource(R.string.speech_challenges),
                    stringResource(R.string.in_the_speech_tab_everyone_reads_the_same_script_read_it_wit_932336))
                GroupedRowDivider()
                Item(Icons.Filled.Groups, stringResource(R.string.a_new_watch),
                    stringResource(R.string.your_people_now_sit_around_you_on_a_map_bring_someone_to_the_e12a8b))
                GroupedRowDivider()
                Item(Icons.Filled.TrackChanges, stringResource(R.string.topics_for_why_you_re_learning),
                    stringResource(R.string.tell_us_what_you_re_learning_for_like_an_exam_work_or_travel_13326b)) {
                    IosOutlinedButton(onClick = onChooseGoal, modifier = Modifier.padding(start = 44.dp, top = 10.dp)) {
                        Text(stringResource(R.string.choose_my_goal), fontWeight = FontWeight.SemiBold)
                    }
                }
                GroupedRowDivider()
                Item(Icons.Filled.BarChart, stringResource(R.string.your_effort),
                    stringResource(R.string.in_the_progress_tab_see_what_you_practised_and_how_much_over_25b25f))
            }
            IosButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth().padding(top = 24.dp, start = 4.dp, end = 4.dp)) {
                Text(stringResource(R.string.continue_), fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun Item(icon: ImageVector, title: String, body: String, extra: @Composable () -> Unit = {}) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.width(30.dp).size(26.dp))
            Column(Modifier.padding(start = 14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(body, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        extra()
    }
}
