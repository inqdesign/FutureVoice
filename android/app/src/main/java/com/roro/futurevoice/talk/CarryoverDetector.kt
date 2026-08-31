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
            val hit = firstMatch(card.targetPhrase, userTurns) ?: continue
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

        // ── Suggestions from earlier in THIS call, applied later in it.
        for ((index, turn) in userTurns.withIndex()) {
            val suggestion = turn.suggestion ?: continue
            val later = userTurns.drop(index + 1)
            if (later.isEmpty()) continue
            val key = normalized(suggestion.alternative)
            if (!available(key)) continue
            // Already saying it in the turn that EARNED the suggestion isn't adoption.
            if (firstMatch(suggestion.alternative, listOf(turn)) != null) continue
            val hit = firstMatch(suggestion.alternative, later) ?: continue
            if (!free(hit)) continue
            claim(key, hit, Carryover.Source.SUGGESTION, suggestion.alternative, turn.id)
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
        for (entry in wordHits.sortedByDescending { it.rank }.take(MAX_WORD_CARRYOVERS)) {
            out.add(Carryover(id = StoreJson.newId(), sessionId = sessionId,
                source = Carryover.Source.STUDYING_WORD, item = entry.word,
                quote = entry.hit.quote, turnId = entry.hit.turnId, sourceId = null, detectedAt = now))
        }
        return out
    }

    // MARK: - Matching

    fun firstMatch(item: String, userTurns: List<Turn>): Hit? {
        val needle = tokens(item)
        val core = contentTokens(item)
        if (needle.size < MIN_TOKENS || core.size < MIN_CONTENT_TOKENS) return null
        for (turn in userTurns) {
            if (!contains(needle, core, tokens(turn.transcript))) continue
            return Hit(DrillIngest.relevantFragment(turn.transcript, item), turn.id)
        }
        return null
    }

    fun isCreditable(phrase: String): Boolean =
        tokens(phrase).size >= MIN_TOKENS && contentTokens(phrase).size >= MIN_CONTENT_TOKENS

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
    private fun contains(needle: List<String>, core: List<String>, hay: List<String>): Boolean {
        if (needle.isEmpty() || hay.size < MIN_TOKENS) return false
        val window = needle.size * 2 + 4
        val required = Math.ceil(needle.size * MIN_COVERAGE).toInt()
        if (hay.size < required) return false
        for (start in 0..(hay.size - required)) {
            val slice = hay.subList(start, minOf(hay.size, start + window))
            if (lcsLength(needle, slice) < required) continue
            if (lcsLength(core, slice.filter { it !in FILLER }) != core.size) continue
            return true
        }
        return false
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
