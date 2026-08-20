import Foundation

/// Shadow-attempt scoring. The match score is computed **deterministically**
/// (token-level Levenshtein → 0–100) so the user gets a real number, not an
/// LLM vibe. The LLM only produces the three qualitative bullets, anchored to
/// the same token diff so its feedback can cite actual differing words instead
/// of inventing.
enum ShadowEngine {

    // MARK: - Deterministic scoring

    enum DiffOp: String, Codable, Hashable {
        case match, sub, ins, del
    }

    /// One aligned step between target and learner token streams.
    /// - `match`: both present and equal (after normalization).
    /// - `sub`: both present, differ.
    /// - `del`: target word with no learner counterpart (learner skipped it).
    /// - `ins`: learner word with no target counterpart (learner added it).
    struct DiffStep: Hashable {
        let op: DiffOp
        let target: String?
        let learner: String?
    }

    struct ShadowAnalysis {
        let score: Int                  // 0–100, deterministic
        let steps: [DiffStep]
        let targetTokenCount: Int
        let learnerTokenCount: Int
        let matchCount: Int
    }

    /// `language` picks the token unit via LanguageCatalog: word for
    /// space-delimited scripts, character for CJK (where STT spacing is
    /// absent or unstable). Defaults to word so existing behavior holds.
    static func analyze(target: String, learner: String, language: String = "en") -> ShadowAnalysis {
        let style = LanguageCatalog.tokenStyle(language)
        let targetTokens = tokenize(expandForDiff(target, language: language), style: style)
        let learnerTokens = tokenize(expandForDiff(learner, language: language), style: style)

        let (matches, steps) = align(targetTokens, learnerTokens)
        let denom = max(targetTokens.count, learnerTokens.count)
        let raw = denom > 0 ? Double(matches) / Double(denom) : 0
        // Reanchor: 90+ excellent, 75 good, <60 noticeable. A pure
        // proportion already lives in 0–1; we soften the bottom by mapping
        // sqrt so single-word slips don't crater an otherwise good attempt.
        let curved = raw.squareRoot()
        let score = max(0, min(100, Int((curved * 100).rounded())))
        return ShadowAnalysis(
            score: score,
            steps: steps,
            targetTokenCount: targetTokens.count,
            learnerTokenCount: learnerTokens.count,
            matchCount: matches
        )
    }

    /// Which diff tokens each SPOKEN word of a line occupies.
    ///
    /// The diff runs on `expandForDiff` output, which splits hyphens, expands
    /// contractions and spells out digits — so "Speech-to-text" is ONE word in
    /// the word map and THREE tokens in the diff, and every index mapped
    /// straight across after it is off by two (measured: the karaoke line
    /// coloured "but" for a substitution the diff had recorded on "glitchy").
    /// Every transform in `expandForDiff` stays inside a whitespace-delimited
    /// word, so tokenizing each word on its own reproduces the same stream in
    /// the same order — with the boundaries still known.
    ///
    /// Returns one range per input word, indexing into the token stream
    /// `analyze` diffed. A word that contributes no tokens (a bare "—") keeps
    /// an empty range at its position instead of being dropped, so callers can
    /// still index by word.
    static func tokenSpans(for words: [String], language: String = "en") -> [Range<Int>] {
        let style = LanguageCatalog.tokenStyle(language)
        var out: [Range<Int>] = []
        var cursor = 0
        for word in words {
            let count = tokenize(expandForDiff(word, language: language), style: style).count
            out.append(cursor..<(cursor + count))
            cursor += count
        }
        return out
    }

    /// Diff ops in TARGET order — one per target slot, `ins` skipped (it holds
    /// no target word). Indexes line up with `tokenSpans`' ranges.
    static func targetOps(_ steps: [DiffStep]) -> [DiffOp] {
        steps.filter { $0.op != .ins }.map(\.op)
    }

    // MARK: - Rhythm (deterministic)

    /// One target word the learner also said (diff `match` or `sub`), with
    /// its onset in both timelines. `deviationMs` is how far off the beat the
    /// learner's onset was AFTER pace normalization — positive = behind
    /// (late), negative = ahead (early). Pace itself is judged separately by
    /// the duration ratio, so rhythm only measures the *shape* of the timing.
    struct RhythmWord: Hashable {
        let word: String
        /// Index of the word in the practiced target range (0-based).
        let targetIndex: Int
        /// Onset relative to the first paired word, target timeline (ms).
        let targetOnsetMs: Int
        /// Learner onset mapped onto the target timeline (pace-normalized, ms).
        let learnerOnsetMs: Int
        var deviationMs: Int { learnerOnsetMs - targetOnsetMs }
        /// Word span in the target timeline, for proportional rendering.
        let targetDurationMs: Int
        /// Learner word span, pace-normalized (ms).
        let learnerDurationMs: Int
    }

    struct RhythmAnalysis: Hashable {
        let score: Int              // 0–100, deterministic
        let words: [RhythmWord]
        /// Full extent of the target timeline covered by paired words (ms),
        /// measured from the first paired onset to the last paired word end.
        let targetSpanMs: Int
    }

    /// Full-credit half-width: onsets within ±this of the beat score 1.0.
    private static let rhythmGraceMs = 60.0
    /// Deviations at/after grace+this score 0. Linear in between.
    private static let rhythmRampMs = 400.0

    /// Per-word grade thresholds, shared with the UI so colors and score
    /// always agree. |deviation| ≤ 120ms feels on-beat in casual speech;
    /// beyond 300ms is unmistakably off.
    static func rhythmGrade(deviationMs: Int) -> Int {
        switch abs(deviationMs) {
        case ...120:  return 2   // on beat
        case ...300:  return 1   // slightly off
        default:      return 0   // off
        }
    }

    /// Deterministic rhythm comparison between the target line's word onsets
    /// and the learner's (from final file recognition).
    ///
    /// Pairing walks the diff: a target slot (`match`/`sub`/`del`) consumes
    /// one target TOKEN, a learner slot (`match`/`sub`/`ins`) consumes one
    /// learner token; `match` AND `sub` pairs both count — an STT soundalike
    /// still tells us WHEN the learner hit that slot. Tokens are then folded
    /// back onto WORDS through `tokenSpans`, because that is what a timing is:
    /// "Speech-to-text" carries one onset and three diff tokens, and a slot
    /// consuming one timing each drifted out of the array and returned nil for
    /// every line with a hyphen, a contraction or a number in it. A word takes
    /// the FIRST learner word it was paired with, and no learner word is used
    /// twice.
    ///
    /// Guards mirror `LocalAlignment`'s philosophy: if the token stream and
    /// the word spans don't account for each other exactly, return nil (never
    /// show wrong data); likewise under 3 pairs.
    ///
    /// Normalization: both timelines are re-zeroed on their first paired
    /// onset, then the learner timeline is scaled by targetSpan/learnerSpan.
    /// A uniformly slower attempt therefore scores 100 — overall speed is the
    /// duration card's job; rhythm grades only relative word placement.
    static func analyzeRhythm(
        steps: [DiffStep],
        targetTimings: [WordTiming],
        learnerTimings: [WordTiming],
        language: String = "en"
    ) -> RhythmAnalysis? {
        // token index → index of the word that owns it, both sides.
        func wordOfToken(_ words: [String]) -> [Int] {
            var out: [Int] = []
            for (i, span) in tokenSpans(for: words, language: language).enumerated() {
                out.append(contentsOf: Array(repeating: i, count: span.count))
            }
            return out
        }
        let targetWordOf = wordOfToken(targetTimings.map(\.word))
        let learnerWordOf = wordOfToken(learnerTimings.map(\.word))

        var pairs: [(targetIndex: Int, target: WordTiming, learner: WordTiming)] = []
        var pairedTargets = Set<Int>(), pairedLearners = Set<Int>()
        var t = 0, l = 0
        for step in steps {
            switch step.op {
            case .match, .sub:
                guard t < targetWordOf.count, l < learnerWordOf.count else { return nil }
                let tw = targetWordOf[t], lw = learnerWordOf[l]
                if !pairedTargets.contains(tw), !pairedLearners.contains(lw) {
                    pairs.append((tw, targetTimings[tw], learnerTimings[lw]))
                    pairedTargets.insert(tw); pairedLearners.insert(lw)
                }
                t += 1; l += 1
            case .del:
                guard t < targetWordOf.count else { return nil }
                t += 1
            case .ins:
                guard l < learnerWordOf.count else { return nil }
                l += 1
            }
        }
        // Slots must consume BOTH token streams exactly — anything else means
        // the diff and the timings are describing different text.
        guard t == targetWordOf.count, l == learnerWordOf.count,
              pairs.count >= 3 else { return nil }

        let t0 = pairs[0].target.startMs
        let l0 = pairs[0].learner.startMs
        guard let lastPair = pairs.last else { return nil }
        let targetSpan = lastPair.target.startMs - t0
        let learnerSpan = lastPair.learner.startMs - l0
        guard targetSpan > 0, learnerSpan > 0 else { return nil }
        let scale = Double(targetSpan) / Double(learnerSpan)

        let words = pairs.map { pair in
            RhythmWord(
                word: pair.target.word,
                targetIndex: pair.targetIndex,
                targetOnsetMs: pair.target.startMs - t0,
                learnerOnsetMs: Int((Double(pair.learner.startMs - l0) * scale).rounded()),
                targetDurationMs: max(0, pair.target.endMs - pair.target.startMs),
                learnerDurationMs: max(0, Int((Double(pair.learner.endMs - pair.learner.startMs) * scale).rounded()))
            )
        }

        // Continuous per-word credit: 1.0 inside ±graceMs, fading linearly to
        // 0 at grace+ramp. Mean × 100 → score. First/last words pin the
        // normalization (deviation 0), which slightly flatters short lines —
        // acceptable next to the ≥3-pair guard.
        let credits = words.map { w -> Double in
            let over = max(0, Double(abs(w.deviationMs)) - rhythmGraceMs)
            return max(0, 1 - over / rhythmRampMs)
        }
        let mean = credits.reduce(0, +) / Double(credits.count)
        let score = max(0, min(100, Int((mean * 100).rounded())))
        let spanEnd = lastPair.target.endMs - t0
        return RhythmAnalysis(score: score, words: words, targetSpanMs: max(spanEnd, targetSpan))
    }

    /// Compact rhythm evidence for the coach prompt — only meaningfully
    /// off-beat words, e.g. `[weather +180] [is -240]` (+ = late, − = early).
    static func renderRhythmForPrompt(_ rhythm: RhythmAnalysis?) -> String {
        guard let rhythm else { return "n/a" }
        let off = rhythm.words.filter { rhythmGrade(deviationMs: $0.deviationMs) < 2 }
        guard !off.isEmpty else { return "all words on beat" }
        return off.map { w in
            String(format: "[%@ %+dms]", w.word, w.deviationMs)
        }.joined(separator: " ")
    }

    /// Compact rendering of the diff to inline into the prompt as evidence.
    /// Format example: `[= the] [= weather] [~ today/to-day] [- is] [+ uh]`.
    static func renderDiffForPrompt(_ steps: [DiffStep]) -> String {
        steps.map { step in
            switch step.op {
            case .match:
                return "[= \(step.target ?? "")]"
            case .sub:
                return "[~ \(step.target ?? "")/\(step.learner ?? "")]"
            case .del:
                return "[- \(step.target ?? "")]"
            case .ins:
                return "[+ \(step.learner ?? "")]"
            }
        }.joined(separator: " ")
    }

    // MARK: - LLM prompt (qualitative bullets only)

    /// Wire shape returned by Gemini.
    struct Payload: Decodable {
        let pronunciation: String
        let pacing: String
        let fix: String
    }

    static func systemPrompt(targetLanguage: String,
                             nativeLanguage: String = LanguageCatalog.currentNative) -> String {
        let nativeName = LanguageCatalog.englishName(nativeLanguage)
        return """
        You are a strict but fair pronunciation + delivery coach for \(LanguageCatalog.englishName(targetLanguage)). \
        The learner shadowed a fluent line. You will be given:
          • target_line       — what they tried to say
          • learner_transcript — what on-device STT heard them say
          • duration_ratio    — learner_duration / target_duration
          • diff              — token-level alignment using [= match] [~ sub] [- del] [+ ins]
          • rhythm            — per-word onset deviation after pace \
        normalization, computed from measured audio timestamps. \
        [word +Nms] = the learner hit that word N ms LATE relative to the \
        target's rhythm, [word -Nms] = early. Only off-beat words are listed. \
        May be "n/a" when timing extraction failed.

        Treat the diff as ground truth for which words diverged. If STT clearly \
        misheard (e.g. a homophone), say so plainly — don't penalize the learner \
        for STT errors. The numeric score is computed elsewhere, so do NOT include \
        one in your reply.

        Reply with STRICT JSON only — no prose, no code fences:
        { "pronunciation": "...", "pacing": "...", "fix": "..." }

        Rules:
        - LANGUAGE: write all three fields in \(nativeName). This is coaching \
          the learner reads between attempts, not material they speak — in the \
          practice language it just gets skipped. Words and sounds you cite \
          from the diff stay in their original spelling, quoted inside the \
          \(nativeName) sentence, never transliterated or translated.
        - "pronunciation": one sentence on pronunciation, citing specific tokens \
          from the diff. If the diff is all `=`, congratulate plainly.
        - "pacing": one sentence. Use duration_ratio for overall speed \
          (0.85–1.25 ≈ healthy, <0.85 = rushed, >1.25 = slow — matches the \
          duration card in the UI) and, when rhythm data is present, cite the \
          most off-beat word(s) by name ("you land late on X"). Base timing \
          claims ONLY on duration_ratio and rhythm — you have no pitch data, \
          so never claim to hear intonation, melody, or emphasis.
        - "fix": one concrete thing for the next attempt. Reference a specific \
          word or sound, not generic advice ("stress the second syllable in X", \
          not "speak more clearly").
        - Each field ≤ 22 words.
        - If learner_transcript is empty, put the \(nativeName) equivalent of \
          "I didn't catch anything — try again closer to the mic" in \
          "pronunciation".
        """
    }

    static func userMessage(
        targetText: String,
        learnerText: String,
        targetDurationMs: Int,
        learnerDurationMs: Int,
        diffSteps: [DiffStep],
        rhythm: RhythmAnalysis? = nil
    ) -> String {
        let ratio: String
        if targetDurationMs > 0 {
            ratio = String(format: "%.2f", Double(learnerDurationMs) / Double(targetDurationMs))
        } else {
            ratio = "n/a"
        }
        return """
        target_line: \(targetText)
        learner_transcript: \(learnerText.isEmpty ? "(empty)" : learnerText)
        target_duration_ms: \(targetDurationMs)
        learner_duration_ms: \(learnerDurationMs)
        duration_ratio: \(ratio)
        diff: \(renderDiffForPrompt(diffSteps))
        rhythm: \(renderRhythmForPrompt(rhythm))
        """
    }

    // MARK: - Internals

    /// Canonicalize surface forms that STT and written text spell differently
    /// so they never register as substitutions: digit runs become the
    /// language's spelled-out number ("20" → "twenty" / "이십"), and English
    /// contractions expand ("I'm" → "i am", "won't" → "will not"). Applied to
    /// BOTH sides before tokenizing, so whichever convention each side used,
    /// they meet in the middle. The rendered diff already shows lowercased
    /// tokens, so expanded forms are consistent with the existing display.
    static func expandForDiff(_ text: String, language: String) -> String {
        var out = text.lowercased()
        // Hyphens → spaces so "twenty-one"/"check-in" (written) match
        // "twenty one"/"check in" (how STT writes them). Spell-out below
        // strips its own hyphens at insertion for the same reason.
        out = out.replacingOccurrences(of: "-", with: " ")

        // Digits → spell-out in the practice language. Word-ish digit runs
        // only; anything NumberFormatter can't parse is left alone.
        if let re = try? NSRegularExpression(pattern: #"\d+"#) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .spellOut
            formatter.locale = Locale(identifier: language)
            let matches = re.matches(in: out, range: NSRange(out.startIndex..., in: out))
            for m in matches.reversed() {
                guard let r = Range(m.range, in: out),
                      let n = Int(out[r]),
                      let spelled = formatter.string(from: NSNumber(value: n)) else { continue }
                let flat = spelled.lowercased().replacingOccurrences(of: "-", with: " ")
                out.replaceSubrange(r, with: " \(flat) ")
            }
        }

        guard language.hasPrefix("en") else { return out }
        // Irregulars first, then generic suffixes. "'s"/"'d" are ambiguous
        // (is/has, would/had) but expand identically on both sides, so the
        // comparison stays symmetric even when the gloss is wrong. The
        // colloquial merges matter for DELETIONS: STT writing "wanna" for a
        // learner who said "want to" scored "to" as a word they never said.
        let irregular: [(String, String)] = [
            ("won't", "will not"), ("can't", "can not"), ("cannot", "can not"),
            ("shan't", "shall not"), ("let's", "let us"), ("y'all", "you all"),
            ("wanna", "want to"), ("gonna", "going to"), ("gotta", "got to"),
            ("lemme", "let me"), ("gimme", "give me"), ("kinda", "kind of"),
            ("sorta", "sort of"), ("outta", "out of"), ("dunno", "do not know"),
            ("'cause", "because"), ("cuz", "because"),
        ]
        for (from, to) in irregular {
            // Lookarounds instead of \b: apostrophe-initial forms ("'cause")
            // have no word boundary between the space and the apostrophe.
            out = out.replacingOccurrences(
                of: "(?<![a-z])\(from)(?![a-z])", with: to, options: .regularExpression)
        }
        let suffixes: [(String, String)] = [
            ("n't", " not"), ("'re", " are"), ("'m", " am"), ("'ve", " have"),
            ("'ll", " will"), ("'d", " would"), ("'s", " is"),
        ]
        for (suffix, expansion) in suffixes {
            out = out.replacingOccurrences(
                of: "(?<=[a-z])\(suffix)\\b", with: expansion,
                options: .regularExpression)
        }
        return out
    }

    /// Lowercase + strip punctuation; collapses contractions like "don't" to
    /// a single token. Comparison is case- and punctuation-insensitive.
    /// `.syllable` further splits each word into single characters, so CJK
    /// attempts are compared syllable-by-syllable regardless of how the STT
    /// chose to space them.
    private static func tokenize(_ text: String, style: LanguageCatalog.TokenStyle) -> [String] {
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'-")).inverted)
            .filter { !$0.isEmpty }
        switch style {
        case .word:     return words
        case .syllable: return words.flatMap { $0.map(String.init) }
        }
    }

    /// Standard DP edit-distance alignment over token arrays. Returns the
    /// match count and a step list traceable to the original (non-normalized)
    /// tokens — we keep both inputs as-tokenized so the rendered diff matches
    /// what the user actually sees.
    private static func align(_ a: [String], _ b: [String]) -> (Int, [DiffStep]) {
        let n = a.count, m = b.count
        if n == 0 && m == 0 { return (0, []) }

        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        for i in 1...max(n, 1) where i <= n {
            for j in 1...max(m, 1) where j <= m {
                if a[i-1] == b[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = 1 + min(dp[i-1][j-1], dp[i-1][j], dp[i][j-1])
                }
            }
        }

        var steps: [DiffStep] = []
        var matches = 0
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && a[i-1] == b[j-1] {
                steps.append(DiffStep(op: .match, target: a[i-1], learner: b[j-1]))
                matches += 1
                i -= 1; j -= 1
            } else if i > 0 && j > 0 && dp[i][j] == dp[i-1][j-1] + 1 {
                steps.append(DiffStep(op: .sub, target: a[i-1], learner: b[j-1]))
                i -= 1; j -= 1
            } else if i > 0 && (j == 0 || dp[i][j] == dp[i-1][j] + 1) {
                steps.append(DiffStep(op: .del, target: a[i-1], learner: nil))
                i -= 1
            } else {
                steps.append(DiffStep(op: .ins, target: nil, learner: b[j-1]))
                j -= 1
            }
        }
        steps.reverse()
        return (matches, steps)
    }
}
