package com.roro.futurevoice.ui

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import com.roro.futurevoice.R
import com.roro.futurevoice.data.GoalStore

/**
 * What makes a day count — iOS `StudyGoalsSheet`. Four numbers the learner
 * sets themselves, and the one thing that decides whether a dropped card can
 * ever come back: whether this app is allowed to ring at all.
 *
 * Zero leaves a kind of work OUT of the day rather than demanding it, which
 * is why the steppers start at zero and the footer says so.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudyGoalsSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    var goals by remember { mutableStateOf(GoalStore.load(context)) }
    // Read once per open: the learner may have just come back from settings.
    var notificationsOn by remember {
        mutableStateOf(NotificationManagerCompat.from(context).areNotificationsEnabled())
    }

    fun update(next: GoalStore.Goals) {
        goals = next
        GoalStore.save(context, next)
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(stringResource(R.string.daily_goals), style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(bottom = 8.dp))
            GroupedCard {
                GoalRow(Icons.Filled.ViewAgenda, stringResource(R.string.sentences), goals.sentences, 50) {
                    update(goals.copy(sentences = it))
                }
                GroupedRowDivider(inset = false)
                GoalRow(Icons.Filled.MenuBook, stringResource(R.string.words_d26d55), goals.words, 50) {
                    update(goals.copy(words = it))
                }
                GroupedRowDivider(inset = false)
                GoalRow(Icons.Filled.FormatQuote, stringResource(R.string.expressions), goals.expressions, 30) {
                    update(goals.copy(expressions = it))
                }
                GroupedRowDivider(inset = false)
                GoalRow(Icons.Filled.GraphicEq, stringResource(R.string.shadowing), goals.shadows, 30) {
                    update(goals.copy(shadows = it))
                }
            }
            GroupedFooter(stringResource(R.string.a_day_counts_once_every_goal_here_is_met_and_only_finished_w_970192))

            // Whether the schedule can actually ring. Without this the learner
            // drops a card on "10 min", nothing comes back, and the feature
            // looks broken instead of unpermitted.
            GroupedSectionSpacer()
            GroupedCard {
                if (notificationsOn) {
                    Row(Modifier.fillMaxWidth().padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Filled.NotificationsActive, contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                        Text(stringResource(R.string.reminders_on), Modifier.weight(1f))
                    }
                } else {
                    Row(Modifier.fillMaxWidth().clickable {
                        context.startActivity(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        notificationsOn = NotificationManagerCompat.from(context).areNotificationsEnabled()
                    }.padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Filled.Notifications, contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                        Text(stringResource(R.string.turn_on_reminders), Modifier.weight(1f),
                            color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
            GroupedFooter(stringResource(R.string.when_you_send_a_card_to_10_minutes_tomorrow_or_3_days_this_i_dc4513))
        }
    }
}

/** One goal: what it counts, how many, and two ways to change it. */
@Composable
private fun GoalRow(icon: ImageVector, label: String, value: Int, max: Int, onChange: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(label, Modifier.weight(1f).padding(start = 12.dp),
            style = MaterialTheme.typography.bodyLarge)
        Text("$value", style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
        IconButton(onClick = { onChange((value - 1).coerceAtLeast(0)) }, enabled = value > 0) {
            Icon(Icons.Filled.Remove, contentDescription = null)
        }
        IconButton(onClick = { onChange((value + 1).coerceAtMost(max)) }, enabled = value < max) {
            Icon(Icons.Filled.Add, contentDescription = null)
        }
    }
}
