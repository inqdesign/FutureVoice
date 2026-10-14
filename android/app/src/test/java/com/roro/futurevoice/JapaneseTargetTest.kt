package com.roro.futurevoice

import com.roro.futurevoice.data.DrillIngest
import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.Carryover
import com.roro.futurevoice.talk.DrillCard
import com.roro.futurevoice.talk.JapaneseReading
import com.roro.futurevoice.talk.PhraseFeedback
import com.roro.futurevoice.talk.SessionSummarizer
import com.roro.futurevoice.talk.SpokenWords
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnFix
import com.roro.futurevoice.talk.TurnRole
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File

/**
 * Japanese as a TARGET language, through the paths that assumed spaces —
 * iOS `JapaneseMorphTests.testCarryoverMatchesAJapanesePhrase` and
 * `testScriptOnlyRewriteIsNotACorrection`, plus the card and phrases_used
 * cases the port needed.
 *
 * Segmentation is the platform's (`android.icu.text.BreakIterator`), which a
 * JVM doesn't have, so — like `JapaneseMorphVectorTest` — these feed the
 * tokens `CFStringTokenizer` cuts: each sentence is registered with its cuts
 * marked by `|`.
 */
class JapaneseTargetTest {

    private val cuts = HashMap<String, List<String>>()

    /** Registers [marked]'s cuts and returns the sentence as written. */
    private fun ja(marked: String): String {
        val text = marked.replace("|", "")
        cuts[text] = marked.split('|').filter { piece -> piece.any { it.isLetterOrDigit() } }
        return text
    }

    private var previous: ((String) -> List<String>)? = null

    @Before fun installSegmenter() {
        previous = CarryoverDetector.segmenter
        CarryoverDetector.segmenter = { text -> cuts[text] ?: error("no cuts registered for「$text」") }
        JapaneseReading.override = readingTable
    }

    @After fun restore() {
        previous?.let { CarryoverDetector.segmenter = it }
        JapaneseReading.override = null
    }

    private fun turn(text: String) = Turn(role = TurnRole.USER, transcript = text)

    // ── The phrase matcher (iOS testCarryoverMatchesAJapanesePhrase)

    @Test fun aJapaneseExpressionIsCreditableAndMatches() {
        val phrase = ja("気|を|つけ|て")
        val also = ja("なるほど")
        assertTrue(CarryoverDetector.isCreditable(phrase, "ja"))
        assertTrue(CarryoverDetector.isCreditable(also, "ja"))
        assertNotNull(CarryoverDetector.firstMatch(phrase, listOf(turn(ja("じゃあ|、|気|を|つけ|て|ね|。"))),
            language = "ja"))
        assertNull(CarryoverDetector.firstMatch(phrase, listOf(turn(ja("気分|が|いい|です|。"))),
            language = "ja"))
    }

    /** Grammar on its own is never a phrase: a particle has nothing to credit. */
    @Test fun functionTokensAloneAreNotCreditable() {
        assertFalse(CarryoverDetector.isCreditable(ja("が"), "ja"))
        assertFalse(CarryoverDetector.isCreditable(ja("です|ね"), "ja"))
    }

    /** The bars were never relaxed for anything but ko before: a three-segment
     *  Japanese phrase failed `minTokens` on a spaced split (one "word"). */
    @Test fun studiedExpressionIsCreditedAtSessionEnd() {
        val phrase = ja("お|疲れ|様")
        val out = CarryoverDetector.detect(
            turns = listOf(turn(ja("今日|も|お|疲れ|様|でし|た|。"))),
            cards = emptyList(),
            studyingExpressions = listOf(phrase),
            sessionId = "s", sessionStartedAt = 0L, language = "ja",
        )
        assertEquals(listOf(Carryover.Source.STUDYING_EXPRESSION), out.map { it.source })
    }

    // ── A correction card (DrillIngest.cardPair + rejectingMistake)

    /** A particle fix is too small to credit, so it widens to its sentence —
     *  and that card is marked used only when the FIX is said. */
    @Test fun aJapaneseCorrectionCardCanBeMarkedUsed() {
        ja("は"); ja("が")
        ja("猫|は|好き"); ja("猫|が|好き")
        val transcript = ja("猫|は|好き|。|犬|も|好き|。")
        val fix = TurnFix(was = "は", now = "が", why = "助詞")
        val (source, target) = DrillIngest.cardPair(fix, transcript, "ja")
        assertEquals("猫は好き" to "猫が好き", source to target)
        assertTrue(CarryoverDetector.isCreditable(target, "ja"))

        assertNotNull(CarryoverDetector.firstMatch(target, listOf(turn(ja("やっぱり|猫|が|好き|。"))),
            rejectingMistake = source, language = "ja"))
        // The mistake said again is no credit.
        assertNull(CarryoverDetector.firstMatch(target, listOf(turn(ja("やっぱり|猫|は|好き|。"))),
            rejectingMistake = source, language = "ja"))

        val card = DrillCard(sourcePhrase = source, targetPhrase = target, reason = "助詞",
            createdAt = 0L, nextReviewAt = 0L, box = 0, sourceSessionId = "earlier")
        val out = CarryoverDetector.detect(
            turns = listOf(turn(ja("やっぱり|猫|が|好き|。"))),
            cards = listOf(card), sessionId = "now", sessionStartedAt = 1L, language = "ja",
        )
        assertEquals(listOf(Carryover.Source.DRILL_CARD), out.map { it.source })
    }

    /** iOS `coreSentence` splits on 。！？ and gives the terminator back. */
    @Test fun coreSentenceKeepsAJapaneseQuestionMark() {
        // Sentences reach the overlap with their punctuation stripped.
        ja("今日|は|天気|が|いい|です|ね")
        ja("明日|は|一緒|に|映画|を|見|に|行き|ませ|ん|か")
        ja("駅|の|前|で|待ち合わせ|を|し|ましょう")
        ja("一緒|に|映画")
        val target = "今日は天気がいいですね。明日は一緒に映画を見に行きませんか？駅の前で待ち合わせをしましょう。"
        assertEquals("明日は一緒に映画を見に行きませんか？",
            DrillIngest.coreSentence(target, "一緒に映画", maxChars = 20, language = "ja"))
    }

    // ── Script is the transcriber's (iOS testScriptOnlyRewriteIsNotACorrection)

    @Test fun scriptOnlyRewriteIsNotACorrection() {
        assertTrue(SpokenWords.saysTheSameThing("よく分かった。", "よくわかった！", "ja"))
        assertTrue(SpokenWords.saysTheSameThing("待って下さい", "待ってください", "ja"))
        assertFalse(SpokenWords.saysTheSameThing("面倒くさいでした", "面倒くさかった", "ja"))
        assertFalse(SpokenWords.saysTheSameThing("掃除をするつもりです", "掃除するつもり", "ja"))
    }

    /** The cases the reading table was measured on. */
    @Test fun kanjiAndKanaSpellingsReadAlike() {
        assertTrue(SpokenWords.saysTheSameThing("下さい", "ください", "ja"))
        assertTrue(SpokenWords.saysTheSameThing("分かる", "わかる", "ja"))
        assertTrue(SpokenWords.saysTheSameThing("一緒に行こう", "いっしょに行こう", "ja"))
        assertTrue(SpokenWords.saysTheSameThing("綺麗だね", "きれいだね", "ja"))
        assertTrue(SpokenWords.saysTheSameThing("コーヒー", "こーひー", "ja"))
        // A spelling read two ways (辛い: からい・つらい) is never folded.
        assertFalse(SpokenWords.saysTheSameThing("辛い", "からい", "ja"))
        assertFalse(SpokenWords.saysTheSameThing("分かった", "分からない", "ja"))
        // iOS: an empty left side is never "the same".
        assertFalse(SpokenWords.saysTheSameThing("。", "！", "ja"))
    }

    // ── phrases_used (iOS SessionSummarizer `keptPhrases`)

    @Test fun phrasesUsedKeepsOnlyTheLearnersOwnAudibleFixes() {
        val said = listOf("昨日は友達と映画を見に行ったよ。", "よく分かった。")
        val phrases = listOf(
            PhraseFeedback(userSaid = "映画を見に行った", fluentAlternative = "映画を見に行ってきた", reason = "x"),
            // Not something the learner said.
            PhraseFeedback(userSaid = "公園で走った", fluentAlternative = "公園を走った", reason = "x"),
            // Only the script changed.
            PhraseFeedback(userSaid = "よく分かった", fluentAlternative = "よくわかった", reason = "x"),
        )
        val kept = SessionSummarizer.keptPhrases(phrases, said, "ja")
        assertEquals(listOf("映画を見に行った"), kept.map { it.userSaid })
    }

    @Test fun phrasesUsedDropsAKoreanReorderAndAnEnglishContraction() {
        val ko = SessionSummarizer.keptPhrases(
            listOf(PhraseFeedback(userSaid = "먹었어 아까 라면", fluentAlternative = "아까 라면 먹었어", reason = "x")),
            listOf("응 먹었어 아까 라면"), "ko")
        assertTrue(ko.isEmpty())
        val en = SessionSummarizer.keptPhrases(
            listOf(PhraseFeedback(userSaid = "I am building", fluentAlternative = "I'm building", reason = "x"),
                PhraseFeedback(userSaid = "give me a feedback", fluentAlternative = "give me feedback", reason = "x")),
            listOf("I am building an app, give me a feedback"), "en")
        assertEquals(listOf("give me a feedback"), en.map { it.userSaid })
    }

    companion object {
        private val readingTable: JapaneseReading.Table by lazy {
            fun tsv(name: String, columns: Int): Map<String, String> =
                File("src/main/assets/wordlists/$name").readLines().mapNotNull { line ->
                    val parts = line.split('\t')
                    if (parts.size == columns && parts[columns - 1].isNotBlank()) parts[0] to parts[columns - 1]
                    else null
                }.toMap()
            JapaneseReading.build(tsv("cefr_words_ja.tsv", 3), tsv("ja_forms.tsv", 2))
        }
    }
}
