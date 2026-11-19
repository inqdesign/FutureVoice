package com.roro.futurevoice

import com.roro.futurevoice.talk.PronunciationCall
import com.roro.futurevoice.talk.PronunciationContrast
import com.roro.futurevoice.talk.PronunciationCourse
import com.roro.futurevoice.talk.PronunciationJudge
import com.roro.futurevoice.talk.PronunciationJudge.Verdict
import com.roro.futurevoice.talk.PronunciationResult
import com.roro.futurevoice.talk.PronunciationRound
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `PronunciationContrastTests`: judging a sound by comparison. */
class PronunciationContrastTest {
    private fun word(w: String, accuracy: Int, error: String = "None") =
        PronunciationResult.Word(word = w, accuracy = accuracy, error = error)

    private fun take(words: List<PronunciationResult.Word>, alternate: List<Pair<String, Int>>?) =
        PronunciationResult(score = 60, accuracy = 60, fluency = 60, completeness = 100, locale = "ko-KR",
            words = words,
            alternates = alternate?.let { a ->
                listOf(PronunciationResult.Alternate(a.joinToString(" ") { it.first },
                    a.map { PronunciationResult.Alternate.Scored(it.first, it.second) }))
            })

    private val line = PronunciationRound.Line(text = "", focus = emptyList())
    private fun verdict(r: PronunciationResult, only: Set<String>? = null) =
        PronunciationJudge.verdict(r, line, "", emptyList(), "ko", only)

    @Test fun theTenseConsonantIsSwappedForThePlainOne() {
        assertEquals(listOf("예븐 카페에서 방을 샀어요."),
            PronunciationContrast.alternates("예쁜 카페에서 빵을 샀어요.", "ko.tense"))
    }

    @Test fun aFinalConsonantBeforeItLeavesNothingToCompare() {
        assertEquals(listOf("작꿍이랑"), PronunciationContrast.alternates("짝꿍이랑", "ko.tense"))
        assertEquals(emptyList<String>(), PronunciationContrast.alternates("먹을 때", "ko.tense"))
        assertEquals(emptyList<String>(), PronunciationContrast.alternates("있어요", "ko.tense"))
    }

    @Test fun eachMeasuredSoundHasItsSwap() {
        assertEquals(listOf("거비 보도"), PronunciationContrast.alternates("커피 포도", "ko.asp"))
        assertEquals(listOf("고기 거기"), PronunciationContrast.alternates("거기 고기", "ko.eoo"))
        assertEquals(listOf("구림"), PronunciationContrast.alternates("그림", "ko.eu"))
        assertEquals(listOf("까 가 가", "카 까 카"), PronunciationContrast.alternates("가 까 카", "ko.three"))
    }

    @Test fun otherTopicsAreNotJudgedThisWay() {
        assertEquals(emptyList<String>(), PronunciationContrast.alternates("빵을 먹어요", "ko.batchim"))
        assertEquals(emptyList<String>(), PronunciationContrast.alternates("think", "en.th"))
    }

    @Test fun aLowScoreAloneNeverStopsANativeReading() {
        val r = take(listOf(word("예쁜", 37), word("카페에서", 96)), listOf("예븐" to 30, "카페에서" to 96))
        assertEquals(Verdict.Pass(60), verdict(r))
    }

    @Test fun thePlainConsonantIsNotYet() {
        val r = take(listOf(word("빵을", 52), word("먹었어요", 95)), listOf("방을" to 97, "먹었어요" to 95))
        assertEquals(Verdict.NotYet("빵을", null, 60, "방을"), verdict(r))
    }

    @Test fun tooCloseToCallPasses() {
        val r = take(listOf(word("빵을", 80), word("먹었어요", 95)), listOf("방을" to 85, "먹었어요" to 95))
        assertEquals(Verdict.Pass(60), verdict(r))
    }

    @Test fun aWordOutsideTheLessonIsNeverCompared() {
        val r = take(listOf(word("빵을", 90), word("먹었어요", 40)), listOf("방을" to 60, "먹었어요" to 95))
        assertEquals(Verdict.Pass(60), verdict(r))
    }

    @Test fun aWordLeftOutIsNotYet() {
        val r = take(listOf(word("빵을", 90), word("먹었어요", 0, "Omission")), listOf("방을" to 60, "먹었어요" to 0))
        assertEquals(Verdict.NotYet("먹었어요", null, 60, null), verdict(r))
    }

    @Test fun noAlternateBackMeansNothingIsFailed() {
        assertEquals(Verdict.Pass(60), verdict(take(listOf(word("예쁜", 37), word("카페에서", 96)), null)))
    }

    @Test fun aReadingAfterAMissIsJudgedOnTheWordsThatMissed() {
        val r = take(listOf(word("빵을", 52), word("딸기를", 50)), listOf("방을" to 97, "달기를" to 90))
        assertEquals(listOf("빵을", "딸기를"), PronunciationJudge.missedWords(r, line, "", emptyList(), "ko"))
        assertEquals(Verdict.NotYet("딸기를", null, 60, "달기를"), verdict(r, setOf("딸기를")))
    }

    @Test fun onlyMeasuredSoundsAreOffered() {
        assertTrue(PronunciationCall.isOffered("en"))
        assertTrue(PronunciationCall.isOffered("ko"))
        for (other in listOf("ja", "de", "es", "fr", "zh")) assertFalse(other, PronunciationCall.isOffered(other))
        assertEquals(listOf("ko.tense", "ko.asp", "ko.three", "ko.eoo", "ko.eu"),
            PronunciationCourse.topics("ko").map { it.id })
    }
}
