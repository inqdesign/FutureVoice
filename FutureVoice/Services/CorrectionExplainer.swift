import CryptoKit
import Foundation

/// The margin notes on a sentence card's back: each change with the few
/// words a teacher scribbles beside it, in the native language (2026-10-21;
/// the first cut wrote a sentence or two per change and read as a lesson). The card used to carry only the live
/// correction's `why` — "the grammar point, ≤ 12 words" by contract — which
/// arrives as a category ("word order and preposition") and tells nobody
/// what was wrong with their sentence. That contract stays (the call has to
/// be fast and the reason rides on every card); this is written once, the
/// first time a card is turned over, and kept by CONTENT like
/// `DrillEnrichmentStore`, so the 118 cards already on a phone get it too and
/// a re-minted card never pays twice.
struct CorrectionExplanation: Codable, Equatable {
    struct Change: Codable, Equatable, Hashable {
        /// Verbatim from what they said; empty when the fix only ADDED words.
        var was: String
        /// Verbatim from the fix; empty when the fix only took words OUT.
        var now: String
        /// A margin note in the native language — a few words, not a lesson.
        var why: String
    }
    var changes: [Change]
}

enum CorrectionExplainer {

    private struct Payload: Decodable {
        struct Item: Decodable { let was: String?; let now: String?; let why: String? }
        let changes: [Item]
    }

    /// The cached explanation, or nil. Never asks the network.
    static func cached(said: String, fix: String, target: String, native: String) -> CorrectionExplanation? {
        let url = fileURL(key(said: said, fix: fix, target: target, native: native))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CorrectionExplanation.self, from: data)
    }

    static func explain(said: String, fix: String, reason: String,
                        target: String, native: String) async throws -> CorrectionExplanation {
        if let hit = cached(said: said, fix: fix, target: target, native: native) { return hit }
        let k = key(said: said, fix: fix, target: target, native: native)
        var lines = ["said: \(said)", "fluent: \(fix)"]
        if !reason.isEmpty { lines.append("coach_note: \(reason)") }
        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: systemPrompt(target: target, native: native),
            messages: [GeminiClient.Message(role: .user, content: lines.joined(separator: "\n"))],
            // Native prose is token-hungry for CJK, and gen-3 spends its
            // thinking from the same ceiling. Only produced tokens are billed.
            maxTokens: 1024,
            purpose: "enrichment",
            idempotencyKey: "explain2:" + k
        )
        let result = CorrectionExplanation(changes: verified(payload, said: said, fix: fix))
        guard !result.changes.isEmpty else { throw CocoaError(.coderValueNotFound) }
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: fileURL(k), options: [.atomic])
        }
        return result
    }

    /// A `was` the learner never said, or a `now` the fix doesn't contain,
    /// would explain a different sentence from the one on the card — dropped.
    private static func verified(_ p: Payload, said: String, fix: String) -> [CorrectionExplanation.Change] {
        let s = said.lowercased(), f = fix.lowercased()
        return p.changes.compactMap { item in
            let was = (item.was ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let now = (item.now ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let why = (item.why ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !why.isEmpty, !(was.isEmpty && now.isEmpty) else { return nil }
            guard was.isEmpty || s.contains(was.lowercased()),
                  now.isEmpty || f.contains(now.lowercased()) else { return nil }
            return .init(was: was, now: now, why: why)
        }
        .prefix(3).map { $0 }
    }

    private static func systemPrompt(target: String, native: String) -> String {
        let lang = LanguageCatalog.englishName(target)
        let nativeName = LanguageCatalog.englishName(native)
        return """
        \(CoachingLanguage.contract(target: target, native: native))
        A learner of \(lang) said a sentence out loud in a conversation; it was
        transcribed by speech recognition ("said"). A fluent version was
        written for them ("fluent"). They are now looking at the two on a
        flashcard and need to understand EXACTLY what changed and why.

        Return STRICT JSON only:
        { "changes": [ { "was": "...", "now": "...", "why": "..." } ] }

        - One entry per change that MATTERS, most important first, at most 3.
          Each entry is ONE change with ONE reason: split a long span into
          the separate fixes inside it (word order, a wrong word, a missing
          word are three entries, not one), and keep "was"/"now" as short as
          the change itself. Skip punctuation, capitalisation, fillers (um,
          uh) and anything that only tidies speech.
        - "was": the exact words from "said" that changed, copied verbatim.
          Empty string if words were only added.
        - "now": the exact words from "fluent" that replace them, copied
          verbatim. Empty string if words were only removed.
        - "why": a MARGIN NOTE in \(nativeName), the few words a teacher
          scribbles beside the fix — at most 8 words (Korean/Japanese/Chinese:
          at most 15 characters), WRITTEN IN \(nativeName) whatever language
          these examples are in. It says the reason, not the category — the
          shape is "it was yesterday, so past", "making an app: build",
          "a field takes in", "misheard". Never a grammar term alone ("word
          order", "preposition"). \(lang) words stay in \(lang). Plain; in
          Korean a bare note or 해요체, never 합니다체.
        - If a word in "said" looks like the recognizer mishearing a similar
          sounding word (it makes no sense there, and the fluent version has
          a word that sounds like it), the note says it was misheard, never
          that it was their mistake.
        - "coach_note", when given, is a short hint from the live coach; use
          it, but explain fully.
        """
    }

    private static func key(said: String, fix: String, target: String, native: String) -> String {
        let seed = "v2\n\(target)\n\(native)\n\(said.lowercased())\n\(fix.lowercased())"
        return SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static let dir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = docs.appendingPathComponent("CorrectionExplanations", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func fileURL(_ key: String) -> URL { dir.appendingPathComponent("\(key).json") }
}
