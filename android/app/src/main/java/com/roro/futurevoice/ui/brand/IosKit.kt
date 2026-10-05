package com.roro.futurevoice.ui.brand

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * The stock iOS controls this app is drawn with, measured off the iOS build
 * (simulator, @3x) — not Material's. One file, so a control looks the same on
 * every screen and a correction lands everywhere at once.
 */

@Composable
private fun isDark() = MaterialTheme.colorScheme.background.luminance() < 0.5f

/** iOS `tertiarySystemFill` — the grey a segmented track and a filled field sit on. */
@Composable
fun iosFill(): Color = if (isDark()) Color(0xFF767680).copy(alpha = 0.24f)
    else Color(0xFF767680).copy(alpha = 0.12f)

/**
 * The page chip (Practice shelves, Progress skills, News / Scenarios): a
 * capsule ~37 pt tall, the label at body size in REGULAR weight (iOS doesn't
 * bold the selected one — the fill says it), selected = solid ink, the count
 * as a small raised grey number beside the label.
 */
@Composable
fun IosChip(label: String, selected: Boolean, count: Int? = null,
            /** The selected fill when the chip belongs to something with a
             *  colour of its own (Practice: Talk blue, Watch indigo). Null = ink. */
            selectedFill: Color? = null,
            onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val fill = if (selected) selectedFill ?: scheme.onSurface else AppSurfaces.card
    val ink = if (selected) (if (selectedFill != null) Color.White else scheme.surface) else scheme.onSurface
    val countInk = if (selected) ink.copy(alpha = 0.6f) else scheme.onSurfaceVariant
    // The count is its own Text NUDGED up, not a raised span inside the
    // label: a baseline-shifted span grew the line, so a chip with a count
    // (Practice) stood taller than one without (Progress).
    androidx.compose.foundation.layout.Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(fill)
            .clickable(role = Role.Tab, onClick = onClick)
            .defaultMinSize(minHeight = 37.dp)
            .padding(horizontal = 16.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Normal,
            color = ink, maxLines = 1)
        if (count != null) {
            Text("$count", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = countInk,
                maxLines = 1,
                modifier = Modifier.padding(start = 4.dp).offset(y = (-6).dp))
        }
    }
}

/**
 * iOS's segmented picker (iOS 26): a grey capsule track with a white capsule
 * thumb that SLIDES to the pick; selected label semibold, others regular. No
 * check mark, no outline — Material's SegmentedButton has both.
 */
@Composable
fun IosSegmented(
    options: List<String>,
    selected: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    height: androidx.compose.ui.unit.Dp = 32.dp,  // iOS segmented track, gallery-measured
) {
    val scheme = MaterialTheme.colorScheme
    val dark = isDark()
    val index by animateFloatAsState(selected.toFloat(),
        spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessMediumLow), label = "seg")
    BoxWithConstraints(
        modifier.height(height).clip(CircleShape).background(iosFill()).padding(2.dp),
    ) {
        val w = maxWidth / options.size
        Box(
            Modifier.offset(x = w * index).width(w).fillMaxHeight()
                .shadow(if (dark) 0.dp else 2.dp, CircleShape)
                .background(if (dark) Color(0xFF636366) else Color.White, CircleShape),
        )
        Row(Modifier.fillMaxSize()) {
            options.forEachIndexed { i, label ->
                Box(
                    Modifier.weight(1f).fillMaxHeight()
                        .clickable(interactionSource = remember { MutableInteractionSource() },
                            indication = null, role = Role.Tab) { onSelect(i) },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(label, style = MaterialTheme.typography.bodyMedium, maxLines = 1,
                        fontWeight = if (i == selected) FontWeight.SemiBold else FontWeight.Normal,
                        color = scheme.onSurface)
                }
            }
        }
    }
}

/**
 * iOS's switch: a 51×31 capsule, the accent when on and grey when off, a
 * 27 pt white knob with a soft shadow that slides across.
 */
@Composable
fun IosSwitch(checked: Boolean, onCheckedChange: ((Boolean) -> Unit)?, modifier: Modifier = Modifier,
              enabled: Boolean = true) {
    val scheme = MaterialTheme.colorScheme
    val dark = isDark()
    val track by animateColorAsState(
        if (checked) scheme.primary else if (dark) Color(0xFF39393D) else Color(0xFFE9E9EA), label = "track")
    val x by animateDpAsState(if (checked) 22.dp else 2.dp,
        spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMedium), label = "knob")
    Box(
        modifier.size(51.dp, 31.dp)
            .clip(CircleShape)
            .background(track.copy(alpha = if (enabled) 1f else 0.5f))
            .then(if (onCheckedChange != null && enabled) Modifier.clickable(
                interactionSource = remember { MutableInteractionSource() }, indication = null,
                role = Role.Switch) { onCheckedChange(!checked) } else Modifier),
    ) {
        Box(Modifier.offset(x = x, y = 2.dp).size(27.dp)
            .shadow(3.dp, CircleShape).background(Color.White, CircleShape))
    }
}

/**
 * iOS 26's toolbar button: a white "glass" capsule (text) or circle (icon)
 * with a soft shadow — Done, Cancel, Later, the People button.
 */
@Composable
fun IosGlassButton(onClick: () -> Unit, modifier: Modifier = Modifier, circle: Boolean = false,
                   content: @Composable RowScope.() -> Unit) {
    val dark = isDark()
    Row(
        modifier
            .height(44.dp)
            .then(if (circle) Modifier.width(44.dp) else Modifier)
            // Stronger than a card's: on a white page (sheets, People) the
            // capsule has to lift off it the way iOS's glass does.
            .shadow(if (dark) 0.dp else 12.dp, CircleShape,
                ambientColor = Color.Black.copy(alpha = 0.16f), spotColor = Color.Black.copy(alpha = 0.16f))
            .background(if (dark) Color(0xFF2C2C2E) else Color.White, CircleShape)
            .border(0.5.dp, Color.Black.copy(alpha = if (dark) 0f else 0.06f), CircleShape)
            .clip(CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = if (circle) 0.dp else 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        content = content,
    )
}

/** Glass text button with the accent label (Done, Cancel, Later). */
@Composable
fun IosGlassTextButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier,
                       bold: Boolean = false,
                       /** iOS `.disabled(…)`: the label greys out and the tap does nothing. */
                       enabled: Boolean = true) {
    IosGlassButton({ if (enabled) onClick() }, modifier) {
        Text(text, style = MaterialTheme.typography.bodyLarge,
            color = if (enabled) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f),
            fontWeight = if (bold) FontWeight.SemiBold else FontWeight.Normal)
    }
}
