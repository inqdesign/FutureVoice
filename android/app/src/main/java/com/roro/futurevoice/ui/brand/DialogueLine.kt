package com.roro.futurevoice.ui.brand

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/** Who is speaking. `user` sits trailing on an accent fill; `other` leads. */
enum class DialogueSpeaker { USER, OTHER;
    val isUser: Boolean get() = this == USER
}

/** Text size: the call is read at arm's length, the archives are dense lists. */
enum class DialogueScale { CALL, STANDARD }

/**
 * The ONE dialogue-line surface, shared by every conversation view — Watch's
 * scripted scene, the live call transcript, past-conversation detail
 * (`DialogueLine.swift`).
 *
 * Speaker separation (the name label, which side the line sits on, the bubble
 * fill, the playback ring) is defined HERE and nowhere else, so restyling the
 * conversation UI stays a single-file change. Callers supply their own line
 * content and accessories — never the chrome.
 */
@Composable
fun DialogueLine(
    speaker: DialogueSpeaker,
    name: String,
    modifier: Modifier = Modifier,
    scale: DialogueScale = DialogueScale.STANDARD,
    /** Playback cursor (Watch) — an accent ring on the line being spoken. */
    isCurrent: Boolean = false,
    accessory: @Composable () -> Unit = {},
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val theme = FutureselfTheme.stored(context)
    val accent = theme.tint()
    // Mono is the one palette whose accent is INK rather than a hue, so the
    // usual 18% wash lands as a barely-there gray and the learner's own lines
    // stop being tellable from the fluent self's — the only job this fill
    // has. In mono the user bubble goes solid instead, and it inverts
    // correctly in dark mode rather than sinking into the background.
    val isMonoUser = speaker.isUser && theme == FutureselfTheme.MONO
    val fill = when {
        isMonoUser -> MaterialTheme.colorScheme.onSurface
        speaker.isUser -> accent.copy(alpha = 0.18f)
        else -> MaterialTheme.colorScheme.surfaceVariant
    }
    val foreground = if (isMonoUser) MaterialTheme.colorScheme.surface
    else MaterialTheme.colorScheme.onSurface
    val ring = if (isMonoUser) MaterialTheme.colorScheme.surface else accent

    Row(modifier.fillMaxWidth()) {
        // The opposite-side gutter is what actually separates the two
        // speakers' columns — without it both sides span full width and the
        // fills alone read as stripes, not as a back-and-forth.
        if (speaker.isUser) Spacer(Modifier.width(40.dp))
        Column(
            Modifier.weight(1f),
            horizontalAlignment = if (speaker.isUser) Alignment.End else Alignment.Start,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(name, style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Column(
                Modifier
                    .background(fill, RoundedCornerShape(14.dp))
                    .then(if (isCurrent) Modifier.border(2.dp, ring, RoundedCornerShape(14.dp))
                    else Modifier)
                    .padding(horizontal = 14.dp, vertical = 10.dp)
            ) {
                androidx.compose.runtime.CompositionLocalProvider(
                    androidx.compose.material3.LocalContentColor provides foreground,
                ) {
                    androidx.compose.material3.ProvideTextStyle(
                        // Long lines stay left-ragged even in a trailing
                        // bubble — centre/right-ragged body text is hard to read.
                        (if (scale == DialogueScale.CALL) MaterialTheme.typography.titleMedium
                        else MaterialTheme.typography.bodyLarge).copy(textAlign = TextAlign.Start),
                    ) { content() }
                }
            }
            accessory()
        }
        if (!speaker.isUser) Spacer(Modifier.width(40.dp))
    }
}
