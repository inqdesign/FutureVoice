package com.roro.futurevoice

import com.roro.futurevoice.data.SpeechPrompterRecord
import com.roro.futurevoice.data.SpeechTake
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.talk.PronunciationResult
import com.roro.futurevoice.talk.SpeechDelivery
import com.roro.futurevoice.talk.SpeechLit
import com.roro.futurevoice.talk.SpeechPrompterTrack
import com.roro.futurevoice.ui.speech.SpeechTakeSession
import com.roro.futurevoice.ui.speech.SpeechVideoStyle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** The camera-only take's record of its script — iOS `SpeechVideoComposerTests`
 *  (`8704a191`): when each word was said, how far a replay has got, and what
 *  is lit. */
class SpeechVideoTest {
    private fun assessed(words: List<List<Any?>>, startMs: Int): SpeechDelivery.Piece {
        val text = words.joinToString(" ") { it[0] as String }
        val items = words.map { (word, start, end, error) ->
            PronunciationResult.Word(word as String, 90, (error as String?) ?: "None",
                offsetMs = start as Int, durationMs = (end as Int) - start)
        }
        return SpeechDelivery.Piece(text, PronunciationResult(90, 90, 90, 100, null, "en-US", text, items), startMs)
    }

    @Test fun wordTimesAddThePieceStartAndPassThroughAMissedWord() {
        val pieces = listOf(
            assessed(listOf(listOf("hello", 1000, 1200, null), listOf("well", 1300, 1400, null),
                listOf("known", 1400, 1600, null)), 0),
            // Said again from the last piece's overlap: not said in this one.
            assessed(listOf(listOf("known", 0, 0, "Omission"), listOf("again", 500, 700, null),
                listOf("friend", 800, 1000, null)), 1500),
        )
        val words = listOf("Hello,", "well-known", "world", "again", "friend.", "never", "reached.")
        val times = SpeechPrompterTrack.wordTimes(words, "en", pieces)
        assertNotNull(times)
        // Times are the take's; "world" was missed and passes between its
        // neighbours; the words after the last one heard get no time at all.
        assertEquals(listOf(1000, 1300, 1600, 2000, 2300), times!!.first)
        assertEquals(listOf(1200, 1600, 2000, 2200, 2500), times.second)
    }

    @Test fun wordTimesGiveUpWhenLittleWasHeard() {
        val words = (0 until 20).map { "w$it" }
        val pieces = listOf(assessed(listOf(listOf("w0", 0, 100, null), listOf("w1", 100, 200, null),
            listOf("w19", 300, 400, null)), 0))
        assertNull(SpeechPrompterTrack.wordTimes(words, "en", pieces))
    }

    @Test fun reachedWalksTheWords() {
        var record = SpeechPrompterRecord(390.0, 28.0, true, "a b", "en", listOf(0.0))
        assertNull(record.reached(1.0))
        record = record.copy(wordStarts = listOf(1000, 2000), wordEnds = listOf(1500, 2500))
        assertEquals(SpeechPrompterRecord.Reached(0, 0.0), record.reached(0.5))
        assertEquals(SpeechPrompterRecord.Reached(0, 0.5), record.reached(1.25))
        assertEquals(SpeechPrompterRecord.Reached(1, 0.0), record.reached(1.75))
        assertEquals(SpeechPrompterRecord.Reached(2, 0.0), record.reached(3.0))
    }

    @Test fun offsetGlidesBetweenTheMarks() {
        val record = SpeechPrompterRecord(390.0, 28.0, false, "a b", "en", listOf(0.0, 10.0, 30.0))
        assertEquals(0.0, record.offset(-1.0), 1e-9)
        assertEquals(5.0, record.offset(0.05), 1e-9)
        assertEquals(20.0, record.offset(0.15), 1e-9)
        assertEquals(30.0, record.offset(9.0), 1e-9)
        assertEquals(0.0, record.copy(offsets = emptyList()).offset(1.0), 1e-9)
    }

    /** Nothing said: nothing lit. Mid-word: the column above its line, and
     *  its line up to where the reading has got. Past the last word: all of
     *  the last line up to its end. */
    @Test fun litIsTheColumnAboveAndTheLineSoFar() {
        val words = listOf(SpeechLit.Box(24f, 0f, 74f, 30f), SpeechLit.Box(80f, 0f, 120f, 30f),
            SpeechLit.Box(24f, 40f, 104f, 70f))
        assertEquals(emptyList<SpeechLit.Box>(), SpeechLit.boxes(words, 390f, 0, 0.0))
        assertEquals(emptyList<SpeechLit.Box>(), SpeechLit.boxes(emptyList(), 390f, 3, 0.0))
        assertEquals(listOf(SpeechLit.Box(0f, 0f, 390f, 0f), SpeechLit.Box(0f, 0f, 100f, 30f)),
            SpeechLit.boxes(words, 390f, 1, 0.5))
        assertEquals(listOf(SpeechLit.Box(0f, 0f, 390f, 40f), SpeechLit.Box(0f, 40f, 24f, 70f)),
            SpeechLit.boxes(words, 390f, 2, 0.0))
        assertEquals(listOf(SpeechLit.Box(0f, 0f, 390f, 40f), SpeechLit.Box(0f, 40f, 104f, 70f)),
            SpeechLit.boxes(words, 390f, 3, 0.0))
    }

    /** The merge cuts the picture before the voice, so the script's movement
     *  loses the same lead; the voice's own lead comes off the word times. */
    @Test fun theRecordStartsWhereTheVideoDoes() {
        val base = SpeechPrompterRecord(390.0, 28.0, true, "hello world", "en")
        val pieces = listOf(assessed(listOf(listOf("hello", 1000, 1200, null), listOf("world", 1300, 1500, null)), 0))
        val px = listOf(0f, 3f, 6f, 9f, 12.4f)
        // The picture started 0.2 s before the voice: two marks go.
        val early = SpeechTakeSession.prompterRecord(base, px, 0.2, 3f, listOf("hello", "world"), "en", pieces)!!
        assertEquals(listOf(2.0, 3.0, 4.0), early.offsets)
        assertEquals(listOf(1000, 1300), early.wordStarts)
        // The voice started 0.3 s before the picture: the words move up.
        val late = SpeechTakeSession.prompterRecord(base, px, -0.3, 3f, listOf("hello", "world"), "en", pieces)!!
        assertEquals(listOf(0.0, 1.0, 2.0, 3.0, 4.0), late.offsets)
        assertEquals(listOf(700, 1000), late.wordStarts)
        assertEquals(listOf(900, 1200), late.wordEnds)
        // Too little heard: the script still rolls, nothing is lit.
        val quiet = SpeechTakeSession.prompterRecord(base, px, 0.0, 3f, listOf("hello", "world"), "en", emptyList())!!
        assertNull(quiet.wordStarts)
        assertNull(SpeechTakeSession.prompterRecord(null, px, 0.0, 3f, emptyList(), "en", emptyList()))
    }

    /** A take written by iOS reads here with its record, and one written here
     *  carries iOS's keys. */
    @Test fun aTakeKeepsItsRecordAcrossTheWire() {
        val ios = """
        {"id":"A","scriptId":"B","createdAt":"2026-11-10T08:00:00Z","durationSeconds":12.5,
         "audioFilename":"take-A.wav","videoFilename":"take-A.mov","transcript":"hi",
         "metrics":{"accuracy":90,"rate":140,"rateLow":130,"rateHigh":150,"paceScore":100,"pausesAtBreaks":1,
                    "breaks":1,"hesitations":0,"pauseScore":100,"fillers":0,"fillerScore":100,"steadiness":90,
                    "missed":[],"overall":92},
         "prompter":{"width":390,"textSize":28,"dark":true,"text":"Hi there.","language":"en",
                     "offsets":[0,0.5,1],"wordStarts":[100,400],"wordEnds":[300,700],"somethingNew":1}}
        """
        val take = StoreJson.json.decodeFromString(SpeechTake.serializer(), ios)
        assertEquals(390.0, take.prompter!!.width, 0.0)
        assertEquals(listOf(0.0, 0.5, 1.0), take.prompter!!.offsets)
        assertEquals(listOf(300, 700), take.prompter!!.wordEnds)
        assertEquals(true, take.videoIsCameraOnly)
        val written = StoreJson.json.encodeToString(SpeechTake.serializer(), take)
        for (key in listOf("\"prompter\"", "\"width\"", "\"textSize\"", "\"dark\"", "\"text\"", "\"language\"",
            "\"offsets\"", "\"wordStarts\"", "\"wordEnds\"")) {
            assertEquals("missing $key", true, written.contains(key))
        }
        val plain = take.copy(prompter = null)
        assertEquals(false, StoreJson.json.encodeToString(SpeechTake.serializer(), plain).contains("\"prompter\""))
        assertEquals(false, plain.videoIsCameraOnly)
    }

    @Test fun styleNamesAreTheOnesIosStores() {
        assertEquals(listOf("cameraOnly", "fullScreen", "split"), SpeechVideoStyle.entries.map { it.raw })
        assertEquals(SpeechVideoStyle.FULL_SCREEN, SpeechVideoStyle.from(null))
        assertEquals(SpeechVideoStyle.SPLIT, SpeechVideoStyle.from("split"))
    }
}
