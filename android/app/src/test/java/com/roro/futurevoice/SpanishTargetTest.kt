package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.SpanishMorph
import com.roro.futurevoice.data.VocabLemmas
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.data.WordClass
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.talk.VoicePreset
import com.roro.futurevoice.talk.nameIn
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import java.io.File

/**
 * Spanish as a TARGET language (iOS `SpanishTargetTests`, 2026-10-15). The
 * wordlist's headwords are what the Mac's tagger calls the lemma in context,
 * and `es_forms.tsv` is what both platforms make of a learner's speech; these
 * pin that the two meet on ordinary sentences. Reads the bundled assets.
 */
class SpanishTargetTest {

    companion object {
        private fun asset(name: String) = File("src/main/assets/wordlists/$name")

        @BeforeClass @JvmStatic fun tables() {
            val levels = LinkedHashMap<String, CefrLevel>()
            asset("cefr_words_es.tsv").forEachLine { line ->
                val parts = line.split('\t')
                if (parts.size != 2) return@forEachLine
                val level = CefrLevel.entries.firstOrNull { it.code.equals(parts[1], true) } ?: return@forEachLine
                levels.putIfAbsent(parts[0], level)
            }
            CoreVocabulary.installForTest("es", levels)
            SpanishMorph.opener = { name -> asset(name).takeIf { it.exists() }?.inputStream() }
            SpanishMorph.resetForTest()
            WordClass.opener = { name -> asset(name).takeIf { it.exists() }?.inputStream() }
        }
    }

    @Test fun spanishIsSelectable() {
        assertTrue(LanguageCatalog.selectableTargets.any { it.code == "es" })
    }

    @Test fun poolLoadsWithEveryBand() {
        assertTrue(CoreVocabulary.set("es").size > 8000)
        for (level in CefrLevel.entries) {
            assertTrue("$level", CoreVocabulary.headwords(level, "es").size > 500)
        }
        // The hand core caps what subtitles bury.
        assertEquals(CefrLevel.A1, CoreVocabulary.level("diciembre", "es"))
        assertEquals(CefrLevel.A1, CoreVocabulary.level("cocina", "es"))
        // Left out on purpose, never graded.
        assertNull(CoreVocabulary.level("estar", "es"))
        assertTrue(CoreVocabulary.isUngraded("estar", "es"))
    }

    @Test fun speechLemmasLandOnHeadwords() {
        val said = listOf(
            "Ayer comí una manzana con mi abuela y luego fuimos al mercado.",
            "Mis hermanos viven en una ciudad pequeña cerca de la playa.",
            "¿Me puedes explicar cómo llego a la estación de tren?",
            "Estoy buscando un piso más barato porque el alquiler subió mucho.",
        )
        val lemmas = VocabLemmas.lemmas(said, "es")
        for (word in listOf("comer", "manzana", "abuela", "mercado", "hermano", "vivir",
            "ciudad", "pequeño", "playa", "explicar", "llegar", "estación",
            "tren", "buscar", "piso", "barato", "alquiler", "subir")) {
            assertTrue("lemma $word not produced", word in lemmas)
            assertNotNull("$word not in the pool", CoreVocabulary.level(word, "es"))
        }
    }

    /** No lemma model on either platform; these go through [SpanishMorph]. */
    @Test fun formsReachHeadwordsWithoutATagger() {
        assertEquals("comer", VocabLemmas.lemma("Comí", "es"))
        assertEquals("cansado", VocabLemmas.lemma("cansadas", "es"))
        assertEquals(CefrLevel.A1, CoreVocabulary.levelOfSurface("hermanos", "es"))
        // -a and -o are two nouns, not one word twice.
        assertNotNull(CoreVocabulary.level("casa", "es"))
        assertNotNull(CoreVocabulary.level("caso", "es"))
        // The fluent self's words off the graded list are still found, names aren't.
        val off = VocabStore.offListContentWords(listOf("Mi amiga Lucía trabaja de fontanera en Valencia."), "es")
        assertNull(off["lucía"])
        assertNull(off["valencia"])
    }

    @Test fun wordClassesComeFromTheTable() {
        assertTrue(WordClass.VERB in WordClass.classes("comer", "es"))
        assertTrue(WordClass.NOUN in WordClass.classes("manzana", "es"))
        assertTrue(WordClass.ADJECTIVE in WordClass.classes("rojo", "es"))
    }

    @Test fun spanishPresetsSpeakSpanish() {
        val slot = StockPerson.catalog[0]
        assertNotEquals(slot.voiceId, VoicePreset.speaking(slot.voiceId, "es"))
        assertFalse(slot.nameIn("es").isEmpty())
        assertEquals(listOf("Carolina", "Jorge", "Carmen", "Javier"), StockPerson.catalog.map { it.nameIn("es") })
    }
}
