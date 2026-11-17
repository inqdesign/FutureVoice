import Foundation

/// "That wasn't me" said out loud (2026-11-17).
///
/// A learner's mic picked up a stranger on the street ("She is here for six
/// month."). The call answered it, corrected it, and the next call opened on
/// it; she said twice that the line was not hers and nothing could act on
/// that. The only retraction was a swipe on the transcript page after the
/// call. Now a learner's line that says an earlier line was misheard, or was
/// another voice, flags that line the way the swipe does: out of every
/// score, its cards deleted, out of the next call's record.
///
/// Two steps, because almost no turn is a retraction: a word check in code
/// picks the few turns worth asking about (`mayRetract`), and one small model
/// call decides which line they mean (`retractedLine`). No retraction is the
/// usual answer; a wrong yes takes a real line out of the learner's score, so
/// the judge is told to say none when unsure.
enum MisheardJudge {

    /// An earlier line the learner may be pointing at, with the reply it got.
    struct Candidate: Equatable {
        let turnId: UUID
        let sessionId: UUID
        let said: String
        let reply: String
    }

    /// Could this line be a retraction? Words a learner uses for it, in every
    /// target language and the native ones most learners here speak (they
    /// drop into their own language exactly when something went wrong).
    /// Wide on purpose: a miss means the line is never judged at all.
    static func mayRetract(_ text: String) -> Bool {
        let t = text.lowercased()
        return hints.contains { t.contains($0) }
    }

    private static let hints: [String] = [
        // en
        "misheard", "mishear", "heard wrong", "heard me wrong", "heard it wrong", "wasn't me", "was not me",
        "not me ", "not my voice", "didn't say", "did not say", "never said", "not what i said",
        "someone else", "somebody else", "other people", "another person", "background", "noise",
        // ko
        "잘못 들", "잘못들", "내가 한 말", "내 말이 아니", "내 목소리", "소음", "다른 사람", "말 안 했", "말한 적",
        "그런 말 안", "옆에서", "옆 사람",
        // ja
        "聞き間違", "言ってない", "言っていない", "言ってません", "私じゃ", "僕じゃ", "俺じゃ", "私の声", "雑音",
        "他の人", "周りの",
        // de
        "verhört", "falsch verstanden", "falsch gehört", "nicht gesagt", "nie gesagt", "war ich nicht",
        "nicht meine stimme", "jemand anders", "jemand anderes", "hintergrund", "geräusch",
        // es
        "no dije", "no he dicho", "no fui yo", "no era yo", "no es mi voz", "otra persona", "oíste mal",
        "escuchaste mal", "entendiste mal", "ruido",
        // fr
        "pas dit", "pas moi", "pas ma voix", "quelqu'un d'autre", "mal entendu", "mal compris", "bruit",
        // zh
        "没说", "沒說", "不是我", "听错", "聽錯", "别人", "別人", "噪音", "杂音",
    ]

    static let system = """
        A language learner is on a voice call. Speech recognition writes down \
        what they say, and it sometimes mishears them or writes down another \
        voice near them (a passer-by, a TV) as if it were theirs.
        You get numbered earlier lines that were written down as the \
        learner's, each with the reply it got, and then the learner's newest \
        line. Decide whether the newest line says that ONE of the numbered \
        lines was not what they said: misheard, or not their voice at all.
        It counts only when they are disowning the WORDS: "I didn't say \
        that", "that was someone else", "you misheard me". It does not count \
        when they said it and now think differently ("I didn't mean it", \
        "actually, no"), when they correct a fact inside something they did \
        say, when they complain that the reply misunderstood their point, or \
        when they talk about noise without disowning a line.
        Pick the line by what they point at: its words, its subject, or \
        "what you just heard" (the latest numbered line). If they disown a \
        line that is not in the list, or you are not sure which one, answer \
        none.
        Return {"line": <number>} or {"line": null}.
        """

    static func content(candidates: [Candidate], newest: String) -> String {
        let lines = candidates.enumerated().map { i, c in
            "\(i + 1). learner: \"\(clip(c.said))\"\n   reply: \"\(clip(c.reply))\""
        }.joined(separator: "\n")
        return "Earlier lines, oldest first:\n\(lines)\n\nNewest line from the learner: \"\(clip(newest, 400))\""
    }

    private static func clip(_ s: String, _ max: Int = 220) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= max ? t : String(t.prefix(max - 1)) + "…"
    }

    private struct Verdict: Decodable { let line: Int? }

    /// Which candidate the newest line disowns, or nil. Free (`coach`).
    static func retractedLine(newest: String, candidates: [Candidate], turnId: UUID) async -> Candidate? {
        guard !candidates.isEmpty else { return nil }
        let v: Verdict? = try? await GeminiClient.background.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: content(candidates: candidates, newest: newest))],
            model: .flashLite31, maxTokens: 100, purpose: "coach",
            idempotencyKey: "misheard:\(turnId.uuidString)", requestTimeout: 8,
            fastThinking: true)
        guard let n = v?.line, candidates.indices.contains(n - 1) else { return nil }
        return candidates[n - 1]
    }
}
