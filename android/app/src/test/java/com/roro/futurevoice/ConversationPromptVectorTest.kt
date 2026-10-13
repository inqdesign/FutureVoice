package com.roro.futurevoice

import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.talk.ConversationCharacter
import com.roro.futurevoice.talk.ConversationEngine
import com.roro.futurevoice.talk.CorrectionOnlyPrompt
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.AfterClass
import org.junit.Assert.assertEquals
import org.junit.BeforeClass
import org.junit.Test
import java.util.TimeZone

/**
 * The conversation prompt, byte for byte iOS's. `vectors/conversation-prompts.json`
 * is the REAL iOS `ConversationEngine` output for [ConversationPromptFixtures]
 * (`scripts/android/gen-prompt-vectors.sh`, pinned iOS ref in its `ios_ref`).
 * A failure here means Android would send the model a different prompt from
 * iOS: fix the Kotlin side (or regenerate `ConversationPrompt.kt` with
 * `gen-conversation-prompt.py`), never the vector.
 */
class ConversationPromptVectorTest {
    companion object {
        private var saved: TimeZone? = null
        // The vectors were written under TZ=UTC; a remembered line's age is
        // a calendar distance, so both sides must count days in one zone.
        @BeforeClass @JvmStatic fun utc() { saved = TimeZone.getDefault(); TimeZone.setDefault(TimeZone.getTimeZone("UTC")) }
        @AfterClass @JvmStatic fun restore() { saved?.let { TimeZone.setDefault(it) } }
    }

    private val ios = Json.parseToJsonElement(
        javaClass.getResourceAsStream("/vectors/conversation-prompts.json")!!.bufferedReader().readText()
    ).jsonObject["prompts"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content }

    private fun check(name: String, android: String) {
        val expected = ios[name] ?: error("no iOS vector named $name")
        if (expected != android) {
            val at = expected.zip(android).indexOfFirst { (a, b) -> a != b }.let { if (it < 0) minOf(expected.length, android.length) else it }
            val from = maxOf(0, at - 80)
            assertEquals("$name differs from iOS at char $at", expected.substring(from, minOf(expected.length, at + 160)),
                android.substring(minOf(from, android.length), minOf(android.length, at + 160)))
        }
    }

    @Test fun everySystemPromptMatchesIos() {
        val F = ConversationPromptFixtures
        for (f in F.fixtures) {
            check("system/" + f.name, ConversationEngine.conversationSystemPrompt(
                targetLanguage = f.target, nativeLanguage = f.native, level = f.level,
                topPatterns = f.patterns, weakVocabAreas = f.weak, topic = f.topic,
                persona = f.persona, counterpart = f.counterpart, newsFacts = f.news, brief = f.brief,
                firstMeeting = f.firstMeeting, clock = f.clock, tutor = f.tutor, now = F.now))
        }
        assertEquals(F.fixtures.size, ios.keys.count { it.startsWith("system/") })
    }

    @Test fun everyOutputInstructionMatchesIos() {
        for (o in ConversationPromptFixtures.outputs) {
            check(o[0] as String, ConversationEngine.turnOutputInstruction(
                o[1] as String, o[2] as String, o[3] as Counterpart?, o[4] as Boolean))
        }
    }

    @Test fun everyCorrectionPromptMatchesIos() {
        val all = ConversationPromptFixtures.corrections
        for (o in all) {
            val target = o[1] as String
            val person = o[4] as Counterpart?
            check(o[0] as String, CorrectionOnlyPrompt.build(target, o[2] as String, o[3] as CefrLevel,
                relationshipLine = ConversationCharacter.relationshipRegisterLine(target, person),
                politeLine = ConversationCharacter.politeSettingLine(target, person, inScene = o[5] as Boolean)))
        }
        assertEquals(all.size, ios.keys.count { it.startsWith("correction/") })
    }
}
