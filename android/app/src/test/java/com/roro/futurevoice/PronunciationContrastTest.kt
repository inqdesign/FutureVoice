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

    @Test fun spanishFrenchGermanSwapInsideTheWord() {
        assertEquals(listOf("Mi pero es caro."), PronunciationContrast.alternates("Mi perro es caro.", "es.rr"))
        assertEquals(listOf("Mi perro es carro."), PronunciationContrast.alternates("Mi perro es caro.", "es.r"))
        assertEquals(listOf("El nino come jamón."), PronunciationContrast.alternates("El niño come jamón.", "es.ny"))
        assertEquals(listOf("La yente come yamón."), PronunciationContrast.alternates("La gente come jamón.", "es.j"))
        assertEquals(listOf("Tu es sur la voitoure."), PronunciationContrast.alternates("Tu es sur la voiture.", "fr.u"))
        assertEquals(listOf("Le professour est soul."), PronunciationContrast.alternates("Le professeur est seul.", "fr.eu"))
        assertEquals(listOf("Pendont la chonson", "Pendant la chansan"),
            PronunciationContrast.alternates("Pendant la chanson", "fr.nasal"))
        assertEquals(listOf("Ich bin mude für heute."), PronunciationContrast.alternates("Ich bin müde für heute.", "de.ue"))
        assertEquals(listOf("Mien Wien in Wien", "Mein Wein in Wein"),
            PronunciationContrast.alternates("Mein Wein in Wien", "de.eiie"))
        assertEquals(listOf("Ich mag die Kirsche nischt, auch."),
            PronunciationContrast.alternates("Ich mag die Kirche nicht, auch.", "de.ich"))
    }

    @Test fun japaneseTakesOneBeatOutPerAlternate() {
        assertEquals(listOf("ビルとコーヒーをください。", "ビールとコヒーをください。"),
            PronunciationContrast.alternates("ビールとコーヒーをください。", "ja.long"))
        assertEquals(listOf("切手を買て待っています。", "切手を買って待ています。"),
            PronunciationContrast.alternates("切手を買って待っています。", "ja.tsu"))
        assertEquals(emptyList<String>(), PronunciationContrast.alternates("おばあさんが来ました。", "ja.long"))
    }

    @Test fun japaneseIsLinedUpByLetter() {
        fun ja(words: List<Pair<String, Int>>, alt: List<Pair<String, Int>>) =
            PronunciationResult(score = 80, accuracy = 80, fluency = 80, completeness = 100, locale = "ja-JP",
                words = words.map { word(it.first, it.second) },
                alternates = listOf(PronunciationResult.Alternate("", alt.map { PronunciationResult.Alternate.Scored(it.first, it.second) })))
        fun v(r: PronunciationResult) = PronunciationJudge.verdict(r, line, "", emptyList(), "ja")
        assertEquals(Verdict.Pass(80), v(ja(listOf("先頭" to 85, "に" to 97, "立っ" to 94, "て" to 94, "歌い" to 82),
            listOf("先頭" to 85, "に" to 94, "立て" to 8, "歌い" to 82))))
        assertEquals(Verdict.NotYet("立っ", null, 80, "立て"), v(ja(listOf("先頭" to 85, "に" to 97, "立っ" to 40, "て" to 90, "歌い" to 82),
            listOf("先頭" to 85, "に" to 94, "立て" to 92, "歌い" to 82))))
        assertEquals(Verdict.Pass(80), v(ja(listOf("ビール" to 78, "を" to 97), listOf("ビル" to 90, "を" to 97))))
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
        for (other in listOf("ja", "de", "es", "fr")) assertTrue(other, PronunciationCall.isOffered(other))
        assertFalse(PronunciationCall.isOffered("zh"))
        assertEquals(listOf("es.rr", "es.r", "es.j", "es.ny"), PronunciationCourse.topics("es").map { it.id })
        assertEquals(listOf("fr.u", "fr.nasal", "fr.eu"), PronunciationCourse.topics("fr").map { it.id })
        assertEquals(listOf("de.eiie", "de.ich", "de.oe", "de.ue"), PronunciationCourse.topics("de").map { it.id }.sorted())
        assertEquals(listOf("ja.long", "ja.tsu"), PronunciationCourse.topics("ja").map { it.id })
        assertEquals(emptyList<String>(), PronunciationCourse.topics("zh").map { it.id })
        assertEquals(listOf("ko.tense", "ko.asp", "ko.three", "ko.eoo", "ko.eu"),
            PronunciationCourse.topics("ko").map { it.id })
    }
}
