package com.roro.futurevoice

import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.talk.PitchTracker
import com.roro.futurevoice.talk.PronunciationResult
import com.roro.futurevoice.talk.SpeechAnalyzer
import com.roro.futurevoice.talk.SpeechDelivery
import com.roro.futurevoice.talk.SpeechReading
import com.roro.futurevoice.talk.SpeechReadingLevel
import com.roro.futurevoice.talk.SpeechReadingScore
import com.roro.futurevoice.ui.speech.SpeechTakeSession
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.sin

/** iOS `SpeechReadingTests` and `SpeechDeliveryTests`, over the same fixture. */
class SpeechReadingTest {
    @Serializable
    private data class Row(val g: String, val sp: Double, val rh: Double, val ep: Double, val sl: Double,
                           val so: Double? = null, val h: Double? = null, val t: Int)

    private val rows: List<Row> by lazy {
        Json.decodeFromString(ListSerializer(Row.serializer()),
            javaClass.getResourceAsStream("/speech/reading_validation_20261108.json")!!.bufferedReader().readText())
    }

    private fun score(r: Row) = SpeechReadingScore(
        version = 5, gender = "male",
        parts = SpeechReading.parts(r.sp, r.rh, r.ep, r.sl, r.so), coverage = 1.0,
        speed = r.sp, rhythm = r.rh, pausesPer100 = r.ep, slipsPer100 = r.sl,
        soundAccuracy = r.so?.toInt(), slips = 0,
        extraPauses = emptyList(), held = emptyList(), missed = emptyList(), weakest = emptyList(),
    )
    private fun total(r: Row) = score(r).total

    /** The validation of 2026-11-08, held: every reading as the prototype
     *  scored it (within a point of rounding), and the groups where they sit. */
    @Test fun validationShape() {
        assertEquals(138, rows.size)
        for (r in rows) assertTrue("${r.g} ${r.sp} ${r.rh} ${r.ep}: ${total(r)} vs ${r.t}", abs(total(r) - r.t) <= 1)
        fun totals(g: String) = rows.filter { it.g == g }.map(::total).sorted()
        fun median(g: String) = totals(g).let { it[it.size / 2] }
        assertTrue("${median("narrator")}", median("narrator") in 95..99)
        assertTrue("${median("native")}", median("native") in 93..97)
        assertTrue("${median("learner")}", median("learner") in 60..75)
        assertFalse(totals("learner").contains(100))
        assertTrue("${totals("founder")}", totals("founder").all { it in 60..77 })
        val learners = rows.filter { it.g == "learner" }
        assertTrue(spearman(learners.map { total(it).toDouble() }, learners.mapNotNull { it.h }) >= 0.8)
    }

    /** The pause the native reading doesn't make is found, a stop after
     *  punctuation is not, and the word held far longer is named. */
    @Test fun extraPausesAndHeldWords() {
        val script = (1..30).map { "w$it" }
        val stops = MutableList(30) { SpeechDelivery.Stop.NONE }
        stops[5] = SpeechDelivery.Stop.SENTENCE
        val ref = mutableListOf<SpeechReading.TimedWord>()
        val take = mutableListOf<SpeechReading.TimedWord>()
        var t = 0; var u = 0
        script.forEachIndexed { i, w ->
            ref += SpeechReading.TimedWord(w, t, t + 250, false); t += 270
            val held = if (i == 10) 900 else 300
            take += SpeechReading.TimedWord(w, u, u + held, false); u += held + (if (i == 20 || i == 5) 600 else 20)
        }
        val r = SpeechReading.score(SpeechReading.timeline(take, script), SpeechReading.timeline(ref, script),
            script, stops, 0, 30, emptyList(), 97, emptyList(), 1.0, "male")!!
        assertEquals(listOf("w21"), r.extraPauses.map { it.after })
        assertEquals("w11", r.held.first().word)
        assertTrue(r.held.first().times > 2.5)
        assertFalse(r.isPerfect)
    }

    @Test fun halvesRoundAwayFromZeroLikeSwift() {
        assertEquals(3.0, SpeechReading.round(2.5), 0.0)
        assertEquals(1.0, SpeechReading.round(0.5), 0.0)
        assertEquals(-3.0, SpeechReading.round(-2.5), 0.0)
    }

    @Test fun thirteenBandsCoverEveryScore() {
        assertEquals(13, SpeechReadingLevel.entries.size)
        assertEquals(SpeechReadingLevel.NEWS_ANCHOR, SpeechReadingLevel.of(100))
        assertEquals(SpeechReadingLevel.AUDIOBOOK, SpeechReadingLevel.of(99))
        assertEquals(SpeechReadingLevel.IMMIGRATION, SpeechReadingLevel.of(60))
        assertEquals(SpeechReadingLevel.WARMING_UP, SpeechReadingLevel.of(0))
        assertEquals(100..100, SpeechReadingLevel.NEWS_ANCHOR.range)
        assertEquals(97..99, SpeechReadingLevel.AUDIOBOOK.range)
        assertEquals(0..34, SpeechReadingLevel.WARMING_UP.range)
        assertNull(SpeechReadingLevel.NEWS_ANCHOR.next)
        for (score in 0..100) assertTrue(score in SpeechReadingLevel.of(score).range)
    }

    /** The server's recheck of `total`, `submit_speech_reading_take`. */
    @Test fun coverageScalesTheTotal() {
        val s = score(Row("x", 0.97, 0.94, 0.0, 0.0, 97.0, null, 100))
        assertEquals(100, s.total)
        assertEquals(60, s.copy(coverage = 0.5).total)
        assertNull(s.focus)
    }

    /** iOS's synthesized Codable keys: an empty list is written, nil is left out. */
    @Test fun aScoreRoundTripsUnderIosKeys() {
        val s = score(rows.first()).copy(
            extraPauses = listOf(SpeechReadingScore.Pause("then", 1.0, 3)),
            held = listOf(SpeechReadingScore.Held("with", 4.6, 0.8, 0.1, 7)),
            weakest = listOf(SpeechDelivery.Sound("θ", "think", 40)),
        )
        val text = StoreJson.json.encodeToString(SpeechReadingScore.serializer(), s)
        assertEquals(setOf("version", "gender", "parts", "coverage", "speed", "rhythm", "pausesPer100", "slipsPer100",
            "soundAccuracy", "slips", "extraPauses", "held", "missed", "weakest"),
            Json.parseToJsonElement(text).jsonObject.keys)
        assertEquals(s, StoreJson.json.decodeFromString(SpeechReadingScore.serializer(), text))
        // What iOS writes for a take scored before the fields were added.
        val older = """{"version":5,"gender":"male","parts":{"speed":1,"rhythm":2,"pauses":3,"accuracy":4,"pronunciation":5},
            "coverage":1,"speed":0.5,"rhythm":0.5,"pausesPer100":0,"slipsPer100":0,"slips":0,
            "extraPauses":[{"after":"a","seconds":1}],"held":[{"word":"b","times":2.5}],"missed":[],"weakest":[]}"""
        val read = StoreJson.json.decodeFromString(SpeechReadingScore.serializer(), older)
        assertNull(read.extraPauses.first().index)
        assertNull(read.held.first().seconds)
    }

    @Test fun slipsCountOnlyWithinTheReading() {
        val a = com.roro.futurevoice.talk.ShadowScore.analyze("one two three four five six", "one two four five", "en")
        assertEquals(1, SpeechAnalyzer.slips(a.steps, "en"))
    }

    // MARK: - SpeechDeliveryTests

    private fun word(w: String, startMs: Int, ms: Int = 300, error: String = "None", sounds: List<Int> = listOf(95)) =
        PronunciationResult.Word(w, sounds.minOrNull(), error, startMs, ms,
            sounds.map { PronunciationResult.Phoneme("a", it, null) })

    private fun result(words: List<PronunciationResult.Word>, prosody: Int? = 90) =
        PronunciationResult(90, 95, 92, 100, prosody, "en-US", "", words)

    private fun timing(reference: String, words: List<PronunciationResult.Word>) =
        SpeechDelivery.timing(listOf(SpeechDelivery.Piece(reference, result(words))), "en")

    @Test fun pausesArePlacedAgainstTheScript() {
        val d = timing("Good morning, everyone. Welcome to the show", listOf(
            word("good", 0), word("morning", 300), word("everyone", 900), word("welcome", 2200),
            word("to", 2500), word("the", 3200), word("show", 3500)))
        assertEquals(1, d.midPauses)
        assertEquals(4, d.midBoundaries)
        assertEquals(90, d.prosody)
    }

    @Test fun insertionsAreSkippedAndMismatchesLeftOut() {
        val d = timing("one two three", listOf(word("one", 0), word("um", 300, error = "Insertion"),
            word("two", 700), word("three", 1300)))
        assertEquals(1, d.midPauses)
        assertEquals(1, d.midBoundaries)
        assertNull(timing("alpha beta", listOf(word("one", 0), word("two", 300), word("three", 600))).midPauses)
    }

    @Test fun dashesAndHyphensLineUp() {
        val d = timing("We met — briefly — at a well-known café.", listOf(
            word("we", 0), word("met", 300), word("briefly", 1100), word("at", 1900), word("a", 2200),
            word("well", 2900), word("known", 3200), word("café", 3500)))
        assertEquals(1, d.midPauses)
        assertEquals(5, d.midBoundaries)
        assertEquals("a", d.breaks.first().before)
    }

    @Test fun stumblesAreInteriorInsertions() {
        val d = timing("the quick brown fox jumps", listOf(
            word("so", 0, error = "Insertion"), word("the", 300), word("quick", 600),
            word("quick", 900, error = "Insertion"), word("um", 1200, error = "Insertion"),
            word("brown", 1500), word("fox", 1800), word("jumps", 2100), word("over", 2400, error = "Insertion")))
        assertEquals(listOf("quick"), d.stumbles)
    }

    @Test fun aWordSaidDifferentlyIsNotAStumbleOrAPause() {
        val d = timing("about the five-minute rule here", listOf(
            word("about", 0), word("the", 300),
            word("five", 600, error = "Insertion"), word("minutes", 900, error = "Insertion"),
            word("five-minute", 0, 0, error = "Omission"), word("rule", 1400), word("here", 1700)))
        assertEquals(emptyList<String>(), d.stumbles)
        assertEquals(0, d.midPauses)
        assertTrue(d.breaks.isEmpty())
    }

    @Test fun shortReadBackGivesWayToAzure() {
        val azure = "And guess what? This morning I ran for half an hour and I didn't even notice."
        val lost = SpeechTakeSession.pieceText("And guess what? This morning I went for", azure, "en")
        assertEquals(azure, lost?.first)
        assertEquals(true, lost?.second)
        assertEquals(azure, SpeechTakeSession.pieceText("", azure, "en")?.first)
        val kept = SpeechTakeSession.pieceText(
            "And guess what, this morning I went for half an hour and I did not even notice.", azure, "en")
        assertEquals(false, kept?.second)
        assertNull(SpeechTakeSession.pieceText(null, null, "en"))
        assertEquals("hi", SpeechTakeSession.pieceText("hi", "", "en")?.first)
    }

    @Test fun weakSoundsIsTheFifthPercentile() {
        assertEquals(95, timing("a", listOf(word("a", 0, sounds = List(39) { 95 } + 20))).weakSounds)
        assertEquals(20, timing("a", listOf(word("a", 0, sounds = List(9) { 95 } + 20))).weakSounds)
    }

    @Test fun pitchRangeFollowsTheVoice() {
        val rate = 16000.0
        fun tone(seconds: Double, hz: (Double) -> Double): FloatArray {
            var phase = 0.0
            return FloatArray((seconds * rate).toInt()) { i ->
                phase += 2 * PI * hz(i / rate) / rate
                (0.5 * sin(phase) + 0.2 * sin(2 * phase)).toFloat()
            }
        }
        val flat = PitchTracker.stats(tone(2.0) { 150.0 }, rate)
        assertNotNull(flat)
        assertTrue(flat!!.rangeSemitones < 0.5)
        val glide = PitchTracker.stats(tone(2.0) { t -> 120 * 2.0.pow(t / 2) }, rate)
        assertNotNull(glide)
        assertTrue("${glide!!.rangeSemitones}", glide.rangeSemitones > 7 && glide.rangeSemitones < 11)
    }

    private fun spearman(x: List<Double>, y: List<Double>): Double {
        fun ranks(v: List<Double>): List<Double> {
            val order = v.indices.sortedBy { v[it] }
            val r = MutableList(v.size) { 0.0 }
            var i = 0
            while (i < order.size) {
                var j = i
                while (j + 1 < order.size && v[order[j + 1]] == v[order[i]]) j++
                for (k in i..j) r[order[k]] = (i + j) / 2.0
                i = j + 1
            }
            return r
        }
        return SpeechReading.pearson(ranks(x), ranks(y)) ?: 0.0
    }
}
