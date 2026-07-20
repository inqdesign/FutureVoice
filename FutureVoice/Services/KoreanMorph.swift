import Foundation

/// Deterministic Korean surface-form → dictionary-form matching, for vocab
/// tracking against the graded wordlist (whose headwords are dictionary
/// forms: 가다, 학교, 가깝다 …).
///
/// This is a HEURISTIC, not a morphological analyzer: it generates candidate
/// dictionary forms (particle-stripped nouns, ending-stripped verbs + 다) and
/// the caller keeps only candidates that exist in the lexicon. Wrong guesses
/// therefore cost recall, never precision — "마셔요" may fail to map back to
/// 마시다 (vowel contraction), but nothing maps to a word the user didn't use.
enum KoreanMorph {

    /// Josa (particles) that attach to nouns — longest first so 에서부터
    /// wins over 부터. Stripping happens at most twice (학교에서도).
    private static let particles = [
        "에서부터", "으로부터", "한테서", "에게서", "이라고",
        "께서", "에서", "에게", "한테", "부터", "까지", "처럼",
        "보다", "마다", "조차", "마저", "밖에", "으로", "이나", "이란",
        "라고", "라는", "이랑",
        "은", "는", "이", "가", "을", "를", "에", "의", "도", "만",
        "와", "과", "랑", "로", "나", "요"
    ].sorted { $0.count > $1.count }

    /// Common verb/adjective endings; the remaining stem + 다 is the
    /// dictionary-form guess (먹었어요 → 먹 + 다 → 먹다).
    private static let verbEndings = [
        "었습니다", "았습니다", "였습니다", "겠습니다",
        "습니다", "ㅂ니다",
        "었어요", "았어요", "였어요", "겠어요", "었네요", "았네요",
        "었는데", "았는데", "었지만", "았지만",
        "어요", "아요", "여요", "네요", "지요", "는데", "니까", "면서",
        "었다", "았다", "였다", "겠다",
        "고", "지", "죠", "어", "아", "여", "게", "며", "면", "다"
    ].sorted { $0.count > $1.count }

    /// Ordered dictionary-form candidates for one token, most likely first.
    /// The token itself always leads — many wordlist entries (명사, 부사) are
    /// their own surface form. Verb guesses come before the SECOND layer of
    /// particle stripping: double-stripping happily reduces a conjugated verb
    /// to an unrelated short noun (도와요 → 도), while a verb guess only wins
    /// when its dictionary form really exists.
    static func candidates(for raw: String) -> [String] {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 1, token.allSatisfy(isHangul) else { return [] }
        var out: [String] = [token]

        // Noun + one particle (학교에서 → 학교).
        let onceStripped = strippingParticle(from: token)
        if let onceStripped { out.append(onceStripped) }

        // Conjugated verb/adjective → stem + 다. Vowel contractions hide the
        // stem (갔어요 = 가+았어요, 마셔요 = 마시+어요, 했 = 하+였) — undo
        // them first, then strip the ending.
        var bases = [token]
        bases.append(contentsOf: decontracted(token))
        bases.append(contentsOf: uncontractedHae(token))
        for base in bases {
            for ending in verbEndings where base.count > ending.count {
                if base.hasSuffix(ending) {
                    let stem = String(base.dropLast(ending.count))
                    out.append(stem + "다")
                    break   // longest matching ending only
                }
            }
        }

        // Second particle layer last (집에서도 → 집에서 → 집).
        if let onceStripped, let twiceStripped = strippingParticle(from: onceStripped) {
            out.append(twiceStripped)
        }
        var seen = Set<String>()
        return out.filter { $0.count >= 1 && seen.insert($0).inserted }
    }

    /// First candidate that exists in the lexicon, or nil.
    static func dictionaryForm(of token: String, in lexicon: Set<String>) -> String? {
        candidates(for: token).first { lexicon.contains($0) }
    }

    private static func strippingParticle(from word: String) -> String? {
        for p in particles where word.count > p.count {
            if word.hasSuffix(p) { return String(word.dropLast(p.count)) }
        }
        return nil
    }

    /// 하다-verb contractions of 하 + 여(써): 했 = 하였 (일했어요 → 일하다),
    /// 해 = 하여 (사랑해요 → 사랑하다). Returns both expansions when present so
    /// the ending stripper can recover the 하다 stem.
    private static func uncontractedHae(_ word: String) -> [String] {
        var out: [String] = []
        if let r = word.range(of: "했") {
            out.append(word.replacingCharacters(in: r, with: "하였"))
        }
        if let r = word.range(of: "해") {
            out.append(word.replacingCharacters(in: r, with: "하여"))
        }
        return out
    }

    // MARK: - Vowel-contraction undo

    /// Variants of `word` with one contracted syllable expanded back to
    /// stem-vowel + 아/어 (갔 → 가았, 봤 → 보았, 줬 → 주었, 마셔 → 마시어)
    /// plus the ㅂ-irregular re-fold (가까워 → 가깝어, 도와 → 돕아). All are
    /// GUESSES — the lexicon gate downstream discards the wrong ones.
    private static func decontracted(_ word: String) -> [String] {
        var variants: [String] = []
        let chars = Array(word)
        for (i, ch) in chars.enumerated() {
            guard let s = decompose(ch) else { continue }

            // Syllable with ㅆ final = fused 았/었: split by the vowel.
            if s.jong == 20 {   // ㅆ
                let expansions: [(vowel: Int, suffix: String)]
                switch s.vowel {
                case 0:  expansions = [(0, "았")]            // ㅏ  갔 → 가았
                case 1:  expansions = [(1, "었")]            // ㅐ  냈 → 내었
                case 4:  expansions = [(4, "었")]            // ㅓ  섰 → 서었
                case 6:  expansions = [(6, "었"), (20, "었")] // ㅕ  켰 → 켜었 / 마셨 → 마시었
                case 9:  expansions = [(8, "았")]            // ㅘ  봤 → 보았
                case 10: expansions = [(11, "었")]           // ㅙ  됐 → 되었
                case 14: expansions = [(13, "었")]           // ㅝ  줬 → 주었
                default: expansions = []
                }
                for e in expansions {
                    var v = chars
                    v[i] = compose(onset: s.onset, vowel: e.vowel, jong: 0)
                    variants.append(String(v[0..<i+1]) + e.suffix + String(v[(i+1)...]))
                }
            }

            // ㅕ without final: 마셔요 → 마시어요.
            if s.jong == 0, s.vowel == 6 {
                var v = chars
                v[i] = compose(onset: s.onset, vowel: 20, jong: 0)   // ㅣ
                variants.append(String(v[0..<i+1]) + "어" + String(v[(i+1)...]))
            }

            // ㅂ-irregular: 워/와 after another syllable = stem-final ㅂ
            // (가까워 → 가깝 + 어, 도와 → 돕 + 아).
            if i > 0, s.jong == 0, s.onset == 11 {   // onset ㅇ
                let suffix: String?
                switch s.vowel {
                case 14: suffix = "어"   // 워
                case 9:  suffix = "아"   // 와
                default: suffix = nil
                }
                if let suffix, let prev = decompose(chars[i - 1]), prev.jong == 0 {
                    var v = chars
                    v[i - 1] = compose(onset: prev.onset, vowel: prev.vowel, jong: 17)  // +ㅂ
                    variants.append(String(v[0..<i]) + suffix + String(v[(i+1)...]))
                }
            }
        }
        return variants
    }

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
