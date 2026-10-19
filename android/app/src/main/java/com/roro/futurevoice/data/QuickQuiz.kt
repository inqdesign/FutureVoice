package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.net.WordLore
import com.roro.futurevoice.talk.SessionMode
import com.roro.futurevoice.talk.TurnRole
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** One question of the quick quiz. Every kind is a single tap (iOS `QuickQuizItem`). */
data class QuickQuizItem(
    val kind: Kind,
    /** word: the meaning (native) · expression / grammar: a line with a blank. */
    val prompt: String,
    val answer: String,
    val options: List<String>,
    /** grammar: the point's name (native), shown above the line. */
    val heading: String? = null,
    /** Shown once answered, and the quiz waits for Next: grammar says why, a
     *  level expression what it means (native). */
    val note: String? = null,
    /** A written question from [QuickQuizStock], counted as asked once shown. */
    val stockId: String? = null,
    /** From the learner's own material rather than the level. */
    val isOwn: Boolean = false,
    val id: String = UUID.randomUUID().toString(),
) {
    enum class Kind { WORD, EXPRESSION, GRAMMAR }

    /** The line with its blank filled — what a missed item is listed as. */
    val solved: String get() = prompt.replace(WeeklyTestEngine.BLANK_MARK, answer)
}

/**
 * The quick quiz (iOS `QuickQuizEngine`, 2026-10-18, founder: "a check-in on
 * what I'm studying right now, any time, in a simpler form than the weekly
 * test"). The weekly test stays as it is; this is the light one beside it.
 *
 * Three kinds, all multiple choice, graded in code:
 *
 *   word       a word's meaning → pick the word (the weekly test's decoys)
 *   expression a line with the expression blanked → pick it
 *   grammar    a new everyday line with a blank → pick the form that fits
 *
 * The learner's OWN material comes first — notebook words, the "To study"
 * list in the line the fluent self said it in — and the LEVEL fills the rest:
 * graded words of their CEFR band they have not marked known or used, and
 * written questions from [QuickQuizStock]. A first-day learner gets a full quiz.
 *
 * Nothing here rests on what the RECOGNIZER heard: words and expressions come
 * from the fluent self's own lines (model-written), and grammar items are
 * written fresh.
 *
 * A quiz is built when it opens and gone when it closes. An answer is weaker
 * evidence than a test's, so only a MISS writes back: the word or phrase goes
 * into the notebook, due now. A right answer changes nothing — USED outranks
 * KNOWN, and a tap is neither. Grammar writes nothing.
 */
object QuickQuizEngine {
    const val SIZE = 10
    /** Under this there is nothing to quiz; the screen says so. */
    const val MIN_ITEMS = 3
    const val MAX_WORDS = 4
    const val MAX_EXPRESSIONS = 3
    const val MAX_GRAMMAR = 3
    /** How long word meanings may take to arrive before the quiz goes
     *  without the rest. */
    const val GLOSS_BUDGET_MS = 5_000L
    /** Words the level offers when the notebook runs out: graded at the
     *  learner's band, not already known, used or in the notebook. */
    const val LEVEL_WORD_POOL = 12

    suspend fun build(context: Context, language: String, native: String, level: CefrLevel): List<QuickQuizItem> =
        coroutineScope {
            val rng = WeeklyTestRandom(UUID.randomUUID().toString())
            // The written stock is topped up while the words are looked up.
            val stockTask = async {
                QuickQuizStock.available(context, language, native, level, grammar = SIZE, expressions = SIZE)
            }
            val words = wordItems(context, language, native, level, rng)
            val ownExpressions = expressionItems(context, language, rng)
            val (stockGrammar, stockExpressions) = stockTask.await()

            // The learner's own first, each kind its share; then the level.
            val ownWords = words.filter { it.isOwn }
            val levelWords = words.filter { !it.isOwn }
            val picked = ArrayList<QuickQuizItem>()
            picked += ownWords.take(MAX_WORDS)
            picked += ownExpressions.take(MAX_EXPRESSIONS)
            picked += stockGrammar.take(MAX_GRAMMAR)
            val fill = listOf(stockExpressions, levelWords, stockGrammar.drop(MAX_GRAMMAR),
                ownWords.drop(MAX_WORDS), ownExpressions.drop(MAX_EXPRESSIONS))
            // Round-robin over the fill so a thin learner still gets a mix.
            val queues = fill.map { it.shuffled(rng).toMutableList() }
            while (picked.size < SIZE && queues.any { it.isNotEmpty() }) {
                for (q in queues) {
                    if (picked.size < SIZE && q.isNotEmpty()) picked += q.removeAt(0)
                }
            }
            if (picked.size < MIN_ITEMS) return@coroutineScope emptyList()
            QuickQuizStock.markAsked(context, picked.mapNotNull { it.stockId }.toSet())
            picked.shuffled(rng)
        }

    // ── Kinds

    /** Notebook words first, then level words, each with its meaning. The
     *  meanings are looked up together, capped at [GLOSS_BUDGET_MS]. */
    private suspend fun wordItems(context: Context, language: String, native: String, level: CefrLevel,
                                  rng: kotlin.random.Random): List<QuickQuizItem> = coroutineScope {
        val vocab = VocabStore.shared(context)
        val studying = vocab.studying(language).filter { TextScript.isInTargetScript(it, language) }
        val own = studying.shuffled(rng)
        val taken = (studying.map { it.lowercase() } + vocab.recordedWords(language).map { it.lowercase() }).toSet()
        val levelWords = CoreVocabulary.headwords(level, language)
            .filter { it.lowercase() !in taken }
            .filter { TextScript.isInTargetScript(it, language) }
            .shuffled(rng)
            .take(LEVEL_WORD_POOL)
        val candidates = own.take(SIZE) + levelWords
        if (candidates.isEmpty()) return@coroutineScope emptyList()
        val ownSet = own.map { it.lowercase() }.toSet()

        val graded = ArrayList<String>()
        for (band in WeeklyTestEngine.decoyBands(level)) {
            graded += CoreVocabulary.headwords(band, language)
                .filter { it.lowercase() !in taken }
                .shuffled(rng)
        }

        // Every meaning at once; whatever has not arrived by the budget is left out.
        val lore = WordLore(AuthRepository())
        val senses = ConcurrentHashMap<String, String>()
        withTimeoutOrNull(GLOSS_BUDGET_MS) {
            candidates.map { word ->
                async {
                    val sense = runCatching { lore.entry(word, native, language) }.getOrNull()
                        ?.senses?.firstOrNull()?.meaning?.trim()
                    if (sense != null) senses[word] = sense
                }
            }.awaitAll()
        }

        val out = ArrayList<QuickQuizItem>()
        for (word in candidates) {
            val sense = senses[word]
            if (sense.isNullOrEmpty() || sense.lowercase().contains(word.lowercase())) continue
            val decoys = WeeklyTestEngine.meaningDecoys(word, candidates, graded, language, rng)
            if (decoys.size != WeeklyTestEngine.CHOICE_COUNT - 1) continue
            out += QuickQuizItem(QuickQuizItem.Kind.WORD, prompt = sense, answer = word,
                options = (listOf(word) + decoys).shuffled(rng), isOwn = word.lowercase() in ownSet)
        }
        out
    }

    private suspend fun expressionItems(context: Context, language: String,
                                        rng: kotlin.random.Random): List<QuickQuizItem> {
        val sessions = SessionStore.shared(context).load(language)
            .filter { it.archivedAt == null && it.mode == SessionMode.CONVERSATION }
        // The top of the list is what is being studied now; shuffled within
        // it so two quizzes in a row don't ask the same three.
        val toStudy = runCatching {
            ExpressionCatalog.library(context, language).filter { !it.known }.map { it.text }
        }.getOrDefault(emptyList()).filter { TextScript.isInTargetScript(it, language) }
        val recent = toStudy.take(15).shuffled(rng)
        if (recent.isEmpty()) return emptyList()
        val openers = sessions.mapNotNull { s -> s.turns.firstOrNull { it.role == TurnRole.FLUENT_SELF }?.id }.toSet()
        val fluent = sessions.flatMap { s ->
            s.turns.filter { it.role == TurnRole.FLUENT_SELF && !it.excludedFromScoring && it.id !in openers }
                .map { s to it }
        }
        val sceneExamples = runCatching {
            val out = LinkedHashMap<String, String>()
            for (sc in ScenarioStore.shared(context).load(language)) {
                for (e in sc.curriculum?.expressions.orEmpty()) {
                    val example = e.example ?: continue
                    out.putIfAbsent(e.text.trim().lowercase(), example)
                }
            }
            out.toMap()
        }.getOrDefault(emptyMap())
        val library = runCatching { ExpressionCatalog.all(context, language).map { it.text } }
            .getOrDefault(emptyList())
        return WeeklyTestEngine.gapItems(recent, sessions, fluent, sessions, openers, sceneExamples,
            library, language, rng)
            .map { QuickQuizItem(QuickQuizItem.Kind.EXPRESSION, prompt = it.prompt, answer = it.answer,
                options = it.options, isOwn = true) }
    }

    // ── Writing back

    /** A miss puts the item back in front of the learner; a right answer
     *  writes nothing. */
    suspend fun apply(context: Context, item: QuickQuizItem, correct: Boolean, language: String) {
        if (correct) return
        val vocab = VocabStore.shared(context)
        when (item.kind) {
            QuickQuizItem.Kind.WORD -> {
                if (!vocab.isStudying(item.answer, language)) vocab.addStudying(item.answer, language)
                ReviewQueue.retire(context, StudyScheduleStore.Kind.WORD, item.answer, language)
            }
            QuickQuizItem.Kind.EXPRESSION -> {
                if (!vocab.isStudyingExpression(item.answer, language)) {
                    vocab.setStudyingExpression(item.answer, true, language)
                }
                ReviewQueue.retire(context, StudyScheduleStore.Kind.EXPRESSION, item.answer, language)
            }
            QuickQuizItem.Kind.GRAMMAR -> Unit
        }
        StoreEvents.bump()
    }
}
