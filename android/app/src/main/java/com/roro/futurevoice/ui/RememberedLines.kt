package com.roro.futurevoice.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ShortText
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.Recency
import com.roro.futurevoice.net.PublicPersonaClient
import com.roro.futurevoice.talk.PersonaNote
import com.roro.futurevoice.talk.UserPersona

/**
 * The remembered lines in Me → Profile — iOS `PersonaOnboardingView
 * .rememberedSection`.
 *
 * Two lists by [PersonaNote.Kind]: the durable lines ("What I know about
 * you") and the ones that fade ("Right now"). Every row shows the sentence
 * the line was distilled from (`heard`) as its evidence, and a "Strangers
 * hear" line that says what leaves the notebook — nothing, the gist, or
 * everything — with the model's reason for its pick. The rung moves from the
 * trailing button or the long-press menu. The last section is the paragraph
 * strangers actually get, composed live from [persona] (the DRAFT), so a
 * moved rung is visible on the same screen.
 *
 * Draws nothing when there are no remembered lines. Changes go out through
 * [onNotesChange]; the caller saves (and records share corrections) on its
 * own commit, as iOS does.
 */
@Composable
fun RememberedLinesSection(
    persona: UserPersona,
    onNotesChange: (List<PersonaNote>) -> Unit,
) {
    val notes = persona.learnedNotes
    val hasFacts = notes.any { it.kind == PersonaNote.Kind.FACT }
    val hasRecent = notes.any { it.kind == PersonaNote.Kind.NOW }
    if (!hasFacts && !hasRecent) return

    fun replace(n: PersonaNote) = onNotesChange(notes.map { if (it.id == n.id) n else it })
    fun forget(id: String) = onNotesChange(notes.filterNot { it.id == id })

    @Composable
    fun Rows(kind: PersonaNote.Kind) {
        GroupedCard {
            notes.filter { it.kind == kind }.forEachIndexed { i, n ->
                if (i > 0) GroupedRowDivider(inset = false)
                NoteRow(n, onChange = ::replace, onForget = { forget(n.id) })
            }
        }
    }

    if (hasFacts) {
        GroupedSectionHeader(stringResource(R.string.what_i_know_about_you))
        Rows(PersonaNote.Kind.FACT)
        GroupedFooter(stringResource(R.string.from_your_talks_tap_a_line_to_fix_what_i_misheard_for_each_o_9b8584))
    }
    if (hasRecent) {
        GroupedSectionHeader(stringResource(R.string.right_now))
        Rows(PersonaNote.Kind.NOW)
        GroupedFooter(stringResource(R.string.true_for_a_while_i_forget_these_on_my_own_after_a_month_or_t_f0cb67))
    }
    GroupedSectionHeader(stringResource(R.string.what_strangers_can_see))
    GroupedCard {
        val intro = PublicPersonaClient.composedIntro(persona)
        Text(
            intro.ifEmpty { stringResource(R.string.nothing_yet) },
            style = MaterialTheme.typography.bodyMedium,
            color = if (intro.isEmpty()) MaterialTheme.colorScheme.onSurfaceVariant
            else MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
        )
    }
    GroupedFooter(stringResource(R.string.the_intro_another_learner_s_phone_speaks_as_you_in_find_peop_3caa8f))
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun NoteRow(n: PersonaNote, onChange: (PersonaNote) -> Unit, onForget: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    var rungMenu by remember { mutableStateOf(false) }
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val caption = MaterialTheme.typography.bodySmall
    Box {
        Row(
            Modifier.fillMaxWidth()
                .combinedClickable(onClick = {}, onLongClick = { menu = true })
                .padding(start = 14.dp, end = 4.dp, top = 10.dp, bottom = 10.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                // Tap to fix what was misheard — the line itself is editable.
                // Emptied lines are dropped on save.
                BasicTextField(
                    value = n.text,
                    onValueChange = { onChange(n.copy(text = it)) },
                    textStyle = MaterialTheme.typography.bodyMedium.copy(
                        color = MaterialTheme.colorScheme.onSurface),
                    cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    maxLines = 3,
                    modifier = Modifier.fillMaxWidth(),
                )
                // The evidence: what they actually said.
                n.heard?.takeIf { it.isNotBlank() }?.let {
                    Text(stringResource(R.string.you_said, it), style = caption, color = secondary)
                }
                val fade = fadeLabel(n)
                Text(
                    listOfNotNull(Recency.label(n.learnedAt), fade).joinToString(" · "),
                    style = caption, color = secondary,
                )
                // What leaves the notebook, and the model's reason for it.
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(R.string.strangers_hear_a8bfc4), style = caption, color = secondary)
                    when (n.share) {
                        PersonaNote.Share.NOTHING ->
                            Text(stringResource(R.string.nothing_0feca7), style = caption)
                        PersonaNote.Share.ALL ->
                            Text(stringResource(R.string.everything_d5a63c), style = caption)
                        PersonaNote.Share.GIST -> {
                            val placeholder = stringResource(R.string.the_gist_in_a_few_words)
                            BasicTextField(
                                value = n.gist.orEmpty(),
                                onValueChange = { onChange(n.copy(gist = it.ifEmpty { null })) },
                                textStyle = caption.copy(color = MaterialTheme.colorScheme.onSurface),
                                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                                maxLines = 2,
                                decorationBox = { inner ->
                                    if (n.gist.isNullOrEmpty()) {
                                        Text(placeholder, style = caption,
                                            color = MaterialTheme.colorScheme.outline)
                                    }
                                    inner()
                                },
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                }
                n.why?.takeIf { it.isNotBlank() }?.let {
                    Text(it, style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.outline)
                }
            }
            val label = shareLabel(n.share)
            Box {
                IconButton(onClick = { rungMenu = true },
                    modifier = Modifier.semantics { contentDescription = label }) {
                    Icon(shareIcon(n.share), contentDescription = null,
                        tint = if (n.share == PersonaNote.Share.ALL) secondary
                        else MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp))
                }
                DropdownMenu(expanded = rungMenu, onDismissRequest = { rungMenu = false }) {
                    RungItems(n) { onChange(n.copy(share = it)); rungMenu = false }
                }
            }
        }
        // The long-press menu: the rungs, "That's over now" for a line that
        // fades, and forgetting it outright.
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            RungItems(n) { onChange(n.copy(share = it)); menu = false }
            HorizontalDivider()
            if (n.kind == PersonaNote.Kind.NOW) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.that_s_over_now)) },
                    leadingIcon = { Icon(Icons.Filled.Check, null) },
                    onClick = { menu = false; onForget() },
                )
            }
            DropdownMenuItem(
                text = { Text(stringResource(R.string.forget_this), color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(Icons.Filled.Delete, null, tint = MaterialTheme.colorScheme.error) },
                onClick = { menu = false; onForget() },
            )
        }
    }
}

/**
 * The three rungs. "Just the gist" is offered only when there is one to hand
 * out — a rung that would send nothing is not a choice.
 */
@Composable
private fun RungItems(n: PersonaNote, onPick: (PersonaNote.Share) -> Unit) {
    val hasGist = !n.gist.isNullOrBlank()
    @Composable
    fun item(share: PersonaNote.Share, title: String) = DropdownMenuItem(
        text = { Text(title) },
        leadingIcon = { Icon(shareIcon(share), null) },
        trailingIcon = if (n.share == share) ({ Icon(Icons.Filled.Check, null) }) else null,
        onClick = { onPick(share) },
    )
    item(PersonaNote.Share.NOTHING, stringResource(R.string.nothing_448194))
    if (hasGist || n.share == PersonaNote.Share.GIST) {
        item(PersonaNote.Share.GIST, stringResource(R.string.just_the_gist))
    }
    item(PersonaNote.Share.ALL, stringResource(R.string.everything_4a66d1))
}

private fun shareIcon(share: PersonaNote.Share): ImageVector = when (share) {
    PersonaNote.Share.NOTHING -> Icons.Filled.Lock
    PersonaNote.Share.GIST -> Icons.AutoMirrored.Filled.ShortText
    PersonaNote.Share.ALL -> Icons.Filled.LockOpen
}

@Composable
private fun shareLabel(share: PersonaNote.Share): String = stringResource(when (share) {
    PersonaNote.Share.NOTHING -> R.string.strangers_hear_nothing_only_your_fluent_self_knows_this
    PersonaNote.Share.GIST -> R.string.strangers_hear_the_gist_the_outline_not_the_details
    PersonaNote.Share.ALL -> R.string.strangers_hear_everything_may_appear_in_your_find_people_int_8d80de
})

/** "fades in 3 weeks" for a `now` line — how long until it's forgotten on its own. */
@Composable
private fun fadeLabel(n: PersonaNote): String? {
    if (n.kind != PersonaNote.Kind.NOW) return null
    val left = n.learnedAt + PersonaNote.NOW_HORIZON_MS - System.currentTimeMillis()
    if (left <= 0) return null
    val days = (left / 86_400_000L).toInt()
    return when {
        days >= 14 -> stringResource(R.string.fades_in_lld_weeks, days / 7)
        days >= 2 -> stringResource(R.string.fades_in_lld_days, days)
        else -> stringResource(R.string.fades_tomorrow)
    }
}

/**
 * The draft as it should be saved (iOS `commit`): a line edited down to
 * nothing was meant as a delete, text is trimmed, and every rung the learner
 * moved by hand is recorded against what is on file so the next summary
 * call can learn from it.
 */
fun UserPersona.committingNotes(onFile: List<PersonaNote>): UserPersona =
    copy(learnedNotes = learnedNotes.mapNotNull { n ->
        val t = n.text.trim()
        if (t.isEmpty()) null else n.copy(text = t)
    }).recordingShareCorrections(onFile)
