package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.ui.draw.clip
import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.ui.graphics.Color
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.audio.LiveTranscriber

/**
 * One answer, spoken or typed.
 *
 * SPEAKING is the primary path and typing the fallback, not the other way
 * round: this is an app about talking, and a page of text fields asks a
 * learner to write about their life in a language they may be practising.
 * What is dictated is marked [usedVoice], because only dictated text goes
 * through the polish pass — rewriting what someone deliberately typed would
 * surprise them.
 *
 * The recognizer writes into the SAME field the keyboard does, so a dictated
 * answer can be corrected by hand without starting over.
 */
@Composable
fun SpeakOrTypeField(
    text: String,
    onText: (String) -> Unit,
    usedVoice: Boolean,
    onUsedVoice: (Boolean) -> Unit,
    placeholder: String,
    /** BCP-47 for the recognizer — the language being answered IN. */
    locale: String,
    /**
     * Controls the HOST puts inside this field's own control row (iOS
     * `leadingControls` / `trailingControls`, `9fe8cc7`). Given either, the
     * field lays out as a BOX — the text on top, one strip of controls under
     * it with the mic at its end — so a host with its own buttons never
     * stacks a second toolbar under the field's.
     */
    leadingControls: (@Composable () -> Unit)? = null,
    trailingControls: (@Composable () -> Unit)? = null,
    /** A quiet mic, for a host whose own primary button shares the screen —
     *  two filled accent shapes side by side read as two primaries. */
    plainMic: Boolean = false,
    /** Hidden while the box shows its reel; the host watches focus. */
    fieldModifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val transcriber = remember { LiveTranscriber(context) }
    var listening by remember { mutableStateOf(false) }
    // What the field held before this dictation, so a second take appends to
    // the answer rather than wiping it.
    var base by remember { mutableStateOf("") }
    var unavailable by remember { mutableStateOf(false) }

    fun begin() {
        base = text.trim()
        runCatching {
            transcriber.start(locale) { heard ->
                onText(listOf(base, heard.trim()).filter { it.isNotBlank() }.joinToString(" "))
            }
            listening = true
            onUsedVoice(true)
        }.onFailure { unavailable = true }
    }

    fun end() {
        listening = false
        runCatching { transcriber.stop() }
    }

    // A mic left open behind a dismissed sheet is both a battery cost and a
    // thing nobody can see to turn off.
    DisposableEffect(Unit) { onDispose { runCatching { transcriber.stop() } } }

    val micPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> if (granted) begin() }

    val micButton: @Composable () -> Unit = {
        FilledTonalIconButton(
            onClick = {
                if (listening) end()
                else if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED) begin()
                else micPermission.launch(Manifest.permission.RECORD_AUDIO)
            },
            colors = when {
                listening -> IconButtonDefaults.filledTonalIconButtonColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer)
                plainMic -> IconButtonDefaults.filledTonalIconButtonColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    contentColor = MaterialTheme.colorScheme.onSurface)
                else -> IconButtonDefaults.filledTonalIconButtonColors()
            },
        ) {
            Icon(
                if (listening) Icons.Filled.Stop else Icons.Filled.Mic,
                contentDescription = stringResource(
                    if (listening) R.string.stop_dictation else R.string.dictate),
                modifier = Modifier.size(20.dp),
            )
        }
    }

    // ALWAYS one box (iOS `SpeakOrTypeField`): the text on top, one 44 pt
    // control strip under it with the mic at its end. Without host controls
    // the box draws its own filled card; a host with controls (the Watch
    // composer) supplies the card around it.
    val ownCard = leadingControls == null && trailingControls == null
    run {
        Column(
            (if (ownCard) Modifier.fillMaxWidth()
                .clip(com.roro.futurevoice.ui.brand.ContinuousShape(12.dp))
                .background(com.roro.futurevoice.ui.brand.iosFill())
            else Modifier),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            TextField(
                value = text,
                onValueChange = {
                    onText(it)
                    if (!listening && usedVoice) onUsedVoice(false)
                },
                placeholder = { Text(placeholder, style = MaterialTheme.typography.bodyLarge) },
                maxLines = 5,
                minLines = if (ownCard) 2 else 1,
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.Transparent,
                    unfocusedContainerColor = Color.Transparent,
                    disabledContainerColor = Color.Transparent,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                ),
                modifier = fieldModifier.fillMaxWidth(),
            )
            // ONE control strip: the host's buttons on the left, the
            // language and the mic on the right — contents swap, geometry
            // doesn't, so the box never resizes itself as they change.
            Row(
                Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                leadingControls?.invoke()
                if (listening) {
                    Text(stringResource(R.string.listening_tap_to_finish),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary, maxLines = 1)
                }
                Spacer(Modifier.weight(1f))
                if (!listening) trailingControls?.invoke()
                micButton()
            }
            if (unavailable) {
                Text(stringResource(R.string.speech_recognition_isnt_available_type_instead),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 12.dp))
            }
        }
    }

}
