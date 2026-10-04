package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.SpeechRegister
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.data.knowsLearnersLife
import com.roro.futurevoice.talk.ConversationCharacter
import com.roro.futurevoice.talk.ConversationEngine
import com.roro.futurevoice.talk.CorrectionOnlyPrompt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS `CounterpartCharacterTests` (`ede039e`), case for case: a cast call's
 * character by kind of person, and how the two address each other. Reported:
 * a friend was voiced in polite speech, and a public figure (BTS RM) opened
 * every call on the same museum fact.
 */
class CounterpartCharacterTest {

    private fun person(kind: String? = "Friend") = Counterpart(
        name = "Boram",
        relationship = "College roommate",
        background = "We still argue about the dishes.",
        relationshipKind = kind,
    )

    private fun block(c: Counterpart, lang: String = "ko") =
        ConversationCharacter.characterBlock(ConversationEngine.Cast.of(c), lang,
            com.roro.futurevoice.data.LanguageCatalog.englishName(lang))

    @Test fun ownPersonIsNotANewAcquaintance() {
        val b = block(person())
        assertTrue(b.contains("ALREADY KNOW"))
        assertFalse(b.contains("new acquaintances"))
        assertTrue("the relationship must reach the call", b.contains("College roommate"))
        assertTrue("the note is shared history, not a self-intro", b.contains("Your history together"))
    }

    @Test fun setRegisterIsSpelledOutInTheTargetLanguage() {
        val c = person().copy(myRegister = SpeechRegister.CASUAL, theirRegister = SpeechRegister.CASUAL)
        assertTrue(block(c, "ko").contains("반말"))
        assertTrue(block(c, "de").contains("du"))
    }

    @Test fun unsetOwnPersonLetsTheRelationshipDecide() {
        assertTrue(block(person(kind = null)).contains("form of address your relationship"))
    }

    @Test fun strangerDefaultsToPolite() {
        val b = block(person(kind = null).copy(remoteId = "abc"))
        assertTrue(b.contains("new acquaintances"))
        assertTrue(b.contains("해요체"))
    }

    /** A Find-people persona with no saved row yet is a stranger, spoken to politely. */
    @Test fun poolPersonaWithoutARowIsAPoliteStranger() {
        val b = ConversationCharacter.characterBlock(
            ConversationEngine.Cast(name = "Mina", intro = "I run a bakery."), "ko", "Korean")
        assertTrue(b.contains("new acquaintances"))
        assertTrue(b.contains("해요체"))
    }

    /**
     * A public figure is its confirmed identity and nothing else — an old
     * row's stored summary (the museums) must never reach the call.
     */
    @Test fun publicFigureIsTheIdentityAlone() {
        val c = person(kind = "Public figure").copy(
            isPublicFigure = true, publicIdentity = "BTS RM · rapper",
            background = "Loves visiting art museums.", commonTopics = "art exhibitions")
        val b = block(c)
        assertTrue(b.contains("BTS RM · rapper"))
        assertFalse(b.contains("museums"))
        assertFalse(b.contains("exhibitions"))
        assertFalse(b.contains("ALREADY KNOW"))
    }

    /**
     * The measured correction prompts must not move for any call without a
     * hand-set level (`scripts/correction-probe.py` numbers stand on them).
     */
    @Test fun correctionPromptsUnchangedWithoutASetLevel() {
        fun prompt(lang: String, c: Counterpart?) = CorrectionOnlyPrompt.build(lang, "en", CefrLevel.B1,
            relationshipLine = ConversationCharacter.relationshipRegisterLine(lang,
                c?.let { ConversationEngine.Cast.of(it) }))
        val base = CorrectionOnlyPrompt.build("ko", "en", CefrLevel.B1)
        assertEquals(base, prompt("ko", null))
        assertEquals(base, prompt("ko", person()))
        val set = person().copy(myRegister = SpeechRegister.POLITE)
        assertTrue(prompt("ko", set).contains("EXCEPTION FOR THIS CALL"))
        // English has no form of address to get wrong.
        assertEquals(prompt("en", null), prompt("en", set))
        // The in-call turn instruction follows the same rule.
        assertEquals(ConversationEngine.turnOutputInstruction("ko", "en"),
            ConversationEngine.turnOutputInstruction("ko", "en", ConversationEngine.Cast.of(person())))
        assertTrue(ConversationEngine.turnOutputInstruction("ko", "en", ConversationEngine.Cast.of(set))
            .contains("EXCEPTION FOR THIS CALL"))
    }

    @Test fun closeKindsKnowTheLearnersLifeStrangersNever() {
        assertTrue(person(kind = "Friend").knowsLearnersLife)
        assertFalse(person(kind = "Manager").knowsLearnersLife)
        assertFalse(person(kind = "Friend").copy(remoteId = "abc", knowsMyLife = true).knowsLearnersLife)
    }

    /** A cast call never carries the fluent self's warmth rule as its own voice. */
    @Test fun futureSelfPromptCarriesSelfWarmth() {
        val p = ConversationEngine.conversationSystemPrompt("ko", "en", CefrLevel.B1)
        assertTrue(p.contains("WARM MEANS INTERESTED, NOT AFFECTIONATE"))
    }

    /** iOS's encoder dropped `isPublicFigure` until 2026-09-28; pin it here too. */
    @Test fun roundTripKeepsPublicFigureAndSpeech() {
        val c = person(kind = "Public figure").copy(
            isPublicFigure = true, publicIdentity = "BTS RM · rapper",
            myRegister = SpeechRegister.POLITE, theirRegister = SpeechRegister.CASUAL,
            iCallThem = "남준 씨", knowsMyLife = false)
        val json = StoreJson.json.encodeToString(Counterpart.serializer(), c)
        val back = StoreJson.json.decodeFromString(Counterpart.serializer(), json)
        assertEquals(true, back.isPublicFigure)
        assertEquals("BTS RM · rapper", back.publicIdentity)
        assertEquals(SpeechRegister.POLITE, back.myRegister)
        assertEquals(SpeechRegister.CASUAL, back.theirRegister)
        assertEquals("남준 씨", back.iCallThem)
        assertEquals(false, back.knowsMyLife)
        assertEquals("Public figure", back.relationshipKind)
        assertTrue(json.contains("\"myRegister\": \"polite\""))
    }

    /** A rung a newer build wrote reads as "not set", never a lost person. */
    @Test fun unknownRungDecodesAsUnset() {
        val back = StoreJson.json.decodeFromString(Counterpart.serializer(),
            """{"id":"X","name":"Boram","myRegister":"royal","theirRegister":null}""")
        assertEquals("Boram", back.name)
        assertNull(back.myRegister)
        assertNull(back.theirRegister)
    }
}
