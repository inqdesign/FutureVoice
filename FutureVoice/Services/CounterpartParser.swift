import Foundation

/// Turns a free-spoken description (often in the user's native language) into
/// a structured `Counterpart`. The point: voice input + AI parse is way less
/// friction than asking the user to fill 4 form fields, AND yields richer
/// background because people speak more freely in their mother tongue.
enum CounterpartParser {

    private struct Payload: Decodable {
        let name: String
        let relationship: String
        let location: String?
        let how_we_met: String?
        let background: String
        let conversation_style: String
        let common_topics: String?
    }

    static func parse(
        spokenDescription: String,
        languageHint: String
    ) async throws -> Counterpart {
        let system = systemPrompt()
        let userMsg = """
        language_hint: \(languageHint)
        spoken_description:
        \(spokenDescription)
        """

        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: userMsg)],
            model: .flashLite31,
            maxTokens: 600,
            purpose: "parse"
        )

        return Counterpart(
            name: payload.name,
            relationship: payload.relationship,
            location: payload.location ?? "",
            howWeMet: payload.how_we_met ?? "",
            background: payload.background,
            conversationStyle: payload.conversation_style,
            commonTopics: payload.common_topics ?? "",
            voicePresetId: VoicePreset.catalog.first!.id
        )
    }

    private static func systemPrompt() -> String {
        """
        The user just described a person they know — someone they'd practice
        speaking their target language with in a simulated dialogue. The description was
        spoken, so it may be casual, contain restarts, or trail off. Extract
        a structured profile.

        The user likely spoke in their native language (e.g. Korean). For app
        consistency, return ALL fields except `name` in English. The name stays
        in the original script the user used.

        Return STRICT JSON only — no prose, no code fences:
        {
          "name": "...",
          "relationship": "...",
          "location": "...",
          "how_we_met": "...",
          "background": "...",
          "conversation_style": "...",
          "common_topics": "..."
        }

        Rules:
        - name: as the user said it (original script for names — 보람 stays
          보람, "Sarah" stays "Sarah").
        - relationship: a short 2–5 word English label that names the type of
          relationship — "Best friend", "Kita parent", "Senior at work",
          "College roommate".
        - location: 1 short sentence in English on where they live, work, or
          spend time. Empty string "" if the user didn't say.
        - how_we_met: 1 sentence on how they met the user and roughly how
          long they've known each other. Empty string "" if unknown.
        - background: 2–3 dense English sentences. Shared history, inside
          jokes, what they know about the user, anything specific that would
          make a dialogue feel real. Keep concrete details the user gave —
          don't generalize.
        - conversation_style: 1–2 English sentences on how they talk — tempo,
          formality, humor, directness, energy.
        - common_topics: short English phrase — what the two of them usually
          end up talking about. Empty string "" if unclear.
        - Don't invent facts the user didn't imply. Use empty strings ("")
          rather than fabricating for fields the user didn't touch.
        """
    }
}
