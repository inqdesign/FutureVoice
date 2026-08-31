package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.TurnRole
import java.util.Calendar

/**
 * The day's hand for the word and expression decks.
 *
 * Both funnels share one rule that is easy to lose and expensive to lose:
 * **every source honors the schedule, not just the notebook.** A word put away
 * for 10 minutes is still in the core list, still unmastered in its Watch
 * book, still a pickup word from the last talk — and those sources judge by
 * `records`, which `addStudying` never writes. So a snoozed word came straight
 * back on the next deal and the promise meant nothing. The gate lives inside
 * the ONE `add` funnel every source runs through, so a fifth source can't
 * quietly reintroduce it. Never re-gate per source.
 */
object DailyStudyPick {

    /**
     * Deal today's words, most personal material first:
     *   1. notebook `studying` words — rotated by day so a 30-word backlog
     *      doesn't deal the same 10 forever
     *   2. unmastered words from active Watch books
     *   3. pickup words from the two most recent talks (fluent-self lines, at
     *      the learner's level and up)
     *   4. core-list top-up at the learner's level and up, so the hand is
     *      never short even on day one
     * Deterministic within a day; dedup is case-insensitive.
     */
    suspend fun words(context: Context, goal: Int, language: String, level: CefrLevel?,
                      now: Long = System.currentTimeMillis()): List<String> {
        val vocab = VocabStore.shared(context)
        val schedule = StudyScheduleStore.shared(context).snapshot(language)
        val seen = HashSet<String>()
        val out = ArrayList<String>()
        fun add(w: String) {
            val k = w.trim().lowercase()
            if (k.isEmpty() || k in seen) return
            if (!schedule.isDue(StudyScheduleStore.Kind.WORD, w, now)) return
            seen.add(k); out.add(w)
        }

        // Overdue scheduled words come first (earliest return first);
        // never-scheduled ones follow, oldest-first and rotated by the day.
        val studying = vocab.studying(language)
            .filter { schedule.isDue(StudyScheduleStore.Kind.WORD, it, now) }
        studying.mapNotNull { w ->
            schedule.nextReview(StudyScheduleStore.Kind.WORD, w)?.let { w to it }
        }.sortedBy { it.second }.forEach { add(it.first) }
        rotated(studying.filter { schedule.nextReview(StudyScheduleStore.Kind.WORD, it) == null }, now)
            .forEach { add(it) }

        if (out.size < goal) {
            // Skip words the store already counts as known/used — a book that
            // hasn't refreshed its mastery yet can still list them unmastered.
            for (sc in activeScenarios(context, language)) {
                for (item in sc.curriculum?.words.orEmpty()) {
                    if (item.masteredAt != null) continue
                    if (vocab.state(item.text.lowercase(), language) != null) continue
                    add(item.text)
                }
            }
        }

        if (out.size < goal) {
            val fluent = SessionStore.shared(context).load(language)
                .filter { it.endedAt != null }
                .sortedByDescending { it.startedAt }
                .take(2)
                .flatMap { s -> s.turns.filter { it.role != TurnRole.USER }.map { it.transcript } }
            vocab.pickupWords(fluent, level, language).forEach { add(it) }
        }

        if (out.size < goal && level != null) {
            for (w in CoreVocabulary.wordsAtOrAbove(level, language)) {
                if (vocab.state(w, language) != null) continue
                add(w)
                if (out.size >= goal) break
            }
        }

        return out.take(goal)
    }

    /**
     * Deal today's expressions, most personal material first:
     *   1. bookmarked phrases not yet known — rotated by day
     *   2. unmastered expressions from active Watch books
     *   3. phrases the fluent self used in a call and they haven't said
     *   4. phrases they said themselves, newest first, not yet known
     *
     * 3 before 4 on purpose: a deck exists to teach what you can't say yet,
     * and the phrases you already produced are already yours. There is no
     * core list for phrases, so the hand can run short — the empty state on
     * the deck says where they come from.
     */
    suspend fun expressions(context: Context, goal: Int, language: String,
                            now: Long = System.currentTimeMillis()): List<String> {
        val vocab = VocabStore.shared(context)
        val schedule = StudyScheduleStore.shared(context).snapshot(language)
        val seen = HashSet<String>()
        val out = ArrayList<String>()
        suspend fun add(p: String) {
            val k = p.trim().lowercase()
            if (k.isEmpty() || k in seen) return
            if (!schedule.isDue(StudyScheduleStore.Kind.EXPRESSION, p, now)) return
            seen.add(k); out.add(p)
        }

        val studying = vocab.studyingExpressions(language)
            .filter { !vocab.isKnownExpression(it, language) &&
                schedule.isDue(StudyScheduleStore.Kind.EXPRESSION, it, now) }
        studying.mapNotNull { p ->
            schedule.nextReview(StudyScheduleStore.Kind.EXPRESSION, p)?.let { p to it }
        }.sortedBy { it.second }.forEach { add(it.first) }
        rotated(studying.filter { schedule.nextReview(StudyScheduleStore.Kind.EXPRESSION, it) == null }, now)
            .forEach { add(it) }

        if (out.size < goal) {
            for (sc in activeScenarios(context, language)) {
                for (item in sc.curriculum?.expressions.orEmpty()) {
                    if (item.masteredAt != null) continue
                    if (vocab.isKnownExpression(item.text, language)) continue
                    add(item.text)
                }
            }
        }

        if (out.size < goal) {
            // One merge, shared with the Library — heard-in-a-call comes
            // before said-it in the catalog's own order, because a deck
            // exists to teach what you can't say yet.
            for (item in ExpressionCatalog.all(context, language)) {
                if (!item.known) add(item.text)
            }
        }

        return out.take(goal)
    }

    private suspend fun activeScenarios(context: Context, language: String): List<Scenario> =
        ScenarioStore.shared(context).load(language).filter { it.archivedAt == null }

    /**
     * Oldest first, then rotated by the day of the year — so a big notebook
     * deals a different slice each day instead of the same ten forever, and
     * the same day always deals the same slice.
     */
    private fun <T> rotated(items: List<T>, now: Long): List<T> {
        if (items.isEmpty()) return items
        val day = Calendar.getInstance().apply { timeInMillis = now }
            .get(Calendar.DAY_OF_YEAR)
        val ordered = items.reversed()
        val offset = day % ordered.size
        return ordered.drop(offset) + ordered.take(offset)
    }
}
