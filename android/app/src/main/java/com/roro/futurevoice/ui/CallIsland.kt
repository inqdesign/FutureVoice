package com.roro.futurevoice.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel

/** How the fluent self guides the call (iOS `CallGuidance`). */
enum class CallGuidance { FREE, COACH, TUTOR }

/**
 * The tutor inside a call (iOS `CallIsland`, d29542ee, founder 2026-11-11):
 * ONE view in both states. Open when the call starts, it folds into a pill in
 * the bar's title slot once the learner speaks, and a tap on the pill opens it
 * again. It lies OVER the bar and the transcript and never pushes them; the
 * title and the call clock stay where they are in both states.
 */
@Composable
fun CallIsland(
    title: String,
    level: CefrLevel,
    minutesLeft: Int?,
    /** The call's own clock, mm:ss; null hides it. */
    clock: String?,
    /** Null hides the row: a scene or a person's call keeps the way it was launched. */
    guidance: CallGuidance?,
    onGuidance: (CallGuidance) -> Unit,
    /** Null hides "Change": the topic of a scene or a person's call is theirs. */
    onChangeTopic: (() -> Unit)?,
    onSettings: () -> Unit,
    expanded: Boolean,
    onExpanded: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    var showingLevel by remember { mutableStateOf(false) }
    if (showingLevel) LevelInfoSheet(level) { showingLevel = false }
    val dark = appIsDark()
    val shape = RoundedCornerShape(if (expanded) 24.dp else CALL_ISLAND_PILL_HEIGHT / 2)
    Column(
        modifier
            .padding(horizontal = 16.dp)
            .then(if (expanded) Modifier.widthIn(max = 520.dp).fillMaxWidth() else Modifier.widthIn(max = 240.dp).wrapContentWidth())
            .shadow(if (expanded) 18.dp else 6.dp, shape, ambientColor = Color.Black.copy(alpha = if (expanded) 0.16f else 0.06f),
                spotColor = Color.Black.copy(alpha = if (expanded) 0.16f else 0.06f))
            .clip(shape)
            .background(if (dark) MaterialTheme.colorScheme.surfaceContainerHigh else Color.White)
            .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f), shape)
            .animateContentSize(spring(dampingRatio = 0.74f, stiffness = Spring.StiffnessMediumLow))
            .padding(horizontal = if (expanded) 16.dp else 0.dp)
            .padding(bottom = if (expanded) 4.dp else 0.dp),
    ) {
        // The pill, and the open card's first row: the face, what the call is
        // about and the call clock stay where they are in both states.
        Box(Modifier.then(if (expanded) Modifier.fillMaxWidth() else Modifier).height(CALL_ISLAND_PILL_HEIGHT)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onExpanded(!expanded) }) {
            Row(Modifier.align(Alignment.Center).padding(start = 6.dp, end = 12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                WeeklyTestCharacter(WeeklyTestHost.Mood.WAITING, 0L, Modifier.size(22.dp), tile = Color.Transparent)
                Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                clock?.let {
                    Text(it, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                minutesLeft?.let { m ->
                    Text(stringResource(R.string.lld_min_b61908, m), style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = if (m <= 3) Color(0xFFFF9500) else MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (expanded) {
                Icon(Icons.Filled.KeyboardArrowUp, null, tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.align(Alignment.CenterEnd).size(18.dp))
            }
        }
        AnimatedVisibility(expanded, enter = fadeIn(), exit = fadeOut()) {
            Column {
                HorizontalDivider()
                Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(stringResource(R.string.topic), style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                            maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    Spacer(Modifier.width(8.dp))
                    onChangeTopic?.let { change ->
                        Text(stringResource(R.string.change), style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.clickable { onExpanded(false); change() })
                    }
                }
                guidance?.let { current ->
                    HorizontalDivider()
                    val options = listOf(CallGuidance.FREE to R.string.free_talk, CallGuidance.COACH to R.string.coach_mode,
                        CallGuidance.TUTOR to R.string.tutor_mode)
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
                        options.forEachIndexed { i, (g, label) ->
                            SegmentedButton(selected = current == g, onClick = { onGuidance(g) },
                                shape = SegmentedButtonDefaults.itemShape(i, options.size), icon = {}) {
                                Text(stringResource(label), maxLines = 1, overflow = TextOverflow.Ellipsis,
                                    style = MaterialTheme.typography.labelMedium)
                            }
                        }
                    }
                }
                HorizontalDivider()
                IslandRow(stringResource(R.string.level_7c7f5d), level.code.uppercase()) { showingLevel = true }
                HorizontalDivider()
                IslandRow(stringResource(R.string.call_settings), null) { onExpanded(false); onSettings() }
            }
        }
    }
}

@Composable
private fun IslandRow(label: String, value: String?, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        value?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.outline,
            modifier = Modifier.size(16.dp))
    }
}

/** The pill's height (iOS `CallIsland.pillHeight`). */
val CALL_ISLAND_PILL_HEIGHT = 34.dp
