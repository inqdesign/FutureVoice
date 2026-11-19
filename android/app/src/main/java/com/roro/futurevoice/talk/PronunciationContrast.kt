package com.roro.futurevoice.talk

/**
 * Judging a sound by COMPARISON (iOS `PronunciationContrast`, 2026-11-19).
 *
 * Azure's score for a word cannot be held to a bar outside English: on real
 * native Korean (FLEURS, 1,087 words) a bar of 50 let 951 of 1,087 wrong
 * consonants pass, a bar of 85 failed one native word in nine, and a native
 * speaker was drilled on "예쁜" at 37. The model's bias on a word is the same
 * whatever it is told to expect, so the same take is read twice: against the
 * sentence as written and against the sentence with the lesson's sound
 * swapped for the one it is confused with ("빵을" → "방을"). Whichever
 * spelling scores higher on that word is what was said. On the same words:
 * right 926, wrong 11, and 150 within the margin, which passes. A take is
 * never failed on a guess.
 */
object PronunciationContrast {
    /** A spelling must beat the other by more than this on the word. Per
     *  language, set where a native reading is almost never taken for the
     *  other sound: Korean 5, Spanish and French 10, Japanese and German 15. */
    fun margin(locale: String): Int = when (locale.take(2)) {
        "ko" -> 5
        "ja", "de" -> 15
        else -> 10
    }
    const val MAX_ALTERNATES = 2

    /** Topics judged by comparison. A topic is added once its own swap has
     *  been measured on native recordings. */
    fun isOffered(topicId: String): Boolean =
        swaps(topicId) != null || wordRules(topicId) != null || occurrenceRule(topicId) != null || tone(topicId) != null

    /** The languages with at least one such topic. */
    fun isOfferedLanguage(language: String): Boolean =
        language.substringBefore('-') in setOf("ko", "es", "fr", "ja", "de", "zh")

    // Spanish, French, German: a swap inside a word.

    /** A spelling swap inside one word. [minLength] keeps it off the short
     *  function words it was not measured on. */
    private data class WordRule(val pattern: Regex, val replacement: String, val minLength: Int = 3)

    /** One list per alternate; the measurements are on iOS
     *  `PronunciationContrast.wordRules`. */
    private fun wordRules(topicId: String): List<List<WordRule>>? {
        val v = "aeiouáéíóú"
        return when (topicId) {
            "es.rr" -> listOf(listOf(WordRule(Regex("rr"), "r")))
            "es.r" -> listOf(listOf(WordRule(Regex("(?<=[$v])r(?=[$v])"), "rr")))
            "es.ny" -> listOf(listOf(WordRule(Regex("ñ"), "n")))
            "es.j" -> listOf(listOf(WordRule(Regex("j(?=[$v])|g(?=[eiéí])"), "y")))
            "fr.u" -> listOf(listOf(WordRule(Regex("(?<![aeoqgé])u(?![inmeé])"), "ou", 4)))
            "fr.eu" -> listOf(listOf(WordRule(Regex("(?<![aœ])eu(?![xi])"), "ou", 4)))
            "de.ue" -> listOf(listOf(WordRule(Regex("ü"), "u", 4)))
            "de.oe" -> listOf(listOf(WordRule(Regex("ö"), "o")))
            "de.eiie" -> listOf(listOf(WordRule(Regex("ei"), "ie")), listOf(WordRule(Regex("ie"), "ei")))
            "de.ich" -> listOf(listOf(WordRule(Regex("(?<=[eiäöülnr])ch(?!s)"), "sch")))
            "fr.nasal" -> listOf(listOf(WordRule(Regex("an(?![aeiouynm])"), "on", 4)),
                                 listOf(WordRule(Regex("on(?![aeiouynm])"), "an", 4)))
            else -> null
        }
    }

    private fun applying(rules: List<WordRule>, word: String): String {
        var out = word
        for (rule in rules) if (out.codePointCount(0, out.length) >= rule.minLength) out = rule.pattern.replace(out, rule.replacement)
        return out
    }

    /** Japanese: the beat the lesson is about, removed, one occurrence per
     *  alternate. The long mark only after katakana, where it is written. */
    private fun occurrenceRule(topicId: String): Regex? = when (topicId) {
        "ja.long" -> Regex("(?<=[ァ-ヴ])ー")
        "ja.tsu" -> Regex("[っッ]")
        else -> null
    }

    private const val INITIALS = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
    private val TENSE_TO_PLAIN = mapOf('ㄲ' to 'ㄱ', 'ㄸ' to 'ㄷ', 'ㅃ' to 'ㅂ', 'ㅆ' to 'ㅅ', 'ㅉ' to 'ㅈ')

    private val ASPIRATED_TO_PLAIN = mapOf('ㅋ' to 'ㄱ', 'ㅌ' to 'ㄷ', 'ㅍ' to 'ㅂ', 'ㅊ' to 'ㅈ')
    private fun reversed(t: Map<Char, Char>) = t.entries.associate { it.value to it.key }

    /** One alternate: the lesson's consonants and vowels → what each is
     *  swapped for. Vowels by their index in a syllable (ㅓ 4, ㅗ 8, ㅜ 13, ㅡ 18). */
    private data class Swap(val consonants: Map<Char, Char> = emptyMap(), val vowels: Map<Int, Int> = emptyMap())

    /** Every swap here was measured on FLEURS (right / wrong / within the
     *  margin): tense ↔ plain 926 / 11 / 150, aspirated ↔ plain 180 / 2 / 20,
     *  tense ↔ aspirated 743 / 15 / 126, ㅓ ↔ ㅗ 279 / 1 / 18, ㅡ ↔ ㅜ 244 /
     *  2 / 21. A consonant lesson is compared with BOTH other kinds: with
     *  plain alone, an aspirated consonant read tense passed. */
    private val TENSE_TO_ASPIRATED = mapOf('ㄲ' to 'ㅋ', 'ㄸ' to 'ㅌ', 'ㅃ' to 'ㅍ', 'ㅉ' to 'ㅊ')
    private fun swaps(topicId: String): List<Swap>? = when (topicId) {
        "ko.tense" -> listOf(Swap(TENSE_TO_PLAIN), Swap(TENSE_TO_ASPIRATED))
        "ko.asp" -> listOf(Swap(ASPIRATED_TO_PLAIN), Swap(reversed(TENSE_TO_ASPIRATED)))
        // Each of the three turned one way round, then the other: plain →
        // tense → aspirated → plain, and back. ㅅ and ㅆ swap with each other.
        "ko.three" -> listOf(
            Swap(reversed(TENSE_TO_PLAIN) + TENSE_TO_ASPIRATED + ASPIRATED_TO_PLAIN + ('ㅆ' to 'ㅅ')),
            Swap(reversed(ASPIRATED_TO_PLAIN) + reversed(TENSE_TO_ASPIRATED) + TENSE_TO_PLAIN + ('ㅅ' to 'ㅆ')))
        "ko.eoo" -> listOf(Swap(vowels = mapOf(4 to 8, 8 to 4)))
        "ko.eu" -> listOf(Swap(vowels = mapOf(18 to 13)))
        else -> null
    }

    private fun isSyllable(c: Char) = c in '가'..'힣'
    private fun initial(c: Char) = (c - '가') / 588
    private fun vowel(c: Char) = ((c - '가') % 588) / 28
    private fun final(c: Char) = (c - '가') % 28

    /** The syllable before leaves the consonant as written: no final
     *  consonant, or ㄴ ㅁ ㅇ. After any other final a plain consonant is
     *  said tense anyway ("짝궁" and "짝꿍" sound the same). */
    private fun leavesNextAsWritten(c: Char?): Boolean = c == null || final(c) in setOf(0, 4, 16, 21)

    private fun swapped(word: String, previousWord: String?, table: Swap): String {
        val out = StringBuilder()
        var before: Char? = previousWord?.lastOrNull { isSyllable(it) }
        for (c in word) {
            if (isSyllable(c) && leavesNextAsWritten(before)) {
                val i = table.consonants[INITIALS[initial(c)]]?.let { INITIALS.indexOf(it) } ?: initial(c)
                val v = table.vowels[vowel(c)] ?: vowel(c)
                out.append('가' + (i * 588 + v * 28 + final(c)))
            } else out.append(c)
            if (isSyllable(c)) before = c
        }
        return out.toString()
    }

    /** [text] with the topic's sound swapped in every word that carries it:
     *  one sentence per swap, the same number of words as [text]. */
    // Chinese: one character said in another tone.

    /** The four tone topics. A tone is a character, so the swap is another
     *  character of the same syllable (买 mǎi → 埋 mái), from the app's own
     *  HSK list ([ChineseToneTable]). One character per alternate; the
     *  measurements are on iOS `PronunciationContrast.tone`. */
    private fun tone(topicId: String): Int? = when (topicId) {
        "zh.t1" -> 1; "zh.t2" -> 2; "zh.t3" -> 3; "zh.t4" -> 4
        else -> null
    }

    private val toneOf: Map<Char, Pair<String, Int>> by lazy {
        ChineseToneTable.DATA.split(';').filter { it.length >= 3 }
            .associate { it[0] to (it.substring(1, it.length - 1) to it.last().digitToInt()) }
    }
    /** The first of a syllable and tone is the most basic word. */
    private val bySyllable: Map<String, Map<Int, Char>> by lazy {
        val out = mutableMapOf<String, MutableMap<Int, Char>>()
        ChineseToneTable.DATA.split(';').filter { it.length >= 3 }.forEach {
            out.getOrPut(it.substring(1, it.length - 1)) { mutableMapOf() }.putIfAbsent(it.last().digitToInt(), it[0])
        }
        out
    }
    /** The tone a learner is most likely to say instead, first. */
    private val CONFUSED_WITH = mapOf(1 to listOf(4, 2, 3), 2 to listOf(3, 1, 4), 3 to listOf(2, 4, 1), 4 to listOf(1, 2, 3))

    private fun toneAlternates(text: String, tone: Int): List<String> {
        val out = mutableListOf<String>()
        for ((i, c) in text.withIndex()) {
            if (out.size >= MAX_ALTERNATES) break
            val (syllable, t) = toneOf[c] ?: continue
            if (t != tone) continue
            val other = CONFUSED_WITH[tone]?.firstNotNullOfOrNull { bySyllable[syllable]?.get(it) } ?: continue
            out.add(text.substring(0, i) + other + text.substring(i + 1))
        }
        return out
    }

    private fun isHan(c: Char) = c in '\u4E00'..'\u9FFF'

    private class Sound(val character: Char, val score: Int?, val name: String?, val word: String)

    /** One character of the take that fit another tone better: each read
     *  laid out character by character with that character's own score. */
    private fun toneMiss(reference: List<PronunciationResult.Word>,
                         other: List<PronunciationResult.Alternate.Scored>, margin: Int): Miss? {
        val mine = reference.flatMap { w ->
            val han = w.word.filter { isHan(it) }
            val per = w.phonemes.size == han.length
            han.mapIndexed { i, c ->
                Sound(c, if (w.isJudged) (if (per) w.phonemes[i].accuracy else w.accuracy) else null,
                      if (per) w.phonemes[i].phoneme else null, w.word)
            }
        }
        val theirs = other.flatMap { w ->
            val han = w.word.filter { isHan(it) }
            val scores = w.phonemes.orEmpty()
            han.mapIndexed { i, c -> c to (if (w.error == "Omission") null else if (scores.size == han.length) scores[i] else w.accuracy) }
        }
        if (mine.size != theirs.size) return null
        for ((m, t) in mine.zip(theirs)) {
            if (m.character == t.first) continue
            val score = m.score ?: return null
            val otherScore = t.second ?: return null
            if (otherScore - score <= margin) return null
            // Azure must have read the character with the tone the swap was made from.
            val expected = toneOf[m.character]?.second
            if (m.name != null && expected != null && m.name.lastOrNull()?.digitToIntOrNull() != expected) return null
            return Miss(m.word, t.first.toString(), otherScore - score)
        }
        return null
    }

    fun alternates(text: String, topicId: String): List<String> {
        tone(topicId)?.let { return toneAlternates(text, it) }
        occurrenceRule(topicId)?.let { re ->
            return re.findAll(text).take(MAX_ALTERNATES).map { text.removeRange(it.range) }.toList()
        }
        val words = text.split(' ').filter { it.isNotEmpty() }
        val out = mutableListOf<String>()
        wordRules(topicId)?.let { lists ->
            for (rules in lists.take(MAX_ALTERNATES)) {
                val alt = words.joinToString(" ") { applying(rules, it) }
                if (alt != text && alt !in out) out.add(alt)
            }
            return out
        }
        val tables = swaps(topicId) ?: return emptyList()
        for (table in tables.take(MAX_ALTERNATES)) {
            val alt = words.mapIndexed { i, w -> swapped(w, words.getOrNull(i - 1), table) }.joinToString(" ")
            if (alt != text && alt !in out) out.add(alt)
        }
        return out
    }

    data class Miss(val word: String, val cameOutAs: String, val gap: Int)

    /** Every word where an alternate beat the reference by more than
     *  the margin, the widest gap first. */
    fun misses(result: PronunciationResult): List<Miss> {
        val reference = result.referenceWords
        val margin = margin(result.locale)
        if (result.locale.startsWith("zh")) {
            return result.alternates.orEmpty().mapNotNull { alt ->
                toneMiss(reference, alt.words.filter { it.error != "Insertion" }, margin)
            }.sortedByDescending { it.gap }
        }
        if (result.locale.startsWith("ja")) {
            return result.alternates.orEmpty().mapNotNull { alt ->
                unspacedMiss(reference, alt.words.filter { it.error != "Insertion" }, margin)
            }.sortedByDescending { it.gap }
        }
        val best = mutableMapOf<Int, Miss>()
        for (alt in result.alternates.orEmpty()) {
            val other = alt.words.filter { it.error != "Insertion" }
            if (other.size != reference.size) continue
            reference.zip(other).forEachIndexed { i, (r, a) ->
                if (PronunciationJudge.key(r.word) == PronunciationJudge.key(a.word)) return@forEachIndexed
                if (!r.isJudged || a.error == "Omission") return@forEachIndexed
                val gap = (a.accuracy ?: return@forEachIndexed) - (r.accuracy ?: return@forEachIndexed)
                if (gap > margin && gap > (best[i]?.gap ?: 0)) best[i] = Miss(r.word, a.word, gap)
            }
        }
        return best.values.sortedByDescending { it.gap }
    }

    private class Piece(val letters: String, val word: String, val accuracy: Int?)

    /** A language written without spaces: the two reads are cut into words
     *  differently ("立っ · て" against "立て"), so they are lined up by
     *  letter, and the words that cover the one change are compared, the
     *  lowest score on each side. */
    private fun unspacedMiss(reference: List<PronunciationResult.Word>,
                             other: List<PronunciationResult.Alternate.Scored>, margin: Int): Miss? {
        val mine = reference.map { Piece(PronunciationJudge.key(it.word), it.word, if (it.isJudged) it.accuracy else null) }
        val theirs = other.map { Piece(PronunciationJudge.key(it.word), it.word, if (it.error == "Omission") null else it.accuracy) }
        val t = mine.joinToString("") { it.letters }
        val a = theirs.joinToString("") { it.letters }
        if (t == a || t.isEmpty() || a.isEmpty()) return null
        var p = 0
        while (p < minOf(t.length, a.length) && t[p] == a[p]) p++
        var s = 0
        while (s < minOf(t.length, a.length) - p && t[t.length - 1 - s] == a[a.length - 1 - s]) s++
        fun covering(words: List<Piece>, lo: Int, hi: Int): Pair<String, Int>? {
            var position = 0
            val text = StringBuilder()
            var lowest: Int? = null
            for (w in words) {
                val start = position
                val end = position + w.letters.length
                position = end
                val hit = if (hi > lo) start < hi && end > lo else (start < lo && lo <= end) || (lo == 0 && start == 0)
                if (!hit) continue
                val accuracy = w.accuracy ?: return null
                text.append(w.word)
                lowest = minOf(lowest ?: accuracy, accuracy)
            }
            return lowest?.let { text.toString() to it }
        }
        val (word, score) = covering(mine, p, t.length - s) ?: return null
        val (otherWord, otherScore) = covering(theirs, p, a.length - s) ?: return null
        if (otherScore - score <= margin) return null
        return Miss(word, otherWord, otherScore - score)
    }

    /** Off script, a word left out, or the lesson's sound said as the other
     *  one. Nothing else stops a reading. */
    fun verdict(result: PronunciationResult?, only: Set<String>? = null,
                excluding: Set<String> = emptySet()): PronunciationJudge.Verdict {
        result ?: return PronunciationJudge.Verdict.Unheard
        if ((result.completeness ?: 100) < PronunciationJudge.COMPLETENESS_BAR) return PronunciationJudge.Verdict.OffScript
        fun inScope(word: String): Boolean {
            val k = PronunciationJudge.key(word)
            return k !in excluding && (only?.contains(k) ?: true)
        }
        misses(result).firstOrNull { inScope(it.word) }?.let {
            return PronunciationJudge.Verdict.NotYet(it.word, null, result.soundScore, it.cameOutAs)
        }
        result.referenceWords.firstOrNull { it.isOmission && inScope(it.word) }?.let {
            return PronunciationJudge.Verdict.NotYet(it.word, null, result.soundScore, null)
        }
        return PronunciationJudge.Verdict.Pass(result.soundScore)
    }
}
