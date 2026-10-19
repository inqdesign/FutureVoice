package com.roro.futurevoice

import com.roro.futurevoice.data.Furigana
import com.roro.futurevoice.data.JapaneseDictionary
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/**
 * `Furigana` (iOS eb22e429). The okurigana cut and the hand fixes are pure
 * and pinned on iOS-shaped tokens; the readings themselves come from Sudachi
 * here and from `CFStringTokenizer` on iOS, so the last test lays both over
 * the 88 recorded iOS lines (`japanese/ios-cuts.json`) and counts the lines
 * whose ruby comes out different.
 */
class FuriganaTest {

    @Serializable
    data class Line(val text: String, val words: List<String>, val readings: List<String>)

    @After fun tearDown() {
        Furigana.tokensOverride = null
        Furigana.clearMemoForTest()
        JapaneseDictionary.unloadForTest()
    }

    /** iOS's tokens for a line, placed in the text in order. */
    private fun iosTokens(text: String, words: List<String>, readings: List<String>): List<Furigana.Token> {
        var at = 0
        return words.zip(readings).map { (w, r) ->
            val start = text.indexOf(w, at)
            at = start + w.length
            Furigana.Token(w, start, at, r)
        }
    }

    private fun ruby(text: String): String = Furigana.runs(text).joinToString("") {
        val base = text.substring(it.start, it.end)
        if (it.reading == null) base else "$base(${it.reading})"
    }

    private fun withTokens(text: String, vararg pairs: Pair<String, String>): String {
        Furigana.clearMemoForTest()
        Furigana.tokensOverride = { iosTokens(text, pairs.map { it.first }, pairs.map { it.second }) }
        return ruby(text)
    }

    @Test fun readingSitsOnTheKanjiOnly() {
        assertEquals("食(た)べた", withTokens("食べた", "食べ" to "たべ", "た" to "た"))
        assertEquals("晩(ばん)ご飯(はん)を食(た)べた。",
            withTokens("晩ご飯を食べた。", "晩ご飯" to "ばんごはん", "を" to "を", "食べ" to "たべ", "た" to "た"))
    }

    @Test fun kanaOnlyLineHasNoRuby() {
        Furigana.tokensOverride = { error("not asked") }
        assertEquals("わかった。", ruby("わかった。"))
    }

    @Test fun handFixes() {
        assertEquals("明日(あした)", withTokens("明日", "明日" to "みょうにち"))
        assertEquals("何(なに)を", withTokens("何を", "何" to "なん", "を" to "を"))
        assertEquals("一日中(いちにちじゅう)",
            withTokens("一日中", "一" to "いち", "日" to "にち", "中" to "なか"))
    }

    @Test fun noDictionaryMeansNoRuby() {
        Furigana.tokensOverride = { null }
        assertEquals("駅に行く", ruby("駅に行く"))
    }

    @Test fun sudachiAgainstIos() {
        val dic = System.getProperty("sudachi.dic")?.let(::File)
        assumeTrue("run through Gradle: :ja_dict:fetchSudachiDict provides the dictionary",
            dic != null && dic.isFile)
        JapaneseDictionary.load(dic!!)
        val lines: List<Line> = Json.decodeFromString(File("src/test/resources/japanese/ios-cuts.json").readText())
        var same = 0
        val differ = ArrayList<String>()
        for (line in lines) {
            Furigana.clearMemoForTest()
            Furigana.tokensOverride = { iosTokens(line.text, line.words, line.readings) }
            val ios = ruby(line.text)
            Furigana.clearMemoForTest()
            Furigana.tokensOverride = null
            val android = ruby(line.text)
            if (ios == android) same++ else differ.add("ios $ios\nand $android")
        }
        println("furigana: $same/${lines.size} lines identical to iOS\n" + differ.joinToString("\n"))
        assertEquals(lines.size, same + differ.size)
        org.junit.Assert.assertTrue("furigana matched iOS on $same/${lines.size}", same >= MIN_SAME)
    }

    private companion object {
        /** Measured when ported (2026-10-19): every line's ruby identical,
         *  the two lines Sudachi cuts differently included. */
        const val MIN_SAME = 88
    }
}
