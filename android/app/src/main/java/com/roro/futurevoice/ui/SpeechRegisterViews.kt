package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.SpeechRegister
import com.roro.futurevoice.ui.brand.IosSegmented

/** The rung's name on screen, in the app language (iOS `SpeechRegister.title`). */
@Composable
internal fun SpeechRegister.title(): String = stringResource(when (this) {
    SpeechRegister.CASUAL -> R.string.rel_casual
    SpeechRegister.POLITE -> R.string.rel_polite
    SpeechRegister.FORMAL -> R.string.rel_formal
})

/**
 * The intake's register card row (iOS `registerPicker` in
 * `CounterpartVoiceIntakeView`): a semibold title, a segmented picker, and —
 * where the target language has a name for the rung — "In Korean: 반말".
 */
@Composable
internal fun RegisterSegmentedRow(
    title: String,
    selection: SpeechRegister,
    targetLanguage: String,
    nativeLanguage: String,
    onSelect: (SpeechRegister) -> Unit,
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
        IosSegmented(
            options = SpeechRegister.entries.map { it.title() },
            selected = selection.ordinal,
            onSelect = { onSelect(SpeechRegister.entries[it]) },
            modifier = Modifier.fillMaxWidth(),
        )
        selection.term(targetLanguage)?.let { term ->
            Text(stringResource(R.string.rel_in_s_s, LanguageCatalog.ownName(targetLanguage, nativeLanguage), term),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * The form's register row (iOS `Picker` in a `Form`): the title on the left,
 * the pick on the right, a menu on tap. "Automatic" is null — the
 * relationship decides, which is what every person made before the field did.
 */
@Composable
internal fun RegisterMenuRow(
    title: String,
    selection: SpeechRegister?,
    targetLanguage: String,
    onSelect: (SpeechRegister?) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    @Composable
    fun label(r: SpeechRegister?): String = r?.let { reg ->
        reg.term(targetLanguage)?.let { "${reg.title()} · $it" } ?: reg.title()
    } ?: stringResource(R.string.rel_automatic)
    Box {
        Row(
            Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable { open = true }
                .padding(start = 16.dp, end = 12.dp, top = 11.dp, bottom = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            Text(label(selection), style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.End,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Icon(Icons.Filled.UnfoldMore, contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 4.dp).size(18.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false },
            modifier = Modifier.align(Alignment.TopEnd)) {
            (listOf<SpeechRegister?>(null) + SpeechRegister.entries).forEach { r ->
                DropdownMenuItem(
                    text = { Text(label(r)) },
                    leadingIcon = {
                        if (r == selection) Icon(Icons.Filled.Check, contentDescription = null)
                        else Box(Modifier.size(24.dp))
                    },
                    onClick = { open = false; onSelect(r) },
                )
            }
        }
    }
}
