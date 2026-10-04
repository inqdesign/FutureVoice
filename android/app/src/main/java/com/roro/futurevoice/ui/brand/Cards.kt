package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
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
    /** A person's photo, clipped to the icon disc (a scene with someone). */
    photo: androidx.compose.ui.graphics.ImageBitmap? = null,
    /** A person's initials on the disc, when there is no photo. */
    initials: String? = null,
    /** The tall shelf shape. Off on the Studying page, where the card has no
     *  whole-book bar and its chapter buttons sit right under it. */
    tall: Boolean = true,
    onClick: (() -> Unit)? = null,
) {
    Card(
        modifier = modifier.fillMaxWidth().heightIn(min = if (tall) 150.dp else 0.dp).then(
            if (onClick != null) Modifier.clickable { onClick() } else Modifier),
        colors = CardDefaults.cardColors(
            // White off the grouped ground, as iOS's book cards are — the
            // tinted Material container read as a second, greyer surface.
            containerColor = AppSurfaces.card),
    ) {
        Column(Modifier.fillMaxWidth().padding(14.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                // In a soft round disc in the book's colour — the card's one
                // coloured mark besides its bar (iOS `BookIconDisc`). A scene
                // with a person shows THAT person: photo, else initials.
                if (photo != null || initials != null || icon != null) {
                    BookIconDisc(accent = accent, photo = photo) {
                        when {
                            initials != null -> Text(initials, style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold, color = accent)
                            icon != null -> Icon(icon, contentDescription = null, tint = accent,
                                modifier = Modifier.size(22.dp))
                        }
                    }
                }
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                if (mastered) {
                    // Neutral: colour lives on the bars and the disc alone.
                    Icon(Icons.Filled.WorkspacePremium, contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(22.dp))
                }
                score?.let { ScoreRing(it) }
                trailing?.invoke()
            }
            if (tall) androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
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
                    // iOS's strip: one rounded hairline on a grey track — no
                    // Material stop dot, no gap between fill and track.
                    LinearProgressIndicator(
                        progress = { it.coerceIn(0f, 1f) },
                        color = if (mastered) Books.mastery else accent,
                        trackColor = iosFill(),
                        strokeCap = androidx.compose.ui.graphics.StrokeCap.Round,
                        gapSize = 0.dp,
                        drawStopIndicator = {},
                        modifier = Modifier.fillMaxWidth().height(4.dp))
                }
                progressLabel?.let {
                    Text(it, style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** The talk's overall score as a small ring — quiet, but present. Neutral
 *  since iOS `912d6f4`: the page keeps colour for its bars. */
@Composable
private fun ScoreRing(score: Int) {
    androidx.compose.foundation.layout.Box(
        Modifier.size(30.dp)
            .border(2.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text("$score", style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** A book card's icon: a soft tinted circle with the glyph (or initials) in
 *  it, or a person's photo clipped to the same circle (iOS `BookIconDisc`). */
@Composable
fun BookIconDisc(accent: Color, photo: androidx.compose.ui.graphics.ImageBitmap? = null,
                 size: androidx.compose.ui.unit.Dp = 44.dp, content: @Composable () -> Unit) {
    androidx.compose.foundation.layout.Box(
        Modifier.size(size).clip(CircleShape)
            .then(if (photo == null) Modifier.background(accent.copy(alpha = 0.14f)) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        if (photo != null) {
            androidx.compose.foundation.Image(photo, contentDescription = null,
                contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                modifier = Modifier.size(size))
        } else content()
    }
}
