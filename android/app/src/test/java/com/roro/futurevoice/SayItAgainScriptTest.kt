package com.roro.futurevoice

import com.roro.futurevoice.data.SayItAgainScript
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.TalkCurriculum
import com.roro.futurevoice.talk.DialogueEngineTurn
import com.roro.futurevoice.talk.PhraseFeedback
import com.roro.futurevoice.talk.ScenarioCurriculum
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.SessionSummary
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnFix
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.TurnSuggestion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `SayItAgainScript` decides what the learner reads on their own turn (iOS
 * `SayItAgainScriptTests`). Three things it must never get wrong: a turn's
 * own correction outranks everything, a phrase fix goes back where it was
 * SAID, and only a line that is review material carries the id a passing
 * read is filed under.
 */
class SayItAgainScriptTest {

    private fun turn(
        text: String,
        role: TurnRole = TurnRole.USER,
        suggestion: TurnSuggestion? = null,
        misheard: Boolean = false,
        id: String = StoreJson.newId(),
    ) = Turn(id = id, role = role, transcript = text, suggestion = suggestion,
        excludedFromScoring = misheard)

    private fun session(turns: List<Turn>, fixes: List<PhraseFeedback> = emptyList()) = Session(
        userId = "u", targetLanguage = "en", topic = "Interview",
        startedAt = System.currentTimeMillis() - 300_000, endedAt = System.currentTimeMillis(),
        turns = turns,
        summary = if (fixes.isEmpty()) null else SessionSummary(phrasesUsed = fixes))

    // ── What lands on the prompter

    @Test fun turnCorrectionIsWhatTheLearnerReads() {
        val id = StoreJson.newId()
        val steps = SayItAgainScript.build(session(listOf(
            turn("it go really well",
                suggestion = TurnSuggestion("it went really well", "past tense"), id = id))))
        assertEquals(1, steps.size)
        assertEquals("it went really well", steps[0].text)
        assertEquals("it go really well", steps[0].said)
        assertTrue(steps[0].isCorrected)
        assertEquals("past tense", steps[0].note)
        // Material: a passing read has to master the book's own correction.
        assertEquals(TalkCurriculum.correctionId(id), steps[0].attemptId)
    }

    @Test fun aPhraseFixIsSplicedBackWhereItWasSaid() {
        val steps = SayItAgainScript.build(session(
            listOf(turn("Honestly, it go really well and I felt prepared.")),
            fixes = listOf(PhraseFeedback(userSaid = "it go really well",
                fluentAlternative = "it went really well", reason = "past tense"))))
        assertEquals("Honestly, it went really well and I felt prepared.", steps[0].text)
        assertTrue(steps[0].isCorrected)
        // A summary correction's item is minted with a fresh id every build.
        assertNull(steps[0].attemptId)
    }

    @Test fun turnCorrectionOutranksThePhraseFix() {
        val steps = SayItAgainScript.build(session(
            listOf(turn("it go really well",
                suggestion = TurnSuggestion("it went really well — I was ready", "past tense"))),
            fixes = listOf(PhraseFeedback(userSaid = "it go really well",
                fluentAlternative = "it went really well", reason = "past tense"))))
        assertEquals("it went really well — I was ready", steps[0].text)
        assertNotNull(steps[0].attemptId)
    }

    @Test fun anUncorrectedTurnIsReadBackAsSaid() {
        val steps = SayItAgainScript.build(session(listOf(turn("I felt prepared."))))
        assertEquals("I felt prepared.", steps[0].text)
        assertFalse(steps[0].isCorrected)
        assertEquals("", steps[0].said)
        assertNull(steps[0].attemptId)
    }

    // ── The line has to be the whole turn (2026-09-27)

    /** The reported bug: a legacy one-sentence rewrite replaced a 29-word
     *  turn and the re-run answered a question nobody had asked. */
    @Test fun aLegacyFragmentDoesNotReplaceTheTurn() {
        val said = "Hey, um yeah, we can definitely do so, but I had a bad experience " +
            "uh right uh before and checking if that is consistent uh issue or temporal issue."
        val steps = SayItAgainScript.build(session(listOf(
            // fixes == null dates it: written before the whole-turn contract.
            turn(said, suggestion = TurnSuggestion(
                "I want to check if that is a consistent issue or a temporary issue.",
                "관사와 단어 선택")))))
        assertEquals("the prompter must not lose the rest of the turn", said, steps[0].text)
        assertEquals("the better wording rides along instead of replacing the line",
            "I want to check if that is a consistent issue or a temporary issue.", steps[0].note)
        assertNull("a fragment is not the book's correction", steps[0].attemptId)
    }

    @Test fun aWholeTurnRewriteIsWhatTheLearnerReads() {
        val id = StoreJson.newId()
        val said = "Hey, um yeah, we can definitely do so, but I had a bad experience " +
            "uh right uh before and checking if that is consistent uh issue or temporal issue."
        val rewrite = "Hey, yeah, we can definitely do that, but I had a bad experience right " +
            "before, and I'm checking if that's a consistent issue or a temporary issue."
        val steps = SayItAgainScript.build(session(listOf(
            turn(said, suggestion = TurnSuggestion(rewrite, "더 자연스러운 흐름",
                fixes = listOf(TurnFix(was = "temporal issue", now = "temporary issue",
                    why = "'temporal'은 시간에 관한 뜻이에요"))), id = id))))
        assertEquals(rewrite, steps[0].text)
        assertEquals(said, steps[0].said)
        assertEquals(TalkCurriculum.correctionId(id), steps[0].attemptId)
    }

    /** Hesitation removal is legitimately much shorter — the `fixes` marker,
     *  not length, is what says it covers the turn. */
    @Test fun hesitationRemovalIsNotAFragment() {
        val steps = SayItAgainScript.build(session(listOf(
            turn("어 그 그니까 그게 뭐냐면 좀 복잡해.",
                suggestion = TurnSuggestion("그게 뭐냐면 좀 복잡해.", "군더더기 없이",
                    fixes = emptyList())))))
        assertEquals("그게 뭐냐면 좀 복잡해.", steps[0].text)
        assertNotNull(steps[0].attemptId)
    }

    // ── What never reaches it

    @Test fun aMisheardTurnIsDroppedButTheAnswerToItStays() {
        val steps = SayItAgainScript.build(session(listOf(
            turn("So — how did it go?", role = TurnRole.FLUENT_SELF),
            turn("show me the clock once",
                suggestion = TurnSuggestion("show me the clock", "article"), misheard = true),
            turn("Glad to hear it.", role = TurnRole.FLUENT_SELF),
        )))
        assertEquals(listOf(false, false), steps.map { it.isSpoken })
        assertEquals(listOf("So — how did it go?", "Glad to hear it."), steps.map { it.text })
    }

    @Test fun anEmptyTurnIsNotAStep() {
        val steps = SayItAgainScript.build(session(listOf(turn("   "), turn("Real line."))))
        assertEquals(1, steps.size)
    }

    @Test fun stepIdIsTheTurnIdSoStoredAudioStillResolves() {
        val id = StoreJson.newId()
        val steps = SayItAgainScript.build(session(listOf(
            turn("So — how did it go?", role = TurnRole.FLUENT_SELF, id = id))))
        assertEquals(id, steps[0].id)
    }

    // ── A Watch scene

    @Test fun aSceneReadsTheLearnersSideAndPlaysTheOther() {
        val mine = DialogueEngineTurn(speaker = "user", text = "Could I get it with oat milk?")
        val theirs = DialogueEngineTurn(speaker = "counterpart", text = "Sure, anything else?")
        val steps = SayItAgainScript.build(listOf(theirs, mine), emptyList())
        assertEquals(listOf(false, true), steps.map { it.isSpoken })
        // Written fluent — nothing is marked as a fix.
        assertFalse(steps[1].isCorrected)
        assertEquals(listOf(theirs.id, mine.id), steps.map { it.id })
    }

    @Test fun aSceneLineIsFiledUnderTheBooksShadowItem() {
        val mine = DialogueEngineTurn(speaker = "user", text = "Could I get it with oat milk?")
        val item = ScenarioCurriculum.Item(text = "could I get it with oat milk")
        val steps = SayItAgainScript.build(listOf(mine), listOf(item))
        // Case and punctuation don't separate a line from its chapter item.
        assertEquals(item.id, steps[0].attemptId)
    }

    @Test fun theCounterpartsLinesAreNeverFiled() {
        val theirs = DialogueEngineTurn(speaker = "counterpart", text = "Sure, anything else?")
        val item = ScenarioCurriculum.Item(text = "Sure, anything else?")
        val steps = SayItAgainScript.build(listOf(theirs), listOf(item))
        assertNull(steps[0].attemptId)
    }

    // ── The splice itself

    @Test fun aFixThatChangesNothingIsNotACorrection() {
        val out = SayItAgainScript.applyPhraseFixes("I went to the bank.",
            listOf(PhraseFeedback(userSaid = "I went to the bank",
                fluentAlternative = "I Went to the Bank", reason = "")))
        assertFalse(out.changed)
    }

    @Test fun aQuoteFromAnotherTurnIsIgnored() {
        val out = SayItAgainScript.applyPhraseFixes("I felt prepared.",
            listOf(PhraseFeedback(userSaid = "it go really well",
                fluentAlternative = "it went really well", reason = "")))
        assertEquals("I felt prepared.", out.text)
        assertFalse(out.changed)
    }

    @Test fun severalFixesInOneLineAllLand() {
        val out = SayItAgainScript.applyPhraseFixes("it go well and I is happy", listOf(
            PhraseFeedback(userSaid = "it go well", fluentAlternative = "it went well", reason = "a"),
            PhraseFeedback(userSaid = "I is happy", fluentAlternative = "I was happy", reason = "b")))
        assertEquals("it went well and I was happy", out.text)
        assertTrue(out.changed)
        // The first fix's reason is the one shown.
        assertEquals("a", out.note)
    }

    // ── Android-only: the splice's folding keeps indices honest

    @Test fun theSpliceIgnoresCaseAndAccents() {
        val out = SayItAgainScript.applyPhraseFixes("Ich habe ÜBER das Problem gesprochen",
            listOf(PhraseFeedback(userSaid = "uber das problem", fluentAlternative = "über das Problem",
                reason = "")))
        assertEquals("Ich habe über das Problem gesprochen", out.text)
    }

    @Test fun aHangulQuoteSplicesByItsOwnSyllables() {
        val out = SayItAgainScript.applyPhraseFixes("어제 학교에 가요 그리고 공부했어",
            listOf(PhraseFeedback(userSaid = "학교에 가요", fluentAlternative = "학교에 갔어",
                reason = "시제")))
        assertEquals("어제 학교에 갔어 그리고 공부했어", out.text)
    }
    // ── A cut-in is not a turn (iOS 2026-09-29)

    private fun heard(text: String, id: String = StoreJson.newId()) =
        turn(text, role = TurnRole.FLUENT_SELF, id = id).copy(durationMs = 2400)

    /** Some audio arrived; the flag is what decides. */
    private fun cutIn(text: String) =
        turn(text, role = TurnRole.FLUENT_SELF).copy(talkedOver = true, durationMs = 800)

    @Test fun theTwoHalvesOfACutInSentenceAreOneLine() {
        val steps = SayItAgainScript.build(session(listOf(
            heard("How was the weekend?"),
            turn("I went to the"),
            cutIn("Oh nice, where did you go?"),
            turn("mountains with my sister."),
            heard("That sounds lovely."),
        ))) { false }
        assertEquals(listOf(false, true, false), steps.map { it.isSpoken })
        assertEquals("I went to the mountains with my sister.", steps[1].text)
        assertEquals("That sounds lovely.", steps[2].text)
    }

    @Test fun aLineWithNoAudioAtAllCountsAsUnheard() {
        // Talks saved before the flag: nothing played, so nothing recorded.
        val steps = SayItAgainScript.build(session(listOf(
            turn("I went to the"),
            turn("Where?", role = TurnRole.FLUENT_SELF),
            turn("mountains."),
        ))) { false }
        assertEquals(1, steps.size)
        assertEquals("I went to the mountains.", steps[0].text)
    }

    @Test fun aHeardAnswerStillSeparatesTwoLines() {
        val id = StoreJson.newId()
        // Duration lost, but its recording is on disk.
        val answer = turn("Where?", role = TurnRole.FLUENT_SELF, id = id)
        val steps = SayItAgainScript.build(session(listOf(
            turn("I went away."), answer, turn("To the mountains."),
        ))) { it == id }
        assertEquals(3, steps.size)
    }

    @Test fun aChainOfCutInsIsOneLine() {
        val steps = SayItAgainScript.build(session(listOf(
            turn("So I"), cutIn("Mm?"), turn("was thinking"), cutIn("Yes?"), turn("about moving."),
        ))) { false }
        assertEquals(listOf("So I was thinking about moving."), steps.map { it.text })
    }

    @Test fun mergedHalvesKeepTheirCorrectionsAndTheDiffCoversBoth() {
        val a = StoreJson.newId()
        val steps = SayItAgainScript.build(session(listOf(
            turn("yesterday I go to",
                suggestion = TurnSuggestion("yesterday I went to", "past tense"), id = a),
            cutIn("Where to?"),
            turn("the museum."),
        ))) { false }
        assertEquals(1, steps.size)
        assertEquals("yesterday I went to the museum.", steps[0].text)
        assertEquals("yesterday I go to the museum.", steps[0].said)
        assertEquals("past tense", steps[0].note)
        // Exactly one half was material, and the merged line contains it whole.
        assertEquals(TalkCurriculum.correctionId(a), steps[0].attemptId)
        assertEquals(a, steps[0].id)
    }

    @Test fun anUnspacedLanguageJoinsWithoutASpace() {
        val s = session(listOf(turn("昨日は"), cutIn("うん"), turn("山に行った。")))
            .copy(targetLanguage = "ja")
        val steps = SayItAgainScript.build(s) { false }
        assertEquals(listOf("昨日は山に行った。"), steps.map { it.text })
    }

    @Test fun aCutInAtTheEndOfTheCallIsLeftAlone() {
        val steps = SayItAgainScript.build(session(listOf(turn("I think"), cutIn("Go on?")))) { false }
        assertEquals(2, steps.size)
    }

    // ── Android-only: the flag is written only when true

    @Test fun talkedOverIsEncodedOnlyWhenTrue() {
        val plain = StoreJson.json.encodeToString(Turn.serializer(),
            Turn(role = TurnRole.FLUENT_SELF, transcript = "Hi"))
        assertFalse(plain.contains("talkedOver"))
        val flagged = StoreJson.json.encodeToString(Turn.serializer(),
            Turn(role = TurnRole.FLUENT_SELF, transcript = "Hi", talkedOver = true))
        assertTrue(flagged.contains("\"talkedOver\""))
        assertTrue(StoreJson.json.decodeFromString(Turn.serializer(), flagged).talkedOver)
    }
}
