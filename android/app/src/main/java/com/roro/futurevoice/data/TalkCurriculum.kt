package com.roro.futurevoice.data

import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.ScenarioCurriculum
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole

/**
 * The review material of ONE finished talk — the same anatomy as a Watch
 * book's [ScenarioCurriculum] (words to master + lines to shadow), but
 * DERIVED on demand, never persisted:
 *
 *  - words → the fluent self's pickup words (words it used that the learner
 *    hasn't), mastered through [VocabStore] exactly like a scenario word
 *  - shadow lines → the corrected versions of the learner's own sentences
 *    (`Turn.suggestion`), mastered by a shadow attempt scoring at least
 *    [SHADOW_MASTERY_SCORE], or by the correction's drill card reaching the
 *    top Leitner box (the book page studies corrections as CARDS, so the
 *    card's "Got it" has to be able to finish the book)
 *
 * Deriving instead of storing keeps ONE source of truth: mastery lives in
 * `VocabStore` / `ShadowAttemptStore`, and old sessions get a curriculum
 * retroactively with no migration.
 */
object TalkCurriculum {

    /** How many pickup words one talk's book keeps. */
    const val MAX_WORDS = 24

    /** How many fluent-self lines a talk offers for shadowing. */
    const val MAX_SHADOW_LINES = 4

    const val SHADOW_MASTERY_SCORE = 80

    data class Snapshot(
        val words: List<ScenarioCurriculum.Item> = emptyList(),
        val shadowLines: List<ScenarioCurriculum.Item> = emptyList(),
    ) {
        val totalCount: Int get() = words.size + shadowLines.size
        val masteredCount: Int get() = (words + shadowLines).count { it.masteredAt != null }
        val progress: Double get() = if (totalCount == 0) 0.0 else masteredCount.toDouble() / totalCount
        val isMastered: Boolean get() = totalCount > 0 && masteredCount == totalCount
        /** Most recent mastery event — when this book was last studied. */
        val lastStudiedAt: Long? get() = (words + shadowLines).mapNotNull { it.masteredAt }.maxOrNull()
    }

    /**
     * Split a spoken turn into the sentences it is made of.
     *
     * Deliberately naive — terminal punctuation only. The text is
     * model-written speech, not prose with abbreviations and decimals, and a
     * bad split produces a fragment the 4-word floor throws away.
     */
    fun sentences(text: String): List<String> {
        val out = ArrayList<String>()
        val current = StringBuilder()
        for (c in text) {
            current.append(c)
            if (c !in ".!?") continue
            val piece = current.toString().trim()
            if (piece.isNotEmpty()) out.add(piece)
            current.setLength(0)
        }
        current.toString().trim().takeIf { it.isNotEmpty() }?.let { out.add(it) }
        return out
    }

    /**
     * Stable id for one sentence of a turn, so a shadow attempt made today is
     * still recognised tomorrow. Derived off a DIFFERENT byte than
     * [shadowLineId] so the two can never collide.
     */
    fun sentenceLineId(turnId: String, index: Int): String =
        xorLastHexDigit(turnId, 0xA + (index and 0x0F))

    /** Stable shadow-line id derived from the source turn — the same
     *  transform the transcript's suggestion-shadow uses, so attempts made
     *  from either surface land on the same line. */
    fun shadowLineId(turnId: String): String = xorFirstHexDigit(turnId)

    private fun xorFirstHexDigit(id: String): String {
        val i = id.indexOfFirst { it.isLetterOrDigit() }
        if (i < 0) return id
        val v = Character.digit(id[i], 16)
        if (v < 0) return id
        return id.substring(0, i) + Integer.toHexString(v xor 0xF).uppercase() + id.substring(i + 1)
    }

    private fun xorLastHexDigit(id: String, mask: Int): String {
        val i = id.indexOfLast { it.isLetterOrDigit() }
        if (i < 0) return id
        val v = Character.digit(id[i], 16)
        if (v < 0) return id
        return id.substring(0, i) + Integer.toHexString(v xor mask).uppercase() + id.substring(i + 1)
    }

    /**
     * The fluent-self SENTENCES worth shadowing, in conversation order.
     *
     * The unit is a SENTENCE, not a turn, and that is the point: the fluent
     * self speaks long turns, so whole-turn candidates drop the substantive
     * middle of the call and keep the short ritual lines.
     *
     * "Worth" means the learner could say it again somewhere else. Two things
     * decide that, in order: a line carrying one of the summary's
     * `expressionsOffered` (already picked and verified) outranks everything;
     * then core-list lemmas AT or ABOVE the learner's level. Below-level
     * lemmas score nothing — counting them is exactly how "So nice to talk to
     * you today!" beats the middle of the call.
     *
     * The opener and farewell are excluded by POSITION — they are ritual, not
     * material, and no word list can see that — unless nothing else scores.
     */
    fun shadowPicks(session: Session, level: CefrLevel, language: String): List<Turn> {
        val fluent = session.turns.filter { it.role == TurnRole.FLUENT_SELF }
        val edgeIds = setOfNotNull(fluent.firstOrNull()?.id, fluent.lastOrNull()?.id)
        val offered = (session.summary?.expressionsOffered ?: emptyList())
            .map { CarryoverDetector.normalized(it) }.filter { it.isNotEmpty() }
        val minRank = CoreVocabulary.levelRank(level)

        fun teachScore(text: String): Int {
            var total = 0
            val line = " " + CarryoverDetector.normalized(text) + " "
            for (p in offered) if (line.contains(" $p ")) total += 3
            for (lemma in VocabLemmas.lemmas(listOf(text))) {
                val lv = CoreVocabulary.level(lemma, language) ?: continue
                if (CoreVocabulary.levelRank(lv) >= minRank) total += 1
            }
            return total
        }

        data class Candidate(val index: Int, val turn: Turn, val isEdge: Boolean)
        val candidates = ArrayList<Candidate>()
        val seen = HashSet<String>()
        for (turn in fluent) {
            val parts = sentences(turn.transcript)
            parts.forEachIndexed { offset, sentence ->
                val words = sentence.split(Regex("\\s+")).count { it.isNotBlank() }
                if (words !in 4..28) return@forEachIndexed
                // The fluent self repeats itself across a call; a chapter that
                // asks for the same line twice wastes a slot.
                if (!seen.add(CarryoverDetector.normalized(sentence))) return@forEachIndexed
                // A turn that IS one sentence keeps its own identity: its
                // recorded audio still matches, and any attempt already made
                // against it still counts.
                val piece = if (parts.size == 1) turn
                else turn.copy(id = sentenceLineId(turn.id, offset), transcript = sentence)
                candidates.add(Candidate(candidates.size, piece, turn.id in edgeIds))
            }
        }

        var scored = candidates.filter { !it.isEdge }
            .map { it to teachScore(it.turn.transcript) }.filter { it.second > 0 }
        if (scored.isEmpty()) {
            scored = candidates.filter { it.isEdge }
                .map { it to teachScore(it.turn.transcript) }.filter { it.second > 0 }
        }
        if (scored.isEmpty()) {
            // Nothing scoreable at all — fall back to the last substantive
            // lines so the chapter never goes empty.
            val middle = candidates.filter { !it.isEdge }.map { it.turn }
            val pool = middle.ifEmpty { candidates.map { it.turn } }
            return pool.takeLast(MAX_SHADOW_LINES)
        }
        return scored
            .sortedWith(compareByDescending<Pair<Candidate, Int>> { it.second }
                .thenBy { it.first.index })
            .take(MAX_SHADOW_LINES)
            .sortedBy { it.first.index }
            .map { it.first.turn }
    }

    suspend fun build(
        session: Session,
        level: CefrLevel,
        language: String,
        vocab: VocabStore,
        attempts: List<ShadowAttempt>,
        drillCards: List<DrillCard>,
    ): Snapshot {
        // Lemma membership, not a substring match: the pickup words ARE
        // lemmas, so this is the symmetric test. It credits inflected forms
        // ("went" masters "go") and survives languages that glue particles on.
        val userLemmas = VocabLemmas.lemmas(
            session.turns.filter { it.role == TurnRole.USER }.map { it.transcript })

        // CANDIDATES, not pickupWords: the latter drops every word that has a
        // vocab record — i.e. exactly the ones the learner has since mastered
        // — so the chapter would shrink as you learned and sit at 0 forever.
        val pickups = vocab.pickupCandidates(
            session.turns.filter { it.role == TurnRole.FLUENT_SELF }.map { it.transcript },
            level, language).take(MAX_WORDS)

        val words = pickups.map { w ->
            val when_ = vocab.lastAt(w, language)
                ?: if (userLemmas.contains(w.trim().lowercase()))
                    (session.endedAt ?: session.startedAt) else null
            ScenarioCurriculum.Item(text = w, note = "", masteredAt = when_)
        }

        // Shadow lines — every corrected sentence, in conversation order.
        // Misheard-flagged turns are skipped: their "correction" fixes a
        // sentence the learner never said.
        val sessionCards = drillCards.filter { it.sourceSessionId == session.id }
        val lines = ArrayList<ScenarioCurriculum.Item>()
        for (turn in session.turns) {
            if (turn.role != TurnRole.USER || turn.excludedFromScoring) continue
            val s = turn.suggestion ?: continue
            val id = shadowLineId(turn.id)
            var masteredAt = attempts
                .filter { it.turnId == id && it.matchScore >= SHADOW_MASTERY_SCORE }
                .maxOfOrNull { it.createdAt }
            if (masteredAt == null) {
                // The book page studies corrections as drill CARDS, so a card
                // in the top box masters the line — otherwise the cover counts
                // work no chapter offers.
                val needle = CarryoverDetector.normalized(s.alternative)
                val card = sessionCards.firstOrNull {
                    it.box >= DrillIngest.MAX_BOX &&
                        (it.sourceTurnId == turn.id ||
                            CarryoverDetector.normalized(it.targetPhrase) == needle)
                }
                masteredAt = card?.let { it.lastReviewedAt ?: it.createdAt }
            }
            lines.add(ScenarioCurriculum.Item(
                id = id, text = s.alternative, note = s.reason, masteredAt = masteredAt))
        }

        return Snapshot(words = words, shadowLines = lines)
    }
}
