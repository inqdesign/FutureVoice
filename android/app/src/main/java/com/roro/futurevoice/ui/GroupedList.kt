package com.roro.futurevoice.ui

import androidx.compose.ui.text.withStyle
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.ui.brand.AppSurfaces

/**
 * iOS's inset-grouped `List`, in one place.
 *
 * Every settings-shaped screen on iOS is a `List` with `.insetGrouped`:
 * uppercase section headers, rounded cards holding the rows, and a footer
 * paragraph under each card. Rebuilding that per screen is how two pages that
 * are the same page on iOS end up looking different here — which is exactly
 * what happened between the invite page and the talk-time guide.
 */
@Composable
fun GroupedSectionHeader(text: String) {
    // Grouped list headers are uppercased by the system on iOS.
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 4.dp, top = 20.dp, bottom = 6.dp),
    )
}

/** The gap between two cards that have no header between them — iOS's
 *  section spacing. An empty header would leave a taller, uneven gap. */
@Composable
fun GroupedSectionSpacer() {
    Spacer(Modifier.height(22.dp))
}

@Composable
fun GroupedCard(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth()
            .background(AppSurfaces.card, RoundedCornerShape(12.dp))
            .padding(vertical = 4.dp),
    ) { content() }
}

/** Between rows INSIDE a card — inset past the icon column, as iOS insets
 *  past a row's leading content. */
@Composable
fun GroupedRowDivider(inset: Boolean = true) {
    HorizontalDivider(
        Modifier.padding(start = if (inset) 52.dp else 0.dp),
        color = MaterialTheme.colorScheme.outlineVariant,
    )
}

@Composable
fun GroupedFooter(text: String) {
    Text(
        // One translated footer carries **bold** from the iOS catalog, which
        // SwiftUI renders and Compose does not. Parse it rather than shipping
        // asterisks — the catalog is generated, so it can't be edited here.
        markdownBold(text),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 4.dp, end = 4.dp, top = 6.dp),
    )
}

/** `**bold**` as a span. Deliberately tiny: the catalog uses nothing else. */
@Composable
fun markdownBold(text: String): androidx.compose.ui.text.AnnotatedString =
    androidx.compose.ui.text.buildAnnotatedString {
        var rest = text
        while (true) {
            val open = rest.indexOf("**")
            val close = if (open < 0) -1 else rest.indexOf("**", open + 2)
            if (open < 0 || close < 0) { append(rest); return@buildAnnotatedString }
            append(rest.substring(0, open))
            withStyle(androidx.compose.ui.text.SpanStyle(
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)) {
                append(rest.substring(open + 2, close))
            }
            rest = rest.substring(close + 2)
        }
    }
