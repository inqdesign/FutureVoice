package com.roro.futurevoice.data

/**
 * Measured signals → CEFR bands, the four axes the level page draws as an
 * equalizer (iOS `ProgressTab`'s band tables). Deterministic: fixed
 * thresholds over real measurements, never an opinion — which is why the
 * labels carry "≈" and the AI verdict does not.
 */
object LevelBands {
    private class Band(val level: CefrLevel, val from: Double, val to: Double)

    /** Articulation pace. Native speakers run ~150+; wall-clock WPM reads
     *  ~20 lower (think-time and the turn wait included), so it is shifted up
     *  before banding rather than reading a level or two too low. */
    private val fluency = listOf(
        Band(CefrLevel.A1, 0.0, 60.0), Band(CefrLevel.A2, 60.0, 85.0), Band(CefrLevel.B1, 85.0, 105.0),
        Band(CefrLevel.B2, 105.0, 125.0), Band(CefrLevel.C1, 125.0, 145.0), Band(CefrLevel.C2, 145.0, 200.0))

    /** Words per turn — how far an idea gets developed. The WEAKEST proxy of
     *  the four (it measures length, not quality), so the thresholds sit
     *  deliberately high. */
    private val expression = listOf(
        Band(CefrLevel.A1, 0.0, 6.0), Band(CefrLevel.A2, 6.0, 10.0), Band(CefrLevel.B1, 10.0, 16.0),
        Band(CefrLevel.B2, 16.0, 24.0), Band(CefrLevel.C1, 24.0, 34.0), Band(CefrLevel.C2, 34.0, 60.0))

    /** Half-open lookup; a value past the table's end takes the LAST entry,
     *  so an off-scale measurement doesn't go unbanded. */
    private fun band(value: Double, specs: List<Band>): CefrLevel =
        specs.firstOrNull { value >= it.from && value < it.to }?.level ?: specs.last().level

    /** The learner's own voiced seconds a fluency band needs (3 min). */
    const val MIN_FLUENCY_SPEAKING_SECONDS = 180.0

    /**
     * Pace → band, with iOS's two guards (2026-10-14: a B1 learner read ≈C2
     * after a few plain calls of short answers). Under three minutes of the
     * learner's own voice there is no band; and pace alone rewards short
     * answers, so turn length caps it at one band above the ≈Expression band
     * — the way range caps grammar. Returns the band and, when the cap
     * decided it, the cap.
     */
    fun fluencyRead(wpm: Double, fromVoicedSpeech: Boolean,
                    speakingSeconds: Double, wordsPerTurn: Double): Pair<CefrLevel, CefrLevel?>? {
        if (wpm <= 0 || speakingSeconds < MIN_FLUENCY_SPEAKING_SECONDS) return null
        val byPace = band(if (fromVoicedSpeech) wpm else wpm + 20, fluency)
        if (wordsPerTurn <= 0) return byPace to null
        val all = CefrLevel.entries
        val cap = all[minOf(all.indexOf(band(wordsPerTurn, expression)) + 1, all.size - 1)]
        return if (all.indexOf(cap) < all.indexOf(byPace)) cap to cap else byPace to null
    }

    fun expressionBand(wordsPerTurn: Double): CefrLevel? =
        if (wordsPerTurn <= 0) null else band(wordsPerTurn, expression)

    /** The 0–100 grammar score as a band. Android has no verified-slip
     *  density yet, so this is iOS's fallback branch, not its primary one. */
    fun grammarBand(score: Int): CefrLevel? = when {
        score <= 0 -> null
        score < 40 -> CefrLevel.A1
        score < 55 -> CefrLevel.A2
        score < 70 -> CefrLevel.B1
        score < 82 -> CefrLevel.B2
        score < 92 -> CefrLevel.C1
        else -> CefrLevel.C2
    }

    /**
     * Vocabulary as WHICH words, not how many (iOS `VocabSophistication`):
     * the MEAN LEVEL (A1 = 0 … C2 = 5) of the graded words said, repeats
     * counted, minus auxiliaries and the homographs the pool grades by a
     * rare sense (`that` B2, auxiliary `will` as the noun — counting them
     * made half of a native's score the word `that`). iOS keeps content
     * words by NLTagger class in context; Android has no tagger, so it reads
     * list words (content words by construction) minus the same stop list.
     * NICT JLE: the mean separates A1 / A2 / B1 and a native speaker's
     * range, and is flat from SST 6 to 9, so the assessment's precision read
     * decides B2–C2. German is not read here: Android has no German
     * lemmatizer. Korean, Japanese and Spanish (2026-11-06, iOS d9e0a0c6) are
     * read by the app's own analyzers, exactly as iOS reads them, with cuts
     * carried over from English through Tatoeba pairs (PROVISIONAL, weaker
     * than English: Korean's native-like edge is barely resolved, Japanese's
     * top is crowded since JLPT has no C2).
     */
    object VocabShare {
        const val MIN_GRADED_TOKENS = 300
        const val WINDOW_GRADED_TOKENS = 1200

        /** How a language's words are cut and lemmatized: the same way the
         *  notebook reads that language, so the level and the notebook agree
         *  on what a word is (iOS `VocabSophistication.Reader`). */
        enum class Reader {
            /** List words via the [read] `lemma` argument (English). */
            TOKENS,
            /** [KoreanMorph] headwords; one syllable is a word (집, 눈, 말). */
            KOREAN,
            /** [JapaneseMorph] headwords, content classes only, and only when
             *  every kanji said is in the headword (船 is not 舟). */
            JAPANESE,
            /** [SpanishMorph]'s table; a participle after haber is its verb. */
            SPANISH,
            /** [FrenchMorph]'s table, read in the sentence (l'été → été,
             *  j'ai aimé → aimer). */
            FRENCH,
        }

        class Profile(val a2: Double, val b1: Double, val nativeLike: Double, val stopWords: Set<String>,
                      val reader: Reader = Reader.TOKENS)

        val profiles = mapOf(
            "en" to Profile(0.25, 0.31, 0.36, setOf("be", "have", "do", "will", "would", "can", "could",
                "may", "might", "shall", "should", "must", "ought", "that", "found", "mine", "plus")),
            "ko" to Profile(0.56, 0.60, 0.62, setOf(
                // Light and auxiliary verbs, pro-verbs (be / have / do).
                "있다", "없다", "하다", "되다", "이다", "아니다", "않다", "싶다",
                "말다", "못하다", "그러다", "그렇다", "이렇다", "저렇다", "어떻다",
                // Pronouns, question words, determiners.
                "나", "내", "너", "네", "저", "제", "우리", "저희", "그", "그녀",
                "그들", "당신", "자기", "자신", "걔", "얘", "쟤", "누구", "누가",
                "뭐", "무엇", "뭘", "무슨", "어디", "언제", "왜", "이것", "그것",
                "저것", "이거", "그거", "저거", "이게", "그게", "아무", "모든", "이",
                "어느", "어떤", "몇",
                // Bound nouns, postposition verbs.
                "것", "거", "건", "게", "수", "줄", "데", "적", "때문", "뿐",
                "지", "듯", "만큼", "대로", "채", "대하다", "위하다", "통하다",
                "관하다", "의하다",
                // Interjections, numerals; 해 is 하다 read as 'sun', 수도 is -ㄹ 수도.
                "예", "응", "아니", "아니요", "아니야", "어", "아", "음", "하나",
                "둘", "셋", "넷", "일", "삼", "사", "오", "육", "칠", "팔",
                "구", "십", "백", "천", "만", "해", "수도",
            ), Reader.KOREAN),
            "ja" to Profile(0.86, 0.90, 0.93, setOf(
                // Light verbs and benefactives, formal nouns.
                "する", "なる", "いる", "ある", "できる", "やる", "くれる", "もらう",
                "あげる", "こと", "事", "もの", "物", "よう", "ため", "ところ", "方",
                "はず", "わけ", "つもり",
                // Pronouns, question words, determiners, numerals.
                "私", "僕", "俺", "あなた", "君", "彼", "彼女", "彼ら", "我々",
                "お前", "自分", "わたし", "あたし", "これ", "それ", "あれ", "どれ",
                "ここ", "そこ", "あそこ", "どこ", "こちら", "そちら", "あちら", "どちら",
                "誰", "何", "なに", "いつ", "どう", "どうして", "なぜ", "この",
                "その", "あの", "どの", "こう", "そう", "ああ", "これら", "それら",
                "一", "二", "三", "四", "五", "六", "七", "八", "九", "十",
                "百", "千", "万", "一つ", "二つ", "三つ",
                // Grammar and affixes.
                "ほど", "大", "対", "関する", "様",
                // Grammar the analyzer reads as a word (てしまう → 始末, とき → 解く, …).
                "始末", "解く", "点く", "老いる", "擦れる", "放る", "冴える", "分ける",
                "荒れる", "尽きる", "叱る", "積もる", "姉妹", "係わる", "憎い", "何か",
                "揉む", "毛糸", "まじる", "詰まる", "それる", "どく", "やつ", "まと",
                "さじ",
            ), Reader.JAPANESE),
            "es" to Profile(0.30, 0.33, 0.36, setOf(
                // Auxiliaries and modals.
                "ser", "estar", "haber", "tener", "hacer", "poder", "deber", "soler",
                // Question adverbs, numerals, possessive pronouns.
                "como", "donde", "cuando", "uno", "dos", "tres", "cuatro", "cinco", "seis",
                "siete", "ocho", "nueve", "diez", "cien", "mil", "mío", "mía", "tuyo", "tuya",
                "suyo", "suya", "nuestro", "nuestra",
            ), Reader.SPANISH),
            // French (iOS 2026-11-13): 365k Tatoeba en–fr pairs pooled like
            // speakers, r 0.89 (as good as Spanish); cuts 0.331/0.356/0.385 and
            // 0.335/0.358/0.398 on the two halves. Frequency bands, like Spanish.
            "fr" to Profile(0.33, 0.36, 0.39, setOf(
                // Auxiliaries and modals (be / have / do / go / can / must).
                "être", "avoir", "faire", "aller", "pouvoir", "devoir",
                "vouloir", "falloir",
                // The negation (ne … pas is one "not"), numerals.
                "ne", "pas", "un", "deux", "trois", "quatre", "cinq",
                "six", "sept", "huit", "neuf", "dix", "cent", "mille",
            ), Reader.FRENCH),
        )

        fun isCalibrated(language: String) = language in profiles

        data class Read(val graded: Int, val levelSum: Int, val talks: Int) {
            val mean: Double get() = if (graded > 0) levelSum.toDouble() / graded else 0.0
        }

        /** What set the band: no precision read yet (null, above B1 is
         *  undecided), or that read. */
        data class Ceiling(val precision: CefrLevel?)

        fun level(read: Read, profile: Profile, precision: CefrLevel?): Pair<CefrLevel, Ceiling?>? {
            if (read.graded < MIN_GRADED_TOKENS) return null
            val m = read.mean
            if (m < profile.a2) return CefrLevel.A1 to null
            if (m < profile.b1) return CefrLevel.A2 to null
            val measured = if (m >= profile.nativeLike) CefrLevel.B2 else CefrLevel.B1
            if (precision == null) return measured to Ceiling(null)
            var set = if (precision.ordinal < CefrLevel.B1.ordinal) CefrLevel.B1 else precision
            if (set.ordinal > CefrLevel.B2.ordinal && m < profile.nativeLike) set = CefrLevel.B2
            return set to Ceiling(precision)
        }

        /** Talks NEWEST FIRST, each the learner's evidence lines, until
         *  [WINDOW_GRADED_TOKENS]. [lemma] maps a surface token to its
         *  headword. */
        fun read(talksNewestFirst: List<List<String>>, profile: Profile,
                 lemma: (String) -> String, gradeOf: (String) -> CefrLevel?): Read {
            var graded = 0; var sum = 0; var talks = 0
            for (texts in talksNewestFirst) {
                if (graded >= WINDOW_GRADED_TOKENS) break
                val before = graded
                for (text in texts) for (head in contentLemmas(text, profile, lemma)) {
                    val lv = gradeOf(head) ?: continue
                    graded++; sum += lv.ordinal
                }
                if (graded > before) talks++
            }
            return Read(graded, sum, talks)
        }

        private val TOKEN_SPLIT = Regex("[^\\p{L}\\p{N}]+")
        private val japaneseContent = setOf(WordClass.NOUN, WordClass.VERB, WordClass.ADJECTIVE,
            WordClass.NA_ADJECTIVE, WordClass.ADVERB)

        /** Every content word's headword in [text], in order, repeats
         *  counted, minus the profile's stop words (iOS `contentLemmas`). */
        fun contentLemmas(text: String, profile: Profile, lemma: (String) -> String): List<String> {
            val lemmas: List<String> = when (profile.reader) {
                Reader.TOKENS -> text.split(TOKEN_SPLIT).filter { it.length > 1 }.map { lemma(it.lowercase()) }
                Reader.KOREAN -> {
                    val lexicon = CoreVocabulary.set("ko")
                    text.split(TOKEN_SPLIT).mapNotNull {
                        if (it.isEmpty()) null
                        else KoreanMorph.dictionaryForm(it, lexicon, CoreVocabulary::koreanRank)
                    }
                }
                Reader.JAPANESE -> {
                    // A hit whose said kanji aren't in the headword is a
                    // reading match onto another word (船 → 舟, 回 → さじ).
                    JapaneseMorph.headwords(text, CoreVocabulary.set("ja"), CoreVocabulary.forms("ja"))
                        .filter { (head, start, end) ->
                            val said = text.substring(start.coerceIn(0, text.length), end.coerceIn(0, text.length))
                            said.all { !isKanji(it) || head.contains(it) } &&
                                WordClass.classes(head, "ja").any { it in japaneseContent }
                        }
                        .map { it.first }
                }
                Reader.SPANISH -> {
                    // The table keeps a masculine participle as its own
                    // adjective graded by ITS frequency (comprado C2), so
                    // after a form of haber it is read as the verb.
                    val found = ArrayList<String>()
                    var afterHaber = false
                    for ((word, _) in SpanishMorph.words(text)) {
                        val entry = SpanishMorph.entry(word)
                        var head = entry?.lemma
                        if (afterHaber) spanishParticipleVerb(word.lowercase())?.let { head = it }
                        afterHaber = entry?.lemma == "haber"
                        head?.takeIf { it.length > 1 }?.let(found::add)
                    }
                    found
                }
                // Content readings only: a function word has no entry. The
                // participle after avoir is already the verb (FrenchMorph's
                // context rule), so the Spanish repair isn't needed here.
                Reader.FRENCH -> FrenchMorph.analyze(text).mapNotNull { it.entry?.lemma }.filter { it.length > 1 }
            }
            return lemmas.filter { it !in profile.stopWords }
        }

        private val spanishIrregularParticiples = mapOf(
            "dicho" to "decir", "hecho" to "hacer", "puesto" to "poner", "visto" to "ver",
            "escrito" to "escribir", "vuelto" to "volver", "devuelto" to "devolver",
            "resuelto" to "resolver", "abierto" to "abrir", "cubierto" to "cubrir",
            "descubierto" to "descubrir", "muerto" to "morir", "roto" to "romper",
            "supuesto" to "suponer", "propuesto" to "proponer", "compuesto" to "componer",
            "impuesto" to "imponer", "satisfecho" to "satisfacer", "deshecho" to "deshacer",
            "frito" to "freír", "impreso" to "imprimir",
        )

        /** The infinitive a participle after haber belongs to, when the
         *  table knows it as a verb (comprado → comprar, leído → leer). */
        fun spanishParticipleVerb(form: String): String? {
            spanishIrregularParticiples[form]?.let { return it }
            fun isVerb(w: String) = SpanishMorph.entry(w)?.wordClass == "verb"
            val (stem, endings) = when {
                form.endsWith("ado") -> form.dropLast(3) to listOf("ar")
                form.endsWith("ído") -> form.dropLast(3) to listOf("er", "ír")
                form.endsWith("ido") -> form.dropLast(3) to listOf("er", "ir")
                else -> return null
            }
            if (stem.isEmpty()) return null
            return endings.map { stem + it }.firstOrNull(::isVerb)
        }

        private fun isKanji(c: Char) = c.code in 0x4E00..0x9FFF || c.code in 0x3400..0x4DBF || c == '々'
    }

    /**
     * Vocabulary: the highest band where enough DISTINCT words have actually
     * been produced. The bar rises with the level — six A2 words are decent
     * evidence, six lucky C1 words (one song, one topic) are not — and a
     * baseline of 15 graded words is needed before any level is claimed.
     */
    fun vocabularyLevel(countsByLevel: Map<CefrLevel, Int>): CefrLevel? {
        val total = countsByLevel.values.sum()
        if (total < 15) return null
        var estimate: CefrLevel? = null
        for (lv in CefrLevel.entries) {
            val need = when (lv) {
                CefrLevel.A1, CefrLevel.A2 -> 6
                CefrLevel.B1 -> 8
                CefrLevel.B2 -> 10
                CefrLevel.C1 -> 12
                CefrLevel.C2 -> 15
            }
            if ((countsByLevel[lv] ?: 0) >= need) estimate = lv
        }
        return estimate ?: CefrLevel.A1
    }
}
