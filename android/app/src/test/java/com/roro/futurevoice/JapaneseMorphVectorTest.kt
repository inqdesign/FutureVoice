package com.roro.futurevoice

import com.roro.futurevoice.data.JapaneseMorph
import com.roro.futurevoice.data.WordClass
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Before
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
 * tokens the Swift side produced — with their readings, which Sudachi gives
 * on a device — rather than re-cutting the sentence.
 */
class JapaneseMorphVectorTest {

    private val vectors = Json.parseToJsonElement(
        File("src/test/resources/vectors/summary-ingestion.json").readText()).jsonObject

    /** Every headword, read or not — a kana word (する, いい) has no reading
     *  column, and vecgen's lexicon carries both. */
    private val lexicon: Set<String> by lazy {
        tsv("cefr_words_ja.tsv", 2).keys + tsv("cefr_words_ja.tsv", 3).keys
    }
    private val forms: Map<String, String> by lazy { tsv("ja_forms.tsv", 2) }

    private fun tsv(name: String, columns: Int): Map<String, String> {
        val file = File("src/main/assets/wordlists/$name")
        if (!file.exists()) return emptyMap()
        return file.readLines().mapNotNull { line ->
            val parts = line.split('\t')
            if (parts.size == columns) parts[0] to parts[columns - 1] else null
        }.toMap()
    }

    /** The word classes a stem rule's guess is checked against — the app's
     *  asset, as vecgen hands the Swift side the same file. */
    @Before fun classes() {
        WordClass.opener = { name ->
            File("src/main/assets/wordlists/$name").takeIf { it.exists() }?.inputStream()
        }
    }

    /** Tokens as the Swift side cut them, with spans recomputed over the
     *  text and the readings it gave each one. */
    private fun tokens(text: String, words: List<String>, readings: List<String>?): List<JapaneseMorph.Token> {
        var cursor = 0
        return words.mapIndexed { i, w ->
            val start = text.indexOf(w, cursor).let { if (it < 0) cursor else it }
            cursor = start + w.length
            JapaneseMorph.Token(w, start, cursor, readings?.getOrNull(i))
        }
    }

    private fun case(text: String) = vectors["japanese"]!!.jsonArray.map { it.jsonObject }
        .first { it["text"]!!.jsonPrimitive.content == text }

    /** Headwords of a vector sentence, read off the Swift side's cuts. */
    private fun heads(text: String): List<String> {
        val o = case(text)
        val words = o["words"]!!.jsonArray.map { it.jsonPrimitive.content }
        val readings = o["readings"]?.jsonArray?.map { it.jsonPrimitive.content }
        return JapaneseMorph.headwords(tokens(text, words, readings), lexicon, forms).map { it.first }
    }

    @Test fun headwordsMatchTheSwiftImplementation() {
        for (case in vectors["japanese"]!!.jsonArray) {
            val o = case.jsonObject
            val text = o["text"]!!.jsonPrimitive.content
            val expected = o["headwords"]!!.jsonArray.map { it.jsonPrimitive.content }
            assertEquals(text, expected, heads(text))
        }
    }

    /** iOS `testNoHomophoneOrGrammarBecomesAnotherWord` (79c20a9c): a word
     *  never lands on a DIFFERENT headword that only shares its reading or
     *  one of its stem shapes, and grammar stays grammar. */
    @Test fun noHomophoneOrGrammarBecomesAnotherWord() {
        val wrong = listOf(
            "一週間前に来た。" to "習慣", "三回見た。" to "さじ", "部屋の中で寝た。" to "当たる",
            "紙を二枚ください。" to "びら", "行くつもりだった。" to "積もる", "それでいいよ。" to "それる",
            "子供のとき、" to "解く", "日本について話す。" to "点く", "世界において有名だ。" to "老いる",
            "勉強すればいい。" to "擦れる", "こっちのほうがいい。" to "放る", "水さえない。" to "冴える",
            "そういうわけで、" to "分ける", "時間があれば行く。" to "荒れる", "百円しかない。" to "叱る",
            "どこで会う？" to "どく", "何をやっているの？" to "やつ", "理論的には正しい。" to "まと",
            "船に乗った。" to "舟", "好きな曲を聴く。" to "局", "飛行機は詩情を奪ってしまった。" to "始末",
        )
        for ((line, head) in wrong) assertFalse("$line → ${heads(line)}", head in heads(line))
        // …while the right word is still found.
        assertEquals(listOf("三", "見る"), heads("三回見た。"))
        assertEquals(listOf("何", "やる"), heads("何をやっているの？"))
        assertEquals(listOf("部屋", "中", "寝る"), heads("部屋の中で寝た。"))
        assertEquals(listOf("行く", "つもり"), heads("行くつもりだった。"))
        assertEquals(listOf("勉強", "する", "いい"), heads("勉強すればいい。"))
        assertEquals("まと", heads("的を射る。").first())
        assertEquals(listOf("かばん", "買う"), heads("鞄を買った。"))
        assertEquals(listOf("準備", "できる"), heads("準備できてる？"))
        assertEquals(listOf("話す", "分かる"), heads("話せば分かる。"))
        // A lone し: する after a noun, the particle after an inflected word.
        assertEquals(listOf("運動", "する"), heads("運動した。"))
        assertFalse("する" in heads("おいしいし、安い。"))
        // A one-kanji spelling of a kana word survives when read as it (事 → こと).
        assertEquals(listOf("それ", "大事", "こと"), heads("それは大事な事だ。"))
    }

    /** With no reading (ICU's cut, before Sudachi loads) a one-kanji spelling
     *  of a kana word still reads as it — 事 is こと — while a kanji
     *  headword that doesn't share the kanji (船 → 舟) stays out. */
    @Test fun withoutAReadingTheKanaSpellingStands() {
        val toks = tokens("大事な事だ。", listOf("大事", "な", "事", "だ"), null)
        assertEquals(listOf("大事", "こと"), JapaneseMorph.headwords(toks, lexicon, forms).map { it.first })
        val ship = tokens("船に乗った。", listOf("船", "に", "乗っ", "た"), null)
        assertEquals(listOf("乗る"), JapaneseMorph.headwords(ship, lexicon, forms).map { it.first })
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
