package com.roro.futurevoice.data

/**
 * Where Japanese words begin, and what dictionary word each one is — port of
 * `JapaneseMorph.swift`, vector-tested against the real Swift
 * (`docs/contracts/vectors`, section `japanese`).
 *
 * **One platform difference, and it is honest rather than hidden.** iOS
 * segments with `CFStringTokenizer`, which also hands back a READING for each
 * token, so a kana spelling can meet a kanji headword through the tokenizer
 * itself. Android's `BreakIterator` gives boundaries and nothing else, so a
 * token here carries no reading: the forms table (`ja_forms.tsv`, which maps
 * わかる → 分かる) does that work instead, and a kanji spelling the table does
 * not carry simply isn't resolved. It costs recall, never correctness.
 */
object JapaneseMorph {

    /** One segmented word and where it sat in the text. */
    data class Token(val surface: String, val start: Int, val end: Int)

    /** A run of the original text: a word, or what sat between two words.
     *  Concatenating every piece gives the text back. */
    data class Piece(val text: String, val isWord: Boolean)

    // ── Segmentation ──

    /** Words in [text], in order, punctuation and whitespace skipped. */
    fun words(text: String): List<Token> {
        if (text.isEmpty()) return emptyList()
        val it = android.icu.text.BreakIterator.getWordInstance(java.util.Locale.JAPANESE)
        it.setText(text)
        val out = ArrayList<Token>()
        var start = it.first()
        var end = it.next()
        while (end != android.icu.text.BreakIterator.DONE) {
            val surface = text.substring(start, end)
            // Digits are words too (3時 is 3 + 時): only a token with no
            // letter or digit at all is punctuation.
            if (surface.any { it.isLetterOrDigit() }) out.add(Token(surface, start, end))
            start = end
            end = it.next()
        }
        return out
    }

    /** Surface words only — the drop-in for splitting on spaces. */
    fun segments(text: String): List<String> = words(text).map { it.surface }

    /** The whole text as words and the gaps between them, for a view that
     *  styles words and must still draw the 、。「」 around them. */
    fun displayPieces(text: String): List<Piece> {
        val out = ArrayList<Piece>()
        var cursor = 0
        for (t in words(text)) {
            if (t.start > cursor) out.add(Piece(text.substring(cursor, t.start), false))
            out.add(Piece(t.surface, true))
            cursor = t.end
        }
        if (cursor < text.length) out.add(Piece(text.substring(cursor), false))
        return out
    }

    // ── Headwords ──

    /** Every headword spoken in [text], with the span it was said over.
     *
     *  Adjacent tokens are tried joined first (up to three, EXACT headword
     *  only), because the tokenizer cuts some listed compounds in two
     *  (面倒|くさい, お|疲れ|様). The join never reaches into a function
     *  token — し + た would otherwise spell した and read back as 下. */
    fun headwords(text: String, lexicon: Set<String>, forms: Map<String, String>):
        List<Triple<String, Int, Int>> = headwords(words(text), lexicon, forms)

    /** The same over tokens already segmented — what a JVM test can reach,
     *  since the segmenter itself is the platform's. */
    fun headwords(tokens: List<Token>, lexicon: Set<String>, forms: Map<String, String>):
        List<Triple<String, Int, Int>> {
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
            val token = tokens[i]
            val inflected = i + 1 < tokens.size && tokens[i + 1].surface in INFLECTIONS
            dictionaryForm(token.surface, inflected, lexicon, forms)?.let {
                out.add(Triple(it, token.start, token.end))
            }
            i += 1
        }
        return out
    }

    /** The notebook key for every piece of [displayPieces], in the same
     *  order — "" for punctuation and for a word the pool doesn't know. A
     *  compound headword puts its key on each token it spans, so the whole
     *  word lights up and any of it can be tapped. */
    fun pieceKeys(text: String, lexicon: Set<String>, forms: Map<String, String>): List<String> {
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
            val inflected = i + 1 < tokens.size && tokens[i + 1].surface in INFLECTIONS
            keyByToken[i] = dictionaryForm(tokens[i].surface, inflected, lexicon, forms) ?: ""
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

    private fun compound(i: Int, tokens: List<Token>, lexicon: Set<String>,
                         forms: Map<String, String>): Pair<String, Int>? {
        if (tokens.size - i < 2) return null
        for (width in minOf(3, tokens.size - i) downTo 2) {
            val slice = tokens.subList(i, i + width)
            if (slice.any { isFunctionToken(it.surface) }) continue
            val joined = slice.joinToString("") { it.surface }
            if (joined in lexicon) return joined to width
            forms[joined]?.takeIf { it in lexicon }?.let { return it to width }
        }
        return null
    }

    /**
     * The headword one token stands for, or null.
     *
     * [inflected] — the next token is inflection (ます, たい, て …), so this
     * token is a verb or adjective stem. That flips the order: 行き before
     * ました is 行く, not the noun 行き.
     */
    fun dictionaryForm(surface: String, inflected: Boolean = false,
                       lexicon: Set<String>, forms: Map<String, String>): String? {
        if (isFunctionToken(surface)) return null
        fun resolve(c: String): String? {
            val head = if (c in lexicon) c else forms[c]?.takeIf { it in lexicon }
            return head?.takeIf { !isFunctionToken(it) }
        }
        val all = candidates(surface, inflected)
        val ordered = if (inflected && all.isNotEmpty()) all.drop(1) + all.first() else all
        for (c in ordered) resolve(c)?.let { return it }
        return null
    }

    /**
     * Ordered dictionary-form candidates for one token, most likely first.
     * The token itself leads — nouns, adverbs and a dictionary-form verb are
     * their own surface.
     *
     * A surface written entirely in kanji is a noun unless [inflected] says
     * otherwise — 語 must not become 語る, 日本 must not become 日本る. The
     * handful of one-kanji ichidan verbs (見, 出, 寝 …) are listed, because
     * 見に行く puts a particle, not inflection, after the stem.
     */
    fun candidates(raw: String, inflected: Boolean = true): List<String> {
        val token = raw.trim()
        if (token.isEmpty() || !token.all { isJapanese(it) }) return emptyList()
        val bases = mutableListOf(token)
        // A chunk the tokenizer left whole (食べました) — strip inflection
        // down to the stem the rules below expect.
        strippingSuffix(token)?.let { bases.add(it) }

        val out = ArrayList<String>()
        for (base in bases) {
            out.add(base)
            // Irregulars first, where a single kana would otherwise guess wild.
            IRREGULARS[base]?.let { out.addAll(it) }
            ONE_KANJI_ICHIDAN[base]?.let { out.add(it) }
            if (!inflected && base.none { isKana(it) }) continue
            // A lone kana stem is almost always inflection; only the
            // irregulars above may speak for it.
            if (base.length < 2 && isKana(base[0])) continue
            val last = base.last().toString()
            val head = base.dropLast(1)

            // i-adjective: 多く / 高かっ / 高けれ → 多い / 高い.
            if (base.endsWith("かっ") || base.endsWith("けれ")) out.add(base.dropLast(2) + "い")
            if (last == "く" && head.isNotEmpty()) out.add(head + "い")

            // Ichidan: the stem IS the dictionary form minus る (疲れ, 見, 食べ).
            out.add(base + "る")

            // Godan: the stem's last kana moves to the u-row (行き → 行く).
            // Onbin stems (行っ, 読ん, 書い) have several possible sources;
            // the lexicon picks.
            if (head.isNotEmpty()) GODAN_ENDINGS[last]?.forEach { out.add(head + it) }

            // Suru-noun: 勉強し / 勉強さ / 勉強せ → 勉強 (the list carries the noun).
            if (last in setOf("し", "さ", "せ") && head.isNotEmpty()) {
                out.add(head)
                out.add(head + "する")
            }
        }
        val seen = LinkedHashSet<String>()
        for (c in out) if (c.isNotEmpty()) seen.add(c)
        return seen.toList()
    }

    // ── Tables ──

    /** 行っ reads 行く, never 行う — the one onbin collision common enough to
     *  matter, and the only godan verb whose te-form is irregular. */
    private val IRREGULARS = mapOf(
        "し" to listOf("する"), "さ" to listOf("する"), "せ" to listOf("する"),
        "き" to listOf("来る", "くる"), "こ" to listOf("来る", "くる"), "来" to listOf("来る"),
        "行っ" to listOf("行く"), "いっ" to listOf("行く", "いく"),
    )

    private val ONE_KANJI_ICHIDAN = mapOf(
        "見" to "見る", "出" to "出る", "寝" to "寝る", "着" to "着る",
        "居" to "居る", "似" to "似る",
    )

    /** Tokens that mark the one before them as a stem. */
    private val INFLECTIONS = setOf(
        "ます", "まし", "ませ", "たい", "たく", "たかっ", "て", "た", "で", "だ",
        "ない", "なかっ", "なく", "なけれ", "なきゃ", "れる", "られ", "られる",
        "せる", "させ", "させる", "ちゃ", "じゃ", "ば", "う", "よう", "ろ",
    )

    private val GODAN_ENDINGS = mapOf(
        // i-row (masu stem)
        "い" to listOf("う", "く", "ぐ"), "き" to listOf("く"), "ぎ" to listOf("ぐ"),
        "し" to listOf("す"), "ち" to listOf("つ"), "に" to listOf("ぬ"),
        "び" to listOf("ぶ"), "み" to listOf("む"), "り" to listOf("る"),
        // a-row (negative, passive, causative)
        "わ" to listOf("う"), "か" to listOf("く"), "が" to listOf("ぐ"),
        "さ" to listOf("す"), "た" to listOf("つ"), "な" to listOf("ぬ"),
        "ば" to listOf("ぶ"), "ま" to listOf("む"), "ら" to listOf("る"),
        // e-row (potential, conditional, imperative)
        "え" to listOf("う"), "け" to listOf("く"), "げ" to listOf("ぐ"),
        "せ" to listOf("す"), "て" to listOf("つ"), "ね" to listOf("ぬ"),
        "べ" to listOf("ぶ"), "め" to listOf("む"), "れ" to listOf("る"),
        // o-row (volitional)
        "お" to listOf("う"), "こ" to listOf("く"), "ご" to listOf("ぐ"),
        "そ" to listOf("す"), "と" to listOf("つ"), "の" to listOf("ぬ"),
        "ぼ" to listOf("ぶ"), "も" to listOf("む"), "ろ" to listOf("る"),
        // onbin (te/ta stems) — い also covers 書い → 書く / 泳い → 泳ぐ
        "っ" to listOf("う", "つ", "る"), "ん" to listOf("む", "ぶ", "ぬ"),
    )

    /** Inflection a tokenizer may leave attached, longest first. */
    private val SUFFIXES = listOf(
        "ませんでした", "なかった", "ました", "ません", "ている", "ていた",
        "でした", "たかった", "られる", "させる",
        "ます", "ない", "たい", "です",
        "て", "た", "で", "だ", "う",
    ).sortedByDescending { it.length }

    /** Particles, auxiliaries and copulas: tokens that are grammar, never a
     *  word to track. Without this ない reads back as 無い and まし as 増し. */
    private val FUNCTION_TOKENS = setOf(
        "は", "が", "を", "に", "へ", "と", "も", "や", "か", "ね", "よ", "な",
        "の", "ん", "で", "て", "た", "だ", "う", "ぞ", "さ", "わ",
        "から", "まで", "より", "けど", "けれど", "って", "ので", "のに", "でも",
        "ます", "まし", "ませ", "です", "でし", "だっ", "でしょ", "だろ",
        "ない", "なかっ", "なく", "なけれ", "なきゃ", "ば", "たい", "たく", "たかっ",
        "れる", "られ", "られる", "せる", "させ", "させる", "ちゃ", "じゃ",
        "いる", "い", "ある", "あっ", "おり", "ござい",
        // Spoken contractions and the passive/potential れ on its own —
        // 追わ|れ|てる. てる is what ている sounds like; it is not 照る.
        "れ", "てる", "てた", "てて", "てれ", "とく", "とい", "とる",
        "ちゃう", "ちゃっ", "ちゃい", "じゃう", "じゃっ",
        "たり", "ながら", "ず", "ぬ", "まい", "じゃん", "かな", "かしら", "っけ",
    )

    fun isFunctionToken(s: String): Boolean = s in FUNCTION_TOKENS

    private fun strippingSuffix(word: String): String? {
        for (s in SUFFIXES) if (word.length > s.length && word.endsWith(s)) {
            return word.dropLast(s.length)
        }
        return null
    }

    // ── Script helpers ──

    /**
     * One spelling per SOUND, for comparing what was said — never shown.
     *
     * A Latin-spelled word inside Japanese (the app's own name, "nawana")
     * comes back from a ja transcriber as ナワナ and sits in the target as
     * nawana: the same three morae in two scripts, and a letter-by-letter
     * comparison scored every one of them as a word the learner never said.
     * Latin runs and katakana both land on hiragana; kanji passes through —
     * its reading depends on the words around it. ー is kept: it is the long
     * vowel in either kana.
     */
    fun soundSpelling(text: String): String {
        val folded = mapLatinRuns(normalizeWidth(text).lowercase()) { hiraganaFromLatin(it) }
        val out = StringBuilder(folded.length)
        for (ch in folded) {
            val c = ch.code
            if (c in 0x30A1..0x30F6) out.append((c - 0x60).toChar()) else out.append(ch)
        }
        return out.toString()
    }

    /** Latin letters as hiragana — ICU's own transliteration, the same table
     *  Foundation uses on the other side. */
    fun hiraganaFromLatin(latin: String): String = runCatching {
        android.icu.text.Transliterator.getInstance("Latin-Hiragana").transliterate(latin)
    }.getOrDefault(latin)

    /** [text] with every run of Latin letters written in katakana
     *  (nawana → ナワナ) — what a shadow diff DISPLAYS for a romaji name. */
    fun katakanaFromLatinIn(text: String): String = mapLatinRuns(text) { run ->
        runCatching {
            android.icu.text.Transliterator.getInstance("Latin-Katakana").transliterate(run)
        }.getOrDefault(run)
    }

    private fun normalizeWidth(text: String): String =
        java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFKC)

    /** Applies [transform] to each maximal run of ASCII letters in [text]. */
    private fun mapLatinRuns(text: String, transform: (String) -> String): String {
        val out = StringBuilder()
        val run = StringBuilder()
        for (ch in text) {
            if (ch.code < 128 && ch.isLetter()) { run.append(ch); continue }
            if (run.isNotEmpty()) { out.append(transform(run.toString())); run.setLength(0) }
            out.append(ch)
        }
        if (run.isNotEmpty()) out.append(transform(run.toString()))
        return out.toString()
    }

    private fun isKana(ch: Char): Boolean = ch.code in 0x3041..0x30FF

    private fun isJapanese(ch: Char): Boolean = ch.code in 0x3041..0x30FF ||
        ch.code in 0x4E00..0x9FFF || ch.code == 0x3005
}
