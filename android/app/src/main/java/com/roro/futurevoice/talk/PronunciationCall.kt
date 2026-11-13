package com.roro.futurevoice.talk

import android.content.Context
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.IsoDateMillisSerializer
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.StoreJson
import com.roro.futurevoice.net.GeminiClient
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import java.io.File
import java.text.Normalizer

/**
 * The pronunciation call (iOS `PronunciationCall`, ffaf0c58, founder
 * 2026-11-04: "a call whose goal is pronunciation, like tutor mode — mainly
 * for beginners").
 *
 * The third page of the Talk ring. It IS a call: same screen, same gateway,
 * same voice, metered as talk time. What changes is who decides: the
 * learner's screen shows one sentence in big letters, they read it aloud,
 * the turn is HELD at the gateway (`holdReplies`) while the app judges the
 * take with Azure's pronunciation assessment ([PronunciationAssessor]), and
 * the fluent self says ONE line built from the app's verdict. The same "the
 * app decides, the voice says it" contract as tutor mode, with Azure in
 * place of the correction call and the judge.
 *
 * No summary and no book: what it leaves is the ledger and the course's
 * progress.
 */
object PronunciationCall {
    /** Written by the ring: true while its pronunciation page is showing. */
    const val KEY = "futurevoice.call.pronunciationMode"
    const val SENTENCES_PER_ROUND = 5

    fun lastTopicKey(language: String) = "futurevoice.pron.lastTopic.${language.substringBefore('-')}"
    fun lastFinishedKey(language: String) = "futurevoice.pron.lastFinished.${language.substringBefore('-')}"

    private fun prefs(context: Context) = context.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)

    fun isOn(context: Context): Boolean = prefs(context).getBoolean(KEY, false)
    fun set(context: Context, on: Boolean) = prefs(context).edit().putBoolean(KEY, on).apply()

    fun rememberTopic(context: Context, language: String, topicId: String) =
        prefs(context).edit().putString(lastTopicKey(language), topicId)
            .putBoolean(lastFinishedKey(language), false).apply()

    fun markFinished(context: Context, language: String) =
        prefs(context).edit().putBoolean(lastFinishedKey(language), true).apply()

    /** The topic the next call opens on (founder, 2026-11-04: a session
     *  finished and ended starts a NEW one next time): the course's next
     *  sound once the last topic's round was finished; the same sound when
     *  it was left halfway; the course's first otherwise. */
    fun startingTopic(context: Context, language: String, level: CefrLevel): PronunciationCourse.Topic? {
        val course = PronunciationCourse.topics(language)
        val p = prefs(context)
        val id = p.getString(lastTopicKey(language), null)
        val t = id?.let { i -> course.firstOrNull { it.id == i } }
        if (t != null) {
            if (!p.getBoolean(lastFinishedKey(language), false)) return t
            return PronunciationCourse.next(context, language, level, excluding = id) ?: t
        }
        return PronunciationCourse.next(context, language, level)
    }
}

// MARK: - Course

/**
 * The pronunciation course ("교재", founder): chapters of sounds per target
 * language, the same for everyone, written by us. `symbol` and `examples`
 * are target-language material and are never translated; the chapter names
 * are chrome.
 */
object PronunciationCourse {
    data class Chapter(val id: String, val icon: String, @androidx.annotation.StringRes val title: Int, val topics: List<Topic>)

    data class Topic(
        val id: String,
        /** How the sound is written, as a learner would recognise it. */
        val symbol: String,
        /** Three or four words that carry it, in the target language. */
        val examples: String,
        /** Azure's IPA names for the sound (en-US only). */
        val phonemes: List<String>,
        /** For the planner and the voice: what the sound is, in English. */
        val english: String,
    )

    private fun t(id: String, symbol: String, examples: String, phonemes: List<String>, english: String) =
        Topic(id, symbol, examples, phonemes, english)

    fun chapters(language: String): List<Chapter> {
        val consonants = R.string.consonants
        val vowels = R.string.vowels
        val flow = R.string.endings_and_flow
        val tones = R.string.tones
        return when (language.substringBefore('-')) {
            "en" -> listOf(
                Chapter("en.cons", "mouth", consonants, listOf(
                    t("en.th", "th", "think · three · thank", listOf("θ"),
                        "the voiceless 'th' /θ/ (think, three, thank): tongue tip lightly between the teeth, air out — not 's', 't' or 'f'"),
                    t("en.dh", "th", "this · that · mother", listOf("ð"),
                        "the voiced 'th' /ð/ (this, that, mother): tongue between the teeth with voice — not 'd' or 'z'"),
                    t("en.r", "r", "right · red · very", listOf("ɹ", "r", "ɻ"),
                        "the English 'r' /ɹ/ (right, red, very): tongue pulled back, never touching the roof of the mouth, lips a little round"),
                    t("en.rl", "r · l", "right · light · read · lead", listOf("ɹ", "r", "l"),
                        "telling 'r' and 'l' apart (right/light, read/lead): for 'l' the tongue tip touches behind the top teeth, for 'r' it touches nothing"),
                    t("en.f", "f · p", "coffee · five · phone", listOf("f", "p"),
                        "'f' (coffee, five, phone) as the top teeth on the lower lip with air — not 'p'"),
                    t("en.v", "v · b", "very · love · video", listOf("v", "b"),
                        "'v' (very, love, video) as top teeth on the lower lip with voice — not 'b'"),
                    t("en.z", "z", "zoo · is · music", listOf("z"),
                        "'z' (zoo, is, music) as a buzzing 's' — not 'j' or 's'"),
                    t("en.sh", "s · sh", "see · she · sip · ship", listOf("s", "ʃ"),
                        "telling 's' and 'sh' apart (see/she, sip/ship): 'sh' with rounded lips and the tongue further back"),
                )),
                Chapter("en.vow", "waveform", vowels, listOf(
                    t("en.i", "ee · i", "sheep · ship · leave · live", listOf("i", "iː", "ɪ"),
                        "long 'ee' /i/ vs short 'i' /ɪ/ (sheep/ship, leave/live): 'ee' is long with a wide smile, 'i' is short and relaxed"),
                    t("en.ae", "a", "cat · bad · apple", listOf("æ"),
                        "the 'a' in cat /æ/: mouth wide open and spread — not 'e' as in bed"),
                    t("en.uh", "u", "cup · but · love", listOf("ʌ"),
                        "the short 'u' in cup /ʌ/: short, relaxed, mouth half open — not 'o'"),
                    t("en.oo", "oo · u", "food · good · pool · pull", listOf("u", "uː", "ʊ"),
                        "long 'oo' /u/ vs short /ʊ/ (food/good, pool/pull)"),
                    t("en.er", "or · er", "walk · work · born · burn", listOf("ɔ", "ɝ", "ɚ", "ɜ"),
                        "'or' /ɔ/ vs 'er' /ɝ/ (walk/work, born/burn): 'er' with the tongue pulled back like an 'r'"),
                )),
                Chapter("en.flow", "spacing", flow, listOf(
                    t("en.final", "-t · -d · -k", "cat · bed · book", emptyList(),
                        "ending a word on a consonant (cat, bed, book) without adding a vowel after it ('book-u')"),
                    t("en.sed", "-s · -ed", "walks · walked · needs", listOf("s", "z", "t", "d"),
                        "saying the -s and -ed endings (walks, walked, needs) instead of dropping them"),
                    t("en.cluster", "str · spr", "street · spring · strong", emptyList(),
                        "consonant groups (street, spring, strong) said together, no vowel slipped in between"),
                )),
            )
            "de" -> listOf(
                Chapter("de.vow", "waveform", vowels, listOf(
                    t("de.ue", "ü", "über · grün · müde", emptyList(), "German 'ü' (über, grün, müde): say 'i' with the lips rounded like 'u'"),
                    t("de.oe", "ö", "schön · hören · Möbel", emptyList(), "German 'ö' (schön, hören): say 'e' with the lips rounded like 'o'"),
                    t("de.eiie", "ei · ie", "mein · mir · Wein · Wien", emptyList(), "'ei' is 'ai', 'ie' is a long 'ee' (mein/mir, Wein/Wien)"),
                    t("de.long", "aa · ah", "Staat · Stadt · Bahn · Bann", emptyList(), "long vs short vowels (Staat/Stadt, Bahn/Bann)"),
                )),
                Chapter("de.cons", "mouth", consonants, listOf(
                    t("de.ich", "ch", "ich · nicht · Milch", emptyList(), "the soft 'ch' after e/i (ich, nicht, Milch): a hissing sound, not 'sch' and not 'k'"),
                    t("de.ach", "ch", "Bach · noch · Buch", emptyList(), "the rough 'ch' after a/o/u (Bach, noch, Buch): from the back of the throat"),
                    t("de.r", "r", "rot · Reise · Brot", emptyList(), "German 'r' (rot, Reise): from the back of the throat, and soft like 'a' at the end of a word (Lehrer)"),
                    t("de.z", "z", "Zeit · zehn · Pizza", emptyList(), "German 'z' (Zeit, zehn) is 'ts', never a buzzing 'z'"),
                    t("de.w", "w", "Wasser · wann · Wein", emptyList(), "German 'w' (Wasser, wann) is an English 'v', never 'w'"),
                )),
            )
            "ja" -> listOf(
                Chapter("ja.len", "waveform", vowels, listOf(
                    t("ja.long", "ー", "おばさん · おばあさん · ビル · ビール", emptyList(), "long vowels (おばさん/おばあさん, ビル/ビール): a long vowel takes twice the time"),
                    t("ja.tsu", "っ", "きって · きて · まって", emptyList(), "the small っ (きって/きて): a short pause, one beat long, before the next sound"),
                    t("ja.n", "ん", "ほん · きんえん · せんせい", emptyList(), "ん is a full beat of its own (ほん, きんえん)"),
                )),
                Chapter("ja.cons", "mouth", consonants, listOf(
                    t("ja.r", "ら", "らいねん · くるま · ありがとう", emptyList(), "the Japanese r (ら行): a light tap of the tongue, between r, l and d"),
                    t("ja.tsusu", "つ · す", "つくえ · すし · なつ", emptyList(), "'tsu' vs 'su' (つくえ, すし): つ starts with a 't'"),
                    t("ja.zuji", "ざ · じゃ", "ざっし · じゃあ · ぜんぶ", emptyList(), "the z-row (ざ, ぜ, ぞ) vs じゃ"),
                )),
            )
            "ko" -> listOf(
                Chapter("ko.cons", "mouth", consonants, listOf(
                    t("ko.tense", "ㄲ ㄸ ㅃ ㅆ ㅉ", "까치 · 딸기 · 빵 · 싸다", emptyList(), "tense consonants (까, 따, 빠, 싸, 짜): tight throat, no puff of air"),
                    t("ko.asp", "ㅋ ㅌ ㅍ ㅊ", "커피 · 토요일 · 포도 · 차", emptyList(), "aspirated consonants (커, 터, 퍼, 처): a strong puff of air"),
                    t("ko.three", "ㄱ ㄲ ㅋ", "가다 · 까다 · 카드", emptyList(), "the three-way contrast (가/까/카, 달/딸/탈)"),
                    t("ko.batchim", "받침", "밥 · 국 · 옷 · 꽃", emptyList(), "final consonants (밥, 국, 옷): closed and not released, no vowel after"),
                )),
                Chapter("ko.vow", "waveform", vowels, listOf(
                    t("ko.eoo", "ㅓ · ㅗ", "어머니 · 오늘 · 거기 · 고기", emptyList(), "ㅓ (open, lips not rounded) vs ㅗ (rounded) — 거기/고기"),
                    t("ko.eu", "ㅡ", "그림 · 크다 · 음악", emptyList(), "ㅡ: lips spread flat, tongue back — not 'u'"),
                    t("ko.link", "연음", "한국어 · 음악 · 옷이", emptyList(), "linking a final consonant into the next vowel (한국어 → 한구거, 옷이 → 오시)"),
                )),
            )
            "es" -> listOf(
                Chapter("es.cons", "mouth", consonants, listOf(
                    t("es.rr", "rr", "perro · carro · rojo", emptyList(), "the trilled 'rr' (perro, carro, rojo at the start of a word): the tongue tip flutters"),
                    t("es.r", "r", "pero · caro · para", emptyList(), "the single tapped 'r' (pero, caro): one quick tap — pero vs perro"),
                    t("es.j", "j · g", "jamón · gente · ojo", emptyList(), "'j' and 'g' before e/i (jamón, gente): a rough 'h' from the throat"),
                    t("es.bv", "b · v", "vino · bueno · Cuba", emptyList(), "'b' and 'v' are the same sound, soft between vowels (Cuba, uva)"),
                    t("es.ny", "ñ", "año · España · niño", emptyList(), "'ñ' (año, España): like 'ny' in canyon"),
                )),
                Chapter("es.vow", "waveform", vowels, listOf(
                    t("es.vowels", "a e i o u", "casa · mesa · libro · todo", emptyList(), "the five pure vowels (casa, mesa, todo): short and clean, never glided like English 'o-u' or 'e-i'"),
                )),
            )
            "fr" -> listOf(
                Chapter("fr.vow", "waveform", vowels, listOf(
                    t("fr.u", "u · ou", "tu · tout · dessus · dessous", emptyList(), "'u' (tu, rue): lips rounded tight as for 'oo' while the tongue says 'ee' — tu vs tout"),
                    t("fr.nasal", "an · on · in", "vent · vont · vin · pain", emptyList(), "the nasal vowels (vent, vont, vin): air through the nose, no 'n' or 'ng' sound at the end"),
                    t("fr.e", "é · è", "été · café · père · mère", emptyList(), "'é' closed and short (été, café) vs 'è' open (père, mère), never glided into 'ay'"),
                    t("fr.eu", "eu", "deux · peu · peur · heure", emptyList(), "'eu' (deux, peur): rounded lips with the tongue forward — not 'oo', not 'uh'"),
                )),
                Chapter("fr.cons", "mouth", consonants, listOf(
                    t("fr.r", "r", "rouge · Paris · très · rentrer", emptyList(), "the French 'r' (rouge, très): made at the back of the throat, a light scrape, never rolled or English"),
                    t("fr.liaison", "liaison", "les amis · vous avez · un enfant", emptyList(), "liaison: a silent final consonant joins the next vowel (les amis → lé-za-mi, vous avez → vou-za-vé)"),
                    t("fr.silent", "lettres muettes", "petit · beaucoup · ils parlent", emptyList(), "silent endings: the final t, p, s, x and -ent of verbs are not said (petit, beaucoup, ils parlent)"),
                )),
            )
            // zh-CN scores a syllable WITH its tone ("mai 3"), and a wrong
            // tone only pulls it to the 60s–90s (measured 2026-11-13 with
            // macOS voices), so tones are judged on the focus words' bar.
            "zh" -> listOf(
                Chapter("zh.tone", "waveform.path", tones, listOf(
                    t("zh.t1", "ā", "妈妈 · 喝 · 书 · 星期天", emptyList(), "the first tone (mā, shū): high and level, held flat like a note — it does not fall at the end"),
                    t("zh.t2", "á", "来 · 学 · 茶 · 中国", emptyList(), "the second tone (lái, xué): rising from the middle to the top, like a surprised 'what?'"),
                    t("zh.t3", "ǎ", "我 · 买 · 好 · 喜欢", emptyList(), "the third tone (wǒ, mǎi): low; in speech it mostly stays low and does not rise again unless it ends a phrase"),
                    t("zh.t4", "à", "去 · 是 · 再见 · 谢谢", emptyList(), "the fourth tone (qù, shì): falling sharply from the top, short and firm"),
                    t("zh.sandhi", "ǎ → á", "你好 · 可以 · 很好 · 洗澡", emptyList(), "two third tones in a row (nǐ hǎo): the first becomes a rising second tone, ní hǎo"),
                    t("zh.yibu", "一 · 不", "一起 · 一样 · 不是 · 不对", emptyList(), "一 and 不 change tone: 不 is bú before a fourth tone (bú shì), 一 is yí before a fourth tone (yíyàng) and yì before the others (yìqǐ)"),
                    t("zh.neutral", "ma", "妈妈 · 朋友 · 东西 · 你们", emptyList(), "the neutral tone (māma, péngyou): the second syllable short and light, with no tone of its own"),
                )),
                Chapter("zh.cons", "mouth", consonants, listOf(
                    t("zh.retro", "zh ch sh", "知道 · 吃 · 是 · 老师", emptyList(), "zh, ch, sh (zhīdào, chī, shì): tongue tip curled back toward the roof of the mouth — not z, c, s"),
                    t("zh.flat", "z c s", "在 · 菜 · 四 · 自己", emptyList(), "z, c, s (zài, cài, sì): tongue tip flat behind the bottom teeth; c is 'ts' with a puff of air"),
                    t("zh.jqx", "j q x", "家 · 去 · 谢谢 · 学校", emptyList(), "j, q, x (jiā, qù, xièxie): tongue flat against the front of the palate, lips spread — not English j/ch/sh"),
                    t("zh.r", "r", "人 · 热 · 日本 · 认识", emptyList(), "the Chinese r (rén, rè): like sh with voice, the tongue curled back — not an English r and not l"),
                    t("zh.asp", "p t k", "朋友 · 他 · 可以 · 怕", emptyList(), "aspirated p, t, k, q, ch, c (péngyou, tā, kěyǐ): a strong puff of air; b, d, g have none (bù vs pù)"),
                )),
                Chapter("zh.vow", "waveform", vowels, listOf(
                    t("zh.u", "ü", "绿 · 去 · 鱼 · 女", emptyList(), "ü (lǜ, nǚ, and the u in qù, yú): say 'ee' with the lips rounded tight"),
                    t("zh.e", "e", "饿 · 喝 · 哥哥 · 车", emptyList(), "e (è, hē): from the back of the mouth, lips not rounded — between 'uh' and 'o'"),
                    t("zh.i", "-i", "是 · 四 · 吃 · 字", emptyList(), "the i after zh/ch/sh/r and z/c/s (shì, sì): a buzzing continuation of the consonant, never 'ee'"),
                    t("zh.n", "-n · -ng", "人 · 能 · 看 · 忙", emptyList(), "-n vs -ng (rén/néng, kàn/máng): -n ends at the teeth, -ng at the back of the mouth"),
                )),
            )
            else -> emptyList()
        }
    }

    fun topics(language: String): List<Topic> = chapters(language).flatMap { it.topics }

    fun topic(id: String, language: String): Topic? = topics(language).firstOrNull { it.id == id }

    /** The first topic never practiced; once every topic has been, the one
     *  with the lowest recent score. */
    fun next(context: Context, language: String, level: CefrLevel, excluding: String? = null): Topic? {
        val progress = PronunciationProgressStore.all(context, language)
        val all = topics(language).filter { it.id != excluding }
        all.firstOrNull { progress[it.id] == null }?.let { return it }
        return all.minByOrNull { progress[it.id]?.lastScore ?: 0 }
    }
}

// MARK: - Progress

@Serializable
data class PronunciationTopicProgress(
    /** Rounds finished on this topic. */
    val rounds: Int = 0,
    /** Sentences passed, all rounds. */
    val passed: Int = 0,
    /** The mean sound score of the last finished round. */
    val lastScore: Int? = null,
    val bestScore: Int? = null,
    @Serializable(with = IsoDateMillisSerializer::class)
    val lastAt: Long? = null,
    /** Words that still didn't come out after the round brought them back
     *  once (newest 8 kept): the next round is written around them. */
    val missedWords: List<String>? = null,
)

/** `lang/<code>/pronunciation_course.json`. Device-local, like iOS. */
object PronunciationProgressStore {
    private val serializer = MapSerializer(String.serializer(), PronunciationTopicProgress.serializer())
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = false }

    private fun file(context: Context, language: String) =
        File(LanguageScope.directory(context, language.substringBefore('-')), "pronunciation_course.json")

    fun all(context: Context, language: String): Map<String, PronunciationTopicProgress> =
        runCatching { json.decodeFromString(serializer, file(context, language).readText()) }.getOrDefault(emptyMap())

    @Synchronized
    fun update(context: Context, language: String, topicId: String,
               change: (PronunciationTopicProgress) -> PronunciationTopicProgress) {
        val all = all(context, language).toMutableMap()
        all[topicId] = change(all[topicId] ?: PronunciationTopicProgress()).copy(lastAt = System.currentTimeMillis())
        runCatching {
            val f = file(context, language)
            f.parentFile?.mkdirs()
            val tmp = File(f.parentFile, f.name + ".tmp")
            tmp.writeText(json.encodeToString(serializer, all))
            tmp.renameTo(f)
        }
    }
}

// MARK: - Round

/** One round: five sentences for one sound, read one at a time. */
data class PronunciationRound(
    val id: String = StoreJson.newId(),
    val topic: PronunciationCourse.Topic,
    /** How to make the sound, in the learner's NATIVE language (coaching). */
    val tip: String,
    val lines: List<Line>,
    val language: String,
    /** The sentence the learner just skipped: what it was about and when it
     *  comes back, shown on the next sentence's card until its first take. */
    val carried: Carried? = null,
) {
    data class Line(
        val id: String = StoreJson.newId(),
        val text: String,
        /** The words in [text] that carry the sound, as written there. */
        val focus: List<String>,
        val tries: Int = 0,
        val passed: Boolean = false,
        /** Left by the learner's "Next sentence" without a pass. */
        val skipped: Boolean = false,
        /** The last judged take, drawn on the card. */
        val lastResult: PronunciationResult? = null,
        val bestScore: Int? = null,
        /** The last take's word that came out as ANOTHER word (text-only fallback). */
        val heardWord: String? = null,
        val heardAs: String? = null,
        /** The last take had every sound but stopped and started. */
        val notSmooth: Boolean = false,
        /** A word that didn't come out, practiced ON ITS OWN before the
         *  sentence is read again. null = the sentence. */
        val drillWord: String? = null,
        val drillTries: Int = 0,
        /** The words (keys) that missed on this sentence's first judged
         *  reading. A reading after that is judged on these alone and the
         *  set only shrinks (2026-11-06, iOS 5b9ee99d). null = not judged yet. */
        val watch: Set<String>? = null,
        /** Words (keys) already said right ON THEIR OWN in this sentence's
         *  drill. One that misses in the sentence again is practiced with its
         *  neighbours next ([PronunciationJudge.flowText]): the sentence's
         *  score is the one that counts (founder, 2026-11-06, iOS cd5be2f3). */
        val soloPassed: Set<String> = emptySet(),
        /** The last take's verdict as the learner sees it. */
        val feedback: Feedback? = null,
        /** The second time this sentence comes up in the round. */
        val isRetry: Boolean = false,
    )

    data class Feedback(
        /** The word; null when the flow was judged. */
        val word: String?,
        /** The sound in it, English only. */
        val sound: String?,
        val score: Int,
        val ok: Boolean,
        /** How that sound came out, when Azure heard something else. */
        val heardAs: PronunciationJudge.HeardAs? = null,
    )

    data class Carried(val word: String?, val sound: String?, val laterInRound: Boolean)

    val current: Int? get() = lines.indexOfFirst { !it.passed && !it.skipped }.takeIf { it >= 0 }
    val isFinished: Boolean get() = current == null
    val doneCount: Int get() = lines.count { it.passed || it.skipped }
    val passedCount: Int get() = lines.count { it.passed }
    /** Sentences in the round, a sentence brought back at the end counted once. */
    val sentenceCount: Int get() = lines.map { it.text }.toSet().size

    /** Mean of each line's best sound score, over the lines that have one. */
    val meanScore: Int? get() {
        val s = lines.mapNotNull { it.bestScore }
        return if (s.isEmpty()) null else s.sum() / s.size
    }

    fun replacing(i: Int, change: (Line) -> Line): PronunciationRound =
        copy(lines = lines.mapIndexed { j, l -> if (j == i) change(l) else l })
}

// MARK: - Planner

object PronunciationPlanner {
    @Serializable
    private data class Plan(val tip: String? = null, val sentences: List<Item>? = null) {
        @Serializable data class Item(val text: String = "", val focus: List<String>? = null)
    }

    fun systemPrompt(topic: PronunciationCourse.Topic, targetLanguage: String, nativeLanguage: String,
                     level: CefrLevel, persona: UserPersona?, avoid: List<String>, review: List<String>): String {
        val target = LanguageCatalog.englishName(targetLanguage)
        val native = LanguageCatalog.englishName(nativeLanguage)
        val length = when (level) {
            CefrLevel.A1 -> "4 to 7 words, the most everyday words there are"
            CefrLevel.A2 -> "5 to 9 words, everyday words"
            CefrLevel.B1 -> "7 to 12 words"
            else -> "8 to 14 words, natural and a little challenging"
        }
        val about = listOf(persona?.occupation, persona?.city).mapNotNull { it?.trim() }
            .filter { it.isNotEmpty() }.joinToString(" · ")
        val reviewLine = if (review.isEmpty()) "" else
            "\n\n- These words did NOT come out right last time: ${review.joinToString(", ")}. Put them in the FIRST sentences, one or two per sentence, and list them in \"focus\" too."
        return "You write PRONUNCIATION practice for a $target learner at CEFR " +
            "${level.code.uppercase()} whose own language is $native. They " +
            "will read each sentence aloud from their screen, and a machine will " +
            "score how they pronounced it.\n\n" +
            "Today's sound: ${topic.english}.\n" +
            "Example words: ${topic.examples}.\n\n" +
            "Write ${PronunciationCall.SENTENCES_PER_ROUND} sentences in $target:\n" +
            "- Each sentence is $length, something a person would really say, " +
            "in first person or about everyday life. Spoken, so contracted the " +
            "way people talk.\n" +
            "- Each sentence carries today's sound at least TWICE, in different " +
            "words where possible. Start easy (the sound once or twice, short " +
            "words) and get a little harder toward the last.\n" +
            "- \"focus\": the words in that sentence that carry the sound, copied " +
            "EXACTLY as they are written in it (same spelling, same case).\n" +
            "- No names, numbers written as digits, abbreviations, brackets or " +
            "quotes — only words a reader can say.\n" +
            "- No two sentences alike, and none of these: ${if (avoid.isEmpty()) "(none)" else avoid.joinToString(" | ")}." +
            reviewLine + "\n\n" +
            "\"tip\": ONE or two short sentences in $native telling a beginner how " +
            "to make the sound with their mouth (tongue, lips, teeth, breath), " +
            "concrete, friendly, no phonetic symbols.\n" +
            (if (about.isEmpty()) "" else "\nWhat is known about them: $about. Context only.") + "\n" +
            "Return STRICT JSON only:\n" +
            "{\"tip\": \"...\", \"sentences\": [{\"text\": \"...\", \"focus\": [\"...\"]}]}"
    }

    /** Five sentences for [topic] at the learner's level, and a one-line tip
     *  in their native language. Null when the call failed. */
    suspend fun plan(topic: PronunciationCourse.Topic, targetLanguage: String, nativeLanguage: String,
                     level: CefrLevel, persona: UserPersona?, avoid: List<String> = emptyList(),
                     review: List<String> = emptyList()): PronunciationRound? {
        val system = systemPrompt(topic, targetLanguage, nativeLanguage, level, persona, avoid, review)
        var plan: Plan? = null
        repeat(2) {
            if (plan != null) return@repeat
            plan = kotlinx.coroutines.withTimeoutOrNull(20_000) {
                runCatching {
                    GeminiClient(AuthRepository()).sendJson(
                        system = system,
                        messages = listOf(GeminiClient.Message(GeminiClient.Message.Role.USER,
                            "Sound: ${topic.symbol} (${topic.examples})")),
                        serializer = Plan.serializer(),
                        maxTokens = 1500, purpose = "tutor",
                        idempotencyKey = "pron-plan:${StoreJson.newId()}",
                    )
                }.getOrNull()
            }
            if (plan?.sentences.isNullOrEmpty()) plan = null
        }
        val items = plan?.sentences ?: return null
        val lines = items.take(PronunciationCall.SENTENCES_PER_ROUND).mapNotNull { item ->
            val text = item.text.trim()
            if (text.isEmpty()) return@mapNotNull null
            // A focus word the sentence doesn't contain would mark nothing.
            val focus = item.focus.orEmpty().filter { it.isNotEmpty() && PronunciationJudge.contains(text, it) }
            PronunciationRound.Line(text = text, focus = focus)
        }
        if (lines.size < 3) return null
        return PronunciationRound(topic = topic, tip = plan?.tip?.trim().orEmpty(), lines = lines,
            language = targetLanguage)
    }
}

// MARK: - Judge

/** What a take of the sentence on screen gets. Code, never a model: the
 *  numbers are Azure's, the bar is ours. */
object PronunciationJudge {
    sealed class Verdict {
        /** Every sound clear and the sentence said in one go. */
        data class Pass(val score: Int) : Verdict()
        /** One word to work on. `heard` is set only by the text-only fallback. */
        data class NotYet(val word: String, val sound: String?, val score: Int, val heard: String?) : Verdict()
        /** Every sound was clear but the reading stopped and started. */
        data class NotSmooth(val score: Int) : Verdict()
        /** They said something else. */
        data object OffScript : Verdict()
        /** Nothing usable came back. */
        data object Unheard : Verdict()

        val name: String get() = when (this) {
            is Pass -> "pass"; is NotYet -> "not_yet"; is NotSmooth -> "not_smooth"
            OffScript -> "off_script"; Unheard -> "unheard"
        }
    }

    /** The AUDIO decides, never the transcript (founder, 2026-11-04). Bars
     *  set on the founder's own takes that day (iOS). */
    /** Outside the lesson's sound only what plainly didn't come out stops a
     *  sentence (2026-11-06, iOS 5b9ee99d: a learner's 85–97 readings failed
     *  41 times in 52, somewhere new each time). A non-lesson VOWEL never
     *  stops a reading ("decision" with /ə/ or /ɪ/). */
    const val LESSON_SOUND_BAR = 70
    const val WORD_BAR = 50
    const val SOUND_BAR = 50
    const val FINAL_STOP_BAR = 40
    const val PROSODY_BAR = 80
    const val FLUENCY_BAR = 70
    const val COMPLETENESS_BAR = 50
    /** Kept for the course's colour of a topic's last score. */
    const val PASS_BAR = 70

    private val FINAL_STOPS = setOf("p", "t", "k", "b", "d", "g")

    /** [only]: judge just these words (keys) — a sentence read again after a
     *  miss is judged on what was wrong the first time ([PronunciationRound.Line.watch]).
     *  [excluding]: skip these words, for listing every miss ([missedWords]).
     *  [wordDrill]: a word (or a short chunk) practiced on its own — every
     *  sound of it is the take, so a sound Azure heard as ANOTHER sound is
     *  "not yet" even when its score clears the bars ([swappedTo]). */
    fun verdict(result: PronunciationResult?, line: PronunciationRound.Line, said: String,
                phonemes: List<String>, language: String,
                only: Set<String>? = null, excluding: Set<String> = emptySet(),
                wordDrill: Boolean = false): Verdict {
        result ?: return Verdict.Unheard
        if ((result.completeness ?: 100) < COMPLETENESS_BAR) return Verdict.OffScript
        fun inScope(w: PronunciationResult.Word): Boolean {
            val k = key(w.word)
            return k !in excluding && (only?.contains(k) ?: true)
        }
        val judged = result.referenceWords.filter { it.isJudged && inScope(it) }

        // 1. The lesson's sound, wherever it is in the sentence.
        if (phonemes.isNotEmpty()) {
            val hits = judged.mapNotNull { w ->
                val worst = w.phonemes.filter { isLesson(it.phoneme, phonemes) && it.accuracy != null }
                    .minByOrNull { it.accuracy!! } ?: return@mapNotNull null
                if (worst.accuracy!! < LESSON_SOUND_BAR) w to worst else null
            }
            hits.minByOrNull { it.second.accuracy!! }?.let { (w, p) ->
                return Verdict.NotYet(w.word, p.phoneme, result.soundScore, null)
            }
        } else {
            // No phoneme names (every language but English): the words that
            // carry the sound, held to a higher bar than the rest.
            val focusKeys = line.focus.map(::key).toSet()
            judged.filter { key(it.word) in focusKeys && (it.accuracy ?: 100) < 85 }
                .minByOrNull { it.accuracy ?: 100 }?.let {
                    return Verdict.NotYet(it.word, null, result.soundScore, null)
                }
        }
        // 2. Any SOUND that came out badly, wherever it is; a word-final
        //    stop gets a lower bar (left unreleased, as English often does).
        val soundHits = judged.mapNotNull { w ->
            val named = w.phonemes.filter { it.accuracy != null }
            val off = named.filterIndexed { i, p ->
                // Vowels outside the lesson never stop a reading; an unnamed
                // phoneme (not English) is judged as before.
                if (p.phoneme.isNotEmpty() && hasVowel(p.phoneme) && !isLesson(p.phoneme, phonemes)) return@filterIndexed false
                val finalStop = i == named.size - 1 && p.phoneme in FINAL_STOPS
                p.accuracy!! < (if (finalStop) FINAL_STOP_BAR else SOUND_BAR)
            }
            off.minByOrNull { it.accuracy!! }?.let { w to it }
        }
        soundHits.minByOrNull { it.second.accuracy!! }?.let { (w, p) ->
            return Verdict.NotYet(w.word, p.phoneme.ifEmpty { null }, result.soundScore, null)
        }
        // 2b. A word on its own: a sound that came out as ANOTHER sound,
        //     whatever its score. Scripted Azure scores a sound against the
        //     word it was told to expect, so "sink" read as "think" kept θ at
        //     73 and both drills passed (iOS e272f61f). Its list of what it
        //     heard does not forgive: s at 100 with θ absent.
        if (wordDrill) {
            val swaps = judged.mapNotNull { w ->
                val named = w.phonemes.filter { it.accuracy != null }
                val off = named.filterIndexed { i, p ->
                    val finalStop = i == named.size - 1 && p.phoneme in FINAL_STOPS
                    !finalStop && swappedTo(p) != null
                }
                off.minByOrNull { it.accuracy!! }?.let { w to it }
            }
            swaps.minByOrNull { it.second.accuracy!! }?.let { (w, p) ->
                return Verdict.NotYet(w.word, p.phoneme, result.soundScore, null)
            }
        }
        // 3. Any word that came out badly, or a word left out.
        result.referenceWords.filter { inScope(it) && (it.isOmission || (it.isJudged && (it.accuracy ?: 100) < WORD_BAR)) }
            .minByOrNull { it.accuracy ?: 0 }?.let { w ->
                return Verdict.NotYet(w.word, if (w.isJudged) sound(w, phonemes) else null, result.soundScore, null)
            }
        // 4. Smooth: in one go, without stopping and starting.
        if ((result.prosody ?: 100) < PROSODY_BAR || result.fluency < FLUENCY_BAR) {
            return Verdict.NotSmooth(result.soundScore)
        }
        return Verdict.Pass(result.soundScore)
    }

    /** Every word that missed in a take, worst first: the verdict asked again
     *  with each word it named set aside. */
    fun missedWords(result: PronunciationResult?, line: PronunciationRound.Line, said: String,
                    phonemes: List<String>, language: String, only: Set<String>? = null): List<String> {
        val out = mutableListOf<String>()
        val seen = mutableSetOf<String>()
        while (out.size < 12) {
            val v = verdict(result, line, said, phonemes, language, only, seen) as? Verdict.NotYet ?: break
            val k = key(v.word)
            if (k.isEmpty() || !seen.add(k)) break
            out += v.word
        }
        return out
    }

    /** [word] with the words on either side of it, as the sentence runs them
     *  together ("I'd rather walk"): the drill for a word that is right alone
     *  and slips in the sentence. At the sentence's edge, the two words after
     *  or before it. */
    fun flowText(word: String, sentence: String): String {
        val words = sentence.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val k = key(word.split(Regex("\\s+")).firstOrNull { it.isNotEmpty() } ?: word)
        val i = words.indexOfFirst { key(it) == k }
        if (words.size < 2 || i < 0) return trimPunctuation(word)
        val lo = maxOf(0, minOf(i - 1, words.size - 3))
        val hi = minOf(words.size - 1, lo + 2)
        return trimPunctuation(words.subList(lo, hi + 1).joinToString(" "))
    }

    /** What the card shows for a verdict: the word and sound that were
     *  judged and the score that decided it. */
    fun feedback(verdict: Verdict, result: PronunciationResult?, line: PronunciationRound.Line,
                 phonemes: List<String>): PronunciationRound.Feedback? {
        result ?: return null
        val words = result.referenceWords.filter { it.isJudged }
        fun scoreOf(word: String, sound: String?): Int? {
            val w = words.firstOrNull { key(it.word) == key(word) } ?: return null
            if (sound != null) w.phonemes.filter { it.phoneme == sound }.mapNotNull { it.accuracy }.minOrNull()?.let { return it }
            return w.accuracy
        }
        return when (verdict) {
            is Verdict.NotYet -> PronunciationRound.Feedback(verdict.word, verdict.sound,
                scoreOf(verdict.word, verdict.sound) ?: result.soundScore, ok = false,
                heardAs = heardAs(result, verdict.word, verdict.sound))
            is Verdict.NotSmooth -> PronunciationRound.Feedback(null, null, result.prosody ?: result.fluency, ok = false)
            is Verdict.Pass -> {
                // The lesson's weakest sound in what was said, or the take's
                // sound score when the language names no phonemes.
                val lesson = words.flatMap { w ->
                    w.phonemes.filter { isLesson(it.phoneme, phonemes) }.mapNotNull { p ->
                        p.accuracy?.let { Triple(w.word, p.phoneme, it) }
                    }
                }
                val worst = lesson.minByOrNull { it.third }
                when {
                    worst != null -> PronunciationRound.Feedback(worst.first, worst.second, worst.third, ok = true)
                    words.size == 1 -> PronunciationRound.Feedback(words[0].word, null,
                        words[0].accuracy ?: result.soundScore, ok = true)
                    else -> PronunciationRound.Feedback(null, null, result.soundScore, ok = true)
                }
            }
            Verdict.OffScript, Verdict.Unheard -> null
        }
    }

    private val WEAK = setOf("the", "a", "an", "to", "of", "for", "and", "but", "or", "at",
        "from", "as", "than", "that", "can", "was", "were", "have",
        "has", "had", "do", "does", "you", "your", "them", "her",
        "his", "him", "some", "are", "is", "am", "be", "been", "would",
        "could", "should", "just", "there", "us", "our")

    private fun trimPunctuation(s: String): String =
        s.trim { !it.isLetterOrDigit() && !it.isWhitespace() }

    /** What is practiced on its own when [word] didn't come out. A word whose
     *  sound DEPENDS on the sentence is never cut out alone: English weak
     *  forms and any one- or two-letter word go with their neighbour. */
    fun drillText(word: String, sentence: String, language: String): String {
        val clean = trimPunctuation(word)
        val k = key(clean)
        val dependsOnSentence = k.length <= 2 || (language.substringBefore('-') == "en" && k in WEAK)
        if (!dependsOnSentence) return clean
        val words = sentence.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val i = words.indexOfFirst { key(it) == k }
        if (i < 0) return clean
        val pair = when {
            i + 1 < words.size -> listOf(words[i], words[i + 1])
            i > 0 -> listOf(words[i - 1], words[i])
            else -> return clean
        }
        return trimPunctuation(pair.joinToString(" "))
    }

    /** How a sound came out, read off Azure's list of what it heard. */
    sealed class HeardAs {
        /** It came out as another sound ("f" → "p"). */
        data class Sound(val phoneme: String) : HeardAs()
        /** A vowel slipped in with this consonant ("드링크" for "drink"). */
        data object VowelAdded : HeardAs()
    }

    private const val VOWEL_CHARS = "aeiouɪʊəɛæʌɔɑɒɐɜɝɚy"
    private fun hasVowel(p: String) = p.any { it in VOWEL_CHARS }

    /** A sound under this whose list puts another sound on top and its own
     *  at [SWAP_OWN_MAX] or below (or not at all) came out as that other
     *  sound. Measured 2026-11-07 on iOS (en-US, single words): every
     *  minimal-pair swap the bars missed sat at 50–82 with its own sound at
     *  38 or absent; every native word kept its own sound above 50 in the
     *  list or scored 75+. */
    const val SWAP_BAR = 75
    const val SWAP_OWN_MAX = 50

    /** The sound [p] came out as, when Azure heard it as another one.
     *  Reduced vowels don't count: a schwa said as ɪ or ʌ is a dialect, not
     *  another word. */
    fun swappedTo(p: PronunciationResult.Phoneme): String? {
        if (p.phoneme.isEmpty()) return null
        val list = p.heard ?: return null
        val top = list.firstOrNull() ?: return null
        if (top.phoneme == p.phoneme || top.score < 70) return null
        if ((p.accuracy ?: 100) >= SWAP_BAR) return null
        if ((list.firstOrNull { it.phoneme == p.phoneme }?.score ?: 0) > SWAP_OWN_MAX) return null
        val loose = setOf("ə", "ɚ")
        if (p.phoneme in loose || top.phoneme in loose ||
            setOf(p.phoneme, top.phoneme) == setOf("ɝ", "ɚ")) return null
        return top.phoneme
    }

    fun heardAs(p: PronunciationResult.Phoneme): HeardAs? {
        swappedTo(p)?.takeIf { (p.accuracy ?: 100) >= 70 }?.let { other ->
            return if (!hasVowel(p.phoneme) && hasVowel(other)) HeardAs.VowelAdded else HeardAs.Sound(other)
        }
        val list = p.heard
        if (list.isNullOrEmpty() || (p.accuracy ?: 100) >= 70) return null
        val isConsonant = !hasVowel(p.phoneme)
        val top = list.first()
        if (top.phoneme != p.phoneme && top.score >= 70) {
            return if (isConsonant && hasVowel(top.phoneme)) HeardAs.VowelAdded else HeardAs.Sound(top.phoneme)
        }
        if (isConsonant && list.any { hasVowel(it.phoneme) && it.score >= 60 }) return HeardAs.VowelAdded
        return null
    }

    /** The word the longest stop of a reading came in front of, when one
     *  stop stands out (Azure's word times). null when no gap is long
     *  enough to name. */
    fun pauseBefore(result: PronunciationResult?): String? {
        val words = result?.judgedWords?.filter { it.durationMs > 0 }?.sortedBy { it.offsetMs } ?: return null
        if (words.size < 2) return null
        var best: Pair<Int, String>? = null
        for ((a, b) in words.zip(words.drop(1))) {
            val gap = b.offsetMs - (a.offsetMs + a.durationMs)
            if (gap >= 350 && gap > (best?.first ?: 0)) best = gap to b.word
        }
        return best?.second
    }

    fun heardAs(result: PronunciationResult?, word: String, sound: String?): HeardAs? {
        sound ?: return null
        val w = result?.referenceWords?.firstOrNull { key(it.word) == key(word) } ?: return null
        val p = w.phonemes.filter { it.phoneme == sound }.minByOrNull { it.accuracy ?: 100 } ?: return null
        return heardAs(p)
    }

    /** Whether Azure's phoneme [p] is (or carries) one of the lesson's sounds. */
    fun isLesson(p: String, lesson: List<String>): Boolean {
        if (p in lesson) return true
        if (lesson.any { it.length == 1 && p.length > 1 && p.contains(it) }) return true
        if ("ɹ" in lesson && (p.contains("ɝ") || p.contains("ɚ"))) return true
        return false
    }

    /** Words for comparing a reading with its sentence (contractions spelled out). */
    fun tokens(text: String, language: String): List<String> =
        ShadowScore.expandForDiff(text, language).split(Regex("\\s+")).filter { key(it).isNotEmpty() }

    /** Words of the sentence the transcript has as a DIFFERENT single word. */
    fun substitutions(said: String, line: String, language: String): List<Pair<String, String>> {
        val ref = tokens(line, language)
        val hyp = tokens(said, language)
        if (ref.size < 2 || hyp.size < 2) return emptyList()
        val a = ref.map(::key); val b = hyp.map(::key)
        val dp = Array(a.size + 1) { IntArray(b.size + 1) }
        for (i in a.size - 1 downTo 0) for (j in b.size - 1 downTo 0) {
            dp[i][j] = if (a[i] == b[j]) dp[i + 1][j + 1] + 1 else maxOf(dp[i + 1][j], dp[i][j + 1])
        }
        val out = mutableListOf<Pair<String, String>>()
        var i = 0; var j = 0
        val gapA = mutableListOf<Int>(); val gapB = mutableListOf<Int>()
        fun add(x: Int, y: Int) {
            if (b[y].all { it.isDigit() }) return
            out += trimPunctuation(ref[x]) to trimPunctuation(hyp[y])
        }
        fun flush() {
            if (gapA.size == gapB.size) {
                gapA.zip(gapB).forEach { (x, y) -> add(x, y) }
            } else {
                val used = mutableSetOf<Int>()
                for (y in gapB) {
                    val best = gapA.filter { it !in used }.map { it to similarity(a[it], b[y]) }.maxByOrNull { it.second }
                    if (best != null && best.second >= 0.5) { used += best.first; add(best.first, y) }
                }
            }
            gapA.clear(); gapB.clear()
        }
        while (i < a.size || j < b.size) {
            if (i < a.size && j < b.size && a[i] == b[j]) {
                flush(); i++; j++
            } else if (j >= b.size || (i < a.size && dp[i + 1][j] >= dp[i][j + 1])) {
                gapA += i; i++
            } else {
                gapB += j; j++
            }
        }
        flush()
        return out
    }

    /** 1 − edit distance / longer length. */
    fun similarity(x: String, y: String): Double {
        if (x.isEmpty() && y.isEmpty()) return 1.0
        if (x.isEmpty() || y.isEmpty()) return 0.0
        var row = IntArray(y.length + 1) { it }
        for (i in 1..x.length) {
            val next = IntArray(y.length + 1)
            next[0] = i
            for (j in 1..y.length) {
                next[j] = minOf(row[j] + 1, next[j - 1] + 1, row[j - 1] + if (x[i - 1] == y[j - 1]) 0 else 1)
            }
            row = next
        }
        return 1 - row[y.length].toDouble() / maxOf(x.length, y.length)
    }

    /** Text-only verdict for when no assessment can be had. */
    fun fallback(line: PronunciationRound.Line, said: String, language: String): Verdict {
        if (overlap(said, line.text) < 0.85) return Verdict.OffScript
        val focusKeys = line.focus.map(::key).toSet()
        substitutions(said, line.text, language).firstOrNull { key(it.first) in focusKeys }?.let {
            return Verdict.NotYet(it.first, null, 0, it.second)
        }
        return Verdict.Pass(0)
    }

    /** The weakest named sound in a word, the lesson's own first. */
    fun sound(word: PronunciationResult.Word, preferring: List<String>): String? {
        val weak = word.weakPhonemes
        return weak.firstOrNull { it.phoneme in preferring }?.phoneme ?: weak.firstOrNull()?.phoneme
    }

    fun key(word: String): String = word.lowercase().filter { it.isLetterOrDigit() }

    /** Case- and accent-insensitive "contains" (Swift's
     *  `.caseInsensitive, .diacriticInsensitive`). */
    fun contains(text: String, part: String): Boolean = indexOf(text, part, 0) >= 0

    private fun fold(s: String): String =
        Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase()

    /** Index of [part] in [text] from [from], ignoring case and accents, or -1.
     *  Folding keeps the length for the scripts the course uses only when a
     *  character carries no mark; the search maps back character by character. */
    fun indexOf(text: String, part: String, from: Int): Int {
        if (part.isEmpty()) return -1
        val target = fold(part)
        for (start in from until text.length) {
            var end = start
            val sb = StringBuilder()
            while (end < text.length && sb.length < target.length) {
                sb.append(fold(text[end].toString())); end++
            }
            if (sb.toString() == target) return start
        }
        return -1
    }

    /** Length in [text] of the match of [part] found at [start] by [indexOf]. */
    fun matchLength(text: String, part: String, start: Int): Int {
        val target = fold(part)
        var end = start
        val sb = StringBuilder()
        while (end < text.length && sb.length < target.length) { sb.append(fold(text[end].toString())); end++ }
        return end - start
    }

    /** Share of the sentence's letters found in what was said. */
    fun overlap(said: String, line: String): Double {
        val a = key(line); val b = key(said)
        if (a.isEmpty()) return 0.0
        val pool = mutableMapOf<Char, Int>()
        for (c in b) pool[c] = (pool[c] ?: 0) + 1
        var hit = 0
        for (c in a) {
            val n = pool[c] ?: 0
            if (n > 0) { pool[c] = n - 1; hit++ }
        }
        // Letters alone would let an anagram pass; the length check keeps a
        // long ramble that happens to contain the letters from counting.
        val lengthRatio = minOf(a.length, b.length).toDouble() / maxOf(a.length, b.length, 1)
        return hit.toDouble() / a.length * minOf(1.0, lengthRatio + 0.3)
    }
}

// MARK: - Notes

/** What the app tells the voice after each take (`RealtimeTalkClient.nudge`).
 *  English instructions; the model speaks the target language. */
object PronunciationNotes {
    fun systemPrompt(target: String, level: CefrLevel, round: PronunciationRound?, planning: Boolean): String {
        val lang = LanguageCatalog.englishName(target)
        var now = ""
        if (round != null) {
            now = "\nToday's sound: ${round.topic.symbol} — ${round.topic.english}."
            val i = round.current
            now += when {
                i != null && round.lines[i].drillWord != null ->
                    "\nTheir screen now shows ONLY the word \"${round.lines[i].drillWord}\": they are practicing it on its own, out of the sentence \"${round.lines[i].text}\"."
                i != null -> "\nThe sentence on their screen now: \"${round.lines[i].text}\"."
                else -> "\nThe round is finished."
            }
        } else if (planning) {
            now = "\nThe sentences are being prepared; there is nothing on their screen yet."
        }
        return "You are the learner's fluent self: them, a few years on, speaking " +
            "$lang fluently, in their own voice. This call is PRONUNCIATION " +
            "PRACTICE, not a conversation. Their screen shows one $lang sentence " +
            "at a time in big letters; they read it aloud, and the APP listens and " +
            "decides how it went. You never judge a line yourself, never correct " +
            "grammar or word choice, and never ask about their life.\n\n" +
            "HOW YOU SPEAK\n" +
            "- $lang only, the simplest words (they are around CEFR " +
            "${level.code.uppercase()}), short sentences, warm and calm, " +
            "like a friend. Informal.\n" +
            "- Each of your lines answers ONE note from the app. Do exactly what " +
            "the note says and nothing more. Keep it SHORT: a few words is a " +
            "whole line here.\n" +
            "- A NOT YET note tells you what the app measured. Say it to them: " +
            "which word, what was off, and ONE thing to do with the mouth " +
            "(tongue, lips, teeth, air, voice, length). Never just \"again\", " +
            "and never a tip you already gave in this call for the same word: " +
            "take another angle. Only what the note measured; never invent a " +
            "fault it doesn't name. A sound in the note is a phonetic symbol " +
            "for YOU: never say a symbol, name it by its letters in the word " +
            "(\"the th in think\").\n" +
            "- When you say a word or a sentence for them to copy, say it clearly " +
            "at a natural pace. Never spell it, never cut it into letters or " +
            "syllables, no symbols, nothing in brackets.\n" +
            "- \"Perfect\", \"great\", \"well done\" only when the note says PASSED.\n" +
            "- If they say something that isn't the sentence (\"this is hard\", a " +
            "question), answer it in a few words and bring them back to the " +
            "sentence on their screen.\n" +
            now
    }

    fun ready(round: PronunciationRound, first: Boolean): String {
        val intro = if (first)
            "No greeting. In one short sentence say today's sound is \"${round.topic.symbol}\", as in ${round.topic.examples}."
        else "Say in a few words that the new sentences for \"${round.topic.symbol}\" are ready."
        return "$intro Then ask them to read the first sentence on their screen out loud. Don't read it for them."
    }

    fun preparing(topic: PronunciationCourse.Topic, picked: Boolean): String =
        if (picked) "They picked a new sound on their screen: \"${topic.symbol}\" (${topic.examples}). Say in a few words that you're getting the sentences ready — nothing else."
        else "Say hi in a few words and that you're getting today's sentences ready — nothing else."

    private fun only(example: String, max: Int): String =
        "Say ONLY this, in the call's language, at most $max words, nothing before or after it: \"$example\""

    // A pass is said many times a call; the reaction rotates, never the same
    // twice in a row, and fits HOW it passed (iOS, 2026-11-04).
    @Volatile private var lastReaction: String? = null

    private fun reaction(pool: List<String>): String {
        val pick = pool.filter { it != lastReaction }.randomOrNull() ?: pool[0]
        lastReaction = pick
        return pick
    }

    fun passed(score: Int, next: PronunciationRound.Line?, round: PronunciationRound, afterMisses: Boolean = false): String {
        if (next != null) {
            val pool = when {
                afterMisses -> listOf("There it is! Next one.", "You got it! Next.", "That's the one! Next.",
                    "Yes, much better! Next one.", "Nailed it this time. Next.")
                score >= 90 -> listOf("Perfect! Next one.", "Spot on. Next.", "Beautiful! Next one.",
                    "First try, perfect! Next.", "Wow, clean! Next one.")
                else -> listOf("Yes! Next one.", "Good! Next.", "Nice, that works. Next.",
                    "Well done! Next one.", "Great. On to the next.")
            }
            return "Result: PASSED. " + only(reaction(pool), 6)
        }
        return "Result: PASSED — the last sentence of the round (${round.passedCount} of ${round.sentenceCount} passed). In one or two short sentences: the round is done; another round of this sound, or a different one with the button on their screen?"
    }

    // A miss is never a bare "again" (iOS, founder 2026-11-10): every one
    // says what the app measured and one thing to do about it, still short,
    // and never the same tip twice.

    /** What the app measured on [word], for the voice to say. */
    fun measured(word: String, sound: String?, heard: String?, heardAs: PronunciationJudge.HeardAs?,
                 score: Int?, topic: PronunciationCourse.Topic): String {
        val points = score?.let { " ($it of 100)" } ?: ""
        var what = when {
            heard != null -> "\"$word\" came out as the word \"$heard\""
            sound != null && heardAs is PronunciationJudge.HeardAs.Sound ->
                "the \"$sound\" sound in \"$word\" came out like \"${heardAs.phoneme}\"$points"
            sound != null && heardAs == PronunciationJudge.HeardAs.VowelAdded ->
                "a little extra vowel slipped in at the \"$sound\" sound in \"$word\"$points — it should be one tight sound"
            sound != null -> "the \"$sound\" sound in \"$word\" wasn't clear$points"
            else -> return "What the app measured: \"$word\" as a whole wasn't clear$points. It can't tell which sound, so don't name one: the tip is about the whole word (its beat, its length, opening the mouth, not swallowing the end)."
        }
        if (sound != null && PronunciationJudge.isLesson(sound, topic.phonemes)) {
            what += ". That is today's sound: ${topic.english}"
        }
        return "What the app measured: $what."
    }

    /** The sentence missed on [word]: the screen now shows that word alone. */
    fun notYet(word: String, sound: String?, heard: String?, topic: PronunciationCourse.Topic,
               sentence: String, heardAs: PronunciationJudge.HeardAs? = null, score: Int? = null): String =
        "Result: NOT YET. Their screen now shows only \"$word\". " +
            measured(word, sound, heard, heardAs, score, topic) +
            " In at most 28 words: say what was off, give ONE tip for the mouth that fixes exactly that, then say \"$word\" twice, clearly, and ask for just that." +
            AS_IN_SENTENCE

    /** The word on its own missed again. [tries]: misses on this word so
     *  far, this one included; [previous]: the last take's score for it. */
    fun wordAgain(word: String, sound: String?, topic: PronunciationCourse.Topic,
                  heardAs: PronunciationJudge.HeardAs? = null, score: Int? = null,
                  previous: Int? = null, tries: Int = 1): String {
        var note = "Result: NOT YET, try $tries on \"$word\" alone. " +
            measured(word, sound, null, heardAs, score, topic)
        if (score != null && previous != null) {
            if (score >= previous + 8) note += " It is closer than their last try ($previous → $score): say so, as a fact."
            else if (score <= previous - 8) note += " The last try was nearer ($previous → $score): the new tip should be simpler."
        }
        note += " In at most 24 words: say what is still off, give ONE tip you have NOT given for this word yet (another angle: where the tongue is, the lips, the air, the voice, how long it is, or an easy word with the same sound), then say \"$word\" once, clearly, and ask again."
        if (tries == 3) {
            note += " Then add, in a few words, that it's fine to leave it for now with the button under the word and come back to it. Up to 34 words this time."
        }
        return note + AS_IN_SENTENCE
    }

    /** Said alone, a word can lose the sound it has in the sentence. */
    const val AS_IN_SENTENCE = " Say it exactly the way it sounds inside the sentence on their screen (a reduced \"the\" stays \"thuh\" before a consonant), never a careful dictionary form."

    /** The word is right alone and slipped in the sentence again: now it is
     *  practiced joined to its neighbours. */
    fun inFlow(chunk: String, word: String, topic: PronunciationCourse.Topic, sound: String? = null,
               heardAs: PronunciationJudge.HeardAs? = null, score: Int? = null): String =
        "Result: NOT YET. \"$word\" was right on its own and slipped again inside the sentence. " +
            measured(word, sound, null, heardAs, score, topic) +
            " Their screen now shows \"$chunk\". In at most 26 words: say the word alone is good and what happens to it next to the other words, ONE tip for joining them (don't rush into it, keep the sound when the next word starts), then say \"$chunk\" twice, as one piece." +
            AS_IN_SENTENCE

    fun wordPassed(word: String): String =
        "Result: PASSED. " + only(reaction(listOf("Yes! Now the whole sentence.",
            "That's it! Now the sentence.", "Good! Back to the whole sentence.",
            "There it is. Now all of it.", "Nice! Now read the sentence.")), 7)

    fun wordBack(word: String, sound: String?, topic: PronunciationCourse.Topic): String {
        val which = sound?.let { " (its \"$it\" sound)" } ?: ""
        return "They chose to go back to the sentence. \"$word\"$which isn't there yet — that's fine. Give ONE short tip on how to make it (today's sound: ${topic.english}), at most 10 words, say \"$word\" once, clearly, then: now the whole sentence. At most 25 words in all."
    }

    fun wordOffScript(word: String): String = only("Just the word: $word.", 5)

    /** Every sound was there and the reading broke. [pauseBefore]: the word
     *  the longest stop came in front of; [tries]: misses on this sentence
     *  so far, this one included. */
    fun notSmooth(sentence: String, pauseBefore: String? = null, tries: Int = 1): String {
        val where = pauseBefore?.let { " The longest stop was right before \"$it\": say so." }
            ?: " The app can't tell where it stopped, so don't name a place."
        val tip = if (tries <= 1) "ONE tip: slower is fine, but in one breath, the words joined"
            else "ONE tip you have NOT given for this sentence yet (breathe before starting; say it in two halves first, then all of it; lean on the main words and let the small ones run; look at the next word while saying this one)"
        return "Result: NOT YET, try $tries. Every sound was right; the reading stopped and started.$where In at most 24 words: say the sounds were good and what broke it, $tip, then ask for the whole sentence once more. Don't read the sentence for them."
    }

    /** The learner skipping a sentence: what wasn't there, one tip, the word
     *  said right, and WHEN it comes back. */
    fun moveOn(word: String?, sound: String?, topic: PronunciationCourse.Topic, next: PronunciationRound.Line?,
               round: PronunciationRound, laterInRound: Boolean): String {
        val what = if (word != null) {
            val which = sound?.let { " — its \"$it\" sound" } ?: ""
            "Say which word isn't there yet: \"$word\"$which. Give ONE short tip on how to make it (today's sound: ${topic.english}), at most 10 words, and say \"$word\" once, clearly."
        } else "Say every sound was right, but the reading kept stopping: slowly is fine, just no stops."
        val whenBack = if (laterInRound) "it comes back at the end of this round" else "it'll be in the next round"
        val after = if (next == null)
            "Then: the round is done — another round of this sound, or a different one with the button on their screen?"
        else "Then: the next sentence is on their screen."
        return "They chose to move on to the next sentence. Explain, then move on — never just \"tricky one\". $what Say $whenBack. $after At most 40 words in all."
    }

    fun offScript(said: String): String =
        "They didn't read it (they said: \"$said\"). Answer in at most one short sentence, then ask them to read what's on their screen."

    val UNHEARD: String get() = only("Sorry, once more?", 4)

    const val PLAN_FAILED = "Getting the sentences didn't work. Say sorry in a few words and ask them to pick a sound with the button on their screen."
    const val UNCLEAR_NEXT = "Ask them, in one short question: another round of this sound, or a different sound? (The button on their screen has the sounds.)"
    const val GOODBYE = "They're done for today. Say a warm, short goodbye and that they can hang up whenever they like."
    const val SPOKE_WHILE_PLANNING = "They spoke while the sentences are still being prepared. Say \"one moment\" in a few words."
}

/** A take sent to Azure the moment the app sent the turn, before the
 *  gateway's `user_turn` came back (iOS `PronEarlyRead`). */
class PronEarlyRead(
    val roundId: String,
    val index: Int,
    /** What it was judged against: the word drilled, or the sentence. */
    val reference: String,
    /** Length of the trimmed take that was read. */
    val ms: Int,
    val task: kotlinx.coroutines.Deferred<PronunciationAssessor.Answer>,
) {
    /** The turn that came back is this take: same line, and the audio is
     *  the same length within a breath. More audio means they kept talking
     *  after the send, and the take is read again whole. */
    fun matches(roundId: String, index: Int, reference: String, turnMs: Int): Boolean =
        roundId == this.roundId && index == this.index && reference == this.reference &&
            kotlin.math.abs(turnMs - ms) <= TOLERANCE

    companion object { const val TOLERANCE = 300 }
}
