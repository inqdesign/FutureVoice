package com.roro.futurevoice.talk

/**
 * A line as MOUTHS produced it, not as a transcriber wrote it down.
 *
 * Punctuation, capitalization, spelling and contraction choice all come from
 * the recognizer, never from the speaker — so a correction built on any of
 * them tells someone they made a mistake they did not make, in their own
 * voice, mid-call. Both the drop filter and the highlight compare through
 * here.
 */
object SpokenWords {
    fun of(text: String): List<String> {
        var s = text.lowercase().replace('’', '\'')
        for ((contracted, expanded) in SpokenWordsContent.contractions) {
            s = s.replace(contracted, expanded)
        }
        // Everything that isn't a letter, digit or space is the transcriber's.
        val kept = buildString { for (c in s) append(if (c.isLetterOrDigit()) c else ' ') }
        return kept.split(' ').filter { it.isNotEmpty() }
    }

    /**
     * True when the suggestion's only change is one no mouth can produce.
     * Deliberately narrow: a mixed suggestion that fixes something real AND
     * happens to contract still survives.
     */
    fun saysTheSameThing(a: String, b: String, language: String = "en"): Boolean {
        if (language.substringBefore('-') == "ja") {
            // Japanese has no contractions to expand; what the transcriber
            // chooses there is the SCRIPT — 分かった or わかった, 下さい or
            // ください, which kanji. Compared by reading, a rewrite that only
            // re-spells what was said collapses the same way "I am" / "I'm"
            // does. Any change of sound survives (iOS `saysTheSameThing`).
            val left = JapaneseReading.of(a)
            return left.isNotEmpty() && left == JapaneseReading.of(b)
        }
        // Digits spelled out (the recognizer writes "3" for "three") and, in
        // Korean, word spacing folded away: 띄어쓰기 is the transcriber's
        // (한번 / 한 번), so a rewrite that only re-spaces changes nothing.
        return comparable(a, language).let { it.isNotEmpty() && it == comparable(b, language) }
    }

    private fun comparable(text: String, language: String): String {
        val words = of(ShadowScore.expandForDiff(text, language))
        return words.joinToString(if (language.substringBefore('-') == "ko") "" else " ")
    }

    /**
     * Korean only: the "fix" puts the SAME words in another order. Spoken
     * Korean orders freely ("먹었어, 아까 라면") — an afterthought, not a slip.
     * In English a reorder can be a real correction, so no other language.
     */
    fun changesOnlyWordOrder(a: String, b: String, language: String): Boolean {
        if (language.substringBefore('-') != "ko") return false
        val left = of(ShadowScore.expandForDiff(a, "ko"))
        val right = of(ShadowScore.expandForDiff(b, "ko"))
        if (left.size < 2 || left == right) return false
        return left.sorted() == right.sorted()
    }

    /**
     * Is [quote] something the learner actually said in [line]? The model
     * quotes loosely, so: contained after normalizing, contained with spaces
     * compared away (Korean spacing is the recognizer's; Japanese has none),
     * or three words in four shared (iOS `ConversationEngine.quotes`).
     */
    fun quotes(quote: String, line: String): Boolean {
        val needle = CarryoverDetector.normalized(quote)
        val hay = CarryoverDetector.normalized(line)
        if (needle.isEmpty()) return false
        if (hay.contains(needle)) return true
        val squeezed = needle.replace(" ", "")
        if (squeezed.isNotEmpty() && hay.replace(" ", "").contains(squeezed)) return true
        val words = needle.split(' ').filter { it.isNotEmpty() }.toSet()
        if (words.size < 3) return false
        val have = hay.split(' ').filter { it.isNotEmpty() }.toSet()
        return words.intersect(have).size.toDouble() / words.size >= 0.75
    }

    /**
     * Which display tokens of [alternative] actually changed against
     * [original]. A token is marked only when EVERY comparison word inside it
     * went unmatched, so "I'm" against "I am" lights up nothing.
     */
    fun changedTokens(alternative: String, original: String): List<Boolean> {
        val tokens = alternative.split(" ").filter { it.isNotEmpty() }
        val a = ArrayList<String>()
        val owner = ArrayList<Int>()
        tokens.forEachIndexed { idx, token -> of(token).forEach { a.add(it); owner.add(idx) } }
        val o = of(original)
        val m = a.size; val n = o.size
        // Longest common subsequence: what survived the rewrite.
        val dp = Array(m + 1) { IntArray(n + 1) }
        for (i in m - 1 downTo 0) for (j in n - 1 downTo 0) {
            dp[i][j] = if (a[i] == o[j]) dp[i + 1][j + 1] + 1 else maxOf(dp[i + 1][j], dp[i][j + 1])
        }
        val kept = BooleanArray(m)
        var i = 0; var j = 0
        while (i < m && j < n) {
            when {
                a[i] == o[j] -> { kept[i] = true; i++; j++ }
                dp[i + 1][j] >= dp[i][j + 1] -> i++
                else -> j++
            }
        }
        val hasWord = BooleanArray(tokens.size)
        val changed = BooleanArray(tokens.size)
        owner.forEachIndexed { position, tokenIndex ->
            hasWord[tokenIndex] = true
            if (!kept[position]) changed[tokenIndex] = true
        }
        // A token with no words in it is punctuation — never highlighted.
        return tokens.indices.map { changed[it] && hasWord[it] }
    }

    /**
     * The highlight as CHARACTER ranges of [alternative] — what every
     * correction surface paints (iOS `highlightedCorrection`). A spaced
     * language folds [changedTokens] onto its tokens and the single spaces
     * between them; an unspaced one (Japanese) is diffed and painted by
     * CHARACTER, because its segments are cut differently on each side of a
     * fix (面倒|くさかっ|た against 面倒|くさい|でし|た) and no segment-level
     * answer can say "かっ" changed and "くさ" didn't. Until 5.4 Android
     * split Japanese on spaces, so a whole line lit up as one token.
     *
     * The display text is [displayText]: tokens re-joined by one space for a
     * spaced language (what the screens always drew), the line itself for
     * an unspaced one.
     */
    fun changedRanges(alternative: String, original: String, language: String): List<IntRange> {
        if (!com.roro.futurevoice.data.WordSplitter.spaced(language)) {
            return changedCharacters(alternative, original).let(::runs)
        }
        val tokens = alternative.split(" ").filter { it.isNotEmpty() }
        val flags = changedTokens(alternative, original)
        val out = ArrayList<IntRange>()
        var at = 0
        tokens.forEachIndexed { i, token ->
            if (flags.getOrElse(i) { false }) out.add(at until at + token.length)
            at += token.length + 1
        }
        return out
    }

    fun displayText(alternative: String, language: String): String =
        if (com.roro.futurevoice.data.WordSplitter.spaced(language))
            alternative.split(" ").filter { it.isNotEmpty() }.joinToString(" ")
        else alternative

    /**
     * iOS `highlightedCharacters`: an LCS over the letters of both lines
     * (punctuation is the transcriber's, so it never takes part), then every
     * letter of the alternative the learner didn't say is marked — くさ[かっ]た.
     */
    fun changedCharacters(alternative: String, original: String): BooleanArray {
        val aIdx = alternative.indices.filter { alternative[it].isLetterOrDigit() }
        val a = aIdx.map { alternative[it] }
        val o = original.filter { it.isLetterOrDigit() }
        val m = a.size; val n = o.length
        val dp = Array(m + 1) { IntArray(n + 1) }
        for (i in m - 1 downTo 0) for (j in n - 1 downTo 0) {
            dp[i][j] = if (a[i] == o[j]) dp[i + 1][j + 1] + 1 else maxOf(dp[i + 1][j], dp[i][j + 1])
        }
        val changed = BooleanArray(alternative.length)
        var i = 0; var j = 0
        while (i < m) {
            when {
                j < n && a[i] == o[j] -> { i++; j++ }
                j < n && dp[i + 1][j] < dp[i][j + 1] -> j++
                else -> { changed[aIdx[i]] = true; i++ }
            }
        }
        return changed
    }

    private fun runs(flags: BooleanArray): List<IntRange> {
        val out = ArrayList<IntRange>()
        var start = -1
        for (k in flags.indices) {
            if (flags[k] && start < 0) start = k
            if (!flags[k] && start >= 0) { out.add(start until k); start = -1 }
        }
        if (start >= 0) out.add(start until flags.size)
        return out
    }
}

/**
 * A Japanese line as it SOUNDS — the Android stand-in for iOS
 * `JapaneseMorph.reading(of:)`.
 *
 * iOS reads every token through `CFStringTokenizer`'s Latin transcription,
 * which knows how any kanji is read. Android has nothing like it: ICU's only
 * Han transliterator (`Han-Latin`) is Mandarin pinyin, and `BreakIterator`
 * hands back boundaries alone. So the readings come from the app's own
 * Japanese list instead — `cefr_words_ja.tsv`'s third column (分かる →
 * わかる, 一緒 → いっしょ) and `ja_forms.tsv`'s other spellings (下さい →
 * ください, 綺麗 → きれい, 判る → 分かる) — plus each inflecting word's STEM
 * (分か → わか, so 分かった meets わかった), replaced longest-first over
 * the text. Kana and romaji fold through [JapaneseMorph.soundSpelling], as
 * before.
 *
 * Conservative by construction: a spelling with two readings (辛い, からい・
 * つらい; 行 as the stem of both 行く and 行う) is never replaced, and a
 * kanji the list doesn't carry stays a kanji — the two lines then simply
 * read as different, which is what this path answered before. It costs
 * recall against iOS (an off-list kanji word re-spelled in kana still shows
 * as a correction), never a real correction thrown away.
 */
object JapaneseReading {

    /** [text] as hiragana where the list can say how it is read. Punctuation
     *  never takes part (iOS joins token readings, and tokens carry none). */
    fun of(text: String, table: Table = table()): String {
        val s = fold(text.filter { it.isLetterOrDigit() })
        if (table.byKey.isEmpty()) return s
        val out = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            var matched = false
            var len = minOf(table.maxKey, s.length - i)
            while (len >= 1) {
                val reading = table.byKey[s.substring(i, i + len)]
                if (reading != null) {
                    out.append(reading); i += len; matched = true
                    break
                }
                len--
            }
            if (!matched) { out.append(s[i]); i++ }
        }
        return out.toString()
    }

    class Table(val byKey: Map<String, String>) {
        val maxKey: Int = byKey.keys.maxOfOrNull { it.length } ?: 0
    }

    /**
     * Builds the spelling → reading table from the list's headword readings
     * and its other-spelling forms. Only spellings with a kanji in them are
     * keys (kana already spells its sound). Every reading a spelling is ever
     * given is collected, and a key with more than one is dropped outright —
     * 今日 (きょう・こんにち), 私 (わたし・わたくし), 行 (the stem of both 行く
     * and 行う) are left as written rather than guessed.
     */
    fun build(readings: Map<String, String>, forms: Map<String, String>): Table {
        val candidates = HashMap<String, MutableSet<String>>()
        fun add(spelling: String, reading: String) {
            if (!spelling.any(::isKanji)) return
            if (reading.isEmpty() || reading.any(::isKanji)) return
            val key = fold(spelling)
            val sound = fold(reading)
            candidates.getOrPut(key) { HashSet() }.add(sound)
            // An inflecting word ends in the kana its reading ends in: drop
            // it from both and the stem still matches after conjugation —
            // 分か|った, 下さ|い, 食べ|ました. Only a verb or adjective ending:
            // 今日は / こんにちは share a は and are no stem of anything.
            val last = key.last()
            if (key.length >= 2 && sound.length >= 2 && last == sound.last() && last in INFLECTING) {
                val stem = key.dropLast(1)
                if (stem.any(::isKanji)) candidates.getOrPut(stem) { HashSet() }.add(sound.dropLast(1))
            }
        }
        fun readingsOf(headword: String): List<String> =
            readings[headword]?.split('・')?.filter { it.isNotBlank() }
                ?: listOfNotNull(headword.takeIf { h -> h.isNotEmpty() && h.none(::isKanji) })
        // The list's own readings, every one of them.
        for ((headword, reading) in readings) reading.split('・').forEach { add(headword, it) }
        for ((spelling, headword) in forms) {
            if (spelling.any(::isKanji)) {
                // Another way to WRITE the headword (下さい → ください, 判る →
                // 分かる): it reads as the headword does.
                readingsOf(headword).forEach { add(spelling, it) }
            } else if (headword.any(::isKanji) && readings[headword].isNullOrBlank() &&
                !(spelling.endsWith("する") && !headword.endsWith("する"))) {
                // A kana spelling of a kanji headword IS its reading
                // (べんきょう → 勉強) — the list leaves many readings blank,
                // and only those are filled: where it has one, the forms'
                // casual spellings (だいじょぶ, めんどくさい) would only make
                // it ambiguous. あいさつする → 挨拶 is the noun with する.
                add(headword, spelling)
            }
        }
        // An ambiguous spelling stays in the table AS ITSELF, so the longest
        // match still claims it whole: 本当 is left as 本当, never read as
        // 本 + 当 (ほん + the stem of 当たる).
        val out = HashMap<String, String>()
        for ((key, sounds) in candidates) out[key] = if (sounds.size == 1) sounds.first() else key
        return Table(out)
    }

    /** Kana a dictionary-form verb or i-adjective ends in. */
    private const val INFLECTING = "うくぐすつぬぶむるい"

    /** Test seam: the table a JVM builds from the TSVs, which the app reads
     *  through `CoreVocabulary` (assets need a context). */
    @Volatile internal var override: Table? = null
    @Volatile private var cached: Table? = null

    fun table(): Table {
        override?.let { return it }
        cached?.let { return it }
        val lexicon = com.roro.futurevoice.data.CoreVocabulary.set("ja")
        if (lexicon.isEmpty()) return Table(emptyMap())   // no context yet: don't cache empty
        val readings = HashMap<String, String>()
        for (h in lexicon) com.roro.futurevoice.data.CoreVocabulary.reading(h, "ja")?.let { readings[h] = it }
        return build(readings, com.roro.futurevoice.data.CoreVocabulary.forms("ja")).also { cached = it }
    }

    private fun fold(text: String): String = com.roro.futurevoice.data.JapaneseMorph.soundSpelling(text)

    private fun isKanji(ch: Char): Boolean = ch.code in 0x4E00..0x9FFF || ch.code == 0x3005
}
