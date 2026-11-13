package com.roro.futurevoice

import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.ChineseMorph
import com.roro.futurevoice.data.CoreVocabulary
import com.roro.futurevoice.data.ExamKind
import com.roro.futurevoice.data.ExamTopics
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.SpeechLibrary
import com.roro.futurevoice.data.VocabLemmas
import com.roro.futurevoice.data.WordSplitter
import com.roro.futurevoice.talk.CorrectionOnlyPrompt
import com.roro.futurevoice.talk.PronunciationAssessor
import com.roro.futurevoice.talk.ShadowScore
import com.roro.futurevoice.talk.SpokenWords
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.talk.VoicePreset
import com.roro.futurevoice.talk.nameIn
import org.junit.AfterClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import java.io.File

/**
 * Simplified Chinese as a TARGET language (iOS `ChineseTargetTests`,
 * 0197dcbc). The HSK 3.0 list's headwords are what [ChineseMorph] cuts a
 * learner's speech into; these pin that the two meet, that Traditional text
 * folds onto Simplified, and that a transcriber's choice of characters is
 * never a correction.
 *
 * ICU (`android.icu`) doesn't exist on a JVM, so the platform half is a
 * table: the CUTS are the ones ICU's `BreakIterator` makes on a device
 * (measured on the Pixel 9 emulator, API 36, 2026-11-13) — 他是 | 我的 | 三年
 * glued where iOS cuts two — so what is tested is the port's own logic over
 * ICU's real output, including the split back into iOS's words. The script
 * fold, pinyin and spell-out are the few characters these sentences use, as
 * ICU gives them.
 */
class ChineseTargetTest {

    companion object {
        private fun asset(name: String) = File("src/main/assets/wordlists/$name")

        /** ICU's cuts, by sentence (on the Simplified text), marked with |. */
        private val icuCuts = listOf(
            "我们|今天|晚上|去|吃饭|吧|，|你|觉得|怎么|样|？",
            "他是|我的|老师|，|教|汉语|教|了|三年|了|。",
            "我|最近|在|准备|考试|，|有点|紧张|。",
            "这个|问题|我们|说|过|了|。",
            "这个|问题|我们|说|过|了",
            "我们|说|过|了",
            "你好|！|我|叫|小明|，|很|高兴|认识|你|。",
            "他|跑|的|很快|。",
            "他|跑得|很快|。",
            "我想|买|书",
            "我想|卖|书",
            "我|学|了|三年|汉语|。",
            "我|学|了|3|年|汉语",
            "说话",
            "问题",
            "一点",
            "老师",
        ).associate { marked -> marked.replace("|", "") to marked.split('|') }

        private val traditional = mapOf(
            '這' to '这', '個' to '个', '問' to '问', '題' to '题', '們' to '们', '說' to '说',
            '過' to '过', '學' to '学', '漢' to '汉', '語' to '语', '話' to '话',
        )

        /** Han-Latin, character by character, for what these lines use. */
        private val pinyin = mapOf(
            '我' to "wǒ", '们' to "men", '说' to "shuō", '过' to "guò", '了' to "le", '他' to "tā",
            '跑' to "pǎo", '很' to "hěn", '快' to "kuài", '想' to "xiǎng", '买' to "mǎi",
            '卖' to "mài", '书' to "shū", '老' to "lǎo", '师' to "shī", '的' to "de", '得' to "dé",
        )

        private val fake = object : ChineseMorph.Platform {
            override fun simplified(text: String) = text.map { traditional[it] ?: it }.joinToString("")
            override fun cuts(text: String): List<Pair<Int, Int>> {
                val pieces = icuCuts[text] ?: text.map { it.toString() }
                var at = 0
                return pieces.map { p -> (at to at + p.length).also { at += p.length } }
            }
            override fun pinyin(word: String) = word.map { pinyin[it] ?: it.toString() }.joinToString(" ")
            override fun spellOut(n: Int) = mapOf(3 to "三")[n]
        }

        private var saved: ChineseMorph.Platform? = null

        @BeforeClass @JvmStatic fun tables() {
            val levels = LinkedHashMap<String, CefrLevel>()
            val readings = HashMap<String, String>()
            asset("cefr_words_zh.tsv").forEachLine { line ->
                val parts = line.split('\t')
                if (parts.size !in 2..3) return@forEachLine
                val level = CefrLevel.entries.firstOrNull { it.code.equals(parts[1], true) } ?: return@forEachLine
                levels.putIfAbsent(parts[0], level)
                if (parts.size == 3) readings.putIfAbsent(parts[0], parts[2])
            }
            val forms = HashMap<String, String>()
            asset("zh_forms.tsv").forEachLine { line ->
                val parts = line.split('\t')
                if (parts.size == 2) forms.putIfAbsent(parts[0], parts[1])
            }
            CoreVocabulary.installForTest("zh", levels, forms, readings)
            saved = ChineseMorph.platform
            ChineseMorph.platform = fake
        }

        @AfterClass @JvmStatic fun restore() { saved?.let { ChineseMorph.platform = it } }
    }

    @Test fun chineseIsSelectableAndUnspaced() {
        assertTrue(LanguageCatalog.selectableTargets.any { it.code == "zh" })
        assertFalse(WordSplitter.spaced("zh"))
        assertTrue(WordSplitter.isChinese("zh"))
        assertEquals("Simplified Chinese", LanguageCatalog.englishName("zh"))
        assertEquals("B1 · HSK 4", LanguageCatalog.levelLabel(CefrLevel.B1, "zh"))
    }

    @Test fun poolLoadsWithHSKBands() {
        assertTrue(CoreVocabulary.set("zh").size > 10_000)
        for (level in listOf(CefrLevel.A1, CefrLevel.A2, CefrLevel.B1, CefrLevel.B2, CefrLevel.C1)) {
            assertTrue("$level", CoreVocabulary.headwords(level, "zh").size > 400)
        }
        assertEquals(CefrLevel.A1, CoreVocabulary.level("吃饭", "zh"))
        assertEquals(CefrLevel.A1, CoreVocabulary.level("老师", "zh"))
        // Particles are grammar, not vocabulary.
        assertNull(CoreVocabulary.level("的", "zh"))
        assertNull(CoreVocabulary.level("吗", "zh"))
    }

    @Test fun speechLandsOnHeadwords() {
        val said = listOf(
            "我们今天晚上去吃饭吧，你觉得怎么样？",
            "他是我的老师，教汉语教了三年了。",
            "我最近在准备考试，有点紧张。",
        )
        val lemmas = VocabLemmas.lemmas(said, "zh")
        // 有点 is said, 有点儿 is the list's spelling of it.
        for (word in listOf("今天", "晚上", "吃饭", "觉得", "老师", "汉语",
            "最近", "准备", "考试", "有点儿", "紧张")) {
            assertTrue("headword $word not produced", word in lemmas)
        }
        // Content words only: particles and pronouns (我们, 怎么样) are left
        // out of the list on purpose, as in every other language's.
        for (word in listOf("的", "我们", "怎么样")) {
            assertFalse("$word should not be a headword", word in lemmas)
        }
    }

    /** ICU glues a word to the pronoun or particle beside it; the port cuts
     *  it back to iOS's words (measured cuts in the class doc). */
    @Test fun icuGluedCutsSplitBackToIosWords() {
        // The brief's two sentences, cut exactly as iOS cuts them.
        assertEquals(listOf("我们", "今天", "晚上", "去", "吃饭", "吧", "你", "觉得", "怎么样"),
            ChineseMorph.segments("我们今天晚上去吃饭吧，你觉得怎么样？"))
        assertEquals(listOf("他", "是", "我", "的", "老师", "教", "汉语", "教", "了", "三", "年", "了"),
            ChineseMorph.segments("他是我的老师，教汉语教了三年了。"))
        // Left whole: a name (明 is no headword) and a greeting iOS keeps whole.
        assertEquals(listOf("你好", "我", "叫", "小明", "很", "高兴", "认识", "你"),
            ChineseMorph.segments("你好！我叫小明，很高兴认识你。"))
    }

    @Test fun traditionalFoldsOntoSimplified() {
        assertEquals("这个问题我们说过了", ChineseMorph.simplified("這個問題我們說過了"))
        val words = ChineseMorph.words("這個問題我們說過了。")
        // Cut as words (not one character at a time), shown as written.
        assertTrue(words.any { it.surface == "問題" && it.key == "问题" })
        assertTrue(words.any { it.surface == "我們" && it.key == "我们" })
        assertEquals("问题", VocabLemmas.lemma("問題", "zh"))
        assertEquals(CoreVocabulary.level("说话", "zh"), CoreVocabulary.levelOfSurface("說話", "zh"))
    }

    @Test fun erhuaSpellingFindsTheHeadword() {
        assertNotNull(CoreVocabulary.level("一点儿", "zh"))
        assertEquals("一点儿", VocabLemmas.lemma("一点", "zh"))
    }

    @Test fun displayPiecesGiveTheTextBack() {
        val text = "你好！我叫小明，很高兴认识你。"
        val pieces = WordSplitter.displayPieces(text, "zh")
        assertEquals(text, pieces.joinToString("") { it.text })
        assertEquals(text, WordSplitter.timingWords(text, "zh").joinToString(""))
        assertEquals(pieces.size, WordSplitter.pieceKeys(text, "zh").size)
    }

    /** The recognizer picks the characters; a rewrite that only changes them
     *  corrects nothing the learner said. A change of tone is a real word. */
    @Test fun characterChoiceIsNotACorrection() {
        assertTrue(SpokenWords.saysTheSameThing("我們說過了", "我们说过了", "zh"))
        // The probe's one false accusation (2026-11-13): 的 / 得 are both "de".
        assertTrue(SpokenWords.saysTheSameThing("他跑的很快。", "他跑得很快。", "zh"))
        assertFalse(SpokenWords.saysTheSameThing("我想买书", "我想卖书", "zh"))
        assertFalse(CorrectionOnlyPrompt.scriptGuard("zh").isEmpty())
        assertTrue(CorrectionOnlyPrompt.scriptGuard("zh").contains("ASR CHARACTER GUARD"))
    }

    @Test fun shadowScoresTraditionalAndDigitsAsTheSameLine() {
        val a = ShadowScore.analyze("我学了三年汉语。", "我學了3年漢語", "zh")
        assertEquals(100, a.score)
    }

    @Test fun presetsSpeakMandarinWithChineseNames() {
        val slot = "NDTYOmYEjbDIVCKB35i3"
        assertEquals("6eb8965c-e295-47bd-a9e4-3eeebb3abcff", VoicePreset.speaking(slot, "zh"))
        assertEquals(listOf("李静", "张浩", "林兰", "刘洋"), StockPerson.catalog.map { it.nameIn("zh") })
    }

    @Test fun pinyinOnTheWordCard() {
        assertEquals("lǎoshī", CoreVocabulary.reading("老师", "zh"))
        assertNull(CoreVocabulary.reading("HSK", "zh"))
    }

    @Test fun examsAndCourse() {
        assertEquals(listOf(ExamKind.HSKK, ExamKind.TSC, ExamKind.OPIC), ExamKind.options("zh"))
        assertFalse(ExamTopics.topics(ExamKind.TSC, "zh").isEmpty())
        assertTrue(PronunciationAssessor.supports("zh"))
        assertNotNull(SpeechLibrary.builtIn("zh"))
    }
}
