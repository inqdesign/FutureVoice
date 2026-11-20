package com.roro.futurevoice.data

/**
 * Simplified Chinese words for vocab tracking against the graded wordlist
 * (`cefr_words_zh.tsv`, HSK 3.0 headwords: 吃饭, 觉得, 一点儿 …) — port of
 * `ChineseMorph.swift` (iOS 0197dcbc, 2026-11-13).
 *
 * Chinese has no spaces and no inflection, so the job is only segmentation:
 * a word IS its dictionary form, and the analyzer never has to guess a stem
 * the way [JapaneseMorph] and [KoreanMorph] do.
 *
 * **Where the cuts come from.** iOS cuts with `CFStringTokenizer` (zh-Hans),
 * which hands back pinyin too. Here it is ICU: `BreakIterator`'s word
 * instance for the cuts, `Han-Latin` for the pinyin. ICU's dictionary glues
 * a word to the pronoun or particle beside it more often than Apple's does
 * (他是, 我的, 三年, 我想, 跑得 — measured on the emulator, 2026-11-13), so a
 * cut that is no headword is split again when every piece of it is a
 * headword, a particle or a pronoun ([resplit]), and a pronoun ICU cut in two
 * (怎么 | 样) is joined again ([rejoinPronouns]). That brings the cuts back to
 * what iOS sees — on 70 Chinese lines from the app, 517 of iOS's 571 words
 * came out the same against raw ICU's 437; a cut that can't be split that way
 * (小明, a name) stays whole, which costs recall, never correctness.
 *
 * Script: the app teaches Simplified, but a transcriber or a learner may
 * write Traditional (說 for 说). The text is folded to Simplified first
 * ([simplified], ICU's Hant-Hans, one UTF-16 unit per character) and the
 * offsets are mapped back onto the original — the screen keeps what was
 * written, the lookups see Simplified.
 *
 * Same contract as the other analyzers: only the lexicon confirms a word.
 */
object ChineseMorph {

    /** One word: [surface] as written, [key] its Simplified spelling (what
     *  the lexicon is keyed by), [pinyin] with tone marks, no spaces. */
    data class Token(val surface: String, val key: String, val start: Int, val end: Int, val pinyin: String)

    /**
     * What the platform does: fold the script, cut words, read pinyin, spell
     * a number. ICU in the app. A JVM unit test has no `android.icu` (the
     * stub throws), so it installs its own tables here — never set in the app.
     */
    internal interface Platform {
        fun simplified(text: String): String
        /** Word boundaries of [text] (already Simplified), as [start, end) pairs. */
        fun cuts(text: String): List<Pair<Int, Int>>
        fun pinyin(word: String): String
        fun spellOut(n: Int): String?
    }

    @Volatile internal var platform: Platform = Icu

    private object Icu : Platform {
        private val hans by lazy {
            runCatching { android.icu.text.Transliterator.getInstance("Hant-Hans") }.getOrNull()
        }
        private val latin by lazy {
            runCatching { android.icu.text.Transliterator.getInstance("Han-Latin") }.getOrNull()
        }

        override fun simplified(text: String): String {
            val t = hans ?: return text
            return synchronized(t) { runCatching { t.transliterate(text) }.getOrDefault(text) }
        }

        override fun cuts(text: String): List<Pair<Int, Int>> {
            val it = android.icu.text.BreakIterator.getWordInstance(java.util.Locale.SIMPLIFIED_CHINESE)
            it.setText(text)
            val out = ArrayList<Pair<Int, Int>>()
            var start = it.first()
            var end = it.next()
            while (end != android.icu.text.BreakIterator.DONE) {
                out.add(start to end)
                start = end
                end = it.next()
            }
            return out
        }

        override fun pinyin(word: String): String {
            val t = latin ?: return word
            return synchronized(t) { runCatching { t.transliterate(word) }.getOrDefault(word) }
        }

        // ICU's spell-out rules (RuleBasedNumberFormat, which the SDK doesn't
        // expose) reached through MessageFormat's `spellout` argument type.
        override fun spellOut(n: Int): String? = runCatching {
            android.icu.text.MessageFormat("{0,spellout}", android.icu.util.ULocale("zh_Hans"))
                .format(arrayOf<Any>(n))
        }.getOrNull()?.takeIf { it.isNotEmpty() }
    }

    // ── Script ──

    /** [text] in Simplified characters. Han characters only change; the
     *  conversion is one UTF-16 unit for one, which is what lets an offset
     *  found in the folded text land on the same characters of the original. */
    fun simplified(text: String): String {
        if (text.none(::isHan)) return text
        return platform.simplified(text)
    }

    /** [n] spelled in Chinese (3 → 三, 2026 → 二千〇二十六), what a shadow
     *  diff compares a digit as (iOS `written`, NumberFormatter zh-Hans). */
    fun spellOut(n: Int): String? = platform.spellOut(n)

    // ── Segmentation ──

    /** Words in [text], in order, punctuation and whitespace skipped. */
    fun words(text: String): List<Token> {
        if (text.isEmpty()) return emptyList()
        val folded = simplified(text)
        // A conversion that changed the length can't share offsets; read the
        // original as written then.
        val source = if (folded.length == text.length) folded else text
        val lexicon = CoreVocabulary.set("zh")
        val forms = CoreVocabulary.forms("zh")
        val spans = ArrayList<Pair<Int, Int>>()
        for ((start, end) in platform.cuts(source)) {
            if (text.substring(start, end).none { it.isLetterOrDigit() }) continue
            spans += resplit(source, start, end, lexicon, forms)
        }
        val out = ArrayList<Token>()
        for ((s, e) in rejoinPronouns(source, spans)) {
            val key = source.substring(s, e)
            out.add(Token(text.substring(s, e), key, s, e, pinyinOf(key)))
        }
        return out
    }

    /** The other way round: ICU cuts a question word iOS keeps whole
     *  (怎么 | 样 for 怎么样), and 样 alone would light up as a word inside
     *  it. Adjacent cuts that together spell a pronoun are one word again. */
    private fun rejoinPronouns(source: String, spans: List<Pair<Int, Int>>): List<Pair<Int, Int>> {
        val out = ArrayList<Pair<Int, Int>>()
        var i = 0
        while (i < spans.size) {
            var width = 1
            for (w in minOf(3, spans.size - i) downTo 2) {
                val slice = spans.subList(i, i + w)
                if (slice.zipWithNext().any { (a, b) -> a.second != b.first }) continue
                if (source.substring(slice.first().first, slice.last().second) in pronouns) { width = w; break }
            }
            out += spans[i].first to spans[i + width - 1].second
            i += width
        }
        return out
    }

    /**
     * A cut that is no headword, split into pieces that each are one — or a
     * particle or a pronoun, which the list leaves out on purpose. ICU cuts
     * 他是, 我的, 三年, 很快 as one word where iOS cuts two; this gives the
     * two back. The fewest pieces win; a cut with any piece left over (小明)
     * stays whole.
     */
    private fun resplit(source: String, start: Int, end: Int,
                        lexicon: Set<String>, forms: Map<String, String>): List<Pair<Int, Int>> {
        val whole = listOf(start to end)
        val len = end - start
        if (len < 2 || lexicon.isEmpty()) return whole
        val word = source.substring(start, end)
        if (headword(word, lexicon, forms) != null || word.any { !isHan(it) } ||
            word in wholeGreetings || word in pronouns) return whole
        fun known(piece: String) = piece in lexicon || forms[piece]?.let { it in lexicon } == true ||
            piece in functionTokens || piece in pronouns
        // best[i] = fewest pieces covering word[0, i), with the cut before i.
        val best = IntArray(len + 1) { Int.MAX_VALUE }
        val from = IntArray(len + 1) { -1 }
        best[0] = 0
        for (i in 1..len) {
            for (j in maxOf(0, i - MAX_PIECE) until i) {
                if (best[j] == Int.MAX_VALUE || !known(word.substring(j, i))) continue
                if (best[j] + 1 < best[i]) { best[i] = best[j] + 1; from[i] = j }
            }
        }
        if (best[len] == Int.MAX_VALUE || best[len] < 2) return whole
        val out = ArrayList<Pair<Int, Int>>()
        var i = len
        while (i > 0) { val j = from[i]; out.add(start + j to start + i); i = j }
        return out.reversed()
    }

    private const val MAX_PIECE = 4

    /** Greetings iOS keeps as one word that would otherwise split on their
     *  pronoun (你 + 好): the list has neither, and 好 lit inside 你好 is
     *  not a word anyone said. */
    private val wholeGreetings = setOf("你好", "您好", "你们好", "大家好")

    /** Pronouns and question words: the list leaves them out on purpose. A
     *  cut glued to one (他是) is two words on iOS; a cut that IS one (这个,
     *  怎么样) is one word on iOS and stays whole. */
    private val pronouns = setOf(
        "我", "你", "他", "她", "它", "您", "咱", "我们", "你们", "他们", "她们", "它们", "咱们",
        "大家", "自己", "别人",
        "这", "那", "哪", "谁", "这个", "那个", "哪个", "这些", "那些", "哪些",
        "这里", "那里", "哪里", "这儿", "那儿", "哪儿", "这样", "那样",
        "什么", "怎么", "怎么样", "为什么", "多少",
    )

    /** Surface words only — the drop-in for splitting on spaces. */
    fun segments(text: String): List<String> = words(text).map { it.surface }

    /** The whole text as words and the gaps between them (，。「」 …), so a
     *  view can style words and still draw the punctuation around them. */
    fun displayPieces(text: String): List<JapaneseMorph.Piece> {
        val out = ArrayList<JapaneseMorph.Piece>()
        var cursor = 0
        for (t in words(text)) {
            if (t.start > cursor) out.add(JapaneseMorph.Piece(text.substring(cursor, t.start), false))
            out.add(JapaneseMorph.Piece(t.surface, true))
            cursor = t.end
        }
        if (cursor < text.length) out.add(JapaneseMorph.Piece(text.substring(cursor), false))
        return out
    }

    // ── Headwords ──

    /**
     * Every headword spoken in [text], with the span it was said over.
     *
     * Adjacent tokens are tried joined first (up to three, longest first),
     * because a segmenter cuts some listed words in two (打 | 电话 for
     * 打电话). A join never reaches into a particle — 了 + 解 is not 了解
     * unless the segmenter itself kept it together.
     */
    fun headwords(text: String, lexicon: Set<String>,
                  forms: Map<String, String> = CoreVocabulary.forms("zh")): List<Triple<String, Int, Int>> {
        val tokens = words(text)
        val out = ArrayList<Triple<String, Int, Int>>()
        var i = 0
        while (i < tokens.size) {
            val joined = compound(i, tokens, lexicon, forms)
            if (joined != null) {
                val (head, width) = joined
                out.add(Triple(head, tokens[i].start, tokens[i + width - 1].end))
                i += width
                continue
            }
            headword(tokens[i].key, lexicon, forms)?.let { out.add(Triple(it, tokens[i].start, tokens[i].end)) }
            i += 1
        }
        return out
    }

    /** The notebook key for every piece of [displayPieces], in the same
     *  order — "" for punctuation and for a word the pool doesn't know. */
    fun pieceKeys(text: String, lexicon: Set<String>,
                  forms: Map<String, String> = CoreVocabulary.forms("zh")): List<String> {
        val tokens = words(text)
        val keyByToken = MutableList(tokens.size) { "" }
        var i = 0
        while (i < tokens.size) {
            val joined = compound(i, tokens, lexicon, forms)
            if (joined != null) {
                val (head, width) = joined
                for (k in i until i + width) keyByToken[k] = head
                i += width
                continue
            }
            keyByToken[i] = headword(tokens[i].key, lexicon, forms) ?: ""
            i += 1
        }
        val out = ArrayList<String>()
        var next = 0
        for (piece in displayPieces(text)) {
            if (piece.isWord) out.add(keyByToken.getOrElse(next) { "" }.also { next += 1 })
            else out.add("")
        }
        return out
    }

    /** The headword a single word is, if the list carries it. */
    fun headword(word: String, lexicon: Set<String>,
                 forms: Map<String, String> = CoreVocabulary.forms("zh")): String? {
        val key = simplified(word)
        if (key in lexicon) return key
        forms[key]?.takeIf { it in lexicon }?.let { return it }
        return null
    }

    private fun compound(i: Int, tokens: List<Token>, lexicon: Set<String>,
                         forms: Map<String, String>): Pair<String, Int>? {
        if (tokens.size - i < 2) return null
        for (width in minOf(3, tokens.size - i) downTo 2) {
            val slice = tokens.subList(i, i + width)
            if (slice.any { isFunctionToken(it.key) }) continue
            val joined = slice.joinToString("") { it.key }
            if (joined in lexicon) return joined to width
            forms[joined]?.takeIf { it in lexicon }?.let { return it to width }
        }
        return null
    }

    // ── Function words ──

    /** Particles and fillers — grammar or hesitation, never a word to study
     *  or credit (的 了 吗 …, 嗯 啊 when it's a filler). */
    private val functionTokens = setOf(
        "的", "了", "着", "过", "地", "得", "吗", "吧", "呢", "啊", "呀", "嘛",
        "哦", "嗯", "哈", "啦", "喔", "噢", "诶", "欸", "呃", "额", "哎",
    )

    fun isFunctionToken(s: String): Boolean = simplified(s) in functionTokens

    // ── Sound ──

    /**
     * What the line SOUNDS like: pinyin with tones, joined, lowercased.
     * Whatever script the transcriber wrote (說 / 说), however it cut the
     * words, and whichever of two homophones it picked (在 / 再, both zài),
     * the same sentence reads the same — none of those is the learner's.
     * Tones are KEPT: 买 mǎi and 卖 mài are different words a mouth makes.
     */
    fun reading(text: String): String = words(text).joinToString("") { it.pinyin }.lowercase()

    /**
     * How a headword is read, for display beside it — the HSK list's pinyin
     * (both readings for a word that has two: 还 hái・huán), ICU's for a word
     * off the list.
     */
    fun readingOfHeadword(word: String): String? {
        val key = simplified(word)
        if (key.none(::isHan)) return null
        CoreVocabulary.listedReading(key, "zh")?.let { return it }
        val guess = words(key).joinToString("") { it.pinyin }
        return guess.takeIf { it.isNotEmpty() && it != key }
    }

    /**
     * A word's pinyin as iOS's tokenizer writes it: syllables run together
     * (wǒmen, not "wǒ men"). ICU reads a character the same everywhere, and
     * 得 comes out dé where Apple, reading it in context, says the neutral de
     * of 跑得 — so the three structural particles read de, as on iOS, or
     * 跑的 / 跑得 would read as two different things a mouth said.
     */
    private fun pinyinOf(key: String): String {
        if (key in neutralDe) return "de"
        if (key.none(::isHan)) return key
        return platform.pinyin(key).filterNot { it.isWhitespace() }
    }

    private val neutralDe = setOf("的", "得", "地")

    /** One character read on its own, for `ChinesePinyin`'s syllable cut. */
    fun pinyinOfCharacter(s: String): String = platform.pinyin(s).filterNot { it.isWhitespace() }

    private fun isHan(c: Char): Boolean = c.code in 0x4E00..0x9FFF || c.code in 0x3400..0x4DBF
}
