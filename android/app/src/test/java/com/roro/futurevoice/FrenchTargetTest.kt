package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.ExamKind
import com.roro.futurevoice.data.ExamTopics
import com.roro.futurevoice.data.FrenchMorph
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.SpeechLibrary
import com.roro.futurevoice.data.VocabLemmas
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.data.VoiceAccentCatalog
import com.roro.futurevoice.data.WordClass
import com.roro.futurevoice.talk.ShadowScore
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
 * French as a TARGET language (iOS `FrenchTargetTests`, 2026-11-13). The
 * wordlist's headwords and the form table come out of the same Lexique rules
 * (scripts/build-fr-wordlist.py), and [FrenchMorph] reads a word in its
 * sentence; these pin that speech and the list meet, and that the two
 * context readings hold. Reads the bundled assets.
 */
class FrenchTargetTest {

    companion object {
        private fun asset(name: String) = File("src/main/assets/wordlists/$name")

        @BeforeClass @JvmStatic fun tables() {
            val levels = LinkedHashMap<String, CefrLevel>()
            asset("cefr_words_fr.tsv").forEachLine { line ->
                val parts = line.split('\t')
                if (parts.size != 2) return@forEachLine
                val level = CefrLevel.entries.firstOrNull { it.code.equals(parts[1], true) } ?: return@forEachLine
                levels.putIfAbsent(parts[0], level)
            }
            CoreVocabulary.installForTest("fr", levels)
            FrenchMorph.opener = { name -> asset(name).takeIf { it.exists() }?.inputStream() }
            FrenchMorph.resetForTest()
            WordClass.opener = { name -> asset(name).takeIf { it.exists() }?.inputStream() }
        }
    }

    @Test fun frenchIsSelectable() {
        assertTrue(LanguageCatalog.selectableTargets.any { it.code == "fr" })
    }

    @Test fun poolLoadsWithEveryBand() {
        assertTrue(CoreVocabulary.set("fr").size > 8000)
        for (level in CefrLevel.entries) {
            assertTrue("$level", CoreVocabulary.headwords(level, "fr").size > 500)
        }
        // The hand core caps what subtitles bury.
        assertEquals(CefrLevel.A1, CoreVocabulary.level("décembre", "fr"))
        assertEquals(CefrLevel.A1, CoreVocabulary.level("cuisine", "fr"))
        assertEquals(CefrLevel.A1, CoreVocabulary.level("sœur", "fr"))
        // Left out on purpose, never graded.
        assertNull(CoreVocabulary.level("être", "fr"))
        assertTrue(CoreVocabulary.isUngraded("être", "fr"))
    }

    @Test fun speechLemmasLandOnHeadwords() {
        val said = listOf(
            "Hier j'ai mangé une pomme avec ma grand-mère et après on est allés au marché.",
            "Mes frères habitent dans une petite ville près de la plage.",
            "Tu peux m'expliquer comment aller à la gare ?",
            "Je cherche un appartement moins cher parce que le loyer a augmenté.",
        )
        val lemmas = VocabLemmas.lemmas(said, "fr")
        for (word in listOf("manger", "pomme", "grand-mère", "marché", "frère", "habiter",
            "petit", "ville", "plage", "expliquer", "gare", "chercher",
            "appartement", "cher", "loyer", "augmenter")) {
            assertTrue("lemma $word not produced", word in lemmas)
            assertNotNull("$word not in the pool", CoreVocabulary.level(word, "fr"))
        }
        assertFalse("l'" in lemmas)
    }

    /** The two readings the table can't decide alone. */
    @Test fun contextReadings() {
        fun lemmas(s: String) = FrenchMorph.analyze(s).mapNotNull { it.entry?.lemma }
        assertTrue("été" in lemmas("L'été dernier, il faisait chaud."))
        assertFalse("été" in lemmas("J'ai été malade."))
        assertTrue("fatigué" in lemmas("Je suis fatigué."))
        assertTrue("aimer" in lemmas("J'ai aimé le film."))
        // "suis" is être, never suivre (Apple's tagger says suivre).
        assertEquals("être", FrenchMorph.lemma("suis"))
        // Elision and words that keep their apostrophe or hyphen.
        assertEquals(listOf("l’", "école"), FrenchMorph.words("l’école").map { it.word })
        assertEquals(listOf("aujourd'hui"), FrenchMorph.words("aujourd'hui").map { it.word })
        assertEquals(listOf("dis", "moi"), FrenchMorph.words("dis-moi").map { it.word })
        // Lexique writes soeur; speech writes sœur.
        assertEquals("sœur", FrenchMorph.lemma("soeurs"))
    }

    /** No lemma model on either platform; these go through [FrenchMorph]. */
    @Test fun formsReachHeadwordsWithoutATagger() {
        assertEquals("manger", VocabLemmas.lemma("Mangé", "fr"))
        assertEquals("fatigué", VocabLemmas.lemma("fatiguées", "fr"))
        assertEquals(CefrLevel.A1, CoreVocabulary.levelOfSurface("frères", "fr"))
        val off = VocabStore.offListContentWords(
            listOf("Mon amie Camille travaille comme plombière à Marseille."), "fr")
        assertNull(off["camille"])
        assertNull(off["marseille"])
    }

    @Test fun wordClassesComeFromTheTable() {
        assertTrue(WordClass.VERB in WordClass.classes("manger", "fr"))
        assertTrue(WordClass.NOUN in WordClass.classes("pomme", "fr"))
        assertTrue(WordClass.ADJECTIVE in WordClass.classes("rouge", "fr"))
    }

    /** Two accents, Parisian the default; the server reads them from the words. */
    @Test fun frenchAccentsAreOfferedAndReadableByTheServer() {
        val options = VoiceAccentCatalog.options("fr")
        assertEquals(listOf("fr-FR", "fr-CA"), options.map { it.id })
        assertEquals("fr-FR", VoiceAccentCatalog.defaultAccent("fr")?.id)
        assertTrue(options[0].prompt.lowercase().contains("parisian french"))
        assertTrue(options[1].prompt.lowercase().contains("canadian french"))
    }

    @Test fun frenchPresetsSpeakFrench() {
        val slot = StockPerson.catalog[0]
        assertNotEquals(slot.voiceId, VoicePreset.speaking(slot.voiceId, "fr"))
        assertEquals("Emmanuelle", slot.nameIn("fr"))
    }

    /** The JVM has no ICU speller; the device's answers for the numbers used here. */
    @Test fun numbersReadTheFrenchWays() {
        val table = mapOf(
            97 to "quatre-vingt-dix-sept", 9 to "neuf", 7 to "sept",
            21 to "vingt-et-un", 2 to "deux", 1 to "un",
            1985 to "mille neuf cent quatre-vingt-cinq", 19 to "dix-neuf", 85 to "quatre-vingt-cinq",
            8 to "huit", 5 to "cinq",
        )
        val old = ShadowScore.spellOut
        ShadowScore.spellOut = { n, language -> table[n] ?: old(n, language) }
        try {
            val r = ShadowScore.readings("97", "fr")
            assertTrue(r.toString(), "quatre vingt dix sept" in r)
            assertTrue(r.toString(), "nonante sept" in r)
            assertTrue("vingt et une" in ShadowScore.readings("21", "fr"))
            assertTrue("dix neuf cent quatre vingt cinq" in ShadowScore.readings("1985", "fr"))
        } finally {
            ShadowScore.spellOut = old
        }
    }

    @Test fun sampleScriptAndExams() {
        assertNotNull(SpeechLibrary.builtIn("fr"))
        assertEquals(listOf(ExamKind.DELF, ExamKind.TCF, ExamKind.TEF, ExamKind.OPIC), ExamKind.options("fr"))
        for (exam in ExamKind.options("fr")) {
            assertFalse(exam.examName, ExamTopics.topics(exam, "fr").isEmpty())
        }
    }
}
