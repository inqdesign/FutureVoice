package com.roro.futurevoice

import com.roro.futurevoice.data.JapaneseMorph
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/**
 * The Japanese morphology, held to the REAL Swift's answers
 * (`scripts/android/gen-vectors.sh`, section `japanese`). A headword that
 * differs across platforms means one learner's notebook fills differently
 * from another's for the same sentence.
 *
 * What is checked here is everything a JVM can reach: the candidate ladder,
 * the headword each token resolves to, and the timing words a line is cut
 * into. SEGMENTATION itself is the platform's own (`BreakIterator` vs
 * `CFStringTokenizer`) and is checked on a device, so these tests feed the
 * tokens the Swift side produced rather than re-cutting the sentence.
 */
class JapaneseMorphVectorTest {

    private val vectors = Json.parseToJsonElement(
        File("src/test/resources/vectors/summary-ingestion.json").readText()).jsonObject

    private val lexicon: Set<String> by lazy { tsv("cefr_words_ja.tsv", 3).keys }
    private val forms: Map<String, String> by lazy { tsv("ja_forms.tsv", 2) }

    private fun tsv(name: String, columns: Int): Map<String, String> {
        val file = File("src/main/assets/wordlists/$name")
        if (!file.exists()) return emptyMap()
        return file.readLines().mapNotNull { line ->
            val parts = line.split('\t')
            if (parts.size == columns) parts[0] to parts[columns - 1] else null
        }.toMap()
    }

    /** Tokens as the Swift side cut them, with spans recomputed over the text. */
    private fun tokens(text: String, words: List<String>): List<JapaneseMorph.Token> {
        var cursor = 0
        return words.map { w ->
            val start = text.indexOf(w, cursor).let { if (it < 0) cursor else it }
            cursor = start + w.length
            JapaneseMorph.Token(w, start, cursor)
        }
    }

    @Test fun headwordsMatchTheSwiftImplementation() {
        for (case in vectors["japanese"]!!.jsonArray) {
            val o = case.jsonObject
            val text = o["text"]!!.jsonPrimitive.content
            val words = o["words"]!!.jsonArray.map { it.jsonPrimitive.content }
            val expected = o["headwords"]!!.jsonArray.map { it.jsonPrimitive.content }
            val got = JapaneseMorph.headwords(tokens(text, words), lexicon, forms).map { it.first }
            assertEquals(text, expected, got)
        }
    }

    @Test fun theCandidateLadderMatches() {
        for (case in vectors["japanese_candidates"]!!.jsonArray) {
            val o = case.jsonObject
            val surface = o["surface"]!!.jsonPrimitive.content
            assertEquals(surface,
                o["candidates"]!!.jsonArray.map { it.jsonPrimitive.content },
                JapaneseMorph.candidates(surface))
            assertEquals(surface,
                o["dictionary_form"]!!.jsonPrimitive.content,
                JapaneseMorph.dictionaryForm(surface, lexicon = lexicon, forms = forms).orEmpty())
        }
    }

    /** The wordlists have to BE there — an empty lexicon would make every
     *  assertion above pass by resolving nothing. */
    @Test fun theBundledListsAreLoaded() {
        assert(lexicon.size > 5_000) { "lexicon is ${lexicon.size}" }
        assert(forms.size > 5_000) { "forms is ${forms.size}" }
        assertEquals("分かる", forms["わかる"])
    }
}
