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

    static func analyze(target: String, learner: String) -> ShadowAnalysis {
        let targetTokens = tokenize(target)
        let learnerTokens = tokenize(learner)

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

    static func systemPrompt(targetLanguage: String) -> String {
        """
        You are a strict but fair pronunciation + intonation coach for \(targetLanguage). \
        The learner shadowed a fluent line. You will be given:
          • target_line       — what they tried to say
          • learner_transcript — what on-device STT heard them say
          • duration_ratio    — learner_duration / target_duration
          • diff              — token-level alignment using [= match] [~ sub] [- del] [+ ins]

        Treat the diff as ground truth for which words diverged. If STT clearly \
        misheard (e.g. a homophone), say so plainly — don't penalize the learner \
        for STT errors. The numeric score is computed elsewhere, so do NOT include \
        one in your reply.

        Reply with STRICT JSON only — no prose, no code fences:
        { "pronunciation": "...", "pacing": "...", "fix": "..." }

        Rules:
        - "pronunciation": one sentence on pronunciation, citing specific tokens \
          from the diff. If the diff is all `=`, congratulate plainly.
        - "pacing": one sentence using duration_ratio. 0.85–1.15 ≈ healthy. \
          <0.85 = rushed, >1.15 = slow.
        - "fix": one concrete thing for the next attempt. Reference a specific \
          word or sound, not generic advice ("stress the second syllable in X", \
          not "speak more clearly").
        - Each field ≤ 22 words.
        - If learner_transcript is empty, say "I didn't catch anything — try again \
          closer to the mic" in "pronunciation".
        """
    }

    static func userMessage(
        targetText: String,
        learnerText: String,
        targetDurationMs: Int,
        learnerDurationMs: Int,
        diffSteps: [DiffStep]
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
        """
    }

    // MARK: - Internals

    /// Lowercase + strip punctuation; collapses contractions like "don't" to
    /// a single token. Comparison is case- and punctuation-insensitive.
    private static func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'-")).inverted)
            .filter { !$0.isEmpty }
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
