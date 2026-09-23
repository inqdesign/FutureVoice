package com.roro.futurevoice.data

import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.ScenarioCurriculum
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole

/**
 * The review material of ONE finished talk — the same anatomy as a Watch
 * book's [ScenarioCurriculum], but DERIVED on demand, never persisted. Mastery
 * lives in `VocabStore` / `ShadowAttemptStore` / `DrillStore`, so old sessions
 * get a curriculum retroactively with no migration.
 */
object TalkCurriculum {

    /** How many pickup words one talk's book keeps. */
    const val MAX_WORDS = 24

    /** How many fluent-self lines a talk offers for shadowing. */
    const val MAX_SHADOW_LINES = 4

    const val SHADOW_MASTERY_SCORE = 80

    /**
     * ONE ITEM PER PIECE OF WORK THE BOOK ASKS FOR — the four lists are the
     * book's four study chapters, in page order (iOS 54, `29c8fe5`).
     *
     * It used to be two (words + the turn-suggestion corrections) while the
     * page offered four, so the Expressions chapter, the Shadow chapter and
     * every correction the SUMMARY produced counted for nothing, and a talk
     * finished itself the moment its words were ticked. Anything the page
     * asks for has to be in here.
     */
    data class Snapshot(
        val words: List<ScenarioCurriculum.Item> = emptyList(),
        val expressions: List<ScenarioCurriculum.Item> = emptyList(),
        /** The fluent self's lines to say back — the Shadow chapter. */
        val shadowLines: List<ScenarioCurriculum.Item> = emptyList(),
        /** The talk's corrections — the Drill chapter, studied as cards. */
        val corrections: List<ScenarioCurriculum.Item> = emptyList(),
    ) {
        private val all get() = words + expressions + shadowLines + corrections
        val totalCount: Int get() = all.size
        val masteredCount: Int get() = all.count { it.masteredAt != null }
        val progress: Double get() = if (totalCount == 0) 0.0 else masteredCount.toDouble() / totalCount
        val isMastered: Boolean get() = totalCount > 0 && masteredCount == totalCount
        /** Most recent mastery event — when this book was last studied. */
        val lastStudiedAt: Long? get() = all.mapNotNull { it.masteredAt }.maxOrNull()
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
            if (c !in ".!?。！？") continue
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
     * [correctionId] so the two can never collide.
     */
    fun sentenceLineId(turnId: String, index: Int): String =
        xorLastHexDigit(turnId, 0xA + (index and 0x0F))

    /** Stable id for a turn's CORRECTION — the same transform the
     *  transcript's suggestion-shadow uses, so attempts made from either
     *  surface land on the same line. (It was `shadowLineId` while the
     *  corrections WERE the curriculum's shadow lines.) */
    fun correctionId(turnId: String): String = xorFirstHexDigit(turnId)

    /** The turn a correction id was derived from (the transform is its own
     *  inverse). */
    fun turnIdOfCorrection(correctionId: String): String = xorFirstHexDigit(correctionId)

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
    ): Snapshot = build(
        session, level, language,
        pickups = vocab.pickupCandidates(
            session.turns.filter { it.role == TurnRole.FLUENT_SELF }.map { it.transcript },
            level, language,
            // What the LEARNER said in the same talk. The fluent self answers
            // about whatever they brought up, so its turns echo their own
            // vocabulary back — a word you already produce is not a pickup.
            excludingLemmas = VocabLemmas.lemmas(
                session.turns.filter { it.role == TurnRole.USER }.map { it.transcript })),
        wordLastAt = { vocab.lastAt(it, language) },
        expressionMasteredAt = { vocab.expressionMasteredAt(it, language) },
        attempts = attempts, drillCards = drillCards)

    /** The store-free core, so the chapter rules can be tested on the JVM. */
    internal suspend fun build(
        session: Session,
        level: CefrLevel,
        language: String,
        pickups: List<String>,
        wordLastAt: suspend (String) -> Long?,
        expressionMasteredAt: suspend (String) -> Long?,
        attempts: List<ShadowAttempt>,
        drillCards: List<DrillCard>,
    ): Snapshot {
        // Lemma membership, not a substring match: the pickup words ARE
        // lemmas, so this is the symmetric test. It credits inflected forms
        // ("went" masters "go") and survives languages that glue particles on.
        val userLemmas = VocabLemmas.lemmas(
            session.turns.filter { it.role == TurnRole.USER }.map { it.transcript })

        // Words. CANDIDATES, not pickupWords: the latter drops every word that
        // has a vocab record — exactly the ones since mastered — so the
        // chapter would shrink as you learned and sit at 0 forever.
        val words = pickups.take(MAX_WORDS).map { w ->
            val when_ = wordLastAt(w)
                ?: if (userLemmas.contains(w.trim().lowercase()))
                    (session.endedAt ?: session.startedAt) else null
            ScenarioCurriculum.Item(text = w, note = "", masteredAt = when_)
        }

        // Expressions — what the fluent self offered and what the learner
        // said, from the summary's RAW lists: a page that drops a phrase once
        // it is known can never read as finished. Mastered by the expression
        // pool (used in a talk, or "I know it").
        val sm = session.summary
        val credited = sm?.carryovers.orEmpty().map { CarryoverDetector.normalized(it.item) }.toSet()
        val seenExpressions = HashSet<String>()
        val expressions = ArrayList<ScenarioCurriculum.Item>()
        for (phrase in sm?.expressionsUsed.orEmpty() + sm?.expressionsOffered.orEmpty()) {
            val normalized = CarryoverDetector.normalized(phrase)
            if (phrase.isBlank() || normalized in credited || !seenExpressions.add(normalized)) continue
            expressions.add(ScenarioCurriculum.Item(text = phrase, note = "",
                masteredAt = expressionMasteredAt(phrase)))
        }

        // Shadow lines — exactly the lines the Shadow chapter offers
        // ([shadowPicks], so page and count can't ask for different things).
        // Mastered by a take at or above the bar and nothing else: shadowing
        // is the one chapter whose work can only be done out loud.
        val shadowLines = shadowPicks(session, level, language).map { turn ->
            ScenarioCurriculum.Item(id = turn.id, text = turn.transcript, note = "",
                masteredAt = bestTakeAt(attempts, turn.id))
        }

        // Corrections — every corrected sentence, in conversation order, then
        // the summary's own. Misheard-flagged turns are skipped: their
        // "correction" fixes a sentence the learner never said.
        val sessionCards = drillCards.filter { it.sourceSessionId == session.id }
        // Mastered by its drill card reaching the top box — the Drill chapter
        // studies corrections as CARDS — or by a shadow take on the line,
        // which the transcript still offers.
        fun masteryAt(text: String, turnId: String?, itemId: String): Long? {
            bestTakeAt(attempts, itemId)?.let { return it }
            val needle = CarryoverDetector.normalized(text)
            val card = sessionCards.firstOrNull {
                it.box >= DrillIngest.MAX_BOX &&
                    ((turnId != null && it.sourceTurnId == turnId) ||
                        CarryoverDetector.normalized(it.targetPhrase) == needle)
            } ?: return null
            return card.lastReviewedAt ?: card.createdAt
        }
        val seenCorrections = HashSet<String>()
        val corrections = ArrayList<ScenarioCurriculum.Item>()
        for (turn in session.turns) {
            if (turn.role != TurnRole.USER || turn.excludedFromScoring) continue
            val s = turn.suggestion ?: continue
            if (!seenCorrections.add(CarryoverDetector.normalized(s.alternative))) continue
            val id = correctionId(turn.id)
            corrections.add(ScenarioCurriculum.Item(id = id, text = s.alternative, note = s.reason,
                masteredAt = masteryAt(s.alternative, turn.id, id)))
        }
        // The summary's corrections carry a card each and the Drill chapter
        // has always listed them — they just never counted, which is most of
        // how a book finished itself with the chapter untouched.
        for (p in sm?.phrasesUsed.orEmpty()) {
            if (!seenCorrections.add(CarryoverDetector.normalized(p.fluentAlternative))) continue
            val item = ScenarioCurriculum.Item(text = p.fluentAlternative, note = p.reason)
            corrections.add(item.copy(masteredAt = masteryAt(p.fluentAlternative, null, item.id)))
        }

        return Snapshot(words, expressions, shadowLines, corrections)
    }

    private fun bestTakeAt(attempts: List<ShadowAttempt>, lineId: String): Long? =
        attempts.filter { it.turnId == lineId && !it.isPartial &&
            it.matchScore >= SHADOW_MASTERY_SCORE }
            .maxOfOrNull { it.createdAt }
}
