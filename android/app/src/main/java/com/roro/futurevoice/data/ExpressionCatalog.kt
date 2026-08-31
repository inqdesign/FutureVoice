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
    )

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
