package com.roro.futurevoice.data

import android.content.Context

/**
 * How big the collection BEHIND today's hand is — the number on each Practice
 * tile's "To study ›" footer.
 *
 * It has to count what the page that footer opens actually lists, or the tile
 * promises work the page doesn't have (iOS learned this with the shadow tile:
 * it showed bookmarks while the browser listed unpractised lines). So each
 * counter here names its page, and the page's own list is the definition.
 */
object StudyCollections {
    /** What the Words library lists under "To study": the notebook, plus
     *  scene words the learner has no record of yet. */
    suspend fun wordsToStudy(context: Context, language: String): Int {
        val vocab = VocabStore.shared(context)
        val kept = vocab.studying(language).map { it.lowercase() }.toMutableSet()
        ScenarioStore.shared(context).load(language)
            .filter { it.archivedAt == null }
            .forEach { scenario ->
                scenario.curriculum?.words?.forEach { item ->
                    val key = item.text.trim().lowercase()
                    if (key.isNotEmpty() && vocab.state(key, language) == null) kept.add(key)
                }
            }
        return kept.size
    }

    /** The same shape for expressions: the notebook, plus scene expressions
     *  the learner has never said. */
    suspend fun expressionsToStudy(context: Context, language: String): Int {
        val vocab = VocabStore.shared(context)
        val kept = vocab.studyingExpressions(language).map { it.lowercase() }.toMutableSet()
        ScenarioStore.shared(context).load(language)
            .filter { it.archivedAt == null }
            .forEach { scenario ->
                scenario.curriculum?.expressions?.forEach { item ->
                    val key = item.text.trim().lowercase()
                    if (key.isNotEmpty() && !vocab.isKnownExpression(key, language)) kept.add(key)
                }
            }
        return kept.size
    }

    /** Exactly what the shadow browser lists: fluent-self lines never
     *  attempted — from finished talks and from Watch books. */
    suspend fun shadowToStudy(context: Context, language: String): Int {
        val practised = ShadowAttemptStore.shared(context).load(language).map { it.turnId }.toSet()
        val fromTalks = SessionStore.shared(context).load(language)
            .filter { it.endedAt != null }
            .flatMap { it.turns }
            .count { it.role == com.roro.futurevoice.talk.TurnRole.FLUENT_SELF && it.id !in practised }
        val fromScenes = ScenarioStore.shared(context).load(language)
            .filter { it.archivedAt == null }
            .sumOf { scenario ->
                scenario.curriculum?.shadowLines?.count { it.id !in practised } ?: 0
            }
        return fromTalks + fromScenes
    }
}
