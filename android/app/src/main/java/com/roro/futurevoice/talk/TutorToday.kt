package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.data.StudyPlan
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Today, CHOSEN (iOS `TutorToday`, 57ba9c6f, founder: "the app has too many
 * things to do; the tutor should be the place where you never lose what to
 * do"). The note said "Today: 2 things" and then listed six rows — the
 * routine and every pick, side by side. Now the tutor picks: ONE thing now,
 * with why, one thing next, and the rest of the day folded under "N more
 * today". Nothing was removed; it is all one tap down.
 *
 * The order is fixed in code, never asked of a model, so it is instant and
 * can't disagree with My routine:
 * 1. a routine block whose time is on,
 * 2. the nearest goal's next piece not opened today (reading → model answer
 *    → drill) — what the learner said they are preparing for,
 * 3. the routine's next blocks (now's and the one after),
 * 4. the other picks (a challenge rank lost, a new episode, a reading),
 * 5. everything else; done routine blocks last.
 */
object TutorToday {
    sealed interface Entry {
        val id: String
        val isDone: Boolean

        data class Routine(val item: TutorBot.Item) : Entry {
            override val id: String get() = "r-${item.id}"
            override val isDone: Boolean get() = item.done
        }

        data class Pick(val pick: TutorPick) : Entry {
            override val id: String get() = "p-${pick.id}"
            override val isDone: Boolean get() = false
        }
    }

    private const val OPENED_KEY = "futurevoice.tutorBot.openedPicks"

    private fun prefs(c: Context) = c.applicationContext.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)

    /** A pick tapped today drops out of "now" (its own page took over). */
    fun markOpened(c: Context, pick: TutorPick, now: Long = System.currentTimeMillis()) {
        val ids = opened(c, now) + pick.id
        prefs(c).edit().putString(OPENED_KEY, JsonObject(mapOf(
            "day" to JsonPrimitive(StudyPlan.dayKey(now)),
            "ids" to JsonArray(ids.map { JsonPrimitive(it) }),
        )).toString()).apply()
    }

    fun opened(c: Context, now: Long = System.currentTimeMillis()): Set<String> {
        val saved = runCatching {
            Json.parseToJsonElement(prefs(c).getString(OPENED_KEY, null) ?: return emptySet()) as JsonObject
        }.getOrNull() ?: return emptySet()
        if (saved["day"]?.jsonPrimitive?.contentOrNull != StudyPlan.dayKey(now)) return emptySet()
        return (saved["ids"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }?.toSet() ?: emptySet()
    }

    fun ranked(today: TutorBot.Today, picks: List<TutorPick>, now: Long = System.currentTimeMillis(),
               opened: Set<String> = emptySet()): List<Entry> {
        val out = ArrayList<Entry>()
        val used = HashSet<String>()
        fun add(e: Entry) { if (used.add(e.id)) out += e }

        val goalKinds = setOf(TutorPick.Kind.GOAL_READING, TutorPick.Kind.GOAL_SPEECH, TutorPick.Kind.GOAL_DRILL)
        fun isGoal(p: TutorPick) = p.kind in goalKinds
        today.items.firstOrNull { it.isNow(now) }?.let { add(Entry.Routine(it)) }
        picks.firstOrNull { isGoal(it) && it.id !in opened }?.let { add(Entry.Pick(it)) }
        today.next(now)?.let { add(Entry.Routine(it)) }
        // The routine is their own promise, so its next block comes before
        // anything the tutor merely offers.
        today.items.firstOrNull { !it.done && "r-${it.id}" !in used }?.let { add(Entry.Routine(it)) }
        for (p in picks) if (!isGoal(p) && p.id !in opened) add(Entry.Pick(p))
        for (i in today.items) if (!i.done) add(Entry.Routine(i))
        for (p in picks) add(Entry.Pick(p))
        for (i in today.items) if (i.done) add(Entry.Routine(i))
        return out
    }
}
