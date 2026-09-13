package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.border
import androidx.compose.material3.Icon
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.Icons
import androidx.compose.ui.graphics.vector.ImageVector
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
 * One book / topic / talk card — the iOS `TalkBookCard` / `ScenarioBookCard`
 * anatomy: the source icon up top with its verdicts beside it, the title
 * block at the bottom, and the mastery strip under that.
 *
 * A card is TALL on purpose. It is the thing the learner returns to, and the
 * old horizontal row (dot, title, detail) read as a list item — the same
 * weight as a settings row.
 */
@Composable
fun BookCard(
    title: String,
    modifier: Modifier = Modifier,
    /** The source's own glyph — talks share one, a scenario keeps its category's. */
    icon: ImageVector? = null,
    origin: String? = null,
    accent: Color = Books.talks,
    /** When this book was last WORKED, said as recency ("2일 전 학습함"). */
    detail: String? = null,
    progress: Float? = null,
    /** "3/12 mastered", or the hint for a book with nothing in it yet. */
    progressLabel: String? = null,
    mastered: Boolean = false,
    /** The talk's own score, as a ring — how the conversation went. */
    score: Int? = null,
    /** A caller's own accessory, beside the verdicts (the recent-talks row
     *  puts its level there). */
    trailing: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    Card(
        modifier = modifier.fillMaxWidth().heightIn(min = 150.dp).then(
            if (onClick != null) Modifier.clickable { onClick() } else Modifier),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Column(Modifier.fillMaxWidth().padding(14.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                icon?.let {
                    Icon(it, contentDescription = null, tint = accent,
                        modifier = Modifier.size(26.dp))
                }
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                if (mastered) {
                    Icon(Icons.Filled.WorkspacePremium, contentDescription = null,
                        tint = Books.mastery, modifier = Modifier.size(22.dp))
                }
                score?.let { ScoreRing(it) }
                trailing?.invoke()
            }
            androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
            Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                origin?.let {
                    Text(it, style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                }
                Text(title, style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
                detail?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                progress?.let {
                    LinearProgressIndicator(
                        progress = { it.coerceIn(0f, 1f) },
                        color = if (mastered) Books.mastery else accent,
                        modifier = Modifier.fillMaxWidth())
                }
                progressLabel?.let {
                    Text(it, style = MaterialTheme.typography.labelSmall,
                        color = if (mastered) Books.mastery
                        else MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** The talk's overall score as a small ring — quiet, but present. */
@Composable
private fun ScoreRing(score: Int) {
    val band = when {
        score < 50 -> Color(0xFFFF3B30)
        score < 70 -> Color(0xFFFF9500)
        score < 85 -> MaterialTheme.colorScheme.primary
        else -> Books.mastery
    }
    androidx.compose.foundation.layout.Box(
        Modifier.size(30.dp)
            .border(2.dp, band.copy(alpha = 0.35f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text("$score", style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold, color = band)
    }
}
