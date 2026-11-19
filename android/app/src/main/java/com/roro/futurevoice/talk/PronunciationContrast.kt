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
 * right 926, wrong 11, and 150 within [MARGIN], which passes. A take is
 * never failed on a guess.
 */
object PronunciationContrast {
    /** A spelling must beat the other by more than this on the word. */
    const val MARGIN = 5
    const val MAX_ALTERNATES = 2

    /** Topics judged by comparison. A topic is added once its own swap has
     *  been measured on native recordings. */
    fun isOffered(topicId: String): Boolean = swaps(topicId) != null

    /** The languages with at least one such topic. */
    fun isOfferedLanguage(language: String): Boolean = language.substringBefore('-') == "ko"

    private const val INITIALS = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
    private val TENSE_TO_PLAIN = mapOf('ㄲ' to 'ㄱ', 'ㄸ' to 'ㄷ', 'ㅃ' to 'ㅂ', 'ㅆ' to 'ㅅ', 'ㅉ' to 'ㅈ')

    private val ASPIRATED_TO_PLAIN = mapOf('ㅋ' to 'ㄱ', 'ㅌ' to 'ㄷ', 'ㅍ' to 'ㅂ', 'ㅊ' to 'ㅈ')
    private fun reversed(t: Map<Char, Char>) = t.entries.associate { it.value to it.key }

    /** One alternate: the lesson's consonants and vowels → what each is
     *  swapped for. Vowels by their index in a syllable (ㅓ 4, ㅗ 8, ㅜ 13, ㅡ 18). */
    private data class Swap(val consonants: Map<Char, Char> = emptyMap(), val vowels: Map<Int, Int> = emptyMap())

    /** Every swap here was measured on FLEURS (right / wrong / within the
     *  margin): tense ↔ plain 926 / 11 / 150, aspirated ↔ plain 180 / 2 / 20,
     *  ㅓ ↔ ㅗ 279 / 1 / 18, ㅡ ↔ ㅜ 244 / 2 / 21. Tense ↔ aspirated was not,
     *  so the three-way topic compares each with plain. */
    private fun swaps(topicId: String): List<Swap>? = when (topicId) {
        "ko.tense" -> listOf(Swap(TENSE_TO_PLAIN))
        "ko.asp" -> listOf(Swap(ASPIRATED_TO_PLAIN))
        "ko.three" -> listOf(Swap(reversed(TENSE_TO_PLAIN) + ASPIRATED_TO_PLAIN + TENSE_TO_PLAIN),
                             Swap(reversed(ASPIRATED_TO_PLAIN)))
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
    fun alternates(text: String, topicId: String): List<String> {
        val tables = swaps(topicId) ?: return emptyList()
        val words = text.split(' ').filter { it.isNotEmpty() }
        val out = mutableListOf<String>()
        for (table in tables.take(MAX_ALTERNATES)) {
            val alt = words.mapIndexed { i, w -> swapped(w, words.getOrNull(i - 1), table) }.joinToString(" ")
            if (alt != text && alt !in out) out.add(alt)
        }
        return out
    }

    data class Miss(val word: String, val cameOutAs: String, val gap: Int)

    /** Every word where an alternate beat the reference by more than
     *  [MARGIN], the widest gap first. */
    fun misses(result: PronunciationResult): List<Miss> {
        val reference = result.referenceWords
        val best = mutableMapOf<Int, Miss>()
        for (alt in result.alternates.orEmpty()) {
            val other = alt.words.filter { it.error != "Insertion" }
            if (other.size != reference.size) continue
            reference.zip(other).forEachIndexed { i, (r, a) ->
                if (PronunciationJudge.key(r.word) == PronunciationJudge.key(a.word)) return@forEachIndexed
                if (!r.isJudged || a.error == "Omission") return@forEachIndexed
                val gap = (a.accuracy ?: return@forEachIndexed) - (r.accuracy ?: return@forEachIndexed)
                if (gap > MARGIN && gap > (best[i]?.gap ?: 0)) best[i] = Miss(r.word, a.word, gap)
            }
        }
        return best.values.sortedByDescending { it.gap }
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
