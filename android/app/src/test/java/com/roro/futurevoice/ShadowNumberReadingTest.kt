package com.roro.futurevoice

import com.roro.futurevoice.talk.ShadowScore
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `ShadowEngineTests` number readings: a year read as written is not a slip. */
class ShadowNumberReadingTest {
    private fun clean(target: String, learner: String, language: String = "en") =
        ShadowScore.analyze(target, learner, language).steps.all { it.op == ShadowScore.DiffOp.MATCH }

    /** The JVM has no ICU speller; the device's answers for the numbers used here. */
    private fun withSpeller(table: Map<Int, String>, body: () -> Unit) {
        val old = ShadowScore.spellOut
        ShadowScore.spellOut = { n, language -> table[n] ?: old(n, language) }
        try { body() } finally { ShadowScore.spellOut = old }
    }

    @Test fun german() = withSpeller(mapOf(
        1911 to "ein\u00ADtausend\u00ADneun\u00ADhundert\u00ADelf", 19 to "neunzehn", 11 to "elf",
        21 to "ein\u00ADund\u00ADzwanzig", 1 to "eins", 100 to "ein\u00ADhundert",
        2 to "zwei", 0 to "null", 9 to "neun",
    )) {
        assertTrue(clean("Das war neunzehnhundertelf in Paris", "Das war 1911 in Paris", "de"))
        assertTrue(clean("Das war 1911 in Paris", "Das war neunzehnhundertelf in Paris", "de"))
        assertTrue(clean("Ich bin einundzwanzig Jahre alt", "Ich bin 21 Jahre alt", "de"))
        assertTrue(clean("Wir treffen uns um ein Uhr", "Wir treffen uns um 1 Uhr", "de"))
        assertTrue(clean("Das kostet hundert Euro", "Das kostet 100 Euro", "de"))
    }

    @Test fun spanish() = withSpeller(mapOf(
        21 to "veintiuno", 1 to "uno", 2 to "dos", 0 to "cero", 200 to "doscientos",
        1911 to "mil novecientos once", 9 to "nueve",
    )) {
        assertTrue(clean("Tengo veintiún años", "Tengo 21 años", "es"))
        assertTrue(clean("Quiero un café", "Quiero 1 café", "es"))
        assertTrue(clean("Fue en mil novecientos once", "Fue en 1911", "es"))
        assertTrue(clean("Hay doscientas personas", "Hay 200 personas", "es"))
    }

    @Test fun korean() = withSpeller(mapOf(
        3 to "삼", 20 to "이십", 5 to "오", 1911 to "천구백십일", 2 to "이", 0 to "영", 1 to "일", 9 to "구",
    )) {
        assertTrue(clean("세 시에 만나요", "3시에 만나요", "ko"))
        assertTrue(clean("3시에 만나요", "세 시에 만나요", "ko"))
        assertTrue(clean("저는 스무 살이에요", "저는 20살이에요", "ko"))
        assertTrue(clean("사과 다섯 개 주세요", "사과 5개 주세요", "ko"))
        assertTrue(clean("천구백십일 년에 사라졌어요", "1911년에 사라졌어요", "ko"))
        assertFalse(clean("세 시에 만나요", "삼 시에 만나요", "ko"))
    }

    @Test fun yearHeardAsDigitsMatchesItsSpokenForm() {
        assertTrue(clean("in August of nineteen eleven, while the museum was closed",
            "in August of 1911 while the museum was closed"))
    }

    @Test fun numbersMeetWhicheverSideWroteDigits() {
        assertTrue(clean("back in 1911 it was gone", "back in nineteen eleven it was gone"))
        assertTrue(clean("it was nineteen oh five then", "it was 1905 then"))
        assertTrue(clean("we sold one hundred and five tickets", "we sold 105 tickets"))
        assertTrue(clean("we sold 105 tickets", "we sold one hundred and five tickets"))
        assertTrue(clean("room one oh one is free", "room 101 is free"))
        assertTrue(clean("twenty twenty-four was long", "2024 was long"))
        assertTrue(clean("about 1911 people came", "about one thousand nine hundred eleven people came"))
    }

    @Test fun wrongYearIsStillWrong() {
        assertFalse(clean("in nineteen eleven", "in 1912"))
    }
}
