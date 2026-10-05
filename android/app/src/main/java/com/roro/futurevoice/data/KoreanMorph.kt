package com.roro.futurevoice.data

/**
 * Deterministic Korean surface-form → dictionary-form matching, for vocab
 * tracking against the graded wordlist (whose headwords are dictionary forms:
 * 가다, 학교, 가깝다 …). Port of `KoreanMorph.swift` as rewritten in iOS
 * `bee9052d` (2026-10-04); `KoreanMorphTest` pins the same cases against the
 * same bundled pool.
 *
 * This is a HEURISTIC, not a morphological analyzer: it generates candidate
 * dictionary forms (particle-stripped nouns, ending-stripped verbs + 다) and
 * the caller keeps only candidates that exist in the lexicon. A wrong guess
 * that ISN'T a headword costs nothing; one that IS a headword is the real
 * risk, which is what the ranking in [dictionaryForm] is for.
 *
 * Before this Android had no Korean lemmatizer at all — a Korean token was
 * matched as written, so 했어 never met 하다 anywhere: the book's Words
 * chapter, the chip that ticks when a studied word is said, used-in-a-talk
 * credit, the vocabulary estimate. Every Hangul syllable is one UTF-16 char,
 * so `String.length` counts syllables exactly as Swift's `count` does.
 */
object KoreanMorph {

    /** Josa (particles) and the copula that attach to nouns — longest first
     *  so 에서부터 wins over 부터. Stripped up to three layers
     *  (사람들에게는 → 사람들에게 → 사람들 → 사람); 들 is a layer of its own. */
    private val particles = listOf(
        "이었어요", "이었습니다", "에서부터", "으로부터",
        "이에요", "이었어", "이었다", "입니다", "였어요", "이라서", "이니까",
        "한테서", "에게서", "이라고", "에게는", "한테는", "에서는", "으로는",
        "인데요", "이지만",
        "께서", "에서", "에게", "한테", "부터", "까지", "처럼", "만큼",
        "보다", "마다", "조차", "마저", "밖에", "으로", "이나", "이란",
        "라고", "라는", "이랑", "하고", "예요", "이야", "였어", "였다",
        "인데", "이고", "이지", "이죠", "라서", "에는", "에도", "이다",
        "은", "는", "이", "가", "을", "를", "에", "의", "도", "만",
        "와", "과", "랑", "로", "나", "요", "야", "들", "께",
    ).sortedByDescending { it.length }

    /** Verb/adjective endings, written against the UNCONTRACTED stem
     *  ([variants] has already turned 갔어 into 가았어, 바빠 into 바쁘아). Every
     *  ending that matches is tried, longest first; the past/future/honorific
     *  markers in front of it are peeled off afterwards ([preFinals]). */
    private val verbEndings = listOf(
        "습니다", "습니까", "더라고요", "잖아요", "거든요", "으십시오", "으려면",
        "으니까", "으면서", "으려고", "으세요", "을게요", "을까요", "을래요",
        "는데요", "더라고", "니까요", "십시오", "는지요", "을수록",
        "어요", "아요", "여요", "어서", "아서", "여서", "어도", "아도", "여도",
        "어야", "아야", "여야", "어라", "아라", "고요", "지요", "지만", "네요",
        "는데", "는다", "는지", "니까", "으면", "면서", "으러", "려고", "려면",
        "세요", "셔요", "시죠", "자고", "기로", "기에", "기가", "기를", "기는",
        "기도", "도록", "다가", "다고", "다는", "대요", "래요", "냐고", "나요",
        "군요", "구나", "구요", "잖아", "거든", "더라", "던데", "든지", "든가",
        "을게", "을까", "을래", "은데", "은지", "을지", "읍시다", "으니", "으며",
        "어", "아", "여", "요", "고", "지", "죠", "네", "는", "면", "러", "자",
        "기", "게", "다", "대", "래", "냐", "던", "을", "은", "며",
    ).sortedByDescending { it.length }

    /** One-syllable endings that are just as often the LAST SYLLABLE OF A NOUN
     *  (가지, 얘기…). A stem found through one of these counts one band harder
     *  in the ranking, so 가지 stays the noun while 가요 still becomes 가다. */
    private val weakEndings = setOf("지", "기", "게", "대", "래", "냐", "며", "러")

    /** Bound nouns: never said alone, said constantly (할 줄 알아, 갈 수 있어).
     *  As a token each is itself — 줄 is not 주다 + ㄹ in anybody's call. */
    private val boundNouns = setOf(
        "줄", "수", "것", "거", "때", "데", "적", "건", "걸", "뿐", "듯", "중", "채", "김", "리", "바",
    )

    /** Markers between the stem and the ending: past, future, honorific.
     *  Peeled at most twice. */
    private val preFinals = listOf("었었", "았었", "었", "았", "였", "겠", "셨", "으시", "시")

    /** Endings that begin with a stem's FINAL consonant (갈 = 가 + ㄹ,
     *  갑니다 = 가 + ㅂ니다, 간다 = 가 + ㄴ다): the coda and what may follow. */
    private val codaEndings: List<Pair<Int, List<String>>> = listOf(
        4 to listOf("", "다", "데", "데요", "지", "대", "대요"),                 // ㄴ
        8 to listOf("", "게", "게요", "까", "까요", "래", "래요", "지", "수록"), // ㄹ
        17 to listOf("니다", "니까", "시다"),                                   // ㅂ
    )

    // ── Public

    /** Ordered dictionary-form candidates for one token, most likely first. */
    fun candidates(raw: String): List<String> = ranked(raw).map { it.form }

    /**
     * The headword [token] most likely is, or null when no candidate is in
     * the lexicon. Several candidates are often REAL words (자는 is 자다 or the
     * noun 자), so the pick is a ranking: the token itself, one particle or an
     * explicit verb ending (tier 0) beats a deeper strip or a bare stem (tier
     * 1); within a tier the EASIER headword wins ([rank], the CEFR band); the
     * token itself gets one band of credit; ties keep generation order.
     */
    fun dictionaryForm(token: String, lexicon: Set<String>, rank: ((String) -> Int?)? = null): String? {
        val trimmed = token.trim()
        if (trimmed in boundNouns && trimmed in lexicon) return trimmed
        var hits = ranked(token).filter { it.form in lexicon }
        // A token that is itself a word is never read as a SHORTER noun plus a
        // particle — 거의 is not 거 + 의. Only a verb reading may compete.
        if (trimmed in lexicon) hits = hits.filter { it.kind != Kind.NOUN }
        val bestTier = hits.minOfOrNull { it.tier } ?: return null
        val tierHits = hits.filter { it.tier == bestTier }
        if (rank == null) return tierHits.firstOrNull()?.form
        fun score(c: Candidate): Int {
            val r = rank(c.form) ?: 6
            return if (c.form == trimmed) r - 1 else if (c.weak) r + 1 else r
        }
        var best = tierHits[0]
        for (c in tierHits.drop(1)) if (score(c) < score(best)) best = c
        return best.form
    }

    // ── Candidate generation

    private enum class Kind { TOKEN, NOUN, VERB }

    private data class Candidate(val form: String, val tier: Int, val kind: Kind = Kind.VERB,
                                 val weak: Boolean = false)

    private fun ranked(raw: String): List<Candidate> {
        val token = raw.trim()
        if (token.isEmpty() || !token.all(::isHangul)) return emptyList()
        val out = arrayListOf(Candidate(token, 0, Kind.TOKEN))

        // Nouns: one particle is tier 0, deeper layers tier 1. 하고 is a
        // particle (친구하고) and also 하다 + 고 (공부하고) — the verb is said
        // far more often, so that noun reading is a fallback.
        var layer = token
        for (depth in 0 until 3) {
            val stripped = strippingParticle(layer) ?: break
            val viaHago = depth == 0 && layer.endsWith("하고")
            out.add(Candidate(stripped, if (depth == 0 && !viaHago) 0 else 1, Kind.NOUN))
            layer = stripped
        }

        // Verbs and adjectives.
        val bareStems = ArrayList<String>()
        for (base in variants(token)) {
            for ((stem, weak) in endingStems(base)) out.add(Candidate(stem + "다", 0, weak = weak))
            val last = base.lastOrNull()?.let(::decompose)
            if (last != null && last.jong == 0) bareStems.add(base)   // 가 → 가다
        }
        for (stem in bareStems) out.add(Candidate(stem + "다", 1))

        val seen = HashSet<String>()
        return out.filter { it.form.isNotEmpty() && seen.add(it.form) }
    }

    private fun endingStems(base: String): List<Pair<String, Boolean>> {
        val stems = ArrayList<Pair<String, Boolean>>()
        for (ending in verbEndings) {
            if (base.length <= ending.length || !base.endsWith(ending)) continue
            val weak = ending in weakEndings
            stems += peelingPreFinals(base.dropLast(ending.length)).map { it to weak }
        }
        stems += codaStems(base).map { it to false }
        return stems
    }

    private fun peelingPreFinals(stem: String): List<String> {
        val out = arrayListOf(stem)
        var frontier = listOf(stem)
        repeat(2) {
            val next = ArrayList<String>()
            for (s in frontier) for (p in preFinals) {
                if (s.length > p.length && s.endsWith(p)) next.add(s.dropLast(p.length))
            }
            out += next
            frontier = next
        }
        return out
    }

    /** 갈 → 가, 갑니다 → 가, 간다 → 가; plus the stem that ending HID: ㄹ dropped
     *  before ㄴ/ㅂ/ㅅ (사는 → 살) and ㅎ dropped before ㄴ (그런 → 그렇). */
    private fun codaStems(base: String): List<String> {
        if (base.isEmpty()) return emptyList()
        val out = ArrayList<String>()
        for (i in base.length - 1 downTo 0) {
            val s = decompose(base[i]) ?: continue
            val rest = base.substring(i + 1)
            val rule = codaEndings.firstOrNull { it.first == s.jong } ?: continue
            if (rest !in rule.second) continue
            val head = base.substring(0, i)
            // A ㄹ-stem keeps its ㄹ under the ㄹ ending: 알 (수 있어) = 알다.
            if (s.jong == 8) out.add(head + base[i])
            out.add(head + compose(s.onset, s.vowel, 0))
            if (s.jong != 8) out.add(head + compose(s.onset, s.vowel, 8))
            if (s.jong == 4 && s.vowel in listOf(0, 2, 4)) {   // ㅏ ㅑ ㅓ + ㅎ
                out.add(head + compose(s.onset, s.vowel, 27))
            }
        }
        // ㄹ-deletion before a separate syllable: 사는 → 살, 아세요 → 알.
        for (ending in listOf("는", "는데", "는데요", "니까", "세요", "셨어", "셨어요", "시고", "네요", "니")) {
            if (base.length <= ending.length || !base.endsWith(ending)) continue
            val stem = base.dropLast(ending.length)
            val s = stem.lastOrNull()?.let(::decompose) ?: continue
            if (s.jong != 0) continue
            out.add(stem.dropLast(1) + compose(s.onset, s.vowel, 8))
        }
        return out
    }

    private fun strippingParticle(word: String): String? {
        for (p in particles) {
            if (word.length > p.length && word.endsWith(p)) return word.dropLast(p.length)
        }
        return null
    }

    // ── Undoing contraction and irregular stems

    /** [word] itself, then every reading with ONE fused or irregular syllable
     *  restored: 갔 → 가았, 봐 → 보아, 했 → 하였, 바빠 → 바쁘아, 몰라 → 모르아,
     *  들어 → 듣어, 가까워 → 가깝어, 나아 → 낫아, 어때 → 어떻어. All GUESSES. */
    private fun variants(word: String): List<String> {
        val bases = arrayListOf(word)
        if ("밌" in word) bases.add(word.replace("밌", "미있"))   // 재밌어 = 재미있어
        val out = ArrayList<String>()
        for (base in bases) {
            out.add(base)
            out += uncontractedHae(base)
            out += decontracted(base)
            out += irregular(base)
        }
        val seen = HashSet<String>()
        return out.filter { seen.add(it) }
    }

    /** 하다-verb contractions: 했 = 하였, 해 = 하여. */
    private fun uncontractedHae(word: String): List<String> {
        val out = ArrayList<String>()
        word.lastIndexOf('했').takeIf { it >= 0 }?.let { out.add(word.replaceRange(it, it + 1, "하였")) }
        word.lastIndexOf('해').takeIf { it >= 0 }?.let { out.add(word.replaceRange(it, it + 1, "하여")) }
        return out
    }

    /** Regular vowel fusion: a stem vowel + 아/어 (+ ㅆ for the past) written
     *  as one syllable. */
    private fun decontracted(word: String): List<String> {
        val out = ArrayList<String>()
        for (i in word.indices) {
            val s = decompose(word[i]) ?: continue
            if (s.jong != 0 && s.jong != 20) continue
            val past = s.jong == 20
            val expansions: List<Pair<Int, String>> = when (s.vowel) {
                0 -> if (past) listOf(0 to "았") else emptyList()              // 갔 → 가았
                1 -> if (past) listOf(1 to "었") else emptyList()              // 냈 → 내었
                4 -> if (past) listOf(4 to "었") else emptyList()              // 섰 → 서었
                6 -> listOf(6 to (if (past) "었" else "어"), 20 to (if (past) "었" else "어")) // 켰, 마셔
                9 -> listOf(8 to (if (past) "았" else "아"))                   // 봐 → 보아
                10 -> listOf(11 to (if (past) "었" else "어"))                 // 돼 → 되어
                14 -> listOf(13 to (if (past) "었" else "어"))                 // 줘 → 주어
                else -> emptyList()
            }
            for ((vowel, suffix) in expansions) {
                out.add(word.substring(0, i) + compose(s.onset, vowel, 0) + suffix + word.substring(i + 1))
            }
        }
        return out
    }

    /** The irregular conjugations, one syllable at a time. */
    private fun irregular(word: String): List<String> {
        val out = ArrayList<String>()
        for (i in word.indices) {
            val s = decompose(word[i]) ?: continue
            val prev = if (i > 0) decompose(word[i - 1]) else null
            val next = if (i + 1 < word.length) decompose(word[i + 1]) else null
            val past = s.jong == 20
            val fused = s.jong == 0 || past
            val head = word.substring(0, i)
            val tail = word.substring(i + 1)

            // ㅡ-deletion: 바빠 = 바쁘 + 아, 써 = 쓰 + 어, 바빴 = 바쁘 + 았.
            if (fused && (s.vowel == 0 || s.vowel == 4)) {
                val suffix = if (s.vowel == 0) (if (past) "았" else "아") else (if (past) "었" else "어")
                out.add(head + compose(s.onset, 18, 0) + suffix + tail)
                // 르-irregular: 몰라 = 모르 + 아.
                if (s.onset == 5 && prev != null && prev.jong == 8) {
                    val bare = compose(prev.onset, prev.vowel, 0)
                    out.add(word.substring(0, i - 1) + bare + "르" + suffix + tail)
                }
            }

            // ㅂ-irregular: 가까워 = 가깝 + 어, 도와 = 돕 + 아.
            if (i > 0 && fused && s.onset == 11 && (s.vowel == 14 || s.vowel == 9) &&
                prev != null && prev.jong == 0) {
                val suffix = if (s.vowel == 14) (if (past) "었" else "어") else (if (past) "았" else "아")
                out.add(word.substring(0, i - 1) + compose(prev.onset, prev.vowel, 17) + suffix + tail)
            }

            // ㅎ-irregular: 어때 = 어떻 + 어, 빨개 = 빨갛 + 아. Only past the
            // first syllable: a one-syllable 내 is not 넣어.
            if (i > 0 && fused && (s.vowel == 1 || s.vowel == 3)) {
                val options = if (s.vowel == 1)
                    listOf(4 to (if (past) "었" else "어"), 0 to (if (past) "았" else "아"))
                else listOf(2 to (if (past) "았" else "아"))
                for ((vowel, suffix) in options) {
                    out.add(head + compose(s.onset, vowel, 27) + suffix + tail)
                }
            }

            // ㄷ-irregular: 들어 = 듣 + 어 — a ㄹ before a vowel-initial syllable.
            if (s.jong == 8 && next != null && next.onset == 11 && next.vowel in listOf(0, 4, 18)) {
                out.add(head + compose(s.onset, s.vowel, 7) + tail)
            }

            // ㅅ-irregular: 나아 = 낫 + 아, 지었 = 짓 + 었.
            if (s.jong == 0 && next != null && next.onset == 11 && next.vowel in listOf(0, 4, 18)) {
                out.add(head + compose(s.onset, s.vowel, 19) + tail)
            }
        }
        return out
    }

    // ── Hangul

    private data class Syllable(val onset: Int, val vowel: Int, val jong: Int)

    private fun decompose(ch: Char): Syllable? {
        if (ch.code !in 0xAC00..0xD7A3) return null
        val idx = ch.code - 0xAC00
        return Syllable(idx / (21 * 28), (idx % (21 * 28)) / 28, idx % 28)
    }

    private fun compose(onset: Int, vowel: Int, jong: Int): Char =
        (0xAC00 + (onset * 21 + vowel) * 28 + jong).toChar()

    private fun isHangul(ch: Char): Boolean = ch.code in 0xAC00..0xD7A3
}
