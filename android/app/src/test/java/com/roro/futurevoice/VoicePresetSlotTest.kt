package com.roro.futurevoice

import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.talk.VoicePreset
import com.roro.futurevoice.talk.identityIn
import com.roro.futurevoice.talk.nameIn
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A preset id is a SLOT: stored as the English voice, spoken by the target
 * language's own voice where one was picked (iOS `VoicePresetSlotTests`,
 * `b49e91b`).
 */
class VoicePresetSlotTest {

    @Test fun koreanAndJapaneseResolveEverySlot() {
        for (lang in listOf("en", "de", "ko", "ja")) {
            val spoken = StockPerson.catalog.map { VoicePreset.speaking(it.voiceId, lang) }
            assertEquals(lang, StockPerson.catalog.size, spoken.toSet().size)
            StockPerson.catalog.zip(spoken).forEach { (slot, voice) ->
                assertNotEquals("$lang ${slot.name}", slot.voiceId, voice)
            }
        }
        // Since iOS `e9fcb2d` Japanese has its own native voices.
        assertNotEquals(
            StockPerson.catalog.map { VoicePreset.speaking(it.voiceId, "ko") },
            StockPerson.catalog.map { VoicePreset.speaking(it.voiceId, "ja") })
    }

    @Test fun koreanVoicesAreTheIosIds() {
        val c = StockPerson.catalog
        assertEquals("cac92886-4b7c-4bc1-a524-e0f79c0381be", VoicePreset.speaking(c[0].voiceId, "ko"))
        assertEquals("537a82ae-4926-4bfb-9aec-aff0b80a12a5", VoicePreset.speaking(c[1].voiceId, "ko"))
        assertEquals("cd6c48a9-774b-4397-98b4-9948c0a790f0", VoicePreset.speaking(c[2].voiceId, "ko"))
        assertEquals("f7755efb-1848-4321-aa22-5e5be5d32486", VoicePreset.speaking(c[3].voiceId, "ko"))
    }

    @Test fun languagesWithoutNativeVoicesKeepTheOriginals() {
        for (lang in listOf("es", "fr")) {
            for (slot in StockPerson.catalog) {
                assertEquals(slot.voiceId, VoicePreset.speaking(slot.voiceId, lang))
            }
        }
    }

    @Test fun nonPresetVoicesPassThrough() {
        assertEquals("someClone123", VoicePreset.speaking("someClone123", "ko"))
        // A voice that is already the Korean one is not re-mapped.
        assertEquals("cac92886-4b7c-4bc1-a524-e0f79c0381be", VoicePreset.speaking("cac92886-4b7c-4bc1-a524-e0f79c0381be", "ko"))
    }

    @Test fun builtinPersonIsNamedPerLanguage() {
        val names = StockPerson.catalog.map { it.nameIn("ko") }
        assertEquals(listOf("시안", "민준", "한별", "준호"), names)
        assertEquals(listOf("美咲", "翔太", "陽菜", "健太"), StockPerson.catalog.map { it.nameIn("ja") })
        assertEquals(listOf("Lea", "Jonas", "Karin", "Nico"), StockPerson.catalog.map { it.nameIn("de") })
        assertEquals(listOf("Paige", "Mark", "Emma", "James"), StockPerson.catalog.map { it.nameIn("en") })
    }

    @Test fun stockIdentityDropsNationalityOnlyWhereRevoiced() {
        val paige = StockPerson.catalog[0]
        assertTrue(paige.identityIn("en").contains("American"))
        assertFalse(paige.identityIn("ko").contains("American"))
        assertTrue(paige.identityIn("ko").startsWith("시안 — twenties"))
        assertTrue(StockPerson.catalog[3].identityIn("ja").startsWith("健太 — forties"))
    }

    @Test fun savedBuiltinRowIsRenamedOnRead() {
        val paige = StockPerson.catalog[0]
        val row = Counterpart(id = "p", name = "Paige", intro = paige.identity,
            voicePresetId = paige.voiceId, remoteId = "builtin:${paige.voiceId}")
        assertEquals("시안", VoicePreset.localized(row, "ko").name)
        assertEquals("Paige", VoicePreset.localized(row, "en").name)
        // The stored voice id never changes — it is the slot.
        assertEquals(paige.voiceId, VoicePreset.localized(row, "ko").voicePresetId)
        // A person the learner made is never renamed.
        val mine = row.copy(remoteId = null)
        assertEquals("Paige", VoicePreset.localized(mine, "ko").name)
    }
}
