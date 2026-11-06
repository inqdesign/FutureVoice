package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.LevelBands.VocabShare
import com.roro.futurevoice.data.SpanishMorph
import com.roro.futurevoice.data.WordClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import java.io.File

/**
 * iOS `VocabSophisticationTests` (d9e0a0c6): Korean, Japanese and Spanish
 * carry the English cuts over through Tatoeba pairs, and each is read by the
 * app's own analyzer against the real bundled pools. Japanese needs the
 * platform segmenter, so only its cuts are pinned here.
 */
class VocabShareReadersTest {

    companion object {
        private fun asset(name: String) = File("src/main/assets/wordlists/$name")

        private fun levels(file: String): Map<String, CefrLevel> {
            val out = LinkedHashMap<String, CefrLevel>()
            asset(file).forEachLine { line ->
                val parts = line.split('\t')
                if (parts.size !in 2..3) return@forEachLine
                val level = CefrLevel.entries.firstOrNull { it.code.equals(parts[1], true) } ?: return@forEachLine
                out.putIfAbsent(parts[0], level)
            }
            return out
        }

        @BeforeClass @JvmStatic fun tables() {
            CoreVocabulary.installForTest("es", levels("cefr_words_es.tsv"))
            CoreVocabulary.installForTest("ko", levels("cefr_words_ko.tsv"))
            SpanishMorph.opener = { name -> asset(name).takeIf { it.exists() }?.inputStream() }
            SpanishMorph.resetForTest()
            WordClass.opener = { name -> asset(name).takeIf { it.exists() }?.inputStream() }
        }
    }

    private fun read(mean: Double, graded: Int = 1000) = VocabShare.Read(graded, Math.round(mean * graded).toInt(), 3)

    @Test fun koreanJapaneseSpanishHaveTheirOwnCuts() {
        val cases = listOf(
            "ko" to listOf(0.55 to CefrLevel.A1, 0.58 to CefrLevel.A2, 0.61 to CefrLevel.B1, 0.63 to CefrLevel.B2),
            "ja" to listOf(0.85 to CefrLevel.A1, 0.88 to CefrLevel.A2, 0.91 to CefrLevel.B1, 0.94 to CefrLevel.B2),
            "es" to listOf(0.29 to CefrLevel.A1, 0.31 to CefrLevel.A2, 0.34 to CefrLevel.B1, 0.37 to CefrLevel.B2),
        )
        for ((code, bands) in cases) {
            val profile = VocabShare.profiles.getValue(code)
            assertTrue(VocabShare.isCalibrated(code))
            for ((mean, level) in bands) {
                assertEquals("$code $mean", level, VocabShare.level(read(mean), profile, null)?.first)
            }
        }
        assertFalse(VocabShare.isCalibrated("fr"))
    }

    private fun words(text: String, code: String) =
        VocabShare.contentLemmas(text, VocabShare.profiles.getValue(code)) { it }

    /** Korean: [com.roro.futurevoice.data.KoreanMorph] headwords, minus
     *  pronouns, light verbs and postposition verbs (그녀 and 위하다 are on
     *  the list). */
    @Test fun koreanCountsContentHeadwords() {
        assertEquals(listOf("어제", "친구", "만나다"), words("나는 어제 친구를 만났어요.", "ko"))
        assertEquals(listOf("노래"), words("그녀가 나를 위해 노래를 했어요.", "ko"))
    }

    /** Spanish: the form table, with a participle after haber read as its
     *  verb (the table grades "comprado" C2 as its own headword). */
    @Test fun spanishReadsThePerfectAsItsVerb() {
        assertEquals(listOf("comprar", "libro"), words("He comprado un libro.", "es"))
        assertEquals(listOf("leer", "carta"), words("Ella ha leído dos cartas.", "es"))
        assertEquals(listOf("libro", "comprado", "caro"), words("El libro comprado es caro.", "es"))
        assertEquals("decir", VocabShare.spanishParticipleVerb("dicho"))
        assertEquals("oír", VocabShare.spanishParticipleVerb("oído"))
    }
}
