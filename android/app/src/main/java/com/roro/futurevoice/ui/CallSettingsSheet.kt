package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChatBubbleOutline
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Speed
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
    onFlag: (key: String, value: Boolean) -> Unit,
    onSpeedChange: (SpeechSpeed) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    var speed by remember { mutableStateOf(SpeechSpeed.current(context)) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.call_settings), style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f))
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.done), style = MaterialTheme.typography.titleMedium)
                }
            }

            SectionHeader(stringResource(R.string.voice))
            SettingLabel(Icons.Filled.Speed, stringResource(R.string.speaking_speed))
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                val all = SpeechSpeed.entries
                all.forEachIndexed { i, s ->
                    SegmentedButton(
                        selected = speed == s,
                        onClick = {
                            if (speed == s) return@SegmentedButton
                            speed = s
                            SpeechSpeed.set(context, s)
                            onSpeedChange(s)
                        },
                        shape = SegmentedButtonDefaults.itemShape(i, all.size),
                    ) { Text(stringResource(s.label), maxLines = 1) }
                }
            }
            Footer(stringResource(R.string.applies_from_the_next_thing_your_future_self_says))

            SectionHeader(stringResource(R.string.screen))
            ToggleRow(Icons.Filled.ChatBubbleOutline, stringResource(R.string.subtitles), showsTranscript) {
                onFlag(CallSettings.SHOWS_TRANSCRIPT, it)
            }
            if (showsTranscript) {
                ToggleRow(Icons.Filled.AutoAwesome, stringResource(R.string.corrections), showsCorrections) {
                    onFlag(CallSettings.SHOWS_CORRECTIONS, it)
                }
            } else {
                Footer(stringResource(R.string.corrections_sit_inside_your_own_lines_so_they_re_hidden_too))
            }
            ToggleRow(Icons.Filled.Checklist, stringResource(R.string.words_to_use), showsGoalChips) {
                onFlag(CallSettings.SHOWS_GOAL_CHIPS, it)
            }
            Footer(stringResource(R.string.nothing_you_hide_is_lost_your_talk_s_book_keeps_every_correc_4f2f1b))
            androidx.compose.foundation.layout.Spacer(Modifier.size(16.dp))
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(text.uppercase(), style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 14.dp, bottom = 2.dp))
}

@Composable
private fun SettingLabel(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.padding(vertical = 6.dp)) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary)
        Text(text, style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
private fun ToggleRow(icon: ImageVector, text: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary)
        Text(text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun Footer(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
}
