package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.JapaneseMorph
import com.roro.futurevoice.data.VocabLemmas
import com.roro.futurevoice.data.VocabStore
import com.roro.futurevoice.talk.ScorecardMetrics
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnRole
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File

/**
 * Japanese as a TARGET language through the stores — the Android twin of
 * iOS `JapaneseMorphTests.testVocabStoreLemmasAndLookupKeyRouteToJapanese`
 * and `testTitleSnippetAndSentenceCount`, plus the scorecard's word count
 * and level grading (iOS `ScorecardMetrics.compute`).
 *
 * The pool is the REAL bundled list (read from the assets the app ships),
 * installed through the test seam because a JVM has no Context. The
 * segmenter is the platform's (`android.icu` is a stub here), so each line
 * is cut exactly as iOS's `CFStringTokenizer` cut it — what is tested is
 * everything AFTER the cut. Both seams are reset in [tearDown], so no other
 * test sees them.
 */
class JapaneseLemmaTest {

    /** CFStringTokenizer's cuts (`swift`, `kCFStringTokenizerUnitWord`, ja). */
    private val iosCuts = mapOf(
        "家事が多くて疲れた。" to listOf("家事", "が", "多く", "て", "疲れ", "た"),
        "疲れた" to listOf("疲れ", "た"),
        "わかる" to listOf("わかる"),
        "疲れる" to listOf("疲れる"),
        "行きました" to listOf("行き", "まし", "た"),
        "家事" to listOf("家事"),
        "最近、家事がたくさんあって、本当に疲れました。" to listOf(
            "最近", "家事", "が", "たくさん", "あっ", "て", "本当", "に", "疲れ", "まし", "た"),
        "そうなんだ。仕事も忙しかった？" to listOf("そう", "な", "ん", "だ", "仕事", "も", "忙しかっ", "た"),
        "映画を見に行きました。" to listOf("映画", "を", "見", "に", "行き", "まし", "た"),
        // Headwords are graded by re-reading them (iOS `level(ofSurface:)`).
        "多い" to listOf("多い"), "映画" to listOf("映画"), "見る" to listOf("見る"),
        "行く" to listOf("行く"),
    )

    /** Rows as the app's loader reads them (a kana headword has no reading
     *  column, so the wordlist rows are two or three wide). */
    private fun tsv(name: String, columns: IntRange): List<List<String>> =
        File("src/main/assets/wordlists/$name").readLines()
            .map { it.split('\t') }.filter { it.size in columns }

    @Before fun setUp() {
        JapaneseMorph.segmenterOverride = { text ->
            val words = iosCuts[text] ?: error("no iOS cut recorded for \"$text\"")
            var cursor = 0
            words.map { w ->
                val start = text.indexOf(w, cursor)
                cursor = start + w.length
                JapaneseMorph.Token(w, start, cursor)
            }
        }
        val levels = tsv("cefr_words_ja.tsv", 2..3).associate { it[0] to CefrLevel.from(it[1]) }
        val forms = tsv("ja_forms.tsv", 2..2).associate { it[0] to it[1] }
        CoreVocabulary.installForTest("ja", levels, forms)
    }

    @After fun tearDown() {
        JapaneseMorph.segmenterOverride = null
        // Back to what a JVM has without a Context: an empty pool.
        CoreVocabulary.installForTest("ja", emptyMap())
    }

    @Test fun theListIsLoaded() {
        assertTrue(CoreVocabulary.set("ja").size > 7_000)
        assertEquals(CefrLevel.B1, CoreVocabulary.level("家事", "ja"))
    }

    // iOS testVocabStoreLemmasAndLookupKeyRouteToJapanese

    @Test fun lemmasReadHeadwordsNotSegments() {
        assertEquals(setOf("家事", "多い", "疲れる"), VocabLemmas.lemmas(listOf("家事が多くて疲れた。"), "ja"))
    }

    @Test fun lookupKeyReadsTheWholeChunk() {
        assertEquals("疲れる", VocabLemmas.lemma("疲れた", "ja"))
        assertEquals("分かる", VocabLemmas.lemma("わかる", "ja"))
        // A headword stays itself.
        assertEquals("疲れる", VocabLemmas.lemma("疲れる", "ja"))
        assertEquals("家事", VocabLemmas.lemma("家事", "ja"))
    }

    @Test fun aSurfaceIsGradedByItsHeadword() {
        assertEquals(CefrLevel.A1, CoreVocabulary.levelOfSurface("行きました", "ja"))
        assertEquals(CefrLevel.B1, CoreVocabulary.levelOfSurface("家事", "ja"))
    }

    /** Nothing off the list is guessed at, for Japanese as on iOS. */
    @Test fun offListWordsAreEmptyForJapanese() {
        assertTrue(VocabStore.offListContentWords(listOf("最近、家事がたくさんあって、本当に疲れました。"), "ja").isEmpty())
    }

    /** The Words chapter of a Japanese talk: the fluent self's headwords at
     *  or above the level, minus what the learner said themselves. */
    @Test fun aJapaneseTalkHasAWordsChapter() {
        val fluent = listOf("最近、家事がたくさんあって、本当に疲れました。", "そうなんだ。仕事も忙しかった？")
        val rank = { w: String -> CoreVocabulary.level(w, "ja")?.let(CoreVocabulary::levelRank) }
        val picks = VocabStore.orderPickups(
            lemmas = VocabLemmas.lemmas(fluent, "ja"),
            offList = VocabStore.offListContentWords(fluent, "ja"),
            minRank = CoreVocabulary.levelRank(CefrLevel.A2),
            excluded = VocabLemmas.lemmas(listOf("映画を見に行きました。"), "ja"),
            rankOf = rank)
        assertEquals(listOf("最近", "家事"), picks)
        // A1 learner: every graded headword, easiest first.
        val all = VocabStore.orderPickups(VocabLemmas.lemmas(fluent, "ja"), emptyMap(),
            CoreVocabulary.levelRank(CefrLevel.A1), emptySet(), rank)
        assertEquals(listOf("そう", "たくさん", "仕事", "忙しい", "本当", "疲れる", "最近", "家事"), all)
    }

    // iOS ScorecardMetrics.compute — tokens and distinct_words_by_cefr_level

    private fun userTurn(text: String) =
        Turn(id = text, role = TurnRole.USER, transcript = text, durationMs = 3000)

    @Test fun scorecardCountsSegmentsAndGradesHeadwords() {
        val m = ScorecardMetrics.compute(
            listOf(userTurn("家事が多くて疲れた。"), userTurn("映画を見に行きました。")), "ja")
        // Particles count as words, which is what WPM can mean without spaces.
        assertEquals(13, m.userWordCount)
        assertEquals(2, m.userTurnCount)
        // 家事 (b1) + 多い, 疲れる, 映画, 見る, 行く (a1).
        assertEquals(mapOf("a1" to 5, "b1" to 1), m.vocabLevelCounts)
        assertEquals("{\"a1\":5,\"b1\":1}", m.promptJson()["distinct_words_by_cefr_level"].toString())
    }

    /** A spaced language still splits on non-letters, as before. */
    @Test fun scorecardSpacedLanguageUnchanged() {
        val m = ScorecardMetrics.compute(listOf(userTurn("I commute, almost one hour.")), "en")
        assertEquals(5, m.userWordCount)
    }

    // iOS testTitleSnippetAndSentenceCount (iOS Session.displayTitle: 6 words / 14 characters)

    private fun session(language: String, first: String) = Session(
        userId = "u", targetLanguage = language, startedAt = 0L,
        turns = listOf(Turn(id = "t", role = TurnRole.USER, transcript = first, durationMs = 1000)))

    @Test fun aJapaneseTitleIsCutByCharacters() {
        assertEquals("“今日は友達と映画を見に行きま…”",
            session("ja", "今日は友達と映画を見に行きました").displayTitle)
        assertEquals("“疲れた”", session("ja", "疲れた").displayTitle)
    }

    @Test fun aSpacedTitleIsCutByWords() {
        assertEquals("“One two three four five six…”",
            session("en", "One two three four five six seven").displayTitle)
        assertEquals("“Hello there”", session("en", "Hello  there").displayTitle)
    }
}
