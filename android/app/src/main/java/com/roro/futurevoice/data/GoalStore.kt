package com.roro.futurevoice.data

import android.content.Context
import java.util.Calendar

/**
 * Daily challenge targets — how many sentence cards / word judgments /
 * expression judgments / shadow takes count as "done for today". Targets
 * only; the reps themselves come from [PracticeLog]. A target of 0 turns that
 * challenge off.
 *
 * Global across languages, like [PracticeLog]: the habit is one habit,
 * whichever target language happens to be active.
 */
object GoalStore {

    private const val PREFS = "futurevoice"
    private const val SENTENCES = "futurevoice.goal.sentencesPerDay"
    private const val WORDS = "futurevoice.goal.wordsPerDay"
    private const val EXPRESSIONS = "futurevoice.goal.expressionsPerDay"
    private const val SHADOWS = "futurevoice.goal.shadowsPerDay"

    data class Goals(
        /** 20 = one deck's session cap, which is what the tile asked for
         *  before this was settable. */
        val sentences: Int = 20,
        val words: Int = 10,
        val expressions: Int = 3,
        val shadows: Int = 2,
    ) {
        val anyEnabled: Boolean
            get() = sentences > 0 || words > 0 || expressions > 0 || shadows > 0
    }

    fun load(c: Context): Goals {
        val p = c.getSharedPreferences(PREFS, 0)
        return Goals(
            sentences = p.getInt(SENTENCES, 20),
            words = p.getInt(WORDS, 10),
            expressions = p.getInt(EXPRESSIONS, 3),
            shadows = p.getInt(SHADOWS, 2),
        )
    }

    fun save(c: Context, g: Goals) {
        c.getSharedPreferences(PREFS, 0).edit()
            .putInt(SENTENCES, g.sentences)
            .putInt(WORDS, g.words)
            .putInt(EXPRESSIONS, g.expressions)
            .putInt(SHADOWS, g.shadows)
            .apply()
    }

    /**
     * Every enabled challenge met on [at]. False when nothing is enabled — a
     * day with no goals cannot be "met", or the streak would be infinite.
     *
     * Reads FINISHED work only. Reps count every time an item was handled, so
     * reading those would let a day complete itself by postponing cards.
     */
    fun met(c: Context, g: Goals, at: Long): Boolean {
        if (!g.anyEnabled) return false
        val day = PracticeLog.day(c, at) ?: PracticeLog.Day()
        if (g.sentences > 0 && day.drillDone < g.sentences) return false
        if (g.words > 0 && day.wordDone < g.words) return false
        if (g.expressions > 0 && day.expressionDone < g.expressions) return false
        if (g.shadows > 0 && day.shadowDone < g.shadows) return false
        return true
    }

    /**
     * Consecutive goal-met days ending today — or ending YESTERDAY when today
     * isn't done yet, so an unfinished morning doesn't read as a broken run.
     */
    fun streak(c: Context, g: Goals = load(c), now: Long = System.currentTimeMillis()): Int {
        if (!g.anyEnabled) return 0
        val cal = Calendar.getInstance().apply { timeInMillis = now }
        if (!met(c, g, cal.timeInMillis)) cal.add(Calendar.DAY_OF_YEAR, -1)
        var count = 0
        while (met(c, g, cal.timeInMillis)) {
            count += 1
            cal.add(Calendar.DAY_OF_YEAR, -1)
        }
        return count
    }
}
