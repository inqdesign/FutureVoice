package com.roro.futurevoice.ui

import com.roro.futurevoice.ui.brand.AppSurfaces
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Box
import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChatBubbleOutline
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.SpeechSpeed

/**
 * What a learner can change while a call runs (iOS `CallSettings`). Three are
 * pure screen state; the speed is the one that reaches the voice, applied from
 * the fluent self's next line. Nothing hidden is lost — the book keeps it all.
 */
object CallSettings {
    const val SHOWS_TRANSCRIPT = "futurevoice.call.showsTranscript"
    const val SHOWS_CORRECTIONS = "futurevoice.call.showsCorrections"
    const val SHOWS_GOAL_CHIPS = "futurevoice.call.showsGoalChips"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)

    fun flag(context: Context, key: String): Boolean = prefs(context).getBoolean(key, true)
    fun set(context: Context, key: String, value: Boolean) =
        prefs(context).edit().putBoolean(key, value).apply()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CallSettingsSheet(
    showsTranscript: Boolean,
    showsCorrections: Boolean,
    showsGoalChips: Boolean,
    /** Coach mode as it resolves now (the learner's flip, else the level's). */
    coachMode: Boolean,
    onCoachMode: (Boolean) -> Unit,
    onFlag: (key: String, value: Boolean) -> Unit,
    onSpeedChange: (SpeechSpeed) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    var speed by remember { mutableStateOf(SpeechSpeed.current(context)) }
    // iOS: an inset-grouped Form — rounded cards on the grouped ground, a
    // centred title with Done at the trailing edge.
    ModalBottomSheet(
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),
        onDismissRequest = onDismiss, containerColor = AppSurfaces.ground) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).navigationBarsPadding()
            .verticalScroll(rememberScrollState())) {
            Box(Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.call_settings), style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.align(Alignment.Center))
                TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.CenterEnd)) {
                    Text(stringResource(R.string.done), style = MaterialTheme.typography.titleMedium)
                }
            }

            // Drawn INLINE, one row per rung (iOS 6f416de): the call screen
            // under this sheet recomposes on every mic level tick, and a popup
            // or dropdown closed before it could take a tap. A plain row is a
            // tap, nothing to dismiss — and the rung names are words, longer
            // in every language but English, so they get the full width.
            GroupedSectionHeader(stringResource(R.string.speaking_speed))
            GroupedCard {
                SpeechSpeed.entries.forEachIndexed { i, s ->
                    if (i > 0) GroupedRowDivider(inset = false)
                    SpeedRow(stringResource(s.label), selected = speed == s) {
                        if (speed != s) { speed = s; SpeechSpeed.set(context, s); onSpeedChange(s) }
                    }
                }
            }
            GroupedFooter(stringResource(R.string.applies_from_the_next_thing_your_future_self_says))

            // On by default for A1/A2: it trades a little of the call's pace
            // for being walked toward the words being studied (`CoachMode`).
            GroupedSectionSpacer()
            GroupedCard {
                ToggleRow(Icons.Outlined.Lightbulb, stringResource(R.string.cm_coach_mode), coachMode) {
                    onCoachMode(it)
                }
            }
            GroupedFooter(stringResource(R.string.cm_coach_mode_footer))

            GroupedSectionHeader(stringResource(R.string.screen))
            GroupedCard {
                ToggleRow(Icons.Filled.ChatBubbleOutline, stringResource(R.string.subtitles), showsTranscript) {
                    onFlag(CallSettings.SHOWS_TRANSCRIPT, it)
                }
                GroupedRowDivider()
                // With the transcript off this row is replaced by the reason
                // rather than disabled (iOS): the correction lives inside the
                // learner's own line and goes where it goes.
                if (showsTranscript) {
                    ToggleRow(Icons.Filled.AutoAwesome, stringResource(R.string.corrections), showsCorrections) {
                        onFlag(CallSettings.SHOWS_CORRECTIONS, it)
                    }
                } else {
                    Text(stringResource(R.string.corrections_sit_inside_your_own_lines_so_they_re_hidden_too),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp))
                }
                GroupedRowDivider()
                ToggleRow(Icons.Filled.Checklist, stringResource(R.string.words_to_use), showsGoalChips) {
                    onFlag(CallSettings.SHOWS_GOAL_CHIPS, it)
                }
            }
            GroupedFooter(stringResource(R.string.nothing_you_hide_is_lost_your_talk_s_book_keeps_every_correc_4f2f1b))
            androidx.compose.foundation.layout.Spacer(Modifier.size(24.dp))
        }
    }
}

@Composable
private fun SpeedRow(text: String, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        if (selected) Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary)
    }
}

@Composable
private fun ToggleRow(icon: ImageVector, text: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary)
        Text(text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        com.roro.futurevoice.ui.brand.IosSwitch(checked = checked, onCheckedChange = onChange)
    }
}


