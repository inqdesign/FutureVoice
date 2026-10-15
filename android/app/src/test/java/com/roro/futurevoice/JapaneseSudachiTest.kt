package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.JapaneseDictionary
import com.roro.futurevoice.data.JapaneseMorph
import com.roro.futurevoice.talk.SpokenWords
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import java.io.File

/**
 * REAL Sudachi (mode B, SudachiDict SMALL — the file the `ja_dict` asset pack
 * ships, fetched by `:ja_dict:fetchSudachiDict` and handed in as the system
 * property `sudachi.dic`) against iOS's `CFStringTokenizer` on 88 spoken
 * lines. `japanese/ios-cuts.json` is what the Swift tokenizer returned for
 * each line (words + their hiragana readings, `kCFStringTokenizerUnitWord`,
 * locale ja), recorded 2026-10-14.
 *
 * Measured when this was wired: the cuts themselves identical on 86 of the
 * 88 lines (ICU's BreakIterator: 6 of the first 40), the headwords
 * `JapaneseMorph.headwords` reads off them identical on 87 (recall 309/310,
 * nothing extra), and the readings equal on all 228 kanji tokens both sides
 * cut the same. The thresholds below are those numbers.
 */
class JapaneseSudachiTest {

    @Serializable
    data class Line(val text: String, val words: List<String>, val readings: List<String>)

    private lateinit var lines: List<Line>
    private lateinit var lexicon: Set<String>
    private lateinit var forms: Map<String, String>

    private fun tsv(name: String, columns: IntRange): List<List<String>> =
        File("src/main/assets/wordlists/$name").readLines()
            .map { it.split('\t') }.filter { it.size in columns }

    @Before fun setUp() {
        val dic = System.getProperty("sudachi.dic")?.let(::File)
        assumeTrue("run through Gradle: :ja_dict:fetchSudachiDict provides the dictionary",
            dic != null && dic.isFile)
        JapaneseDictionary.load(dic!!)
        assertTrue(JapaneseDictionary.isReady)
        lines = Json.decodeFromString(File("src/test/resources/japanese/ios-cuts.json").readText())
        val levels = tsv("cefr_words_ja.tsv", 2..3).associate { it[0] to CefrLevel.from(it[1]) }
        val readings = tsv("cefr_words_ja.tsv", 3..3).associate { it[0] to it[2] }
        forms = tsv("ja_forms.tsv", 2..2).associate { it[0] to it[1] }
        CoreVocabulary.installForTest("ja", levels, forms, readings)
        lexicon = CoreVocabulary.set("ja")
    }

    @After fun tearDown() {
        JapaneseDictionary.unloadForTest()
        JapaneseMorph.segmenterOverride = null
        CoreVocabulary.installForTest("ja", emptyMap())
    }

    /** Headwords as the app reads them off iOS's cuts — the reference. */
    private fun iosHeadwords(line: Line): List<String> {
        JapaneseMorph.segmenterOverride = { text ->
            var cursor = 0
            line.words.map { w ->
                val start = text.indexOf(w, cursor)
                cursor = start + w.length
                JapaneseMorph.Token(w, start, cursor)
            }
        }
        try {
            return JapaneseMorph.headwords(line.text, lexicon, forms).map { it.first }
        } finally {
            JapaneseMorph.segmenterOverride = null
        }
    }

    @Test fun surfacesAndOffsetsAreTheOriginalText() {
        for (line in lines) {
            val tokens = JapaneseMorph.words(line.text)
            assertTrue(tokens.isNotEmpty())
            for (t in tokens) assertEquals(t.surface, line.text.substring(t.start, t.end))
        }
    }

    @Test fun headwordsMatchIos() {
        var identical = 0
        var hit = 0; var total = 0; var extra = 0
        val misses = ArrayList<String>()
        for (line in lines) {
            val ios = iosHeadwords(line)
            val sudachi = JapaneseMorph.headwords(line.text, lexicon, forms).map { it.first }
            if (ios == sudachi) identical++ else misses += "${line.text}\n  iOS $ios\n  Sud $sudachi"
            val a = ios.groupingBy { it }.eachCount()
            val b = sudachi.groupingBy { it }.eachCount()
            total += ios.size
            hit += a.entries.sumOf { (k, v) -> minOf(v, b[k] ?: 0) }
            extra += b.entries.sumOf { (k, v) -> maxOf(0, v - (a[k] ?: 0)) }
        }
        println("Sudachi headwords: identical ${identical}/${lines.size}, recall ${hit}/${total}, extras $extra")
        misses.forEach(::println)
        assertTrue("identical $identical of ${lines.size}", identical >= 86)
        assertTrue("recall $hit of $total", hit >= 0.97 * total)
        assertEquals(0, extra)
    }

    @Test fun cutsAgreeAsMeasured() {
        val identical = lines.count { JapaneseMorph.segments(it.text) == it.words }
        println("Sudachi raw cuts identical to iOS: $identical/${lines.size}")
        // 86 of 88 when measured; ICU managed 6 of the first 40.
        assertTrue("identical cuts $identical", identical >= 86)
    }

    @Test fun readingsMatchIosOnKanjiTokens() {
        var same = 0; var compared = 0
        val diffs = ArrayList<String>()
        for (line in lines) {
            val iosBySpan = HashMap<Pair<Int, Int>, String>()
            var cursor = 0
            line.words.zip(line.readings).forEach { (w, r) ->
                val start = line.text.indexOf(w, cursor); cursor = start + w.length
                iosBySpan[start to cursor] = r
            }
            for (m in JapaneseDictionary.morphs(line.text).orEmpty()) {
                if (m.surface.none { it.code in 0x4E00..0x9FFF }) continue
                val ios = iosBySpan[m.start to m.end] ?: continue
                compared++
                if (m.reading == ios) same++ else diffs += "${m.surface}: iOS $ios, Sudachi ${m.reading}"
            }
        }
        println("Readings equal on $same/$compared kanji tokens"); diffs.forEach(::println)
        assertTrue(compared >= 200)
        assertEquals(compared, same)
    }

    @Test fun lineReadingIsHiraganaWithoutPunctuation() {
        assertEquals("かじがおおくてつかれた", JapaneseMorph.reading("家事が多くて疲れた。"))
    }

    @Test fun respellingIsTheSameThingButADifferentWordIsNot() {
        assertTrue(SpokenWords.saysTheSameThing("分かった", "わかった", "ja"))
        assertTrue(SpokenWords.saysTheSameThing("ちょっと待って下さい。", "ちょっと待ってください", "ja"))
        assertFalse(SpokenWords.saysTheSameThing("分かった", "分かりました", "ja"))
    }

    @Test fun offListKanjiWordsGetSudachisReading() {
        val offList = "洗濯機"
        assertNull(CoreVocabulary.listedReading(offList, "ja"))
        assertEquals("せんたくき", CoreVocabulary.reading(offList, "ja"))
        // A kana word has no reading to show; a listed one keeps the list's.
        assertNull(CoreVocabulary.reading("ちょっと", "ja"))
        assertEquals(CoreVocabulary.listedReading("辛い", "ja"), CoreVocabulary.reading("辛い", "ja"))
    }

    @Test fun withoutTheDictionaryTheIcuPathStands() {
        JapaneseDictionary.unloadForTest()
        assertNull(JapaneseDictionary.morphs("家事"))
        assertNull(JapaneseMorph.reading("家事"))
    }
}
