package com.roro.futurevoice.data

import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole

/**
 * Today's shadow hand: which of the fluent self's lines to say back.
 *
 * A dealt HAND, not a browser — the same rule the word and expression decks
 * follow. Opening a list of everything ever said and asking the learner to
 * choose is a decision they have no basis for making; a hand of three is a
 * thing you can finish.
 */
object ShadowPicks {

    /** Anything shorter teaches nothing to say back. */
    private const val MIN_WORDS = 4

    /** Score under which a past attempt earns another go. */
    const val RETRY_THRESHOLD = 75

    data class Pick(val turn: Turn, val reason: String)

    /**
     * Word-count band per level. A beginner shadowing a 20-word sentence
     * drowns; a C1 learner repeating 4-word lines learns nothing. Length is a
     * crude but deterministic difficulty proxy — the lines all come from
     * level-calibrated conversations anyway, so length is the main residual
     * variance.
     */
    fun wordBand(level: CefrLevel): IntRange = when (level) {
        CefrLevel.A1 -> 4..8
        CefrLevel.A2 -> 4..10
        CefrLevel.B1 -> 5..14
        CefrLevel.B2 -> 6..18
        CefrLevel.C1, CefrLevel.C2 -> 8..40
    }

    /**
     * How much a line teaches at the learner's level: how many of its words
     * are graded AT or ABOVE their level in the core list. Greetings and
     * small talk score ~0 and sink to the bottom.
     */
    fun lexicalValue(text: String, level: CefrLevel, language: String): Int {
        val learner = level.ordinal
        return text.lowercase().split(Regex("[^\\p{L}\\p{N}'-]+"))
            .filter { it.isNotBlank() }
            .count { w -> (CoreVocabulary.level(w, language)?.ordinal ?: -1) >= learner }
    }

    fun pick(
        sessions: List<Session>,
        attempts: List<ShadowAttempt>,
        level: CefrLevel,
        language: String,
        limit: Int = 3,
    ): List<Pick> {
        // Latest attempt per target line.
        val latestByTurn = HashMap<String, ShadowAttempt>()
        for (a in attempts) {
            val existing = latestByTurn[a.turnId]
            if (existing != null && existing.createdAt >= a.createdAt) continue
            latestByTurn[a.turnId] = a
        }

        data class Candidate(val pick: Pick, val sessionIndex: Int, val value: Int)
        val band = wordBand(level)
        val banded = ArrayList<Candidate>()
        val fallback = ArrayList<Candidate>()
        val openers = ArrayList<Candidate>()
        val seen = HashSet<String>()

        val newestFirst = sessions.sortedByDescending { it.endedAt ?: it.startedAt }
        newestFirst.forEachIndexed { sessionIndex, session ->
            val openerId = session.turns.firstOrNull { it.role == TurnRole.FLUENT_SELF }?.id
            for (turn in session.turns) {
                if (turn.role != TurnRole.FLUENT_SELF) continue
                val text = turn.transcript.trim()
                val key = text.lowercase()
                val words = text.split(Regex("\\s+")).count { it.isNotBlank() }
                if (text.isEmpty() || words < MIN_WORDS) continue
                if (latestByTurn.containsKey(turn.id) || !seen.add(key)) continue
                val c = Candidate(
                    Pick(turn, session.topic?.takeIf { it.isNotBlank() } ?: ""),
                    sessionIndex, lexicalValue(text, level, language))
                when {
                    turn.id == openerId -> openers.add(c)
                    words in band -> banded.add(c)
                    else -> fallback.add(c)
                }
            }
        }

        // Newest session first, then the most teachable line within it.
        fun ranked(list: List<Candidate>) = list
            .sortedWith(compareBy<Candidate> { it.sessionIndex }.thenByDescending { it.value })
            .map { it.pick }

        // Openers are the tier of LAST resort — "how's it going?" is the same
        // line every call and teaches nothing.
        val fresh = when {
            banded.isNotEmpty() -> ranked(banded)
            fallback.isNotEmpty() -> ranked(fallback)
            else -> ranked(openers)
        }

        // Retries: the latest attempt scored low. Reuse the original turn when
        // it still exists so past attempts stay attached; otherwise rebuild
        // from the text the attempt captured.
        val turnById = sessions.flatMap { it.turns }.associateBy { it.id }
        val retries = latestByTurn.values
            .filter { it.matchScore < RETRY_THRESHOLD }
            .sortedByDescending { it.createdAt }
            .map { a ->
                val turn = turnById[a.turnId] ?: Turn(
                    id = a.turnId, role = TurnRole.FLUENT_SELF, transcript = a.targetText,
                    timestamp = a.createdAt)
                Pick(turn, "retry:${a.matchScore}")
            }

        // At most one retry crowds out a fresh line — the hand should still
        // mostly be new material.
        val out = fresh.take((limit - minOf(1, retries.size)).coerceAtLeast(0)).toMutableList()
        for (r in retries) { if (out.size >= limit) break; out.add(r) }
        for (f in fresh) { if (out.size >= limit) break; if (f !in out) out.add(f) }
        return out
    }
}
