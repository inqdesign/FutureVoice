package com.roro.futurevoice.ui

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
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

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top,
        ) {
            OutlinedTextField(
                value = text,
                onValueChange = {
                    onText(it)
                    // Typing over a dictation makes it deliberate text, which
                    // the polish pass must then leave alone.
                    if (!listening && usedVoice) onUsedVoice(false)
                },
                placeholder = { Text(placeholder, style = MaterialTheme.typography.bodyMedium) },
                modifier = Modifier.weight(1f).heightIn(min = 96.dp),
            )
            FilledTonalIconButton(
                onClick = {
                    if (listening) end()
                    else if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                        android.content.pm.PackageManager.PERMISSION_GRANTED) begin()
                    else micPermission.launch(Manifest.permission.RECORD_AUDIO)
                },
                colors = if (listening)
                    IconButtonDefaults.filledTonalIconButtonColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer)
                else IconButtonDefaults.filledTonalIconButtonColors(),
            ) {
                Icon(
                    if (listening) Icons.Filled.Stop else Icons.Filled.Mic,
                    contentDescription = stringResource(
                        if (listening) R.string.stop else R.string.speak),
                    modifier = Modifier.size(20.dp),
                )
            }
        }
        if (unavailable) {
            Text(stringResource(R.string.speech_recognition_isnt_available_type_instead),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else if (listening) {
            Text(stringResource(R.string.listening_tap_to_finish),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.primary)
        }
    }
}
