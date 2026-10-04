package com.roro.futurevoice.ui

import androidx.compose.animation.core.animateFloatAsState
import com.roro.futurevoice.ui.brand.ContinuousShape
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
import androidx.compose.material.icons.outlined.CheckCircle
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
    /** They already said they know this one; the call is what checks it.
     *  Drawn as an empty CHECKED circle, and dealt first. */
    val claimedKnown: Boolean = false,
    /** From a scenario book: the sentence its scene uses the item in, and
     *  the usage hint beside it. The chip sheet shows THAT line first — a
     *  word offered because of this scene is best explained by this scene. */
    val example: String? = null,
    val note: String? = null,
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
            vocab.practicedStudying(language), StudyScheduleStore.Kind.WORD, schedule, now,
        )
            .map {
                // A multi-word entry can land in the notebook (a learner taps
                // a two-word chunk in a transcript); it can't be lemma-matched,
                // so it goes through the phrase rules instead.
                TalkGoalItem(CarryoverDetector.normalized(it), it, isWord = !it.contains(" "))
            }
            .filter { it.isWord || CarryoverDetector.isCreditable(it.text) }

        // A claim is what the call is there to CHECK, so it goes in front of
        // the notebook: they said they know these and nothing has confirmed
        // it (iOS `4fc0068`).
        val claimed = (vocab.unconfirmedKnownExpressions(language)
            .filter { CarryoverDetector.isCreditable(it) }
            .map { TalkGoalItem(CarryoverDetector.normalized(it), it, isWord = false, claimedKnown = true) } +
            vocab.unconfirmedKnownWords(language)
                .map { TalkGoalItem(CarryoverDetector.normalized(it), it,
                    isWord = !it.contains(" "), claimedKnown = true) }
                .filter { it.isWord || CarryoverDetector.isCreditable(it.text) })

        // Interleave so the row opens with something short: a phrase first
        // would fill the visible width on its own and the words would only
        // exist for whoever scrolls.
        val out = ArrayList<TalkGoalItem>(limit)
        val seen = HashSet<String>()
        for (item in claimed) {
            if (out.size >= limit) break
            if (item.key.isEmpty() || !seen.add(item.key)) continue
            out.add(item)
        }
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
     * The row for a talk ON A SCENARIO BOOK: the book's own material first
     * (iOS `pick(forScenario:)`, `cb4252b`). Re-running one scene until it
     * comes out with confidence wants the words THAT scene taught:
     *
     * 1. the book's unmastered words and expressions, rotated by how many
     *    runs the scene has had so the fourth doesn't lead like the first;
     * 2. what the fluent self OFFERED in previous runs of the scene that the
     *    learner has never said;
     * 3. [pick] — the notebook — fills whatever is left, so a global phrase
     *    never takes a slot from a word this book still teaches.
     *
     * Book items ignore the deck's snooze on purpose: here the learner chose
     * the scene, and the scene is the reason to ask.
     */
    suspend fun pickForScenario(
        context: android.content.Context,
        language: String,
        scenario: com.roro.futurevoice.talk.Scenario,
        previousTalks: List<com.roro.futurevoice.talk.Session>,
        level: com.roro.futurevoice.data.CefrLevel,
        limit: Int = MAX_ITEMS,
    ): List<TalkGoalItem> {
        val vocab = VocabStore.shared(context)
        val runs = previousTalks.size
        fun bookItem(item: com.roro.futurevoice.talk.ScenarioCurriculum.Item) = TalkGoalItem(
            key = CarryoverDetector.normalized(item.text), text = item.text,
            isWord = com.roro.futurevoice.data.WordSplitter.count(item.text, language) <= 1,
            example = item.example, note = item.note.takeIf { it.isNotBlank() })
        val curriculum = scenario.curriculum
        val bookWords = rotated(runs, curriculum?.words.orEmpty().filter { it.masteredAt == null }.map(::bookItem))
            .filter { it.isWord || CarryoverDetector.isCreditable(it.text) }
        val bookPhrases = rotated(runs, curriculum?.expressions.orEmpty().filter { it.masteredAt == null }.map(::bookItem))
            .filter { CarryoverDetector.isCreditable(it.text) }

        val talks = previousTalks.sortedByDescending { it.startedAt }
        val offered = talks.flatMap { it.summary?.expressionsOffered.orEmpty() }
            .filter { !vocab.hasUsedExpression(it, language) && CarryoverDetector.isCreditable(it) }
            .map { TalkGoalItem(CarryoverDetector.normalized(it), it, isWord = false) }
        val fluentTexts = talks.flatMap { s -> s.turns.filter { it.role == com.roro.futurevoice.talk.TurnRole.FLUENT_SELF }.map { it.transcript } }
        val userLemmas = com.roro.futurevoice.data.VocabLemmas.lemmas(
            talks.flatMap { s -> s.turns.filter { it.role == com.roro.futurevoice.talk.TurnRole.USER }.map { it.transcript } }, language)
        val pickups = if (fluentTexts.isEmpty()) emptyList() else
            vocab.pickupCandidates(fluentTexts, level, language, excludingLemmas = userLemmas)
                .filter { vocab.state(it, language) == null }
                .map { TalkGoalItem(CarryoverDetector.normalized(it), it, isWord = true) }

        // The brief's key expressions lead the phrases (iOS `59c6481`): the
        // learner attached the posting for exactly this, and the phrases the
        // reading pulled out of it are what the call is there to try. Anything
        // already used in a talk has done its job and isn't asked for again.
        val briefPhrases = rotated(runs, scenario.brief?.keyExpressions.orEmpty()
            .filter { !vocab.hasUsedExpression(it, language) && CarryoverDetector.isCreditable(it) }
            .map { TalkGoalItem(CarryoverDetector.normalized(it), it,
                isWord = com.roro.futurevoice.data.WordSplitter.count(it, language) <= 1) })

        val out = merge(emptyList(), bookWords + pickups,
            (briefPhrases + bookPhrases + offered).take(MAX_EXPRESSIONS), limit)
        if (out.size < limit) {
            val seen = out.map { it.key }.toHashSet()
            for (item in pick(context, language, limit)) {
                if (out.size >= limit) break
                if (seen.add(item.key)) out.add(item)
            }
        }
        return out
    }

    /** Interleave so the row opens with something short — a phrase first
     *  fills the visible width on its own. */
    private fun merge(claimed: List<TalkGoalItem>, words: List<TalkGoalItem>,
                      phrases: List<TalkGoalItem>, limit: Int): MutableList<TalkGoalItem> {
        val out = ArrayList<TalkGoalItem>(limit)
        val seen = HashSet<String>()
        for (item in claimed) {
            if (out.size >= limit) break
            if (item.key.isEmpty() || !seen.add(item.key)) continue
            out.add(item)
        }
        val w = words.iterator(); val p = phrases.iterator()
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

    /** A book list shifted by the number of runs — each leads with a
     *  different slice of what's left. */
    private fun rotated(runs: Int, items: List<TalkGoalItem>): List<TalkGoalItem> {
        if (items.size <= 1) return items
        val offset = runs % items.size
        return items.drop(offset) + items.take(offset)
    }

    /**
     * Coach mode's extra pool (iOS `coachExtras`): notebook words a TALK kept
     * on its own that the chip row leaves out. The row is about what the
     * learner chose, but most notebooks fill this way, and a coach with
     * nothing to coach is a switch that does nothing (iOS device test,
     * 2026-09-28: eleven words on file, all auto-kept, no hint ever). These
     * are words the fluent self taught them — fair to steer toward.
     */
    suspend fun coachExtras(
        context: android.content.Context,
        language: String,
        excluding: Set<String>,
        now: Long = System.currentTimeMillis(),
    ): List<TalkGoalItem> {
        val vocab = VocabStore.shared(context)
        val practiced = vocab.practicedStudying(language).toSet()
        val schedule = StudyScheduleStore.shared(context).snapshot(language)
        return ordered(vocab.studying(language).filter { it !in practiced },
            StudyScheduleStore.Kind.WORD, schedule, now)
            .filter { com.roro.futurevoice.data.WordSplitter.isSingleWord(it, language) }
            .map { TalkGoalItem(CarryoverDetector.normalized(it), it, isWord = true) }
            .filter { it.key !in excluding }
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
            when {
                done -> Icons.Filled.CheckCircle
                // A claim wears an EMPTY checked circle: they said they know
                // it, and nothing has confirmed it yet.
                item.claimedKnown -> Icons.Outlined.CheckCircle
                else -> Icons.Outlined.Circle
            },
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
    // Capture build only: a stubbed entry instead of the lookup.
    val stub = com.roro.futurevoice.capture.flags.TalkCaptureFlags.stubGoalEntry
    var entry by androidx.compose.runtime.remember {
        androidx.compose.runtime.mutableStateOf<com.roro.futurevoice.net.WordLore.Entry?>(stub)
    }
    var loading by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(stub == null) }

    androidx.compose.runtime.LaunchedEffect(item.key) {
        if (stub != null) return@LaunchedEffect
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
                .bottomBarInsets()
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
                // The scene's own sentence (with its usage hint) when the chip
                // came out of a scenario book; the dictionary's line otherwise.
                val sceneLine = item.example?.takeIf { it.isNotBlank() }?.let { it to item.note }
                val dictLine = entry?.examples?.firstOrNull()?.takeIf { it.text.isNotBlank() }?.let { it.text to it.meaning }
                (sceneLine ?: dictLine)?.let { (exText, exMeaning) ->
                    androidx.compose.foundation.layout.Column(
                        Modifier.fillMaxWidth()
                            .background(MaterialTheme.colorScheme.surfaceVariant,
                                ContinuousShape(12.dp))
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(exText, style = MaterialTheme.typography.bodyLarge)
                        exMeaning?.takeIf { it.isNotBlank() }?.let {
                            Text(it, style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}
