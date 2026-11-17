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

    @Test fun thousandWrittenAsDigitsAddsNoOne() {
        assertTrue(clean("more than eighty-six thousand people, aged fifty-one to ninety",
            "more than eighty-six 1000 people aged fifty-one to 90"))
        assertTrue(clean("about a thousand people came", "about 1000 people came"))
        assertTrue(clean("a hundred and five tickets", "105 tickets"))
        assertFalse(clean("eighty-six thousand people", "eighty-six 2000 people"))
    }

    @Test fun pieceIsPlacedInTheScriptByItsOwnWords() {
        val script = "Have you ever heard that learning a language can slow down ageing? It sounds almost too good to be true, so let's look at what the research actually says. In 2025, a large study was published in the journal Nature Aging. Researchers looked at more than eighty-six thousand people, aged fifty-one to ninety, in twenty-seven European countries. People who spoke only one language were more likely to be ageing faster than expected. And the more languages people spoke, the lower that risk was."
        val words = script.split(" ")
        fun span(heard: String) = ShadowScore.scriptRange(heard, words, "en")?.let { words.slice(it).joinToString(" ") }
        org.junit.Assert.assertEquals(
            "thousand people, aged fifty-one to ninety, in twenty-seven European countries. People who spoke only one language",
            span("1000 people aged 51 to 90 in 27 European countries. People who spoke only one language"))
        org.junit.Assert.assertEquals(
            "In 2025, a large study was published in the journal Nature Aging. Researchers looked at more than eighty-six",
            span("In 2025 a large study was published in a journal Nature Aging. Researchers looked at more than 86"))
        org.junit.Assert.assertEquals(
            "It sounds almost too good to be true, so let's look at what the research actually says.",
            span("it sounds almost too good to be true so um let's look what the research actually says"))
        org.junit.Assert.assertNull(span("sorry I lost my place can we start this one again please"))
        org.junit.Assert.assertNull(span("was"))
        val twice = "the more you read the better and the more you read the faster".split(" ")
        org.junit.Assert.assertEquals(7..10, ShadowScore.scriptRange("the more you read", twice, "en", 10))
        org.junit.Assert.assertEquals(0..3, ShadowScore.scriptRange("the more you read", twice, "en", 0))
    }

    @Test fun spellingAndCompoundsAreNotSlips() {
        assertTrue(clean("more likely to be ageing faster", "more likely to be aging faster"))
        assertTrue(clean("my favourite colour is grey", "my favorite color is gray"))
        assertTrue(clean("we realised the centre was cancelled", "we realized the center was canceled"))
        assertTrue(clean("she had a feeling about a shortcut", "she had a feeling about a short cut"))
        assertTrue(clean("through every breakup, every bad haircut", "through every break up every bad hair cut"))
        assertTrue(clean("a happy journey every day", "a happy journey everyday"))
        assertTrue(clean("make sure your seatbelts are fastened", "make sure your seat belts are fastened"))
        assertTrue(clean("All right, everyone, come closer", "Alright everyone come closer"))
        assertTrue(clean("okay, e-books are fine", "OK ebooks are fine"))
        assertFalse(clean("I learned it for four years", "I learnt it for for years"))
        assertFalse(clean("she won the prize", "she won the price"))
        assertFalse(clean("we went in to see him", "we went to see him"))
    }

    @Test fun coverageHasToBeReadTo() {
        val script = "Have you ever heard that learning a language can slow down ageing? It sounds almost too good to be true, so let's look at what the research actually says. In the study, people who spoke only one language were more likely to be ageing faster than expected, and that can't hurt you."
        fun coverage(said: String) = com.roro.futurevoice.talk.SpeechAnalyzer.coverage(ShadowScore.analyze(script, said, "en").steps)
        assertTrue(coverage("chuchu chuchu thank you thank you hello hello anger hello boy boy") < 0.1)
        assertTrue(coverage("you return home hello help help a car car car piece piece piece") < 0.1)
        org.junit.Assert.assertEquals(1.0, coverage(script), 0.001)
        org.junit.Assert.assertEquals(12.0 / 53, coverage("Have you ever heard that learning language can slow down aging"), 0.03)
    }

    @Test fun wrongYearIsStillWrong() {
        assertFalse(clean("in nineteen eleven", "in 1912"))
    }

    @Test fun writtenFormsAreTheWordsSaid() {
        assertTrue(clean("about one thousand five hundred people", "about 1,500 people"))
        assertTrue(clean("it costs five dollars", "it costs $5"))
        assertTrue(clean("just one dollar", "just $1"))
        assertTrue(clean("fifty percent of them", "50% of them"))
        assertTrue(clean("on the twenty-first of May", "on the 21st of May"))
        assertTrue(clean("the first time, the third try", "the 1st time, the 3rd try"))
        assertTrue(clean("in the nineteen sixties", "in the 1960s"))
        assertTrue(clean("back in the eighties", "back in the 80s"))
        assertTrue(clean("three point five million", "3.5 million"))
        assertTrue(clean("Doctor Smith and Mister Lee", "Dr. Smith and Mr. Lee"))
        assertTrue(clean("Dr. Smith is in", "Doctor Smith is in"))
        assertTrue(clean("at three thirty", "at 3:30"))
        org.junit.Assert.assertEquals("a hundred dreams, mister darcy",
            ShadowScore.written("a hundred dreams, Mr Darcy", "en"))
    }

    @Test fun writtenFormsInOtherLanguages() {
        withSpeller(mapOf(50 to "fünfzig", 5 to "fünf", 0 to "null")) {
            assertTrue(clean("fünfzig Prozent der Leute", "50% der Leute", "de"))
            assertTrue(clean("Das kostet fünf Euro", "Das kostet 5 €", "de"))
        }
        withSpeller(mapOf(50 to "cincuenta", 5 to "cinco", 0 to "cero")) {
            assertTrue(clean("el cincuenta por ciento", "el 50%", "es"))
        }
        withSpeller(mapOf(50 to "오십", 1500 to "천오백", 5 to "오", 0 to "영", 1 to "일")) {
            assertTrue(clean("오십 퍼센트예요", "50%예요", "ko"))
            assertTrue(clean("천오백 원이에요", "1,500원이에요", "ko"))
        }
    }
}
