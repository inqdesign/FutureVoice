package com.roro.futurevoice.data

import android.content.Context
import com.roro.futurevoice.talk.GrammarIssue
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionSummary
import com.roro.futurevoice.talk.TurnRole

/**
 * "Misheard — exclude from scoring" (iOS `SessionStore.excludeTurnFromScoring`
 * / `excludeMishearing`). The learner says a line on the transcript is the
 * recognizer's, not theirs: the turn is flagged `excludedFromScoring`, so
 * every reader that judges the learner skips it (scorecard metrics, the
 * book's chapters, Say it again, carryovers, the weekly report and recap,
 * the weekly test, the call's goal chips, the vocab pool); the grammar slips
 * quoted from it are dropped and the stored grammar score is rescaled to the
 * slips that remain; and the drill cards minted from that turn are deleted
 * (one of DrillStore's two deliberate exceptions to "nothing leaves the
 * deck"). There is no undo — iOS offers none either.
 *
 * The rewrite is PURE and lives here so it can be tested; [SessionStore]
 * applies it under its own lock and [apply] does the rest.
 */
object MisheardExclusion {

    /** The session with [turnId] flagged, its slips dropped and the grammar
     *  score rescaled — or null when there's nothing to do (no such turn, not
     *  the learner's, already flagged). */
    fun excludeTurn(session: Session, turnId: String): Session? {
        val idx = session.turns.indexOfFirst { it.id == turnId }
        if (idx < 0) return null
        val turn = session.turns[idx]
        if (turn.role != TurnRole.USER || turn.excludedFromScoring) return null

        val turns = session.turns.toMutableList()
        turns[idx] = turn.copy(excludedFromScoring = true)
        val transcriptKey = normalizedForMatch(turn.transcript)
        val summary = session.summary?.let { sm ->
            rescaled(sm, sm.grammarIssues.filterNot { issue ->
                val needle = normalizedForMatch(issue.quote)
                needle.isNotEmpty() && transcriptKey.contains(needle)
            })
        }
        return session.copy(turns = turns, summary = summary)
    }

    /**
     * A slip in the grammar review marked Misheard: resolved back to the
     * learner turn it was quoted from and that turn excluded (which drops the
     * slip with its siblings). When the quote can't be traced to a turn, the
     * slip alone goes, with the same rescale. Returns the updated session and
     * the excluded turn's id (null when only the slip was dropped).
     */
    fun excludeIssue(session: Session, issueId: String): Pair<Session, String?>? {
        val summary = session.summary ?: return null
        val issue = summary.grammarIssues.firstOrNull { it.id == issueId } ?: return null
        val needle = normalizedForMatch(issue.quote)
        if (needle.isNotEmpty()) {
            val turn = session.turns.firstOrNull {
                it.role == TurnRole.USER && normalizedForMatch(it.transcript).contains(needle)
            }
            if (turn != null) return excludeTurn(session, turn.id)?.let { it to turn.id }
        }
        val updated = session.copy(summary = rescaled(summary,
            summary.grammarIssues.filterNot { it.id == issueId }, alwaysRescale = true))
        return updated to null
    }

    /**
     * The grammar score shrinks its deduction from 100 in proportion to the
     * slips that survived — removing the only slip returns it to 100. iOS
     * rescales a turn exclusion only when a slip went, and an untraceable
     * slip always ([alwaysRescale]); kept the same so both read one number.
     */
    internal fun rescaled(summary: SessionSummary, kept: List<GrammarIssue>,
                          alwaysRescale: Boolean = false): SessionSummary {
        val before = summary.grammarIssues.size
        val removed = before - kept.size
        val card = summary.scorecard
        if (before == 0 || card == null || (!alwaysRescale && removed <= 0)) {
            return summary.copy(grammarIssues = kept)
        }
        val deduction = (100 - card.grammar.score).toDouble()
        val remaining = kept.size.toDouble() / before
        // Math.round is half-up, which for a non-negative product is Swift's
        // `.rounded()` (half away from zero).
        val score = minOf(100, 100 - Math.round(deduction * remaining).toInt())
        return summary.copy(grammarIssues = kept,
            scorecard = card.copy(grammar = card.grammar.copy(score = score)))
    }

    /**
     * The latest weekly report is voided when the talk falls inside the window
     * it was written from (iOS `reassessAfterEvidenceChange`): its level and
     * mistakes were judged with the misheard line in them. [reports] newest
     * first.
     */
    fun reportToVoid(reports: List<WeeklyReport>, session: Session): WeeklyReport? {
        val latest = reports.firstOrNull() ?: return null
        val whenAt = session.endedAt ?: session.startedAt
        val windowStart = reports.getOrNull(1)?.periodEnd ?: Long.MIN_VALUE
        return latest.takeIf { whenAt > windowStart && whenAt <= latest.periodEnd }
    }

    /** iOS `SessionStore.normalizedForMatch`: lowercased, cut on anything
     *  that isn't a letter, digit, mark or apostrophe, joined by one space —
     *  the normalization a slip quote was verified with. */
    fun normalizedForMatch(text: String): String {
        val out = StringBuilder()
        var pendingSpace = false
        for (ch in text.lowercase()) {
            val keep = ch.isLetterOrDigit() || ch == '\'' || when (Character.getType(ch).toByte()) {
                Character.NON_SPACING_MARK, Character.COMBINING_SPACING_MARK,
                Character.ENCLOSING_MARK -> true
                else -> false
            }
            if (keep) {
                if (pendingSpace && out.isNotEmpty()) out.append(' ')
                pendingSpace = false
                out.append(ch)
            } else pendingSpace = true
        }
        return out.toString()
    }

    /**
     * Flag [turnId] in [sessionId] and carry it through: the session written
     * through the store's own funnel, the turn's drill cards deleted, a
     * weekly report judged with the line in it voided (the Progress page then
     * offers it again from the same window), and every open screen told.
     * Returns the stored session, or null when nothing changed.
     */
    suspend fun excludeTurn(context: Context, sessionId: String, turnId: String,
                            language: String): Session? {
        val updated = SessionStore.shared(context).excludeTurnFromScoring(sessionId, turnId, language)
            ?: return null
        afterExclusion(context, updated, turnId, language)
        return updated
    }

    /** The grammar review's swipe: [excludeIssue] through the store. */
    suspend fun excludeIssue(context: Context, sessionId: String, issueId: String,
                             language: String): Session? {
        val (updated, turnId) = SessionStore.shared(context).excludeMishearing(sessionId, issueId, language)
            ?: return null
        if (turnId != null) afterExclusion(context, updated, turnId, language)
        else StoreEvents.bump()
        return updated
    }

    private suspend fun afterExclusion(context: Context, session: Session, turnId: String,
                                       language: String) {
        DrillStore.shared(context).deleteForTurn(turnId, language)
        val reports = WeeklyReportStore.shared(context)
        reportToVoid(reports.load(language), session)?.let { reports.delete(it.id, language) }
        StoreEvents.bump()
    }
}
