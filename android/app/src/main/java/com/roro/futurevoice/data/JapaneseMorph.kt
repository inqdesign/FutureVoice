package com.roro.futurevoice.data

/**
 * Where Japanese words begin, and what dictionary word each one is — port of
 * `JapaneseMorph.swift`, vector-tested against the real Swift
 * (`docs/contracts/vectors`, section `japanese`).
 *
 * **Where the cuts come from.** iOS segments with `CFStringTokenizer`. Here
 * it is Sudachi in mode B (`JapaneseDictionary`), whose cuts match iOS's on
 * 86 of 88 measured sentences (the headwords below on 87) — but its
 * dictionary is an on-demand download, so until
 * it is loaded (or on an install with no Play asset packs) the cut is ICU's
 * `BreakIterator`, which agreed with iOS on 6 of 40. That fallback gives
 * boundaries and nothing else, so its tokens carry no reading: the forms
 * table (`ja_forms.tsv`, わかる → 分かる) does that work instead. It costs
 * recall, never correctness. Sudachi's tokens carry their reading, which
 * [dictionaryForm] reads exactly as iOS reads `CFStringTokenizer`'s.
 */
object JapaneseMorph {

    /** One segmented word and where it sat in the text. [reading] is
     *  hiragana, the reading of the SURFACE (行き → いき) — Sudachi's; null
     *  on ICU's cut, which has none. */
    data class Token(val surface: String, val start: Int, val end: Int, val reading: String? = null)

    /** A run of the original text: a word, or what sat between two words.
     *  Concatenating every piece gives the text back. */
    data class Piece(val text: String, val isWord: Boolean)

    // ── Segmentation ──

    /** Words in [text], in order, punctuation and whitespace skipped. */
    fun words(text: String): List<Token> {
        if (text.isEmpty()) return emptyList()
        segmenterOverride?.let { return it(text) }
        // Sudachi once its dictionary is loaded. Its surfaces, never its
        // dictionaryForm: the headword rules below were written for iOS's
        // cuts, and fed Sudachi's surfaces they match iOS (dictionaryForm
        // measured worse).
        JapaneseDictionary.morphs(text)?.let { morphs ->
            return morphs.filter { m -> m.surface.any { it.isLetterOrDigit() } }
                .map { Token(it.surface, it.start, it.end, it.reading.ifEmpty { it.surface }) }
        }
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

    /**
     * Stands in for `BreakIterator` in a JVM unit test, where `android.icu`
     * is a stub that throws. Never set in the app.
     */
    @Volatile internal var segmenterOverride: ((String) -> List<Token>)? = null

    /**
     * The whole line as hiragana, punctuation dropped — what it SOUNDS like,
     * whatever script the transcriber chose (iOS `reading(of:)`, the token
     * readings joined). Null while Sudachi isn't loaded: ICU gives no
     * readings, and the caller has its own table for that case. A token the
     * dictionary has no reading for (an unknown word) stands as written.
     */
    fun reading(text: String): String? {
        if (segmenterOverride != null) return null
        val morphs = JapaneseDictionary.morphs(text) ?: return null
        return morphs.filter { m -> m.surface.any { it.isLetterOrDigit() } }
            .joinToString("") { it.reading.ifEmpty { JapaneseDictionary.hiragana(it.surface) } }
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
            headword(i, tokens, lexicon, forms)?.let {
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
            keyByToken[i] = headword(i, tokens, lexicon, forms) ?: ""
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

    /** The headword token [i] stands for, or null — [dictionaryForm] with
     *  the tokens around it, which decide most of what the token can be. */
    private fun headword(i: Int, tokens: List<Token>, lexicon: Set<String>,
                         forms: Map<String, String>): String? {
        val token = tokens[i]
        if (isCompoundParticle(i, tokens)) return null
        // て|しまう is grammar ("ended up"), not 閉まる or 始末.
        if (i > 0 && tokens[i - 1].surface in setOf("て", "で") &&
            token.surface in setOf("しまう", "しまっ", "しまい", "しまわ", "しまえ", "しまお")) return null
        // The token after this one, if nothing stands between them — in
        // はい、そう, はい is not a stem before そう.
        val next = if (i + 1 < tokens.size && tokens[i + 1].start == token.end) tokens[i + 1].surface else null
        // A lone し with no inflection after it is する's stem after a noun
        // or an object (運動|し, 耳に|し, 買い物を|し|に) and the particle
        // after anything that inflects (おいしい|し, 話せる|し, ない|し).
        if (token.surface == "し" && (next?.let { stemSlot(it, "し") } ?: Slot.NONE) == Slot.NONE) {
            if (i == 0) return null
            val before = tokens[i - 1].surface.lastOrNull() ?: return null
            val ok = isKanji(before) || before.code in 0x30A1..0x30F6 ||
                tokens[i - 1].surface in setOf("を", "に")
            return if (ok && "する" in lexicon) "する" else null
        }
        // One kanji glued to a kanji word before it is a suffix or a counter
        // (理論|的, 三|回, 二|枚, 一日|中), read on'yomi; glued to the kanji
        // word after it, a prefix (同|意見). Only the exact headword may
        // stand for it: 的 reads まと and 枚 has a JMdict spelling of びら,
        // neither of which was said. A verb stem keeps its rules (三回|見|た).
        if (isSingleKanji(token.surface) &&
            (next?.let { stemSlot(it, token.surface) } ?: Slot.NONE) == Slot.NONE &&
            token.surface !in ONE_KANJI_ICHIDAN && token.surface !in IRREGULARS) {
            val suffix = i > 0 && tokens[i - 1].end == token.start &&
                tokens[i - 1].surface.lastOrNull()?.let(::isKanji) == true
            val prefix = i + 1 < tokens.size && tokens[i + 1].start == token.end &&
                tokens[i + 1].surface.firstOrNull()?.let(::isKanji) == true
            if (suffix || prefix) {
                return if (token.surface in lexicon && !isFunctionToken(token.surface)) token.surface else null
            }
        }
        return dictionaryForm(token.surface, lexicon = lexicon, forms = forms,
            reading = token.reading, next = next)
    }

    /** に|つい|て, に|おい|て …: one particle the tokenizer cut in three, not
     *  点く or 老いる. Kana only — 置いて and 付いて are the verbs. */
    private fun isCompoundParticle(i: Int, tokens: List<Token>): Boolean {
        if (i == 0 || tokens[i - 1].surface != "に" || tokens[i - 1].end != tokens[i].start) return false
        val s = tokens[i].surface
        if (s in setOf("ついて", "おいて", "とって", "よって", "わたって")) return true
        if (s !in setOf("つい", "おい", "とっ", "よっ", "わたっ") || i + 1 >= tokens.size) return false
        return tokens[i + 1].surface == "て" && tokens[i + 1].start == tokens[i].end
    }

    private sealed interface Hit {
        data class Found(val head: String) : Hit
        data object Stop : Hit
        data object Miss : Hit
    }

    /**
     * The headword one token stands for, or null. Tries the surface's
     * candidates, then the same candidates spelled in kana (a kanji spelling
     * the list doesn't carry, 解る, still reads わかる).
     *
     * [next] — the token after this one. Inflection there (ます, ない, て,
     * ば …) marks this token as a stem, and WHICH inflection says which stem:
     * 行き before ました is 行く, not the noun 行き; すれ before ば is する,
     * not 擦れる; 中 before で is the noun with a particle, not 中る.
     * [inflected] is the older, context-free switch — a stem of any shape.
     *
     * [reading] null means UNKNOWN (ICU's cut), not "no reading": a one-kanji
     * `forms` entry onto a kana word (事 → こと) is then kept, since nothing
     * says the word was read otherwise; iOS always has the reading.
     */
    fun dictionaryForm(surface: String, inflected: Boolean = false,
                       lexicon: Set<String>, forms: Map<String, String>,
                       reading: String? = null, next: String? = null): String? {
        if (isFunctionToken(surface)) return null
        val slot = next?.let { stemSlot(it, surface) } ?: if (inflected) Slot.LOOSE else Slot.NONE
        val isStem = slot != Slot.NONE
        fun resolve(c: String, need: Need): Hit {
            // An irregular that is grammar ends the ladder: あれ before ば is
            // ある, and the pronoun あれ further down is not what was said.
            // A rule's guess that is grammar is only a miss (しかし|ながら
            // guesses しか on the way to しかし).
            if (isFunctionToken(c)) return if (need == Need.IRREGULAR) Hit.Stop else Hit.Miss
            val head = when {
                c in lexicon -> c
                else -> forms[c]?.takeIf { it in lexicon && formIsSpelling(c, it, reading) }
            } ?: return Hit.Miss
            if (isFunctionToken(head)) return if (need == Need.IRREGULAR) Hit.Stop else Hit.Miss
            return if (fits(head, need)) Hit.Found(head) else Hit.Miss
        }
        fun ordered(s: String): List<Pair<String, Need>> {
            val all = ladder(s, slot)
            return if (isStem && all.isNotEmpty()) all.drop(1) + all.first() else all
        }
        for ((c, need) in ordered(surface)) {
            when (val hit = resolve(c, need)) {
                is Hit.Found -> return hit.head
                Hit.Stop -> return null
                Hit.Miss -> continue
            }
        }
        if (reading != null && reading != surface && !isFunctionToken(reading)) {
            // A kanji noun's reading is kana, so the stem rules would happily
            // run on it — 箸 reads はし, and はし + る is 走る. The reading may
            // only stand in for the surface, never grow a verb the kanji
            // didn't have.
            val kanjiNoun = !isStem && surface.none { isKana(it) }
            // And a kanji surface may only be read onto a headword that shares
            // a kanji with it (分った → 分かる), or onto a word the list writes
            // in kana, spelled exactly as read — a kanji word (鞄 → かばん), a
            // stem's rule (出来|た → できる) or a verb in its dictionary form
            // (出来る → できる). Anything else is a homophone: 週間 is not 習慣,
            // 曲 is not 局, 回 (かい) is not さじ, 言い is not いい.
            val kanji = surface.filter { isKanji(it) }.toSet()
            val allKanji = surface.none { isKana(it) }
            val steps = if (kanjiNoun) listOf(reading to Need.ANY) else ordered(reading)
            for ((c, need) in steps) {
                when (val hit = resolve(c, need)) {
                    is Hit.Found -> {
                        val head = hit.head
                        val dictionaryVerb = surface.lastOrNull()?.let { it in U_ROW_KANA } == true &&
                            classesOf(head)?.contains("verb") == true
                        val kanaAsRead = head == c && head.all { isKana(it) } &&
                            (allKanji || need != Need.ANY || dictionaryVerb)
                        if (kanji.isNotEmpty() && head.none { it in kanji } && !kanaAsRead) continue
                        return head
                    }
                    Hit.Stop -> return null
                    Hit.Miss -> continue
                }
            }
        }
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
    fun candidates(raw: String, inflected: Boolean = true): List<String> =
        ladder(raw, if (inflected) Slot.LOOSE else Slot.NONE).map { it.first }

    /** What kind of headword a rule's guess has to be: the stem rules make
     *  verbs and adjectives, and a guess that lands on a noun is a homophone
     *  of the stem (やっ + つ is the noun やつ, not やる). */
    private enum class Need(val raw: String) {
        ANY("any"), IRREGULAR("irregular"), VERB("verb"), ADJECTIVE("adjective"), NOUN("noun")
    }

    /** Which stem the token after this one asks for. */
    private enum class Slot {
        /** Not a stem. */
        NONE,
        /** A stem of unknown shape — every rule (a chunk left whole, or a
         *  caller that only said "inflected"). */
        LOOSE,
        MASU,       // ます, たい, ながら — i-row (書き), ichidan (食べ)
        NAI,        // ない, れる, せる — a-row (書か), ichidan
        TE,         // て, た — onbin っ/い, し (話し), ichidan
        DE,         // で, だ — onbin ん/い (読ん, 泳い) only
        BA,         // ば — e-row (書け, すれ, 食べれ)
        VOLITIONAL, // う — o-row (書こ)
        YOO,        // よう — ichidan (食べ)
        IMPERATIVE, // ろ — ichidan (見)
    }

    private fun stemSlot(next: String, stem: String): Slot = when (next) {
        "ます", "まし", "ませ", "ましょ", "ましょう", "ません", "たい", "たく", "たかっ",
        "たけれ", "ながら", "なさい", "なさっ", "そう", "つつ" -> Slot.MASU
        "ない", "なかっ", "なく", "なけれ", "なきゃ", "なけりゃ", "なくちゃ", "なさ", "ず", "ぬ",
        "れ", "れる", "られ", "られる", "せ", "せる", "させ", "させる" -> Slot.NAI
        "て", "た", "ちゃ", "ちゃう", "ちゃっ", "ちゃい", "たり", "たら", "たろ",
        "てる", "てた", "てて", "てれ", "とく", "とい" -> Slot.TE
        // After anything but 読ん / 泳い this is the particle で or the
        // copula だ — 中で, それで, どこで, つもりだ — not inflection.
        "で", "だ", "じゃ", "だり", "だら", "じゃう", "じゃっ",
        "でる", "でた", "でて", "どく", "どい" ->
            if (stem.endsWith("ん") || stem.endsWith("い")) Slot.DE else Slot.NONE
        "ば" -> Slot.BA
        "う" -> Slot.VOLITIONAL
        "よう" -> Slot.YOO
        "ろ" -> Slot.IMPERATIVE
        else -> Slot.NONE
    }

    private fun ladder(raw: String, slot: Slot): List<Pair<String, Need>> {
        val token = raw.trim()
        if (token.isEmpty() || !token.all { isJapanese(it) }) return emptyList()
        val bases = mutableListOf(token to slot)
        // A chunk the tokenizer left whole (食べました) — strip inflection
        // down to the stem the rules below expect.
        strippingSuffix(token)?.let { bases.add(it to Slot.LOOSE) }

        val out = ArrayList<Pair<String, Need>>()
        for ((n, pair) in bases.withIndex()) {
            val (base, baseSlot) = pair
            // A kana chunk's stripped stem is only a stem: そこない is not そこ.
            if (n == 0 || !token.all { isKana(it) }) out.add(base to Need.ANY)
            val isStem = baseSlot != Slot.NONE
            val loneKana = base.length == 1 && isKana(base[0])
            // Irregulars first, where a single kana would otherwise guess
            // wild — and a lone し, き, こ is one only as a stem (on its own,
            // 雨も降るし, し is the particle).
            IRREGULARS[base]?.takeIf { isStem || !loneKana }?.let { l -> l.forEach { out.add(it to Need.IRREGULAR) } }
            ONE_KANJI_ICHIDAN[base]?.let { out.add(it to Need.VERB) }
            val hasKana = base.any { isKana(it) }
            if (!isStem && !hasKana) continue
            // A lone kana stem is almost always inflection; only the
            // irregulars above may speak for it.
            if (loneKana) continue
            val last = base.last()
            val head = base.dropLast(1)

            // i-adjective: 多く / 高かっ / 高けれ → 多い / 高い.
            if (base.endsWith("かっ") || base.endsWith("けれ")) out.add(base.dropLast(2) + "い" to Need.ADJECTIVE)
            if (last == 'く' && head.isNotEmpty()) out.add(head + "い" to Need.ADJECTIVE)

            // A word written in kana with no inflection after it is a word,
            // not a stem: とき is not 解く, しか is not 叱る, ほう is not 放る.
            // Kanji with okurigana keeps every rule (休み, 疲れ).
            val rules = when {
                isStem -> baseSlot
                base.all { isKana(it) } -> continue
                else -> Slot.LOOSE
            }

            // Ichidan: the stem IS the dictionary form minus る (疲れ, 食べ,
            // 起き) — and an ichidan stem ends in an i- or e-row kana, so
            // しか + ない is never しかる. A kanji-final stem (得|られる,
            // 観|たい) only before real inflection — 中|で is not 中る.
            if (rules in ICHIDAN_SLOTS &&
                (last in I_ROW_KANA || last in E_ROW_KANA || (isKanji(last) && rules != Slot.LOOSE))) {
                out.add(base + "る" to Need.VERB)
            }

            // Godan: the stem's last kana moves to the u-row (行き → 行く,
            // 行か → 行く), in the row the next token asks for. Onbin stems
            // (行っ, 読ん, 書い) have several possible sources; the lexicon
            // picks.
            if (head.isNotEmpty()) godanEndings(rules)[last.toString()]?.forEach { out.add(head + it to Need.VERB) }

            // Suru-noun: 勉強し / 勉強さ / 勉強せ → 勉強 (the list carries the noun).
            if (last.toString() in setOf("し", "さ", "せ") && head.isNotEmpty() && rules != Slot.DE) {
                out.add(head to Need.NOUN)
                out.add(head + "する" to Need.VERB)
            }
        }
        val seen = HashSet<String>()
        return out.filter { it.first.isNotEmpty() && seen.add(it.first) }
    }

    /** A rule's guess must be the kind of word the rule makes. A headword the
     *  class table doesn't know passes. */
    private fun fits(head: String, need: Need): Boolean {
        if (need == Need.ANY || need == Need.IRREGULAR) return true
        val classes = classesOf(head) ?: return true
        return need.raw in classes
    }

    /** headword → class names, from `word_classes_ja.tsv` (through
     *  [WordClass], which reads the same file). Null for a word off the
     *  table, which turns the check off — as iOS's empty table does. */
    private fun classesOf(head: String): Set<String>? =
        WordClass.tableClasses(head, "ja")?.mapTo(HashSet()) { it.raw }

    /** A `forms` entry keyed by ONE kanji is a rare spelling far more often
     *  than the word said: 船 → 舟, 枚 → びら, 的 → まと, 具 → 妻. Kept only
     *  when the headword is written with that kanji, or is the kana word the
     *  tokenizer read it as (事 → こと, 所 → ところ). With no reading at all
     *  (ICU's cut) a kana headword is kept — nothing says otherwise. */
    private fun formIsSpelling(key: String, head: String, reading: String?): Boolean {
        if (!isSingleKanji(key) || head == key || head.contains(key)) return true
        return head.all { isKana(it) } && (reading == null || head == reading)
    }

    // ── Tables ──

    /** 行っ reads 行く, never 行う — the one onbin collision common enough to
     *  matter, and the only godan verb whose te-form is irregular. */
    private val IRREGULARS = mapOf(
        "し" to listOf("する"), "さ" to listOf("する"), "せ" to listOf("する"),
        "き" to listOf("来る", "くる"), "こ" to listOf("来る", "くる"), "来" to listOf("来る"),
        "行っ" to listOf("行く"), "いっ" to listOf("行く", "いく"),
        // する and ある before ば: すれ is not 擦れる, あれ is not 荒れる (or
        // the pronoun) — ある is grammar, so the ladder stops there.
        "すれ" to listOf("する"), "あれ" to listOf("ある"),
        // いき before ます in kana is 行く far more often than 生きる.
        "いき" to listOf("行く", "いく"),
    )

    private val ONE_KANJI_ICHIDAN = mapOf(
        "見" to "見る", "出" to "出る", "寝" to "寝る", "着" to "着る",
        "居" to "居る", "似" to "似る",
    )

    /** Every godan rule at once, for a stem of unknown shape. */
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

    private val I_ROW = mapOf(
        "い" to listOf("う"), "き" to listOf("く"), "ぎ" to listOf("ぐ"), "し" to listOf("す"),
        "ち" to listOf("つ"), "に" to listOf("ぬ"), "び" to listOf("ぶ"), "み" to listOf("む"),
        "り" to listOf("る"),
    )
    private val A_ROW = mapOf(
        "わ" to listOf("う"), "か" to listOf("く"), "が" to listOf("ぐ"), "さ" to listOf("す"),
        "た" to listOf("つ"), "な" to listOf("ぬ"), "ば" to listOf("ぶ"), "ま" to listOf("む"),
        "ら" to listOf("る"),
    )
    /** Also the potential stem (書け|ます, 読め|ない), which inflects like
     *  an ichidan verb. */
    private val E_ROW = mapOf(
        "え" to listOf("う"), "け" to listOf("く"), "げ" to listOf("ぐ"), "せ" to listOf("す"),
        "て" to listOf("つ"), "ね" to listOf("ぬ"), "べ" to listOf("ぶ"), "め" to listOf("む"),
        "れ" to listOf("る"),
    )
    private val O_ROW = mapOf(
        "お" to listOf("う"), "こ" to listOf("く"), "ご" to listOf("ぐ"), "そ" to listOf("す"),
        "と" to listOf("つ"), "の" to listOf("ぬ"), "ぼ" to listOf("ぶ"), "も" to listOf("む"),
        "ろ" to listOf("る"),
    )

    /** Swift's `merging { $0 + $1 }`: a key in both keeps a's list, then b's. */
    private fun merge(a: Map<String, List<String>>, b: Map<String, List<String>>): Map<String, List<String>> {
        val out = LinkedHashMap(a)
        for ((k, v) in b) out[k] = (out[k] ?: emptyList()) + v
        return out
    }

    private val GODAN_BY_SLOT: Map<Slot, Map<String, List<String>>> by lazy {
        mapOf(
            Slot.NONE to emptyMap(), Slot.IMPERATIVE to emptyMap(),
            Slot.LOOSE to GODAN_ENDINGS,
            Slot.MASU to merge(I_ROW, E_ROW),
            Slot.NAI to merge(A_ROW, E_ROW),
            Slot.TE to merge(mapOf("っ" to listOf("う", "つ", "る"), "い" to listOf("く"), "し" to listOf("す")), E_ROW),
            Slot.DE to mapOf("ん" to listOf("む", "ぶ", "ぬ"), "い" to listOf("ぐ")),
            Slot.BA to E_ROW, Slot.YOO to E_ROW,
            Slot.VOLITIONAL to O_ROW,
        )
    }

    private fun godanEndings(slot: Slot): Map<String, List<String>> = GODAN_BY_SLOT.getValue(slot)

    private val ICHIDAN_SLOTS = setOf(Slot.LOOSE, Slot.MASU, Slot.NAI, Slot.TE, Slot.YOO, Slot.IMPERATIVE)
    private val I_ROW_KANA = "いきぎしじちぢにひびぴみり".toSet()
    private val E_ROW_KANA = "えけげせぜてでねへべぺめれ".toSet()
    private val U_ROW_KANA = "うくぐすずつづぬふぶぷむゆる".toSet()

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
        // Particles and formal nouns the stem rules would otherwise grow into
        // verbs (しか → 叱る, さえ → 冴える, わけ → 分ける), and the sentence
        // particle かい, which JMdict spells as さじ.
        "しか", "さえ", "すら", "こそ", "わけ", "かい",
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

    private fun isKanji(ch: Char): Boolean = ch.code in 0x4E00..0x9FFF || ch.code == 0x3005

    private fun isSingleKanji(s: String): Boolean = s.length == 1 && isKanji(s[0])

    private fun isJapanese(ch: Char): Boolean = ch.code in 0x3041..0x30FF ||
        ch.code in 0x4E00..0x9FFF || ch.code == 0x3005
}
