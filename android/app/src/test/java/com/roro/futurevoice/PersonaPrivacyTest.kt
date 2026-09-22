package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.net.PublicPersonaClient
import com.roro.futurevoice.talk.ConversationEngine
import com.roro.futurevoice.talk.PersonaNote
import com.roro.futurevoice.talk.SessionSummarizer
import com.roro.futurevoice.talk.UserPersona
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The public-intro privacy rules (iOS 4a5e8df, CLAUDE.md "Find people" and
 * "The first call, and the memory it leaves"): the lenient note decode, the
 * three rungs, what a stranger-facing surface may read, and that `isPrivate`
 * is read but never written.
 */
class PersonaPrivacyTest {

    private fun decode(json: String): UserPersona =
        StoreJson.json.decodeFromString(UserPersona.serializer(), json)

    private fun note(fields: String) = decode("""{"displayName":"A","learnedNotes":[{$fields}]}""").learnedNotes

    @Test fun missingShareKeyIsNothing() {
        val n = note(""""id":"X","text":"runs on Saturdays","learnedAt":"2026-09-01T10:00:00Z"""").single()
        assertEquals(PersonaNote.Share.NOTHING, n.share)
        assertEquals(PersonaNote.Kind.FACT, n.kind)
        assertEquals("X", n.id)
    }

    @Test fun legacyIsPrivateTrueIsNothing() {
        assertEquals(PersonaNote.Share.NOTHING, note(""""text":"a","isPrivate":true""").single().share)
    }

    @Test fun legacyIsPrivateFalseIsAll() {
        assertEquals(PersonaNote.Share.ALL, note(""""text":"a","isPrivate":false""").single().share)
    }

    @Test fun shareOutranksLegacyLock() {
        assertEquals(PersonaNote.Share.GIST,
            note(""""text":"a","share":"gist","gist":"g","isPrivate":false""").single().share)
    }

    @Test fun unknownShareOrKindFallsBackSafely() {
        val n = note(""""text":"a","share":"public","kind":"forever"""").single()
        assertEquals(PersonaNote.Share.NOTHING, n.share)
        assertEquals(PersonaNote.Kind.FACT, n.kind)
    }

    @Test fun oldPersonaFileStillLoads() {
        // A persona written before learnedNotes/shareCorrections existed.
        val p = decode("""{"displayName":"Eunggyu","city":"Munich","englishSituations":["Client calls"],
            "updatedAt":"2026-08-01T00:00:00Z"}""")
        assertEquals("Eunggyu", p.displayName)
        assertTrue(p.learnedNotes.isEmpty())
        assertTrue(p.shareCorrections.isEmpty())
    }

    @Test fun oneBadNoteDoesNotEmptyTheNotebookOrFailTheLoad() {
        val p = decode("""{"displayName":"A","learnedNotes":[{"id":"1"},{"text":"kept"}, "junk"],
            "shareCorrections":[{"text":"x","from":"weird","to":"all","at":"2026-09-01T00:00:00Z"}]}""")
        assertEquals(listOf("kept"), p.learnedNotes.map { it.text })
        assertTrue(p.shareCorrections.isEmpty())
    }

    @Test fun learnedNotesOfWrongTypeReadsEmpty() {
        assertTrue(decode("""{"displayName":"A","learnedNotes":"nope"}""").learnedNotes.isEmpty())
    }

    @Test fun isPrivateIsNeverWrittenAndFieldsRoundTrip() {
        val n = PersonaNote(id = "N", text = "two kids", learnedAt = 1_757_000_000_000,
            share = PersonaNote.Share.GIST, kind = PersonaNote.Kind.NOW,
            heard = "dropped the kids off", gist = "a parent", why = "family")
        val json = StoreJson.json.encodeToString(UserPersona.serializer(), UserPersona(learnedNotes = listOf(n)))
        val obj = Json.parseToJsonElement(json).jsonObject["learnedNotes"].toString()
        assertFalse(obj.contains("isPrivate"))
        assertTrue(obj.contains("\"share\": \"gist\"") || obj.contains("\"share\":\"gist\""))
        val back = decode(json).learnedNotes.single()
        assertEquals(n.copy(learnedAt = 1_757_000_000_000 / 1000 * 1000), back)
    }

    private val sample = UserPersona(
        displayName = "Eunggyu", city = "Munich", country = "Germany", lengthOfStay = "3 years",
        occupation = "Founder", household = "Wife and 4yo daughter at Kita",
        situations = listOf("Kita / school", "Client calls"),
        freeNotes = "Thinking about moving back next year.",
        learnedNotes = listOf(
            PersonaNote(text = "runs along the Isar", share = PersonaNote.Share.ALL),
            PersonaNote(text = "one daughter in kindergarten", share = PersonaNote.Share.GIST, gist = "a parent"),
            PersonaNote(text = "money is tight", share = PersonaNote.Share.NOTHING, gist = "growing a company"),
            PersonaNote(text = "gist rung with no gist", share = PersonaNote.Share.GIST),
            PersonaNote(text = "old trip", share = PersonaNote.Share.ALL, kind = PersonaNote.Kind.NOW,
                learnedAt = System.currentTimeMillis() - 40L * 86_400_000L),
        ),
    )

    @Test fun strangerLinesHonourTheRungs() {
        assertEquals(listOf("runs along the Isar", "a parent"), sample.strangerLines)
    }

    @Test fun composedIntroReadsOnlyStrangerFacingFields() {
        val intro = PublicPersonaClient.composedIntro(sample)
        assertEquals("Founder\nMunich · 3 years\nKita / school, Client calls\nruns along the Isar\na parent", intro)
        assertFalse(intro.contains("Wife"))
        assertFalse(intro.contains("moving back"))
        assertFalse(intro.contains("money"))
    }

    @Test fun castCounterpartGetsOnlyStrangerLines() {
        val prompt = ConversationEngine.conversationSystemPrompt(
            targetLanguage = "en", nativeLanguage = "ko", level = CefrLevel.B1, persona = sample,
            cast = ConversationEngine.Cast(name = "Lena", intro = "I teach piano in Vienna."),
        )
        assertTrue(prompt.contains("a parent"))
        assertFalse(prompt.contains("money is tight"))
        assertFalse(prompt.contains("one daughter in kindergarten"))
        assertFalse(prompt.contains("Wife and 4yo"))
        assertFalse(prompt.contains("moving back"))
    }

    @Test fun fluentSelfStillKnowsTheWholeNotebook() {
        val block = ConversationEngine.personaBlock(sample, "English")
        assertTrue(block.contains("money is tight"))
        assertTrue(block.contains("Wife and 4yo"))
        assertFalse(block.contains("old trip")) // expired `now` line
    }

    @Test fun aboutUserReadsBothShapes() {
        val payload = Json.parseToJsonElement("""{"about_user":[
            "plain string line",
            {"text":"two kids","heard":"dropped them off","kind":"fact","share":"gist","gist":"a parent","why":"family","replaces":null},
            {"text":"back from Seoul","kind":"now","share":"all","replaces":2},
            {"text":"legacy","private":false},
            {"text":"gist without gist","share":"gist"},
            {"no_text":true}
        ]}""").jsonObject
        val a = SessionSummarizer.aboutUser(payload)
        assertEquals(5, a.size)
        assertEquals(PersonaNote.Share.NOTHING, a[0].share)
        assertEquals(PersonaNote.Share.GIST, a[1].share)
        assertEquals("dropped them off", a[1].heard)
        assertNull(a[1].replaces)
        assertEquals(PersonaNote.Kind.NOW, a[2].kind)
        assertEquals(2, a[2].replaces)
        assertEquals(PersonaNote.Share.ALL, a[3].share)
        // "The gist" with no gist falls to the rung below it.
        assertEquals(PersonaNote.Share.NOTHING, a[4].toNote("gist without gist", "S").share)
    }

    @Test fun absorbAppliesUpdatesAndDedupes() {
        val old = PersonaNote(id = "OLD", text = "planning a trip to Seoul", kind = PersonaNote.Kind.NOW)
        val p = UserPersona(learnedNotes = listOf(old, PersonaNote(text = "Runs, along the Isar!")))
        val next = p.absorbing(
            notes = listOf(PersonaNote(text = "runs along the isar")),
            updates = listOf(UserPersona.NoteUpdate("OLD", PersonaNote(text = "back from Seoul"))),
        )
        assertEquals(listOf("Runs, along the Isar!", "back from Seoul"), next.learnedNotes.map { it.text })
    }

    @Test fun shareCorrectionsRecordOnlyMoves() {
        val a = PersonaNote(id = "A", text = "a", share = PersonaNote.Share.NOTHING)
        val b = PersonaNote(id = "B", text = "b", share = PersonaNote.Share.ALL)
        val p = UserPersona(learnedNotes = listOf(a.copy(share = PersonaNote.Share.ALL), b))
            .recordingShareCorrections(listOf(a, b))
        val c = p.shareCorrections.single()
        assertEquals("a", c.text)
        assertEquals(PersonaNote.Share.NOTHING, c.from)
        assertEquals(PersonaNote.Share.ALL, c.to)
        assertNotNull(c.at)
    }
}
