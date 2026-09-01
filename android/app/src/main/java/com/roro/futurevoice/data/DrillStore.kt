package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.SessionSummary
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/**
 * The PURE half of `DrillStore.swift` — minting, fragments, meta-rule guard,
 * Leitner intervals — kept free of files so the golden-vector tests run it
 * directly. [DrillStore] below is the disk half.
 */
object DrillIngest {

    /** Top Leitner rung — box-5 cards are "learned" (30-day interval). */
    const val MAX_BOX = 5

    /** Leitner interval per box, in milliseconds. Box 0 stays due immediately. */
    fun intervalMs(box: Int): Long {
        val days = when (box) { 0 -> 0L; 1 -> 1L; 2 -> 3L; 3 -> 7L; 4 -> 14L; else -> 30L }
        return days * 24 * 60 * 60 * 1000
    }

    /**
     * `DrillStore.ingest`'s card construction: per-turn suggestions, phrase
     * feedback, detected patterns, explicit drills — deduped (normalized)
     * against existing cards and each other, meta-rules dropped, quotes
     * traced back to their turn.
     */
    fun mint(existing: List<DrillCard>, summary: SessionSummary, turns: List<Turn>,
             sessionId: String, now: Long): List<DrillCard> {
        val seenTargets = existing.map { normalizedForMatch(it.targetPhrase) }.toHashSet()
        val newCards = mutableListOf<DrillCard>()
        val userTurns = turns.filter { it.role == TurnRole.USER }

        fun sourceTurnId(phrase: String): String? {
            val needle = normalizedForMatch(phrase)
            if (needle.isEmpty()) return null
            return userTurns.firstOrNull { normalizedForMatch(it.transcript).contains(needle) }?.id
        }

        fun add(source: String, target: String, reason: String, turnId: String? = null) {
            val core = coreSentence(target, source)
            val key = normalizedForMatch(core)
            if (key.isEmpty() || key in seenTargets) return
            if (!isDrillable(core)) return
            seenTargets.add(key)
            newCards.add(DrillCard(sourcePhrase = source, targetPhrase = core, reason = reason,
                createdAt = now, nextReviewAt = now, box = 0,
                sourceSessionId = sessionId, sourceTurnId = turnId))
        }

        for (turn in userTurns) {
            val s = turn.suggestion ?: continue
            add(relevantFragment(turn.transcript, s.alternative), s.alternative, s.reason, turn.id)
        }
        for (p in summary.phrasesUsed) add(p.userSaid, p.fluentAlternative, p.reason, sourceTurnId(p.userSaid))
        for (p in summary.newPatternsDetected) add(p.mistake, p.correction, p.context, sourceTurnId(p.mistake))
        for (d in summary.suggestedDrills) add("", d, "Suggested for you to practice.")
        return newCards
    }

    /** Keep the sentence that corresponds to the correction; prefix-cut otherwise. */
    fun relevantFragment(source: String, target: String, maxChars: Int = 160): String {
        val trimmed = source.trim()
        if (trimmed.length <= maxChars) return trimmed
        val sentences = trimmed.split(Regex("[.!?\n]")).map { it.trim() }.filter { it.isNotEmpty() }
        val targetWords = normalizedForMatch(target).split(' ').filter { it.isNotEmpty() }.toSet()
        if (sentences.size > 1 && targetWords.isNotEmpty()) {
            val best = sentences.maxByOrNull { overlap(it, targetWords) }
            if (best != null && overlap(best, targetWords) > 0) {
                return if (best.length > maxChars) best.take(maxChars) + "…" else best
            }
        }
        return trimmed.take(maxChars) + "…"
    }

    /** Target-side twin — never ellipsis-cut (the result is spoken by TTS). */
    fun coreSentence(target: String, source: String, maxChars: Int = 140): String {
        val trimmed = target.trim()
        if (trimmed.length <= maxChars) return trimmed
        val sentences = trimmed.split(Regex("[.!?\n]")).map { it.trim() }.filter { it.isNotEmpty() }
        val sourceWords = normalizedForMatch(source).split(' ').filter { it.isNotEmpty() }.toSet()
        if (sentences.size <= 1 || sourceWords.isEmpty()) return trimmed
        val best = sentences.maxByOrNull { overlap(it, sourceWords) } ?: return trimmed
        if (overlap(best, sourceWords) == 0) return trimmed
        // Restore terminal punctuation the split ate — a dropped "?" flattens a question.
        val idx = trimmed.indexOf(best)
        if (idx >= 0) {
            val after = idx + best.length
            if (after < trimmed.length && trimmed[after] in ".!?") return best + trimmed[after]
        }
        return best
    }

    private fun overlap(sentence: String, targetWords: Set<String>): Int =
        normalizedForMatch(sentence).split(' ').filter { it.isNotEmpty() }.toSet()
            .intersect(targetWords).size

    fun normalizedForMatch(text: String): String =
        text.filter { it.isLetterOrDigit() || it.isWhitespace() }
            .lowercase().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")

    /** Whether a card with this target survives the read-time filter. */
    fun isDrillable(targetPhrase: String): Boolean = !looksLikeMetaRule(targetPhrase)

    private val BANNED_SUBSTRINGS = listOf(
        "correctly", "properly", "appropriately", "subject-verb", "agreement", "tense",
        "article", "preposition", "vocabulary", "register", "grammar", "pronunciation",
        "fluency", "expand your", "instead of using", "remember to", "make sure to",
        "try to use", "you should use",
    )

    /** "This is a rule, not an utterance" — TTS on a rule is gibberish. */
    fun looksLikeMetaRule(phrase: String): Boolean {
        val lower = phrase.lowercase().trim()
        if (lower.isEmpty()) return true
        if (BANNED_SUBSTRINGS.any { lower.contains(it) }) return true
        // Mostly quoted single items strung with commas = a rule listing examples.
        if (lower.split("'").size - 1 >= 4) return true
        return false
    }
}

/**
 * Disk half — `lang/<code>/drills.json`, same shape and lifecycle rules as
 * `DrillStore.swift`. One instance per process (see [SessionStore]).
 */
class DrillStore private constructor(context: Context) {

    companion object {
        @Volatile private var instance: DrillStore? = null
        fun shared(context: Context): DrillStore =
            instance ?: synchronized(this) {
                instance ?: DrillStore(context.applicationContext).also { instance = it }
            }
        private const val FILE_NAME = "drills.json"
    }

    private val appContext = context.applicationContext
    private val mutex = Mutex()

    private fun file(language: String): File =
        File(LanguageScope.directory(appContext, language), FILE_NAME)

    /** All cards, with the read-time meta-rule filter + core-sentence trim. */
    suspend fun load(language: String = LanguageScope.active(appContext)): List<DrillCard> =
        mutex.withLock { loadLocked(language) }

    private suspend fun loadLocked(language: String): List<DrillCard> = withContext(Dispatchers.IO) {
        val f = file(language)
        if (!f.exists()) emptyList()
        else runCatching {
            StoreJson.json.decodeFromString(ListSerializer(DrillCard.serializer()), f.readText())
        }.getOrElse { emptyList() }
            .filter { !DrillIngest.looksLikeMetaRule(it.targetPhrase) }
            .map { it.copy(targetPhrase = DrillIngest.coreSentence(it.targetPhrase, it.sourcePhrase)) }
    }

    suspend fun clearUnreviewedCards(sessionId: String, language: String = LanguageScope.active(appContext)) =
        mutex.withLock {
            val all = loadLocked(language)
            val kept = all.filterNot { it.sourceSessionId == sessionId && it.box == 0 && it.lastReviewedAt == null }
            if (kept.size != all.size) write(language, kept)
        }

    suspend fun upsertMany(cards: List<DrillCard>, language: String = LanguageScope.active(appContext)) {
        if (cards.isEmpty()) return
        mutex.withLock {
            val newIds = cards.map { it.id }.toSet()
            write(language, loadLocked(language).filterNot { it.id in newIds } + cards)
        }
    }

    /**
     * Producing a card's phrase live outranks any flashcard tap: jump two
     * boxes, land no lower than box 3; cards already past that keep their
     * schedule.
     */
    suspend fun markUsedInConversation(ids: List<String>, language: String = LanguageScope.active(appContext),
                                       now: Long = System.currentTimeMillis()) {
        if (ids.isEmpty()) return
        mutex.withLock {
            val wanted = ids.toSet()
            var touched = false
            val updated = loadLocked(language).map { card ->
                if (card.id !in wanted) return@map card
                val promoted = minOf(maxOf(card.box + 2, 3), DrillIngest.MAX_BOX)
                if (promoted <= card.box) return@map card
                touched = true
                card.copy(box = promoted, lastReviewedAt = now,
                    nextReviewAt = now + DrillIngest.intervalMs(promoted))
            }
            if (touched) write(language, updated)
        }
    }

    /** Cards due now, newest first (fresh corrections feel more relevant). */
    suspend fun due(language: String = LanguageScope.active(appContext),
                    now: Long = System.currentTimeMillis()): List<DrillCard> =
        load(language).filter { it.nextReviewAt <= now }.sortedByDescending { it.createdAt }

    /**
     * "Got it" GRADUATES the card to the top rung rather than climbing one —
     * five separate Got-its before a card left the pile made the filter look
     * broken (iOS, `DrillStore.markKnown`).
     */
    suspend fun markKnown(card: DrillCard, language: String = LanguageScope.active(appContext),
                          now: Long = System.currentTimeMillis()) {
        upsertMany(listOf(card.copy(
            timesSeen = card.timesSeen + 1, timesCorrect = card.timesCorrect + 1,
            lastReviewedAt = now, box = DrillIngest.MAX_BOX,
            nextReviewAt = now + DrillIngest.intervalMs(DrillIngest.MAX_BOX))), language)
        PracticeLog.record(appContext, PracticeLog.Kind.DRILL, finished = true)
    }

    /**
     * File a card into a chosen bin — the learner picking WHEN it comes back
     * rather than the box deciding for them. Same four verdicts the word deck
     * offers, so "Soon" cannot mean two different things depending on which
     * deck you are in.
     *
     * A rep is logged here (the card was handled); it counts as FINISHED only
     * on the graduating verdict, which goes through [markKnown] instead —
     * otherwise a day could be ticked complete by postponing ten cards.
     */
    suspend fun fileInBin(card: DrillCard, box: Int, delayMs: Long,
                          language: String = LanguageScope.active(appContext),
                          now: Long = System.currentTimeMillis()) {
        upsertMany(listOf(card.copy(
            timesSeen = card.timesSeen + 1, lastReviewedAt = now, box = box,
            nextReviewAt = now + delayMs)), language)
        PracticeLog.record(appContext, PracticeLog.Kind.DRILL)
    }

    /** Demote one box and reschedule soon. */
    suspend fun markIncorrect(card: DrillCard, language: String = LanguageScope.active(appContext),
                              now: Long = System.currentTimeMillis()) {
        val box = maxOf(card.box - 1, 0)
        upsertMany(listOf(card.copy(
            timesSeen = card.timesSeen + 1, lastReviewedAt = now, box = box,
            nextReviewAt = now + DrillIngest.intervalMs(box))), language)
        PracticeLog.record(appContext, PracticeLog.Kind.DRILL)
    }

    suspend fun dueCount(language: String = LanguageScope.active(appContext),
                         now: Long = System.currentTimeMillis()): Int =
        load(language).count { it.nextReviewAt <= now }

    private suspend fun write(language: String, cards: List<DrillCard>) = withContext(Dispatchers.IO) {
        val target = file(language)
        val tmp = File(target.parentFile, "$FILE_NAME.tmp")
        tmp.writeText(StoreJson.json.encodeToString(ListSerializer(DrillCard.serializer()), cards))
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }
}
