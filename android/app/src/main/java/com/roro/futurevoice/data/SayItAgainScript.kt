package com.roro.futurevoice.data

import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.DialogueEngineTurn
import com.roro.futurevoice.talk.PhraseFeedback
import com.roro.futurevoice.talk.ScenarioCurriculum
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TurnRole
import java.text.Normalizer

/**
 * One finished talk — or a Watch book's scene — turned into a script the
 * learner can run AGAIN, speaking their own side of it (iOS
 * `SayItAgainScript`, 2026-09-27). For a talk, their lines are replaced by
 * the corrected versions; a scene was written fluent, so its lines are read
 * as they are.
 *
 * It is the WHOLE conversation, not the corrections: every one of the
 * learner's turns comes up, in order, between the answers they actually got.
 *
 * Pure and derived, like everything else a talk book shows: nothing here is
 * persisted, so a talk re-summarized changes the script the next time it is
 * opened.
 *
 * What a learner reads on their turn, in order of preference:
 *
 * 1. **The turn's own rewrite** (`Turn.suggestion.alternative`) — their WHOLE
 *    turn, said the way a fluent speaker would. The one case that is review
 *    MATERIAL: it carries the book's correction id, so a passing read masters
 *    the Drill chapter exactly as a shadow take on that line does. **Only if
 *    it actually covers the turn** ([coversWholeTurn]) — a record from before
 *    the whole-turn contract carries a one-sentence fragment, which is
 *    demoted: the prompter reads what they SAID and the better wording rides
 *    along as the note.
 * 2. **The summary's phrase fixes spliced in** (`SessionSummary.phrasesUsed`)
 *    — put back where they were said, the rest of the sentence standing. No
 *    attempt id: that curriculum item is minted with a fresh id on every
 *    build, so no attempt could ever be matched to it.
 * 3. **What they said.** A turn nobody corrected is a turn they got right,
 *    and reading it back keeps the run a CONVERSATION.
 *
 * A turn flagged as misheard is dropped outright — its transcript is the
 * recognizer's mistake. The fluent self's answer to it stays.
 */
object SayItAgainScript {

    data class Step(
        /** The source turn's id — also the key the fluent self's recording
         *  is kept under (`turn-audio/<id>.wav`). */
        val id: String,
        /** True for the learner's own line (read on the prompter). */
        val isSpoken: Boolean,
        /** What is on the prompter (a learner step) or on screen. */
        val text: String,
        /** What the learner actually said, for the word diff. Empty unless
         *  this line was corrected. */
        val said: String = "",
        /** The correction's reason — coaching text, native language. */
        val note: String = "",
        /** Where a passing take is filed. Non-null only for case 1 above. */
        val attemptId: String? = null,
    ) {
        val isCorrected: Boolean get() = said.isNotEmpty()
    }

    fun build(session: Session): List<Step> {
        val language = session.targetLanguage
        val fixes = session.summary?.phrasesUsed.orEmpty()
        val out = ArrayList<Step>()
        for (turn in session.turns) {
            val transcript = turn.transcript.trim()
            if (transcript.isEmpty()) continue
            if (turn.role != TurnRole.USER) {
                out.add(Step(id = turn.id, isSpoken = false, text = transcript))
                continue
            }
            if (turn.excludedFromScoring) continue
            val rewrite = turn.suggestion?.alternative.orEmpty().trim()
            if (rewrite.isNotEmpty() && coversWholeTurn(rewrite, transcript, language,
                    fromWholeTurnContract = turn.suggestion?.fixes != null)) {
                out.add(Step(id = turn.id, isSpoken = true, text = rewrite,
                    said = transcript, note = turn.suggestion?.reason.orEmpty(),
                    attemptId = TalkCurriculum.correctionId(turn.id)))
                continue
            }
            // Their own line, with whatever the summary verified put back
            // where it was said. A fragment rewrite becomes the note.
            val spliced = applyPhraseFixes(transcript, fixes)
            val note = if (spliced.note.isEmpty() && rewrite.isNotEmpty()) rewrite else spliced.note
            out.add(Step(id = turn.id, isSpoken = true, text = spliced.text,
                said = if (spliced.changed) transcript else "", note = note))
        }
        return out
    }

    /**
     * A Watch book's scene, run again with the learner on their own side. A
     * scene has no corrections — every line was written fluent — so the "user"
     * lines are shown as they are, and each carries the id of the book's own
     * Shadow-chapter item for that sentence (matched by normalized text, the
     * mapping Watch's "Shadow this" uses), so a passing read files there.
     */
    fun build(scene: List<DialogueEngineTurn>, shadowLines: List<ScenarioCurriculum.Item>): List<Step> {
        val lineIds = HashMap<String, String>()
        for (item in shadowLines) lineIds.putIfAbsent(CarryoverDetector.normalized(item.text), item.id)
        return scene.mapNotNull { turn ->
            val text = turn.text.trim()
            if (text.isEmpty()) return@mapNotNull null
            val isLearner = turn.speaker == "user"
            Step(id = turn.id, isSpoken = isLearner, text = text,
                attemptId = if (isLearner) lineIds[CarryoverDetector.normalized(text)] else null)
        }
    }

    /**
     * Does this rewrite stand in for the WHOLE turn? A suggestion written
     * under the whole-turn contract carries a `fixes` array (never null), so
     * its presence settles it outright — length cannot: `어 그 그니까 그게
     * 뭐냐면 좀 복잡해` → `그게 뭐냐면 좀 복잡해` is the contract working. Only a
     * record from before it is judged by size, where the old ≤15-word cap
     * makes the ratio safe.
     */
    const val WHOLE_TURN_WORD_RATIO = 0.6
    const val SHORT_TURN_WORDS = 6

    fun coversWholeTurn(rewrite: String, said: String, language: String,
                        fromWholeTurnContract: Boolean): Boolean {
        if (fromWholeTurnContract) return true
        val spoken = WordSplitter.count(said, language)
        if (spoken <= SHORT_TURN_WORDS) return true
        return WordSplitter.count(rewrite, language) >= spoken * WHOLE_TURN_WORD_RATIO
    }

    data class Spliced(val text: String, val changed: Boolean, val note: String)

    /**
     * Put each verified phrase fix back where it was said. A quote that isn't
     * in this line belongs to another turn; a fix that changes nothing is
     * dropped, so a run can't claim a correction it didn't make. Matching
     * ignores case and accents, as iOS's `.caseInsensitive, .diacriticInsensitive`.
     */
    fun applyPhraseFixes(line: String, fixes: List<PhraseFeedback>): Spliced {
        var text = line
        var note = ""
        for (fix in fixes) {
            val said = fix.userSaid.trim()
            val better = fix.fluentAlternative.trim()
            if (said.isEmpty() || better.isEmpty()) continue
            if (CarryoverDetector.normalized(said) == CarryoverDetector.normalized(better)) continue
            val at = fold(text).indexOf(fold(said))
            if (at < 0) continue
            text = text.substring(0, at) + better + text.substring(at + said.length)
            if (note.isEmpty()) note = fix.reason
        }
        return Spliced(text, text != line, note)
    }

    /**
     * Case- and accent-folded, ONE CHAR PER CHAR so an index found in the
     * folded text is an index in the original. A character whose decomposition
     * is more than a base + marks (a Hangul syllable → jamo) is kept whole.
     */
    private fun fold(s: String): String {
        val sb = StringBuilder(s.length)
        for (ch in s) {
            val base = Normalizer.normalize(ch.toString(), Normalizer.Form.NFD)
                .filter { Character.getType(it) != Character.NON_SPACING_MARK.toInt() }
            sb.append(if (base.length == 1) base[0].lowercaseChar() else ch.lowercaseChar())
        }
        return sb.toString()
    }
}
