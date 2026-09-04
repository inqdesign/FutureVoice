package com.roro.futurevoice.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.material.icons.filled.ChatBubbleOutline
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.data.StudyScheduleStore
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.Turn
import java.util.Calendar

/**
 * What the learner is studying, put in front of them WHILE they talk.
 *
 * The notebook has always been a place you go to; a talk is the only place
 * the words can actually be spent. Between the two there was nothing — nobody
 * remembers, mid-sentence, that they saved *commute* on Tuesday. This is that
 * reminder: one line above the transcript, and the chip ticks itself the
 * moment the word comes out of the learner's mouth.
 *
 * **The judge is [CarryoverDetector], not a second rule.** The same matcher
 * decides the wrap-up's "you used what you'd been studying" section at the end
 * of the call, so the chip that ticked live and the line in the summary can
 * never disagree — and a live tick can never be a false positive the summary
 * then quietly drops.
 *
 * Nothing here writes to disk. Crediting the word for real is
 * `VocabStore.ingest` + `CarryoverDetector.detect` at session end, on the
 * finished transcript; this row only shows what that pass will find.
 */
data class TalkGoalItem(
    /** Normalized — the key the detector matches on, and what the caller
     *  tracks as "already ticked". */
    val key: String,
    /** What the learner saved, drawn as they saw it. */
    val text: String,
    /** Single words go by lemma ("I commuted for years" ticks *commute*);
     *  everything else goes through the phrase rules. */
    val isWord: Boolean,
)

object TalkGoalPicker {

    /** One line, and a chip has to be readable at a glance from a call screen
     *  the learner is not looking at. Past five nobody reads the row. */
    const val MAX_ITEMS = 5

    /** Phrases are long. Two is enough to be worth reaching for without the
     *  short, scannable words being pushed off screen. */
    private const val MAX_EXPRESSIONS = 2

    /**
     * Today's due studying items, expressions and words mixed.
     *
     * Due-ness comes from [StudyScheduleStore] — the same schedule the daily
     * words/expressions sessions deal from — so an item snoozed to "3 days"
     * stays out of the row too, and the app never asks for the same thing in
     * two voices on the same day. Nothing tops the list up from the core
     * wordlist: this row is about what the learner CHOSE to study.
     */
    suspend fun pick(
        context: android.content.Context,
        language: String,
        limit: Int = MAX_ITEMS,
        now: Long = System.currentTimeMillis(),
    ): List<TalkGoalItem> {
        val vocab = VocabStore.shared(context)
        val schedule = StudyScheduleStore.shared(context).snapshot(language)

        val phrases = ordered(
            vocab.studyingExpressions(language).filter { !vocab.isKnownExpression(it, language) },
            StudyScheduleStore.Kind.EXPRESSION, schedule, now,
        )
            // A phrase that cannot clear the detector is never offered: a
            // checkbox that cannot tick teaches the learner the whole row is
            // decorative.
            .filter { CarryoverDetector.isCreditable(it) }
            .take(MAX_EXPRESSIONS)
            .map { TalkGoalItem(CarryoverDetector.normalized(it), it, isWord = false) }

        val words = ordered(
            vocab.studying(language), StudyScheduleStore.Kind.WORD, schedule, now,
        )
            .map {
                // A multi-word entry can land in the notebook (a learner taps
                // a two-word chunk in a transcript); it can't be lemma-matched,
                // so it goes through the phrase rules instead.
                TalkGoalItem(CarryoverDetector.normalized(it), it, isWord = !it.contains(" "))
            }
            .filter { it.isWord || CarryoverDetector.isCreditable(it.text) }

        // Interleave so the row opens with something short: a phrase first
        // would fill the visible width on its own and the words would only
        // exist for whoever scrolls.
        val out = ArrayList<TalkGoalItem>(limit)
        val seen = HashSet<String>()
        val w = words.iterator()
        val p = phrases.iterator()
        var takeWord = true
        while (out.size < limit) {
            val next = if (takeWord) (if (w.hasNext()) w.next() else if (p.hasNext()) p.next() else null)
            else (if (p.hasNext()) p.next() else if (w.hasNext()) w.next() else null)
            val item = next ?: break
            takeWord = !takeWord
            if (item.key.isEmpty() || !seen.add(item.key)) continue
            out.add(item)
        }
        return out
    }

    /**
     * Overdue-scheduled first (earliest return first), then never-scheduled,
     * oldest save first and rotated by the day so a big notebook doesn't deal
     * the same five forever. Same ordering as the daily words deal.
     */
    private fun ordered(
        items: List<String>,
        kind: StudyScheduleStore.Kind,
        schedule: StudyScheduleStore.Snapshot,
        now: Long,
    ): List<String> {
        val due = items.filter { schedule.isDue(kind, it, now) }
        val scheduled = due.mapNotNull { item -> schedule.nextReview(kind, item)?.let { item to it } }
            .sortedBy { it.second }.map { it.first }
        val unscheduled = due.filter { schedule.nextReview(kind, it) == null }
        if (unscheduled.isEmpty()) return scheduled
        val day = Calendar.getInstance().apply { timeInMillis = now }.get(Calendar.DAY_OF_YEAR)
        val oldestFirst = unscheduled.reversed()   // the store keeps newest-first
        val offset = day % oldestFirst.size
        return scheduled + oldestFirst.drop(offset) + oldestFirst.take(offset)
    }

    /**
     * Which of [items] this turn just produced. Additive by design — the
     * caller keeps the ticks it already has, so a later, better transcript of
     * the same turn can add a tick but never take one back. A check that
     * disappears mid-call reads as the app changing its mind about the
     * learner.
     */
    fun hits(turn: Turn, items: List<TalkGoalItem>): Set<String> {
        if (turn.role != com.roro.futurevoice.talk.TurnRole.USER || turn.excludedFromScoring ||
            turn.transcript.isBlank() || items.isEmpty()) return emptySet()
        val out = HashSet<String>()
        var lemmas: Set<String>? = null   // one pass per turn, at most
        for (item in items) {
            if (item.isWord) {
                val found = lemmas ?: com.roro.futurevoice.data.VocabLemmas.lemmas(listOf(turn.transcript)).also { lemmas = it }
                if (found.contains(item.key)) out.add(item.key)
            } else if (CarryoverDetector.firstMatch(item.text, listOf(turn)) != null) {
                out.add(item.key)
            }
        }
        return out
    }
}

/**
 * The row itself: one line, horizontally scrollable, no header.
 *
 * The hollow circle is what makes it read as a checklist without spending a
 * label on saying so — and it's the only reason a bare row of words is
 * legible as "things to use" rather than "things the app is telling you".
 */
@Composable
fun TalkGoalChipsRow(
    items: List<TalkGoalItem>,
    used: Set<String>,
    /** Tapped chip → the caller opens the goal sheet. A chip that only sat
     *  there was asking the learner to use a word they may not remember the
     *  meaning of; the tap is where the row stops being a demand. */
    onTap: (TalkGoalItem) -> Unit = {},
) {
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items.forEach { item -> Chip(item, used.contains(item.key), onTap) }
    }
}

@Composable
private fun Chip(item: TalkGoalItem, done: Boolean, onTap: (TalkGoalItem) -> Unit) {
    val green = Color(0xFF34C759)
    val fade by animateFloatAsState(targetValue = if (done) 0.6f else 1f, label = "goalChip")
    val usedLabel = androidx.compose.ui.res.stringResource(
        if (done) com.roro.futurevoice.R.string.used else com.roro.futurevoice.R.string.not_used_yet)
    Row(
        Modifier
            .background(MaterialTheme.colorScheme.surfaceVariant, CircleShape)
            .clickable { onTap(item) }
            .padding(horizontal = 10.dp, vertical = 5.dp)
            .semantics { contentDescription = "${item.text}, $usedLabel" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(
            if (done) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
            contentDescription = null,
            modifier = Modifier.size(13.dp),
            tint = if (done) green else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            item.text,
            style = MaterialTheme.typography.bodySmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.alpha(fade),
        )
    }
}

/**
 * What one chip opens: the thing to say, and what it means.
 *
 * Deliberately thin. The call is still running behind this sheet — the
 * learner is standing in the middle of a conversation trying to remember
 * whether *hectic* is the word they want, not opening a dictionary. So: the
 * phrase, one meaning, one example they can copy out loud. The full entry
 * (every sense, collocations, their own past sentences) is the notebook's job
 * and stays there.
 *
 * The lookup is `WordLore`, the same generated-once-and-shared entry the word
 * and expression cards read. It is free and globally cached, so a tap mid-call
 * costs nothing metered and usually resolves instantly.
 */
@androidx.compose.runtime.Composable
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
fun TalkGoalSheet(
    item: TalkGoalItem,
    /** Already said in this call — the sheet leads with that instead of
     *  asking for it again. */
    used: Boolean,
    nativeLanguage: String,
    targetLanguage: String,
    onDismiss: () -> Unit,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var entry by androidx.compose.runtime.remember {
        androidx.compose.runtime.mutableStateOf<com.roro.futurevoice.net.WordLore.Entry?>(null)
    }
    var loading by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(true) }

    androidx.compose.runtime.LaunchedEffect(item.key) {
        loading = true
        entry = com.roro.futurevoice.net.WordLore(com.roro.futurevoice.data.AuthRepository())
            .entry(item.text, nativeLanguage, targetLanguage,
                if (item.isWord) com.roro.futurevoice.net.WordLore.Kind.WORD
                else com.roro.futurevoice.net.WordLore.Kind.EXPRESSION)
        loading = false
    }

    androidx.compose.material3.ModalBottomSheet(onDismissRequest = onDismiss) {
        androidx.compose.foundation.layout.Column(
            Modifier.fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // The ask is not "repeat after me" — it's the word they chose to
            // study, and the call is where it gets spent.
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    if (used) Icons.Filled.CheckCircle
                    else Icons.Filled.ChatBubbleOutline,
                    contentDescription = null,
                    modifier = Modifier.size(15.dp),
                    tint = if (used) Color(0xFF34C759)
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    androidx.compose.ui.res.stringResource(
                        if (used) com.roro.futurevoice.R.string.you_used_it
                        else com.roro.futurevoice.R.string.use_this_in_the_call),
                    style = MaterialTheme.typography.labelMedium,
                    color = if (used) Color(0xFF34C759)
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(item.text, style = MaterialTheme.typography.headlineSmall)

            if (loading) {
                androidx.compose.material3.CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            } else {
                // ONE sense. A word carries several and the notebook card
                // shows them all; mid-call, the second sense is noise.
                entry?.senses?.firstOrNull()?.takeIf { it.meaning.isNotBlank() }?.let { sense ->
                    androidx.compose.foundation.layout.Column(
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        if (sense.pos.isNotBlank()) {
                            Text(sense.pos, style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text(sense.meaning, style = MaterialTheme.typography.bodyLarge)
                        sense.note?.takeIf { it.isNotBlank() }?.let {
                            Text(it, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                entry?.examples?.firstOrNull()?.takeIf { it.text.isNotBlank() }?.let { ex ->
                    androidx.compose.foundation.layout.Column(
                        Modifier.fillMaxWidth()
                            .background(MaterialTheme.colorScheme.surfaceVariant,
                                androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(ex.text, style = MaterialTheme.typography.bodyLarge)
                        ex.meaning?.takeIf { it.isNotBlank() }?.let {
                            Text(it, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}
