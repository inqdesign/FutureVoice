package com.roro.futurevoice

import com.roro.futurevoice.data.DrillIngest
import com.roro.futurevoice.data.KoreanMorph
import com.roro.futurevoice.talk.CarryoverDetector
import com.roro.futurevoice.talk.Turn
import com.roro.futurevoice.talk.TurnFix
import com.roro.futurevoice.talk.TurnRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Port of iOS `KoreanMorphTests` + `KoreanCarryoverTests` (`bee9052d`).
 * Every Korean word the app tracks — the book's Words chapter, the chip that
 * ticks when a studied word is said, used-in-a-talk credit, the vocabulary
 * estimate — goes through [KoreanMorph]. These pin it against the REAL bundled
 * pool, in both directions: a spoken form finds its headword, and a word that
 * is a word stays itself.
 */
class KoreanMorphTest {

    private val levels: Map<String, Int> by lazy {
        val order = listOf("a1", "a2", "b1", "b2", "c1", "c2")
        File("src/main/assets/wordlists/cefr_words_ko.tsv").readLines()
            .mapNotNull { line ->
                val parts = line.split('\t')
                if (parts.size !in 2..3) return@mapNotNull null
                val rank = order.indexOf(parts[1].lowercase()).takeIf { it >= 0 } ?: return@mapNotNull null
                parts[0].lowercase() to rank
            }
            .groupBy({ it.first }, { it.second }).mapValues { it.value.first() }
    }

    private fun head(token: String): String? =
        KoreanMorph.dictionaryForm(token, levels.keys) { levels[it] }

    /** `expected` may list alternatives with "|" — 들어 is 들다 or 듣다. */
    private fun assertHeads(vararg cases: Pair<String, String>) {
        for ((token, expected) in cases) {
            val got = head(token)
            assertTrue("$token → $got, expected $expected", (got ?: "∅") in expected.split("|"))
        }
    }

    @Test fun poolShips() { assertTrue(levels.size > 5000) }

    /** The fluent self talks in 반말 — the most common verb shape in a call. */
    @Test fun casualPast() = assertHeads(
        "했어" to "하다", "왔어" to "오다", "됐어" to "되다", "줬어" to "주다",
        "봤는데" to "보다", "놀았어" to "놀다", "공부했어" to "공부하다",
        "기다렸어" to "기다리다", "이야기했어" to "이야기하다", "없었어" to "없다",
        "재밌었어" to "재미있다", "힘들었어" to "힘들다", "만났어요" to "만나다",
        "배웠어요" to "배우다", "먹었어요" to "먹다", "갔어요" to "가다")

    @Test fun presentAndContracted() = assertHeads(
        "마셔요" to "마시다", "가르쳐" to "가르치다", "봐" to "보다", "봐요" to "보다",
        "줘" to "주다", "돼" to "되다", "와요" to "오다", "피곤해" to "피곤하다",
        "좋아해" to "좋아하다", "괜찮아" to "괜찮다", "같아" to "같다", "있어" to "있다",
        "없어요" to "없다", "싶어요" to "싶다", "가요" to "가다", "간다" to "가다",
        "먹는다" to "먹다", "갑니다" to "가다")

    @Test fun irregulars() = assertHeads(
        "바빠요" to "바쁘다", "써요" to "쓰다", "예뻐요" to "예쁘다", "배고파" to "배고프다",
        "아파" to "아프다", "커" to "크다",
        "몰라요" to "모르다", "빨라" to "빠르다", "달라" to "다르다", "불렀어" to "부르다",
        "들어요" to "들다|듣다", "들었어" to "듣다|들다",
        "추워요" to "춥다", "더워" to "덥다", "가까워" to "가깝다", "고마워" to "고맙다",
        "어려워" to "어렵다", "도와요" to "돕다",
        "어때요" to "어떻다", "어땠어" to "어떻다", "하얀" to "하얗다",
        "사는" to "사다|살다", "압니다" to "알다", "만드는" to "만들다", "아세요" to "알다")

    @Test fun modifiersAndConnectives() = assertHeads(
        "좋은" to "좋다", "먹는" to "먹다", "갈" to "가다", "먹을" to "먹다",
        "자는" to "자다", "가고" to "가다", "먹으면" to "먹다", "가려고" to "가다",
        "가세요" to "가다", "보세요" to "보다", "하셨어" to "하다", "먹을게요" to "먹다",
        "할게" to "하다", "갈래" to "가다", "가자" to "가다", "모르겠어" to "모르다",
        "알" to "알다", "알아" to "알다")

    @Test fun nounsAndCopula() = assertHeads(
        "학교에서" to "학교", "학생이에요" to "학생", "친구예요" to "친구",
        "사람들이" to "사람", "주말에는" to "주말", "시간이" to "시간",
        "커피를" to "커피", "선생님이" to "선생님", "나는" to "나", "저는" to "저",
        "공부하고" to "공부하다", "대화하고" to "대화하다")

    /** The precision half: a word stays itself. */
    @Test fun wordsStayThemselves() = assertHeads(
        "내" to "내", "가지" to "가지", "하나" to "하나", "거의" to "거의",
        "그만" to "그만", "수도" to "수도", "속도" to "속도", "또는" to "또는",
        "줄" to "줄", "수" to "수", "때" to "때", "우리" to "우리", "어제" to "어제",
        "같이" to "같이", "많이" to "많이", "요즘" to "요즘", "바다" to "바다")

    @Test fun aWholeTurnReadsItsWords() {
        val text = "어제 친구랑 영화 봤는데 진짜 재밌었어. 너는 주말에 뭐 했어?"
        val found = text.split(Regex("[^\\p{L}\\p{N}]+")).mapNotNull { if (it.isEmpty()) null else head(it) }.toSet()
        for (word in listOf("어제", "친구", "영화", "보다", "진짜", "재미있다", "주말", "하다")) {
            assertTrue("missing $word in $found", word in found)
        }
    }

    // ── Expression credit (iOS KoreanCarryoverTests)

    private fun turn(text: String) = Turn(role = TurnRole.USER, transcript = text)

    @Test fun shortKoreanExpressionsAreCreditable() {
        assertTrue(CarryoverDetector.isCreditable("잘 모르겠어", "ko"))
        assertTrue(CarryoverDetector.isCreditable("그러게", "ko"))
        assertFalse(CarryoverDetector.isCreditable("잘 가", "ko"))
    }

    @Test fun politeEndingStillCreditsTheExpression() {
        assertNotNull(CarryoverDetector.firstMatch("잘 모르겠어", listOf(turn("음, 저도 잘 모르겠어요.")), language = "ko"))
    }

    @Test fun recognizerSpacingDoesNotMatter() {
        assertNotNull(CarryoverDetector.firstMatch("할 수 있어", listOf(turn("나도 할수있어")), language = "ko"))
    }

    @Test fun differentWordsDoNotMatch() {
        assertNull(CarryoverDetector.firstMatch("잘 모르겠어", listOf(turn("잘 알겠어")), language = "ko"))
    }

    /** A correction card keeps the strict comparison. */
    @Test fun correctionRejectsTheMistake() {
        assertNull(CarryoverDetector.firstMatch("학교에 가요", listOf(turn("저는 학교에서 가요")),
            rejectingMistake = "학교에서 가요", language = "ko"))
        assertNotNull(CarryoverDetector.firstMatch("학교에 가요", listOf(turn("내일 학교에 가요")),
            rejectingMistake = "학교에서 가요", language = "ko"))
    }

    // ── The card a fix becomes (iOS TurnFixTests)

    /** 학교에 갔어 is a card as it is — Korean is credited by syllables. */
    @Test fun aTwoEojeolKoreanFixIsTheCardAsItIs() {
        val fix = TurnFix(was = "학교를 갔어", now = "학교에 갔어", why = "조사")
        assertEquals("학교를 갔어" to "학교에 갔어", DrillIngest.cardPair(fix, "나는 어제 학교를 갔어. 너는?", "ko"))
    }

    @Test fun aShortKoreanFixIsWidenedToItsSentence() {
        val fix = TurnFix(was = "춥어", now = "추워", why = "ㅂ 불규칙")
        val pair = DrillIngest.cardPair(fix, "오늘 날씨가 너무 춥어. 너는?", "ko")
        assertEquals("오늘 날씨가 너무 춥어" to "오늘 날씨가 너무 추워", pair)
        assertTrue(CarryoverDetector.isCreditable(pair.second, "ko"))
    }

    /** iOS `politeSettingLine`: Korean only, never with the fluent self. */
    @Test fun politeSettingLineIsKoreanAndOnlyForAPoliteSetting() {
        val scene = com.roro.futurevoice.talk.ConversationCharacter.politeSettingLine("ko", null, inScene = true)
        assertTrue(scene.contains("EXCEPTION FOR THIS CALL — WHO THEY ARE TALKING TO"))
        assertTrue(scene.contains("반말 is right: nothing to correct"))
        assertEquals("", com.roro.futurevoice.talk.ConversationCharacter.politeSettingLine("ko", null, inScene = false))
        assertEquals("", com.roro.futurevoice.talk.ConversationCharacter.politeSettingLine("en", null, inScene = true))
    }
}
