import Foundation

/// Generates a short, naturalistic dialogue between the user's persona and a
/// counterpart for Watch mode. One Gemini call returns the entire script —
/// Watch mode is observation, not interactive, so we don't need turn-by-turn
/// generation.
enum DialogueEngine {

    enum Speaker: String, Codable, Hashable {
        case user
        case counterpart
    }

    struct Turn: Codable, Hashable, Identifiable {
        var id: UUID = UUID()
        var speaker: Speaker
        var text: String
    }

    private struct Payload: Decodable {
        struct Item: Decodable {
            let speaker: String
            let text: String
        }
        let turns: [Item]
    }

    static func generate(
        persona: UserPersona?,
        counterpart: Counterpart,
        topic: SuggestedTopic?,
        topicTitle: String?,
        topicBlurb: String?,
        targetLanguage: String
    ) async throws -> [Turn] {
        let title = topic?.title ?? topicTitle ?? "a casual catch-up"
        let blurb = topic?.blurb ?? topicBlurb ?? ""

        let system = systemPrompt(targetLanguage: targetLanguage)
        let userMsg = userMessage(
            persona: persona,
            counterpart: counterpart,
            scenarioTitle: title,
            scenarioBlurb: blurb
        )

        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: userMsg)],
            maxTokens: 1500
        )
        return payload.turns.compactMap { item in
            guard let speaker = Speaker(rawValue: item.speaker.lowercased()) else { return nil }
            return Turn(speaker: speaker, text: item.text)
        }
    }

    private static func systemPrompt(targetLanguage: String) -> String {
        """
        You generate naturalistic spoken dialogue in \(targetLanguage) between two \
        specific people. The user will watch this play out to learn how a confident, \
        fluent version of themselves would handle a real interaction.

        Inputs:
        - USER persona: who the learner is.
        - COUNTERPART persona: a specific person from the learner's life.
        - Scenario: the situation.

        Return STRICT JSON only — no prose, no code fences:
        { "turns": [ { "speaker": "user" | "counterpart", "text": "..." }, ... ] }

        Rules:
        - 6 to 10 turns total.
        - Alternate speakers naturally. Either can open — pick whoever opens this \
          situation more naturally.
        - Each turn: 1–3 sentences. Real spoken English — contractions, hedges, \
          half-finished thoughts, gentle interruptions are fine.
        - Reference SHARED context from the personas. Don't restate facts the two \
          already know about each other; show it through how they talk.
        - Match the counterpart's described conversation style.
        - End on a believable beat — not a corporate "great talking to you", more \
          like how a real interaction tapers off.
        - No stage directions, no parentheticals, no narration. Just the spoken words.
        """
    }

    private static func userMessage(
        persona: UserPersona?,
        counterpart: Counterpart,
        scenarioTitle: String,
        scenarioBlurb: String
    ) -> String {
        var out = ["USER persona:"]
        if let p = persona, p.isMinimallyComplete {
            if !p.displayName.isEmpty { out.append("- name: \(p.displayName)") }
            let place = [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", ")
            if !place.isEmpty { out.append("- lives in: \(place)") }
            if !p.occupation.isEmpty { out.append("- work: \(p.occupation)") }
            if !p.household.isEmpty { out.append("- household: \(p.household)") }
            if !p.interests.isEmpty { out.append("- interests: \(p.interests.joined(separator: ", "))") }
        } else {
            out.append("- (sparse — keep dialogue generic but warm)")
        }

        out.append("")
        out.append("COUNTERPART persona:")
        out.append("- name: \(counterpart.name)")
        if !counterpart.relationship.isEmpty {
            out.append("- relationship to user: \(counterpart.relationship)")
        }
        if !counterpart.location.isEmpty {
            out.append("- about them: \(counterpart.location)")
        }
        if !counterpart.howWeMet.isEmpty {
            out.append("- how they met: \(counterpart.howWeMet)")
        }
        if !counterpart.background.isEmpty {
            out.append("- shared context: \(counterpart.background)")
        }
        if !counterpart.conversationStyle.isEmpty {
            out.append("- talks like: \(counterpart.conversationStyle)")
        }
        if !counterpart.commonTopics.isEmpty {
            out.append("- common topics: \(counterpart.commonTopics)")
        }
        if !counterpart.freeNotes.isEmpty {
            out.append("- notes: \(counterpart.freeNotes)")
        }

        out.append("")
        out.append("Scenario:")
        out.append("- \(scenarioTitle)")
        if !scenarioBlurb.isEmpty {
            out.append("- \(scenarioBlurb)")
        }

        return out.joined(separator: "\n")
    }
}
