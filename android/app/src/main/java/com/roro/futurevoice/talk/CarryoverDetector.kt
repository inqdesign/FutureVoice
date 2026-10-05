package com.roro.futurevoice.talk

import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.DrillIngest
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.VocabLemmas

/**
 * Port of `CarryoverDetector.swift` — catches the moment a learner PRODUCES
 * something they'd been studying, inside a real conversation. Deterministic
 * on purpose (no LLM; a single false positive poisons every number on the
 * page), verified against `docs/contracts/vectors/summary-ingestion.json`.
 * Every rule errs toward missing a hit rather than inventing one.
 */
object CarryoverDetector {

    const val MIN_TOKENS = 3
    const val MIN_CONTENT_TOKENS = 2
    const val MIN_COVERAGE = 0.8
    const val MAX_WORD_CARRYOVERS = 5

    data class CurriculumItem(val id: String, val text: String, val isWord: Boolean)

    data class Hit(val quote: String, val turnId: String)

    fun detect(
        turns: List<Turn>,
        cards: List<DrillCard>,
        curriculumItems: List<CurriculumItem> = emptyList(),
        studyingExpressions: List<String> = emptyList(),
        studyingWords: List<String> = emptyList(),
        /**
         * Claimed but unconfirmed — "I know it" on a notebook item, never yet
         * produced in a talk. A claim is what a call is there to CHECK, so
         * saying it here is worth as much as spending a studying item (iOS
         * `4fc0068`).
         */
        knownWords: List<String> = emptyList(),
        knownExpressions: List<String> = emptyList(),
        sessionId: String,
        sessionStartedAt: Long,
        language: String = "en",
        now: Long = System.currentTimeMillis(),
    ): List<Carryover> {
        val userTurns = turns.filter { it.role == TurnRole.USER && !it.excludedFromScoring }
        if (userTurns.isEmpty()) return emptyList()

        val out = mutableListOf<Carryover>()
        val claimed = HashSet<String>()      // one item, one credit per session
        val creditedTurns = HashSet<String>() // one SENTENCE, one credit

        fun claim(key: String, hit: Hit, source: Carryover.Source, item: String, sourceId: String?) {
            claimed.add(key); creditedTurns.add(hit.turnId)
            out.add(Carryover(id = StoreJson.newId(), sessionId = sessionId, source = source,
                item = item, quote = hit.quote, turnId = hit.turnId, sourceId = sourceId, detectedAt = now))
        }
        fun available(key: String) = key.isNotEmpty() && key !in claimed
        fun free(hit: Hit) = hit.turnId !in creditedTurns

        // ── Cards from earlier talks, said unprompted today.
        for (card in cards) {
            if (card.sourceSessionId == sessionId || card.createdAt >= sessionStartedAt) continue
            val key = normalized(card.targetPhrase)
            if (!available(key)) continue
            // Repeating the card's mistake inside a match is no credit — and
            // under used-outranks-known it would retire the card as confirmed.
            val hit = firstMatch(card.targetPhrase, userTurns,
                rejectingMistake = card.sourcePhrase.takeIf { it.isNotBlank() }) ?: continue
            if (!free(hit)) continue
            claim(key, hit, Carryover.Source.DRILL_CARD, card.targetPhrase, card.id)
        }

        // ── Material from a Watch book, produced in a live talk.
        for (item in curriculumItems) {
            val key = normalized(item.text)
            if (!available(key)) continue
            val hit = (if (item.isWord) firstLemmaMatch(key, userTurns) else firstMatch(item.text, userTurns))
                ?: continue
            if (!free(hit)) continue
            claim(key, hit, Carryover.Source.CURRICULUM_ITEM, item.text, item.id)
        }

        // ── Phrases deliberately bookmarked, then said.
        for (phrase in studyingExpressions) {
            val key = normalized(phrase)
            if (!available(key)) continue
            val hit = firstMatch(phrase, userTurns) ?: continue
            if (!free(hit)) continue
            claim(key, hit, Carryover.Source.STUDYING_EXPRESSION, phrase, null)
        }

        // ── Phrases they SAID they knew, now said out loud: the claim
        // confirmed. Same shape as a bookmarked phrase, different source, so
        // the wrap-up can tell "you used what you saved" from "you proved
        // what you claimed".
        for (phrase in knownExpressions) {
            val key = normalized(phrase)
            if (!available(key)) continue
            val hit = firstMatch(phrase, userTurns) ?: continue
            if (!free(hit)) continue
            claim(key, hit, Carryover.Source.KNOWN_EXPRESSION, phrase, null)
        }

        // ── Suggestions from earlier in THIS call, applied later in it.
        for ((index, turn) in userTurns.withIndex()) {
            val suggestion = turn.suggestion ?: continue
            val later = userTurns.drop(index + 1)
            if (later.isEmpty()) continue
            // Since the two-answer contract `alternative` is the WHOLE turn
            // re-said — nobody repeats a whole turn verbatim, so matching it
            // would credit nothing. What can be adopted is a FIX, matched as
            // the card it became and rejecting a span that still carries the
            // mistake. Older turns keep the old one-sentence rule.
            val adoptable: List<Pair<String?, String>> = suggestion.fixes?.map { fix ->
                val (source, target) = DrillIngest.cardPair(fix, turn.transcript)
                source to target
            } ?: listOf(null to suggestion.alternative)
            for ((source, target) in adoptable) {
                val key = normalized(target)
                if (!available(key)) continue
                // Already saying it in the turn that EARNED it isn't adoption.
                if (firstMatch(target, listOf(turn), rejectingMistake = source) != null) continue
                val hit = firstMatch(target, later, rejectingMistake = source) ?: continue
                if (!free(hit)) continue
                claim(key, hit, Carryover.Source.SUGGESTION, target, turn.id)
            }
        }

        // ── Notebook words, by lemma; skipped inside credited phrases; hardest
        // first, display-capped.
        val claimedWords = claimed.flatMap { it.split(' ') }.toHashSet()
        data class WordHit(val word: String, val hit: Hit, val rank: Int)
        val wordHits = mutableListOf<WordHit>()
        for (word in studyingWords) {
            val key = normalized(word)
            if (key.isEmpty() || key in claimedWords) continue
            val hit = firstLemmaMatch(key, userTurns) ?: continue
            if (hit.turnId in creditedTurns) continue
            val rank = CoreVocabulary.level(key, language)?.let { CoreVocabulary.levelRank(it) } ?: 0
            wordHits.add(WordHit(key, hit, rank))
        }
        val emittedWords = HashSet<String>()
        for (entry in wordHits.sortedByDescending { it.rank }.take(MAX_WORD_CARRYOVERS)) {
            emittedWords.add(entry.word)
            out.add(Carryover(id = StoreJson.newId(), sessionId = sessionId,
                source = Carryover.Source.STUDYING_WORD, item = entry.word,
                quote = entry.hit.quote, turnId = entry.hit.turnId, sourceId = null, detectedAt = now))
            creditedTurns.add(entry.hit.turnId)
        }

        // ── Words they SAID they knew, now said out loud. Last, and never
        // for a word the notebook already credited: one item, one credit.
        val knownHits = mutableListOf<WordHit>()
        for (word in knownWords) {
            val key = normalized(word)
            if (key.isEmpty() || key in claimedWords || key in emittedWords) continue
            val hit = firstLemmaMatch(key, userTurns) ?: continue
            if (hit.turnId in creditedTurns) continue
            val rank = CoreVocabulary.level(key, language)?.let { CoreVocabulary.levelRank(it) } ?: 0
            knownHits.add(WordHit(key, hit, rank))
        }
        for (entry in knownHits.sortedByDescending { it.rank }.take(MAX_WORD_CARRYOVERS)) {
            out.add(Carryover(id = StoreJson.newId(), sessionId = sessionId,
                source = Carryover.Source.KNOWN_WORD, item = entry.word,
                quote = entry.hit.quote, turnId = entry.hit.turnId, detectedAt = now))
            creditedTurns.add(entry.hit.turnId)
        }
        return out
    }

    // MARK: - Matching

    /**
     * The first user turn that says [item]. With [rejectingMistake] (the
     * card's own source line) a match that still CARRIES the mistake is no
     * credit: the matcher tolerates inserted words, so "give me a feedback"
     * satisfied the card "give me feedback" — the learner repeated the exact
     * mistake and was credited (iOS 2026-09-16, `showsTheFix`).
     */
    fun firstMatch(item: String, userTurns: List<Turn>, rejectingMistake: String? = null,
                   language: String? = CoreVocabulary.activeLanguage()): Hit? {
        val korean = language == "ko"
        // Korean (iOS bee9052d): an expression is credited whether it was
        // said with the polite 요 or without — the speech level is the
        // learner's, the expression is the same. Never for a correction card:
        // there the speech level can be the fix itself.
        val politeFree = korean && rejectingMistake == null
        val needle = tokens(item).map { if (politeFree) strippingPolite(it) else it }
        val core = if (politeFree) needle else contentTokens(item)
        if (needle.size < minTokens(language) || core.size < minContentTokens(language)) return null
        val koreanNeedle = if (korean) koreanKey(item, politeFree) else ""
        if (korean && koreanNeedle.length < MIN_KOREAN_SYLLABLES) return null
        for (turn in userTurns) {
            val hay = tokens(turn.transcript).map { if (politeFree) strippingPolite(it) else it }
            val span = matchedSpan(needle, core, hay, minTokens(language))
            if (span != null) {
                if (rejectingMistake != null && !showsTheFix(rejectingMistake, item, span)) continue
            } else if (korean && koreanKey(turn.transcript, politeFree).contains(koreanNeedle)) {
                // Same syllables, spaced differently. The match is the phrase
                // itself, contiguous — a correction's fix is in it by
                // construction and its mistake cannot be.
            } else {
                continue
            }
            return Hit(DrillIngest.relevantFragment(turn.transcript, item), turn.id)
        }
        return null
    }

    /** Every token the correction ADDED is in the span; every one it REMOVED is not. */
    fun showsTheFix(source: String, target: String, span: List<String>): Boolean {
        val before = tokens(source); val after = tokens(target)
        if (before.isEmpty() || before == after) return true
        val added = after.toSet() - before.toSet()
        val removed = before.toSet() - after.toSet()
        val said = span.toSet()
        return said.containsAll(added) && removed.none { it in said }
    }

    fun isCreditable(phrase: String, language: String? = CoreVocabulary.activeLanguage()): Boolean =
        tokens(phrase).size >= minTokens(language) && contentTokens(phrase).size >= minContentTokens(language) &&
            (language != "ko" || koreanKey(phrase, politeFree = false).length >= MIN_KOREAN_SYLLABLES)

    /**
     * Korean takes a floor of one word instead of three (iOS `bee9052d`): an
     * eojeol is a word WITH its particles and endings, so a two-eojeol phrase
     * is a whole expression (잘 모르겠어, 그럴 리가) and the three-word bar
     * left most Korean expressions uncreditable. Its floor is
     * [MIN_KOREAN_SYLLABLES] instead — and there is no filler list, so every
     * eojeol must land, in order.
     */
    private fun minTokens(language: String?) = if (language == "ko") 1 else MIN_TOKENS
    private fun minContentTokens(language: String?) = if (language == "ko") 1 else MIN_CONTENT_TOKENS

    /** Shortest Korean phrase worth crediting, in syllables (spaces ignored).
     *  잘 가 (2) is small talk; 그러게 / 잘 모르겠어 are not. */
    const val MIN_KOREAN_SYLLABLES = 3

    /** A Korean phrase as one comparable string: tokens joined with NO space,
     *  because 띄어쓰기 is the recognizer's (할수 있어 / 할 수 있어). */
    private fun koreanKey(text: String, politeFree: Boolean): String =
        tokens(text).joinToString("") { if (politeFree) strippingPolite(it) else it }

    private fun strippingPolite(token: String): String =
        if (token.length > 1 && token.endsWith("요")) token.dropLast(1) else token

    fun firstLemmaMatch(lemma: String, userTurns: List<Turn>): Hit? {
        for (turn in userTurns) {
            if (lemma !in VocabLemmas.lemmas(listOf(turn.transcript))) continue
            return Hit(DrillIngest.relevantFragment(turn.transcript, lemma), turn.id)
        }
        return null
    }

    /**
     * In-order coverage inside a bounded window; EVERY content word must land
     * in order (function words may slip — that's what [MIN_COVERAGE] is for).
     */
    private fun matchedSpan(needle: List<String>, core: List<String>, hay: List<String>,
                            minHay: Int = MIN_TOKENS): List<String>? {
        if (needle.isEmpty() || hay.size < minHay) return null
        val window = needle.size * 2 + 4
        val required = Math.ceil(needle.size * MIN_COVERAGE).toInt()
        if (hay.size < required) return null
        for (start in 0..(hay.size - required)) {
            val slice = hay.subList(start, minOf(hay.size, start + window))
            if (lcsLength(needle, slice) < required) continue
            if (lcsLength(core, slice.filter { it !in FILLER }) != core.size) continue
            // Trim to the phrase: from where its first word lands to its last.
            val lo = slice.indexOf(needle.first()).takeIf { it >= 0 } ?: 0
            val hi = slice.lastIndexOf(needle.last()).takeIf { it >= 0 }?.let { maxOf(it, lo) } ?: (slice.size - 1)
            return slice.subList(lo, hi + 1)
        }
        return null
    }

    /** Longest common subsequence length. */
    private fun lcsLength(a: List<String>, b: List<String>): Int {
        if (a.isEmpty() || b.isEmpty()) return 0
        var prev = IntArray(b.size + 1)
        for (i in 1..a.size) {
            val cur = IntArray(b.size + 1)
            for (j in 1..b.size) {
                cur[j] = if (a[i - 1] == b[j - 1]) prev[j - 1] + 1 else maxOf(prev[j], cur[j - 1])
            }
            prev = cur
        }
        return prev[b.size]
    }

    // MARK: - Tokenizing

    /** Same normalization DrillIngest matches quotes with. */
    fun normalized(text: String): String =
        text.filter { it.isLetterOrDigit() || it.isWhitespace() }
            .lowercase().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")

    private fun tokens(text: String): List<String> =
        normalized(text).split(' ').filter { it.isNotEmpty() }

    private fun contentTokens(text: String): List<String> =
        tokens(text).filter { it !in FILLER }

    /** English-only by design — for other targets nothing is dropped. */
    private val FILLER = setOf(
        "a", "an", "the", "and", "or", "but", "so", "if", "of", "to", "in", "on",
        "at", "for", "with", "is", "am", "are", "was", "were", "be", "been",
        "do", "does", "did", "have", "has", "had", "i", "you", "he", "she", "it",
        "we", "they", "me", "him", "her", "them", "my", "your", "its", "that",
        "this", "there", "as", "by", "from", "im", "ive", "id", "ill", "its",
        "dont", "doesnt", "didnt", "youre", "youve", "well", "just", "very",
    )
}
