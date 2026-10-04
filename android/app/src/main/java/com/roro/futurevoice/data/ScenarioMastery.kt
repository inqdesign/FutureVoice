package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.ScenarioCurriculum
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TurnRole

/**
 * A Watch book's mastery, written onto its curriculum — iOS
 * `AppState.refreshScenarioMastery` (ebf848e). Deterministic, never
 * LLM-judged:
 *  - a word is mastered when the vocab pool has a record of it (used in a
 *    talk, or "I know it" on its card), or the learner said it in a talk on
 *    this scenario;
 *  - an expression on real evidence (`hasUsedExpression` — a bookmark row
 *    alone is not mastery), or said in a talk on this scenario;
 *  - a shadow line (the scene's "user" lines — the fluent self's side) once
 *    a WHOLE-line take scores at or above [TalkCurriculum.SHADOW_MASTERY_SCORE]
 *    by `overallScore`, the number a take is judged by everywhere.
 *
 * Only ever flips items ON, so a later refresh can't un-master anything.
 *
 * Until this, Android never wrote `masteredAt` on a scene book at all: the
 * book page computed words/expressions live and the shelves read the stored
 * field, so a scene book could not finish on this platform, and its Shadow
 * chapter counted for nothing.
 */
object ScenarioMastery {

    /**
     * Which take belongs to a shadow line. iOS matches `turnId == item.id`,
     * because its "Shadow this" and Say it again both stamp the item id. On
     * Android the book's and the scene's Shadow rows open the shadow screen
     * with the line's TEXT, and that screen ids a turn-less line by a UUID of
     * the text — so a take also counts when its target is the same line by
     * normalized text (the matcher `SayItAgainScript` and iOS `WatchView`
     * use to find a line's item). A partial (phrase) take never judges a line.
     */
    fun bestShadowScore(item: ScenarioCurriculum.Item, attempts: List<ShadowAttempt>): Int {
        val key = CarryoverDetector.normalized(item.text)
        return attempts
            .filter { !it.isPartial }
            .filter { it.turnId == item.id ||
                (key.isNotEmpty() && CarryoverDetector.normalized(it.targetText) == key) }
            .maxOfOrNull { it.overallScore } ?: 0
    }

    /** Everything the learner said in the talks run on this scenario — by id,
     *  and by title for talks saved before the book passed its id. A practice
     *  (coach mode) call read its answers off a suggestion, so it is left out. */
    fun spokenText(scenario: Scenario, sessions: List<Session>): String =
        sessions
            .filter { !it.isPractice }
            .filter { it.originScenarioId == scenario.id ||
                (it.originScenarioId == null &&
                    (it.topic == scenario.environment || it.topic == scenario.cardTitle)) }
            .flatMap { it.turns }
            .filter { it.role == TurnRole.USER }
            .joinToString(" ") { it.transcript }
            .lowercase()

    /** iOS `saidByUser`: the phrase as a whole word run in [spoken]. */
    fun saidIn(spoken: String, phrase: String): Boolean {
        val needle = phrase.trim().lowercase()
        if (needle.isEmpty() || spoken.isEmpty()) return false
        return Regex("\\b" + Regex.escape(needle) + "\\b").containsMatchIn(spoken)
    }

    /**
     * The pure half: the curriculum with every newly-evidenced item stamped
     * [now], or null when nothing changed (so the caller writes nothing).
     */
    fun refreshed(
        c: ScenarioCurriculum,
        spoken: String,
        knownWord: (String) -> Boolean,
        usedExpression: (String) -> Boolean,
        attempts: List<ShadowAttempt>,
        now: Long = System.currentTimeMillis(),
    ): ScenarioCurriculum? {
        var changed = false
        val words = c.words.map { w ->
            if (w.masteredAt == null && (knownWord(w.text) || saidIn(spoken, w.text))) {
                changed = true; w.copy(masteredAt = now)
            } else w
        }
        val expressions = c.expressions.map { e ->
            if (e.masteredAt == null && (saidIn(spoken, e.text) || usedExpression(e.text))) {
                changed = true; e.copy(masteredAt = now)
            } else e
        }
        val shadow = c.shadowLines.map { l ->
            if (l.masteredAt == null &&
                bestShadowScore(l, attempts) >= TalkCurriculum.SHADOW_MASTERY_SCORE) {
                changed = true; l.copy(masteredAt = now)
            } else l
        }
        if (!changed) return null
        return c.copy(words = words, expressions = expressions, shadowLines = shadow)
    }

    /** Refresh one scenario against the stores and persist it when anything
     *  flipped. Returns the scenario as it now stands. */
    suspend fun refresh(
        context: Context,
        scenario: Scenario,
        language: String,
        sessions: List<Session>? = null,
        attempts: List<ShadowAttempt>? = null,
    ): Scenario {
        val c = scenario.curriculum ?: return scenario
        val vocab = VocabStore.shared(context)
        val talks = sessions ?: SessionStore.shared(context).load(language)
        val takes = attempts ?: ShadowAttemptStore.shared(context).load(language)
        val known = c.words.filter { it.masteredAt == null }
            .filter { vocab.isKnownWord(it.text, language) }.map { it.text }.toSet()
        val used = c.expressions.filter { it.masteredAt == null }
            .filter { vocab.hasUsedExpression(it.text, language) }.map { it.text }.toSet()
        val next = refreshed(c, spokenText(scenario, talks), { it in known }, { it in used }, takes)
            ?: return scenario
        val saved = scenario.copy(curriculum = next)
        ScenarioStore.shared(context).replace(saved, language)
        return saved
    }
}
