package com.roro.futurevoice

import com.roro.futurevoice.data.TextScript
import com.roro.futurevoice.talk.SpokenWords
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `CorrectionGuardTests` (1.1.1), case for case — plan 5.3. A "fix" that
 *  changes only what the transcriber chose must never reach the learner. */
class CorrectionGuardTest {

    @Test fun englishContractionsDigitsAndPunctuationAreTheTranscribers() {
        assertTrue(SpokenWords.saysTheSameThing("I am building an app", "I'm building an app.", "en"))
        assertTrue(SpokenWords.saysTheSameThing("I said it 3 times", "I said it three times", "en"))
        assertTrue(SpokenWords.saysTheSameThing("a check-in at 9", "a check in at nine", "en"))
        assertFalse(SpokenWords.saysTheSameThing("I very like it", "I really like it", "en"))
    }

    @Test fun koreanSpacingIsTheTranscribers() {
        assertTrue(SpokenWords.saysTheSameThing("한번 해볼게요", "한 번 해 볼게요.", "ko"))
        assertTrue(SpokenWords.saysTheSameThing("못해요", "못 해요", "ko"))
        assertFalse(SpokenWords.saysTheSameThing("밥 먹었어", "밥 먹었어요", "ko"))
    }

    @Test fun koreanReorderAloneIsNotACorrection() {
        assertTrue(SpokenWords.changesOnlyWordOrder("먹었어 아까 라면", "아까 라면 먹었어.", "ko"))
        assertFalse(SpokenWords.changesOnlyWordOrder("나는 너를 보고 싶어 어제", "어제 너를 보고 싶었어", "ko"))
        assertFalse(SpokenWords.changesOnlyWordOrder("밥 먹었어", "밥 먹었어", "ko"))
        assertFalse(SpokenWords.changesOnlyWordOrder("밥 먹었어", "밥 먹었어요", "ko"))
        assertFalse(SpokenWords.changesOnlyWordOrder("I yesterday went home", "I went home yesterday", "en"))
    }

    @Test fun scriptCheckPerLanguage() {
        assertTrue(TextScript.isInTargetScript("Show me the clock once.", "en"))
        assertFalse(TextScript.isInTargetScript("한번 나올게 해줘 시계.", "en"))
        assertTrue(TextScript.isInTargetScript("nawana 앱을 만들고 있어요", "ko"))
        assertTrue(TextScript.isInTargetScript("時計を見せて。", "ja"))
        assertTrue(TextScript.isInTargetScript("nawana アプリを作っています", "ja"))
        assertFalse(TextScript.isInTargetScript("Show me 時計", "ja"))
        assertTrue(TextScript.isInTargetScript("Ich hätte gern einen Kaffee, bitte.", "de"))
        assertFalse(TextScript.isInTargetScript("", "en"))
    }
}
