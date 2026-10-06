import Foundation

/// Whole-turn rewrites written for "Say it again" AFTER the talk, for the
/// learner turns the call itself left without one.
///
/// A turn can reach the book with no whole-turn rewrite in two ways: it was
/// saved before 2026-09-27, when `alternative` was a ≤15-word fragment that
/// `SayItAgainScript.coversWholeTurn` rightly refuses, or the live correction
/// call simply failed — it runs in the background mid-call and its failure
/// was invisible. Either way the prompter fell back to what they SAID, fillers
/// and false starts included (reported 2026-10-06 from a 90-word turn), which
/// is the one screen whose whole point is saying it the better way.
///
/// **Kept OUT of the session on purpose.** Writing a suggestion into the turn
/// would put new `fixes` in front of every reader of "the correction": the
/// talk book's Drill chapter would grow items whose cards `DrillStore.ingest`
/// never minted (ingest ran at the talk's end), so the book could never be
/// finished, and sync would carry a rewrite the other device never asked for.
/// Here it is practice text only: the prompter reads it, nothing is filed
/// under it (`attemptId` nil), and the book is untouched. Device-local, a
/// cache — losing it costs one call on the next open.
///
/// The prompt is the live call's own `correctionOnlyPrompt`, one turn per
/// request with the line said to them as context — the exact contract
/// `scripts/correction-probe.py` measured; a batched prompt would be a new,
/// unmeasured one.
@MainActor
final class SayItAgainRewrites {
    static let shared = SayItAgainRewrites()

    /// `alternative` nil = asked, and the line needed nothing. Remembered so
    /// a clean turn is not asked again on every open.
    struct Entry: Codable, Hashable {
        var alternative: String?
        var reason: String
    }

    /// Lines in flight at once. Enough that a 20-turn talk is ready before
    /// the first answer finishes playing; few enough not to look like a burst.
    static let concurrency = 4

    private var entries: [String: Entry]
    private let url: URL

    private init() {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("say_again_rewrites.json")
        entries = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func entry(for turnId: UUID) -> Entry? { entries[turnId.uuidString] }

    var all: [UUID: Entry] {
        entries.reduce(into: [:]) { out, pair in
            if let id = UUID(uuidString: pair.key) { out[id] = pair.value }
        }
    }

    /// Learner turns the script would read as said because the call left no
    /// whole-turn rewrite, and that haven't been asked about here yet.
    func missing(in session: Session) -> [UUID] {
        session.turns.compactMap { turn in
            guard turn.role == .user, !turn.excludedFromScoring,
                  entries[turn.id.uuidString] == nil else { return nil }
            let said = turn.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            // The live path's own floor: a two-word answer has nothing to re-say.
            guard WordSplitter.count(said) >= 3 else { return nil }
            let rewrite = (turn.suggestion?.alternative ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !rewrite.isEmpty,
               SayItAgainScript.coversWholeTurn(rewrite, said: said,
                                                fromWholeTurnContract: turn.suggestion?.fixes != nil) {
                return nil
            }
            return turn.id
        }
    }

    /// Ask for every missing turn and remember the answers. Returns once all
    /// have landed or failed; a failed one stays missing and is asked again
    /// on the next open.
    func fill(session: Session, nativeLanguage: String, level: CEFRLevel) async {
        let ids = Set(missing(in: session))
        guard !ids.isEmpty else { return }
        var jobs: [(id: UUID, said: String, heard: String)] = []
        var lastHeard = ""
        for turn in session.turns {
            let text = turn.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if turn.role == .fluentSelf { lastHeard = text; continue }
            if ids.contains(turn.id) { jobs.append((turn.id, text, lastHeard)) }
        }
        let counterpart = session.counterpartId.flatMap { id in
            CounterpartStore.shared.load().first { $0.id == id }
        }
        let system = ConversationEngine.correctionOnlyPrompt(
            targetLanguage: session.targetLanguage, nativeLanguage: nativeLanguage,
            level: level, counterpart: counterpart,
            inScene: session.originScenarioId != nil)

        var failed = 0
        var filled = 0
        await withTaskGroup(of: (UUID, Entry?).self) { group in
            var next = 0
            func add() {
                guard next < jobs.count else { return }
                let job = jobs[next]
                next += 1
                group.addTask {
                    let entry = await Self.ask(system: system, said: job.said, heard: job.heard,
                                               turnId: job.id)
                    return (job.id, entry)
                }
            }
            for _ in 0..<Self.concurrency { add() }
            while let (id, entry) = await group.next() {
                if let entry {
                    entries[id.uuidString] = entry
                    if entry.alternative != nil { filled += 1 }
                } else {
                    failed += 1
                }
                add()
            }
        }
        save()
        Telemetry.log("say_again_fill", [
            "asked": String(jobs.count),
            "filled": String(filled),
            "failed": String(failed),
        ])
    }

    /// One turn, through the same gate the live call's answer goes through
    /// (`turnSuggestion`): a fix that isn't theirs or a rewrite that changes
    /// nothing audible never reaches the prompter. Nil = the call failed.
    nonisolated private static func ask(system: String, said: String, heard: String,
                                        turnId: UUID) async -> Entry? {
        let content = heard.isEmpty
            ? "They said: \"\(said)\""
            : "They were just told: \"\(heard)\"\nThey said: \"\(said)\""
        do {
            let payload: ConversationTurnPayload = try await GeminiClient.shared.sendJSON(
                system: system,
                messages: [GeminiClient.Message(role: .user, content: content)],
                maxTokens: 2048,
                purpose: "turn",
                idempotencyKey: "say-again-fill:\(turnId.uuidString)")
            guard let s = payload.turnSuggestion(for: said) else {
                return Entry(alternative: nil, reason: "")
            }
            return Entry(alternative: s.alternative, reason: s.reason)
        } catch {
            return nil
        }
    }

    private func save() {
        // Bounded: one entry per learner turn ever reviewed this way, and an
        // entry is only needed while its talk is still being re-run.
        if entries.count > 4000 {
            entries = Dictionary(uniqueKeysWithValues: entries.suffix(3000).map { ($0.key, $0.value) })
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
