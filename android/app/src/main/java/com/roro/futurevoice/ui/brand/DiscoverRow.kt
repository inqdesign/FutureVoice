package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * ONE list card — leading icon in a tinted circle, title + caption, chevron
 * (`DiscoverSection.listCard`). The shared row anatomy for news stories and
 * scenarios: full-width stacked cards on the 20pt grid, because a horizontal
 * rail read as posters and these read as a list.
 */
@Composable
fun DiscoverRow(
    title: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    caption: String? = null,
    /** A second quiet line — the people rows carry facets AND interests. */
    caption2: String? = null,
    accent: Color = MaterialTheme.colorScheme.primary,
    onClick: (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    Row(
        modifier
            .fillMaxWidth()
            .clip(ContinuousShape(18.dp))
            .background(AppSurfaces.card)
            .then(if (onClick != null) Modifier.clickable { onClick() } else Modifier)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(accent.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(19.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            caption?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            caption2?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (trailing != null) trailing()
        else Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
            tint = MaterialTheme.colorScheme.outline)
    }
}

/**
 * The Discover header's segment chip (`DiscoverSection.chip`): the selected
 * one goes SOLID INK (label colour as fill, background colour as text), the
 * rest sit on the grouped card colour.
 *
 * NOT the page chip ([IosChip], 37 pt, body size): iOS draws this one smaller
 * — subheadline (15) MEDIUM, 14 × 8 padding — 34 pt tall, measured off the
 * iOS build at @3x. Held as a 34 dp MINIMUM rather than 8 dp of padding
 * round the text: a Hangul label falls back to a CJK font whose line box is
 * ~21 dp at 15 sp (measured 37 dp with padding), where SwiftUI's is 18.
 */
@Composable
fun SegmentChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Box(
        Modifier
            .clip(CircleShape)
            .background(if (selected) scheme.onSurface else AppSurfaces.card)
            .clickable(role = androidx.compose.ui.semantics.Role.Tab, onClick = onClick)
            .defaultMinSize(minHeight = 34.dp)
            .padding(horizontal = 14.dp, vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium, maxLines = 1,
            color = if (selected) scheme.surface else scheme.onSurface)
    }
}
