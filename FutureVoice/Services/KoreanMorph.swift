import Foundation

/// Deterministic Korean surface-form → dictionary-form matching, for vocab
/// tracking against the graded wordlist (whose headwords are dictionary
/// forms: 가다, 학교, 가깝다 …).
///
/// This is a HEURISTIC, not a morphological analyzer: it generates candidate
/// dictionary forms (particle-stripped nouns, ending-stripped verbs + 다) and
/// the caller keeps only candidates that exist in the lexicon. A wrong guess
/// that ISN'T a headword costs nothing; one that IS a headword is the real
/// risk, which is what the ranking in `dictionaryForm` is for.
///
/// Rewritten 2026-10-04: the first version mapped 24 of 56 common spoken
/// forms back to their word. It knew 었어요 but not 었어, so the casual past
/// — 했어, 왔어, 됐어, the shape the fluent self speaks in on every call —
/// never matched, and neither did the ㅡ/르/ㄷ irregulars (바빠, 몰라, 들어),
/// noun modifiers (좋은, 먹는, 갈), the copula (학생이에요), -세요 or 들.
/// Everything reading Korean lemmas sat on it: the book's Words chapter,
/// the chip that ticks when a studied word is said, used-in-a-talk credit,
/// the vocabulary estimate. `KoreanMorphTests` pins the cases.
enum KoreanMorph {

    /// Josa (particles) and the copula that attach to nouns — longest first
    /// so 에서부터 wins over 부터. Stripped up to three layers
    /// (사람들에게는 → 사람들에게 → 사람들 → 사람); 들 is a layer of its own.
    private static let particles = [
        "이었어요", "이었습니다", "에서부터", "으로부터",
        "이에요", "이었어", "이었다", "입니다", "였어요", "이라서", "이니까",
        "한테서", "에게서", "이라고", "에게는", "한테는", "에서는", "으로는",
        "인데요", "이지만",
        "께서", "에서", "에게", "한테", "부터", "까지", "처럼", "만큼",
        "보다", "마다", "조차", "마저", "밖에", "으로", "이나", "이란",
        "라고", "라는", "이랑", "하고", "예요", "이야", "였어", "였다",
        "인데", "이고", "이지", "이죠", "라서", "에는", "에도", "이다",
        "은", "는", "이", "가", "을", "를", "에", "의", "도", "만",
        "와", "과", "랑", "로", "나", "요", "야", "들", "께"
    ].sorted { $0.count > $1.count }

    /// Verb/adjective endings, written against the UNCONTRACTED stem
    /// (`variants` has already turned 갔어 into 가았어, 바빠 into 바쁘아).
    /// Every ending that matches is tried, longest first; the past/future/
    /// honorific markers in front of it are peeled off afterwards
    /// (`preFinals`), so 먹었는데 is 는데 + 었 + 먹 and needs no 었는데 entry.
    private static let verbEndings = [
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
        "기", "게", "다", "대", "래", "냐", "던", "을", "은", "며"
    ].sorted { $0.count > $1.count }

    /// One-syllable endings that are just as often the LAST SYLLABLE OF A
    /// NOUN (가지, 얘기, 모습이게…). A stem found through one of these counts
    /// one band harder in the ranking, so 가지 stays the noun while 가요
    /// still becomes 가다.
    private static let weakEndings: Set<String> = ["지", "기", "게", "대", "래", "냐", "며", "러"]

    /// Bound nouns: never said alone, said constantly (할 줄 알아, 갈 수
    /// 있어, 먹은 적 있어). As a token each is itself, whatever verb + ㄹ/ㄴ
    /// it could also spell — 줄 is not 주다 + ㄹ in anybody's call.
    private static let boundNouns: Set<String> = [
        "줄", "수", "것", "거", "때", "데", "적", "건", "걸", "뿐", "듯", "중", "채", "김", "리", "바"
    ]

    /// Markers that sit between the stem and the ending: past, future,
    /// honorific. Peeled at most twice (가셨었 is rare enough to miss).
    private static let preFinals = ["었었", "았었", "었", "았", "였", "겠", "셨", "으시", "시"]

    /// Endings that begin with a stem's FINAL consonant (갈 = 가 + ㄹ,
    /// 갑니다 = 가 + ㅂ니다, 간다 = 가 + ㄴ다): the coda and what may follow it.
    private static let codaEndings: [(coda: Int, rests: [String])] = [
        (4, ["", "다", "데", "데요", "지", "대", "대요"]),                       // ㄴ
        (8, ["", "게", "게요", "까", "까요", "래", "래요", "지", "수록"]),        // ㄹ
        (17, ["니다", "니까", "시다"])                                          // ㅂ
    ]

    // MARK: - Public

    /// Ordered dictionary-form candidates for one token, most likely first.
    /// The token itself always leads — many wordlist entries (명사, 부사) are
    /// their own surface form.
    static func candidates(for raw: String) -> [String] {
        ranked(raw).map(\.form)
    }

    /// The headword `token` most likely is, or nil when no candidate is in
    /// the lexicon.
    ///
    /// Several candidates are often REAL words — 자는 is 자다 or the noun 자,
    /// 가요 is 가다 or the noun 가요, 사는 is 사다 or 살다 — so the pick is a
    /// ranking, not "first hit":
    /// 1. Tier: the token itself, one particle, or an explicit verb ending
    ///    (tier 0) beats a deeper particle strip or a bare stem (tier 1) —
    ///    도와요 must not reach the noun 도 through 요 + 와.
    /// 2. Within a tier, the EASIER headword wins (`rank`, the CEFR band):
    ///    in conversation the a1 verb is the one being said far more often
    ///    than the c1 noun that happens to share its letters.
    /// 3. The token itself gets one band of credit, so a word that exists
    ///    as said keeps its reading unless something clearly easier competes
    ///    (가지 stays 가지; 가요 b2 yields to 가다 a1, 어때 to 어떻다).
    /// 4. Ties keep generation order: noun readings before verb readings,
    ///    regular before irregular (들어 → 들다 before 듣다 — genuinely
    ///    ambiguous without the sentence around it).
    static func dictionaryForm(of token: String, in lexicon: Set<String>,
                               rank: ((String) -> Int?)? = nil) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if boundNouns.contains(trimmed), lexicon.contains(trimmed) { return trimmed }
        var hits = ranked(token).filter { lexicon.contains($0.form) }
        // A token that is itself a word is never read as a SHORTER noun plus
        // a particle — 거의 is not 거 + 의, 그만 not 그 + 만, 수도 not 수 + 도.
        // Only a verb reading may still compete with it (가요 → 가다).
        if lexicon.contains(trimmed) { hits.removeAll { $0.kind == .noun } }
        guard let bestTier = hits.map(\.tier).min() else { return nil }
        let tierHits = hits.filter { $0.tier == bestTier }
        guard let rank else { return tierHits.first?.form }
        func score(_ c: Candidate) -> Int {
            let r = rank(c.form) ?? 6
            return c.form == trimmed ? r - 1 : (c.weak ? r + 1 : r)
        }
        var best = tierHits[0]
        for c in tierHits.dropFirst() where score(c) < score(best) { best = c }
        return best.form
    }

    // MARK: - Candidate generation

    private struct Candidate {
        enum Kind { case token, noun, verb }
        let form: String
        let tier: Int
        var kind: Kind = .verb
        var weak = false
    }

    private static func ranked(_ raw: String) -> [Candidate] {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.allSatisfy(isHangul) else { return [] }
        var out: [Candidate] = [Candidate(form: token, tier: 0, kind: .token)]

        // Nouns: one particle is tier 0, deeper layers tier 1. 하고 is a
        // particle (친구하고) and also 하다 + 고 (공부하고), and the verb is
        // what is said far more often — so that noun reading is a fallback.
        var layer = token
        for depth in 0..<3 {
            guard let stripped = strippingParticle(from: layer) else { break }
            let viaHago = depth == 0 && layer.hasSuffix("하고")
            out.append(Candidate(form: stripped, tier: depth == 0 && !viaHago ? 0 : 1, kind: .noun))
            layer = stripped
        }

        // Verbs and adjectives.
        var bareStems: [String] = []
        for base in variants(of: token) {
            for (stem, weak) in endingStems(of: base) {
                out.append(Candidate(form: stem + "다", tier: 0, weak: weak))
            }
            if let last = base.last, let s = decompose(last), s.jong == 0 {
                bareStems.append(base)   // 가 → 가다; merged 아/어 with nothing after
            }
        }
        for stem in bareStems { out.append(Candidate(form: stem + "다", tier: 1)) }

        var seen = Set<String>()
        return out.filter { !$0.form.isEmpty && seen.insert($0.form).inserted }
    }

    /// Every stem `base` yields by removing an ending and then any markers
    /// in front of it, plus the stems a final-consonant ending leaves.
    private static func endingStems(of base: String) -> [(stem: String, weak: Bool)] {
        var stems: [(String, Bool)] = []
        for ending in verbEndings where base.count > ending.count && base.hasSuffix(ending) {
            let weak = weakEndings.contains(ending)
            stems.append(contentsOf: peelingPreFinals(String(base.dropLast(ending.count))).map { ($0, weak) })
        }
        stems.append(contentsOf: codaStems(of: base).map { ($0, false) })
        return stems
    }

    private static func peelingPreFinals(_ stem: String) -> [String] {
        var out = [stem]
        var frontier = [stem]
        for _ in 0..<2 {
            var next: [String] = []
            for s in frontier {
                for p in preFinals where s.count > p.count && s.hasSuffix(p) {
                    let peeled = String(s.dropLast(p.count))
                    next.append(peeled)
                }
            }
            out.append(contentsOf: next)
            frontier = next
        }
        return out
    }

    /// 갈 → 가, 갑니다 → 가, 간다 → 가; plus the stem that ending HID:
    /// ㄹ dropped before ㄴ/ㅂ/ㅅ (사는 → 살, 압니다 → 알) and ㅎ dropped
    /// before ㄴ (그런 → 그렇, 하얀 → 하얗).
    private static func codaStems(of base: String) -> [String] {
        let chars = Array(base)
        guard !chars.isEmpty else { return [] }
        var out: [String] = []
        for i in stride(from: chars.count - 1, through: 0, by: -1) {
            guard let s = decompose(chars[i]) else { continue }
            let rest = String(chars[(i + 1)...])
            guard let rule = codaEndings.first(where: { $0.coda == s.jong }),
                  rule.rests.contains(rest) else { continue }
            let head = String(chars[..<i])
            // A ㄹ-stem keeps its ㄹ under the ㄹ ending: 알 (수 있어) = 알다.
            if s.jong == 8 { out.append(head + String(chars[i])) }
            out.append(head + String(compose(onset: s.onset, vowel: s.vowel, jong: 0)))
            if s.jong != 8 {
                out.append(head + String(compose(onset: s.onset, vowel: s.vowel, jong: 8)))
            }
            if s.jong == 4, [0, 2, 4].contains(s.vowel) {   // ㅏ ㅑ ㅓ + ㅎ
                out.append(head + String(compose(onset: s.onset, vowel: s.vowel, jong: 27)))
            }
        }
        // ㄹ-deletion before a separate syllable: 사는 → 살, 아세요 → 알,
        // 만드는 → 만들. Applied to stems the ending path found.
        for ending in ["는", "는데", "는데요", "니까", "세요", "셨어", "셨어요", "시고", "네요", "니"]
        where base.count > ending.count && base.hasSuffix(ending) {
            let stem = Array(base.dropLast(ending.count))
            guard let last = stem.last, let s = decompose(last), s.jong == 0 else { continue }
            out.append(String(stem.dropLast()) + String(compose(onset: s.onset, vowel: s.vowel, jong: 8)))
        }
        return out
    }

    private static func strippingParticle(from word: String) -> String? {
        for p in particles where word.count > p.count {
            if word.hasSuffix(p) { return String(word.dropLast(p.count)) }
        }
        return nil
    }

    // MARK: - Undoing contraction and irregular stems

    /// `word` itself, then every reading with ONE fused or irregular
    /// syllable restored: 갔 → 가았, 봐 → 보아, 했 → 하였, 바빠 → 바쁘아,
    /// 몰라 → 모르아, 들어 → 듣어, 가까워 → 가깝어, 나아 → 낫아, 어때 →
    /// 어떻어. All GUESSES — the lexicon and the ranking discard the wrong
    /// ones. Regular readings come first so a tie keeps them.
    private static func variants(of word: String) -> [String] {
        var bases = [word]
        if word.contains("밌") {   // 재밌어 = 재미있어, spoken contraction
            bases.append(word.replacingOccurrences(of: "밌", with: "미있"))
        }
        var out: [String] = []
        for base in bases {
            out.append(base)
            out.append(contentsOf: uncontractedHae(base))
            out.append(contentsOf: decontracted(base))
            out.append(contentsOf: irregular(base))
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// 하다-verb contractions of 하 + 여(ㅆ): 했 = 하였, 해 = 하여.
    private static func uncontractedHae(_ word: String) -> [String] {
        var out: [String] = []
        if let r = word.range(of: "했", options: .backwards) {
            out.append(word.replacingCharacters(in: r, with: "하였"))
        }
        if let r = word.range(of: "해", options: .backwards) {
            out.append(word.replacingCharacters(in: r, with: "하여"))
        }
        return out
    }

    /// Regular vowel fusion: a stem vowel + 아/어 (+ ㅆ for the past)
    /// written as one syllable.
    private static func decontracted(_ word: String) -> [String] {
        var variants: [String] = []
        let chars = Array(word)
        for (i, ch) in chars.enumerated() {
            guard let s = decompose(ch), s.jong == 0 || s.jong == 20 else { continue }
            let past = s.jong == 20
            let expansions: [(vowel: Int, suffix: String)]
            switch s.vowel {
            case 0:  expansions = past ? [(0, "았")] : []              // 갔 → 가았
            case 1:  expansions = past ? [(1, "었")] : []              // 냈 → 내었
            case 4:  expansions = past ? [(4, "었")] : []              // 섰 → 서었
            case 6:  expansions = [(6, past ? "었" : "어"), (20, past ? "었" : "어")] // 켰, 마셔
            case 9:  expansions = [(8, past ? "았" : "아")]            // 봐 → 보아
            case 10: expansions = [(11, past ? "었" : "어")]           // 돼 → 되어
            case 14: expansions = [(13, past ? "었" : "어")]           // 줘 → 주어
            default: expansions = []
            }
            for e in expansions {
                variants.append(String(chars[..<i])
                                + String(compose(onset: s.onset, vowel: e.vowel, jong: 0))
                                + e.suffix + String(chars[(i + 1)...]))
            }
        }
        return variants
    }

    /// The irregular conjugations, one syllable at a time.
    private static func irregular(_ word: String) -> [String] {
        var out: [String] = []
        let chars = Array(word)
        func join(_ head: [Character], _ middle: String, _ tail: ArraySlice<Character>) -> String {
            String(head) + middle + String(tail)
        }
        for (i, ch) in chars.enumerated() {
            guard let s = decompose(ch) else { continue }
            let prev = i > 0 ? decompose(chars[i - 1]) : nil
            let next = i + 1 < chars.count ? decompose(chars[i + 1]) : nil
            let past = s.jong == 20
            let fused = s.jong == 0 || past
            let tail = chars[(i + 1)...]

            // ㅡ-deletion: 바빠 = 바쁘 + 아, 써 = 쓰 + 어, 바빴 = 바쁘 + 았.
            if fused, s.vowel == 0 || s.vowel == 4 {
                let suffix = s.vowel == 0 ? (past ? "았" : "아") : (past ? "었" : "어")
                let stem = String(compose(onset: s.onset, vowel: 18, jong: 0))
                out.append(join(Array(chars[..<i]), stem + suffix, tail))

                // 르-irregular: 몰라 = 모르 + 아 (the ㄹ moved onto the
                // previous syllable and 르 lost its vowel).
                if s.onset == 5, let p = prev, p.jong == 8 {
                    let head = Array(chars[..<(i - 1)])
                    let bare = String(compose(onset: p.onset, vowel: p.vowel, jong: 0))
                    out.append(join(head, bare + "르" + suffix, tail))
                }
            }

            // ㅂ-irregular: 가까워 = 가깝 + 어, 도와 = 돕 + 아, 가까웠 = 가깝 + 었.
            if i > 0, fused, s.onset == 11, s.vowel == 14 || s.vowel == 9,
               let p = prev, p.jong == 0 {
                let suffix = s.vowel == 14 ? (past ? "었" : "어") : (past ? "았" : "아")
                let head = Array(chars[..<(i - 1)])
                let withB = String(compose(onset: p.onset, vowel: p.vowel, jong: 17))
                out.append(join(head, withB + suffix, tail))
            }

            // ㅎ-irregular: 어때 = 어떻 + 어, 빨개 = 빨갛 + 아, 어땠 = 어떻 + 었.
            // Only past the first syllable: every ㅎ-adjective (그렇, 어떻,
            // 하얗, 노랗) has two, and a one-syllable 내 is not 넣어.
            if i > 0, fused, s.vowel == 1 || s.vowel == 3 {
                let options: [(Int, String)] = s.vowel == 1
                    ? [(4, past ? "었" : "어"), (0, past ? "았" : "아")]
                    : [(2, past ? "았" : "아")]
                for (vowel, suffix) in options {
                    let stem = String(compose(onset: s.onset, vowel: vowel, jong: 27))
                    out.append(join(Array(chars[..<i]), stem + suffix, tail))
                }
            }

            // ㄷ-irregular: 들어 = 듣 + 어, 걸었 = 걷 + 었 — a ㄹ before a
            // vowel-initial syllable may be a ㄷ.
            if s.jong == 8, let n = next, n.onset == 11, [0, 4, 18].contains(n.vowel) {
                let stem = String(compose(onset: s.onset, vowel: s.vowel, jong: 7))
                out.append(join(Array(chars[..<i]), stem, tail))
            }

            // ㅅ-irregular: 나아 = 낫 + 아, 지었 = 짓 + 었.
            if s.jong == 0, let n = next, n.onset == 11, [0, 4, 18].contains(n.vowel) {
                let stem = String(compose(onset: s.onset, vowel: s.vowel, jong: 19))
                out.append(join(Array(chars[..<i]), stem, tail))
            }
        }
        return out
    }

    // MARK: - Hangul

    private static func decompose(_ ch: Character) -> (onset: Int, vowel: Int, jong: Int)? {
        guard let scalar = ch.unicodeScalars.first,
              (0xAC00...0xD7A3).contains(scalar.value) else { return nil }
        let idx = Int(scalar.value) - 0xAC00
        return (idx / (21 * 28), (idx % (21 * 28)) / 28, idx % 28)
    }

    private static func compose(onset: Int, vowel: Int, jong: Int) -> Character {
        Character(UnicodeScalar(0xAC00 + (onset * 21 + vowel) * 28 + jong)!)
    }

    private static func isHangul(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        return (0xAC00...0xD7A3).contains(scalar.value)
    }
}
