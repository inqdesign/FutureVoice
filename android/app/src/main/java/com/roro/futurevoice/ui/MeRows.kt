package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

/**
 * iOS `MeTab.row(icon:title:subtitle:value:)`, and the four ways a row in a
 * SwiftUI `List` is drawn depending on what holds it.
 *
 * - A NavigationLink ([MeRowKind.NAV]) keeps primary ink and gets the grey
 *   chevron — it opens a page.
 * - A Button ([MeRowKind.ACTION]) is tinted WHOLE: the title in the accent,
 *   the subtitle in the accent at secondary strength, no chevron — it acts.
 * - A destructive Button ([MeRowKind.DESTRUCTIVE]) is the same in red.
 * - A plain row ([MeRowKind.PLAIN]) states a fact and goes nowhere.
 *
 * The icon column is iOS's: a subheadline-sized glyph in a 22-wide slot, so
 * titles line up down the card whatever the glyph's own width.
 */
enum class MeRowKind { NAV, ACTION, DESTRUCTIVE, PLAIN }

@Composable
fun MeRow(
    icon: ImageVector?,
    title: String,
    subtitle: String? = null,
    kind: MeRowKind = MeRowKind.NAV,
    value: String? = null,
    enabled: Boolean = true,
    /** Drawn in place of [icon] where the mark is not a glyph (the Core's seal). */
    leading: (@Composable () -> Unit)? = null,
    /** Anything after the value — a spinner on a row that is working. */
    trailing: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    val accent = MaterialTheme.colorScheme.primary
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val ink = MaterialTheme.colorScheme.onSurface
    val tint: Color = when (kind) {
        MeRowKind.ACTION -> accent
        MeRowKind.DESTRUCTIVE -> MaterialTheme.colorScheme.error
        else -> ink
    }
    val alpha = if (enabled) 1f else 0.4f
    val subColor = when (kind) {
        MeRowKind.ACTION, MeRowKind.DESTRUCTIVE -> tint.copy(alpha = 0.6f)
        else -> secondary
    }
    Row(
        Modifier.fillMaxWidth()
            .then(if (onClick != null && enabled) Modifier.clickable(onClick = onClick) else Modifier)
            .heightIn(min = 48.dp)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.width(22.dp), contentAlignment = Alignment.Center) {
            if (leading != null) leading()
            else if (icon != null) Icon(icon, contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = (if (kind == MeRowKind.DESTRUCTIVE) tint else accent).copy(alpha = alpha))
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge,
                color = tint.copy(alpha = alpha))
            subtitle?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.labelSmall,
                    color = subColor.copy(alpha = subColor.alpha * alpha))
            }
        }
        value?.takeIf { it.isNotBlank() }?.let {
            Spacer(Modifier.width(8.dp))
            Text(it, style = MaterialTheme.typography.bodyLarge,
                color = if (kind == MeRowKind.ACTION) accent.copy(alpha = 0.6f) else secondary)
        }
        trailing?.let { Spacer(Modifier.width(8.dp)); it() }
        if (kind == MeRowKind.NAV && onClick != null) {
            Spacer(Modifier.width(6.dp))
            MeChevron()
        }
    }
}

/** iOS's disclosure chevron: small, semibold, tertiary grey. */
@Composable
fun MeChevron(tint: Color = MaterialTheme.colorScheme.outline) {
    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
        modifier = Modifier.size(20.dp), tint = tint)
}

/**
 * A menu-style `Picker` row: the title in primary ink, the current value in
 * the accent with the small up-down chevron, and the list opening on it.
 */
@Composable
fun <T> MePickerRow(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    value: String,
    options: List<Pair<T, String>>,
    onPick: (T) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        MeRow(icon = icon, title = title, subtitle = subtitle, kind = MeRowKind.PLAIN,
            trailing = { MePickerValue(value) }, onClick = { expanded = true })
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (item, label) ->
                DropdownMenuItem(
                    text = { Text(label) },
                    onClick = { expanded = false; onPick(item) },
                )
            }
        }
    }
}

/** The accent value + up-down chevron a menu picker shows. */
@Composable
fun MePickerValue(value: String) {
    Row(verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(value, style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.primary)
        Icon(Icons.Filled.UnfoldMore, contentDescription = null,
            modifier = Modifier.size(15.dp), tint = MaterialTheme.colorScheme.primary)
    }
}
