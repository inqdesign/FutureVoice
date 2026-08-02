import Foundation

/// Turns a thin DrillCard (one phrase swap + reason) into a richer learning
/// payload — situational examples grounded in the user's persona, alternate
/// phrasings, and a memory hook. Cached back into `DrillCard.enrichment` so
/// subsequent opens are free.
enum DrillEnrichmentEngine {

    private struct Payload: Decodable {
        struct Item: Decodable {
            let situation: String
            let sentence: String
        }
        struct Var: Decodable {
            let phrase: String
            let note: String
        }
        let examples: [Item]
        let variants: [Var]
        let memory_hook: String
    }

    static func generate(
        card: DrillCard,
        persona: UserPersona?,
        targetLanguage: String,
        nativeLanguage: String = LanguageCatalog.currentNative
    ) async throws -> DrillCardEnrichment {
        let system = systemPrompt(targetLanguage: targetLanguage,
                                  nativeLanguage: nativeLanguage)
        let userMsg = userMessage(card: card, persona: persona)

        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: userMsg)],
            maxTokens: 1000,
            purpose: "enrichment",
            idempotencyKey: "enrichment:\(card.id.uuidString)"
        )

        return DrillCardEnrichment(
            examples: payload.examples.map {
                .init(situation: $0.situation, sentence: $0.sentence)
            },
            variants: payload.variants.map {
                .init(phrase: $0.phrase, note: $0.note)
            },
            memoryHook: payload.memory_hook,
            generatedAt: Date()
        )
    }

    private static func systemPrompt(targetLanguage: String,
                                     nativeLanguage: String) -> String {
        let languageName = LanguageCatalog.englishName(targetLanguage)
        let nativeName = LanguageCatalog.englishName(nativeLanguage)
        return """
        \(CoachingLanguage.contract(target: targetLanguage, native: nativeLanguage))
        The user is studying a flashcard for \(languageName) fluency. The
        card has a target phrase (the natural version) and optionally a source
        phrase (what they originally said) + reason. Generate a rich
        enrichment payload so they really internalize the pattern instead of
        memorizing one swap.

        Use the user's persona to GROUND examples in situations they actually
        live in (their city, work, household, interests). Generic textbook
        scenarios are wrong here.

        Return STRICT JSON only — no prose, no code fences:
        {
          "examples": [
            { "situation": "...", "sentence": "..." },
            { "situation": "...", "sentence": "..." },
            { "situation": "...", "sentence": "..." }
          ],
          "variants": [
            { "phrase": "...", "note": "..." },
            { "phrase": "...", "note": "..." }
          ],
          "memory_hook": "..."
        }

        Rules:
        - examples: 3 short scenarios in DIFFERENT contexts from the persona's
          life, each with one line that uses the target phrase naturally.
          situation = brief frame in \(nativeName) (≤ 14 words). sentence = the
          spoken line in \(languageName).
        - variants: 2-3 alternate ways to express the same intent at similar
          fluency level. phrase = \(languageName). note = ≤ 14 words in
          \(nativeName) on when this variant fits better (register, formality,
          mood).
        - memory_hook: ONE sentence in \(nativeName) — a sensory, situational,
          or relatable trigger that makes the phrase easy to recall later. NOT
          "remember this!" — something concrete like "When you're about to
          apologize but it's not really your fault, reach for this."
        - So: "sentence" and "phrase" in \(languageName) (the learner speaks
          them); "situation", "note" and "memory_hook" in \(nativeName) (the
          learner reads them to understand). A \(languageName) phrase quoted
          inside a \(nativeName) line stays untranslated.
        """
    }

    private static func userMessage(card: DrillCard, persona: UserPersona?) -> String {
        var lines: [String] = []
        if !card.sourcePhrase.isEmpty {
            lines.append("source_phrase: \(card.sourcePhrase)")
        }
        lines.append("target_phrase: \(card.targetPhrase)")
        if !card.reason.isEmpty {
            lines.append("reason: \(card.reason)")
        }
        lines.append("")
        lines.append("persona:")
        if let p = persona, p.isMinimallyComplete {
            if !p.displayName.isEmpty { lines.append("- name: \(p.displayName)") }
            let place = [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", ")
            if !place.isEmpty { lines.append("- lives in: \(place)") }
            if !p.occupation.isEmpty { lines.append("- work: \(p.occupation)") }
            if !p.household.isEmpty { lines.append("- household: \(p.household)") }
            if !p.interests.isEmpty {
                lines.append("- interests: \(p.interests.joined(separator: ", "))")
            }
            if !p.situations.isEmpty {
                lines.append("- target-language situations: \(p.situations.joined(separator: ", "))")
            }
        } else {
            lines.append("- (sparse — pick neutral but believable scenarios)")
        }
        return lines.joined(separator: "\n")
    }
}
