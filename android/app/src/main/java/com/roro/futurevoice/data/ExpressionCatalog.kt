package com.roro.futurevoice.data

import android.content.Context

/**
 * Every expression the app knows about, in one list — merged at READ time.
 *
 * A call's expressions come from BOTH mouths. `expressionsUsed` is what the
 * learner said, verified against their own turns: that is evidence, and it
 * gets a [VocabStore] record. `expressionsOffered` is what the fluent self
 * said and the learner didn't — the reusable chunk people actually learn —
 * and it must NEVER be copied into that store, whose rows count times SAID
 * and would have to lie about a phrase nobody has spoken yet.
 *
 * So it lives on the summary and is folded in here, exactly as scene
 * expressions are. Everything downstream is this merge: the Library list, the
 * talk book's Expressions chapter, the export, and the daily deck — which
 * deals HEARD before SAID, because a deck exists to teach what you can't say
 * yet.
 */
object ExpressionCatalog {

    enum class Origin {
        /** The fluent self used it in a call; the learner hasn't said it. */
        HEARD,
        /** From a Watch scene's study material. */
        SCENE,
        /** The learner said it — the only origin with a record behind it. */
        SAID,
    }

    data class Item(
        val text: String,
        val origin: Origin,
        /** Times said. Always 0 for [Origin.HEARD] — that is the point. */
        val count: Int = 0,
        val known: Boolean = false,
        val bookmarked: Boolean = false,
        val lastAt: Long = 0,
        /** Where it came from, by name: the talk's topic for [Origin.HEARD],
         *  the scenario's situation for [Origin.SCENE]. Empty when unknown. */
        val title: String = "",
    )

    /**
     * The expressions LIBRARY's list (iOS `ExpressionCatalog.all`): one row
     * per phrase, most recent first, and when a phrase arrives from more than
     * one source said-it wins over everything (it carries the count the row
     * shows) and heard-it wins over a scene. Archived talks and scenarios
     * drop out. [all] keeps its own order — it is the deck's teaching order.
     */
    suspend fun library(context: Context, language: String): List<Item> {
        val vocab = VocabStore.shared(context)
        val bookmarked = vocab.studyingExpressions(language).toSet()
        val byKey = LinkedHashMap<String, Item>()
        fun key(t: String) = t.trim().lowercase()

        for (sc in ScenarioStore.shared(context).load(language)) {
            if (sc.archivedAt != null) continue
            val at = sc.lastUsedAt ?: sc.createdAt
            for (item in sc.curriculum?.expressions.orEmpty()) {
                val k = key(item.text)
                if (k.isEmpty() || k in byKey) continue
                byKey[k] = Item(item.text.trim(), Origin.SCENE, lastAt = at,
                    title = sc.environment.trim())
            }
        }
        for (s in SessionStore.shared(context).load(language)) {
            if (s.archivedAt != null) continue
            val at = s.endedAt ?: s.startedAt
            for (p in s.summary?.expressionsOffered.orEmpty()) {
                val k = key(p)
                if (k.isEmpty()) continue
                val existing = byKey[k]
                // Heard twice → the more recent talk names it.
                if (existing != null && existing.origin == Origin.HEARD && existing.lastAt >= at) continue
                byKey[k] = Item(p.trim(), Origin.HEARD, lastAt = at, title = s.topic?.trim().orEmpty())
            }
        }
        for (e in vocab.expressionEntries(language)) {
            val k = key(e.text)
            if (k.isEmpty()) continue
            byKey[k] = Item(e.text.trim(), Origin.SAID, count = e.count, lastAt = e.lastAt)
        }
        return byKey.values
            .map { it.copy(known = vocab.isKnownExpression(it.text, language),
                bookmarked = key(it.text) in bookmarked) }
            .sortedByDescending { it.lastAt }
    }

    /**
     * Heard first, then scene material, then the learner's own — newest-first
     * within each group. The order IS the teaching order.
     */
    suspend fun all(context: Context, language: String): List<Item> {
        val vocab = VocabStore.shared(context)
        val bookmarked = vocab.studyingExpressions(language).toSet()
        fun isBookmarked(text: String) = text.trim().lowercase() in bookmarked

        val out = ArrayList<Item>()
        val seen = HashSet<String>()
        suspend fun add(text: String, origin: Origin, count: Int = 0, lastAt: Long = 0) {
            val key = text.trim().lowercase()
            if (key.isEmpty() || !seen.add(key)) return
            out.add(Item(text.trim(), origin, count,
                known = vocab.isKnownExpression(text, language),
                bookmarked = isBookmarked(text), lastAt = lastAt))
        }

        val sessions = SessionStore.shared(context).load(language)
            .sortedByDescending { it.startedAt }
        for (s in sessions) {
            for (p in s.summary?.expressionsOffered.orEmpty()) {
                add(p, Origin.HEARD, lastAt = s.endedAt ?: s.startedAt)
            }
        }
        for (sc in ScenarioStore.shared(context).load(language)) {
            if (sc.archivedAt != null) continue
            for (item in sc.curriculum?.expressions.orEmpty()) {
                add(item.text, Origin.SCENE, lastAt = sc.lastUsedAt ?: sc.createdAt)
            }
        }
        for (e in vocab.expressionEntries(language)) {
            add(e.text, Origin.SAID, count = e.count, lastAt = e.lastAt)
        }
        return out
    }
}
