package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background

/**
 * The shared card vocabulary for the shelves — `BookCards.swift`.
 *
 * Source colour coding is the one thing carried across every shelf, so a
 * source is tellable at a glance even in a mixed grid: Free talk = blue,
 * News = orange, Scenario = purple. Mastery stays green everywhere.
 */
object Books {
    val talks = Color(0xFF2F6FED)
    val topics = Color(0xFFE8833A)
    val scenarios = Color(0xFF8A5CD1)
    val mastery = Color(0xFF2E9E5B)
}

/**
 * One book / topic / talk card: a source dot, the title, a quiet origin tag,
 * and (for books) the mastery bar. The origin tag is plain secondary text —
 * it names the source without pulling the eye off the title.
 */
@Composable
fun BookCard(
    title: String,
    modifier: Modifier = Modifier,
    origin: String? = null,
    accent: Color = Books.talks,
    detail: String? = null,
    progress: Float? = null,
    onClick: (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    Card(
        modifier = modifier.fillMaxWidth().then(
            if (onClick != null) Modifier.clickable { onClick() } else Modifier),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Row(
            Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                origin?.let {
                    Row(verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        androidx.compose.foundation.layout.Box(
                            Modifier.size(6.dp).clip(CircleShape).background(accent))
                        Text(it, style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Medium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                    }
                }
                Text(title, style = MaterialTheme.typography.titleSmall,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
                detail?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                progress?.let {
                    LinearProgressIndicator(
                        progress = { it.coerceIn(0f, 1f) },
                        color = if (it >= 1f) Books.mastery else accent,
                        modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
                }
            }
            trailing?.let {
                Column(Modifier.padding(start = 10.dp)) { it() }
            }
        }
    }
}
