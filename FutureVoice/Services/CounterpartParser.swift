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
        languageHint: String,
        nativeLanguage: String = LanguageCatalog.currentNative
    ) async throws -> Counterpart {
        let system = systemPrompt(nativeLanguage: nativeLanguage)
        let userMsg = """
        language_hint: \(languageHint)
        spoken_description:
        \(spokenDescription)
        """

        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: userMsg)],
            model: .flashLite31,
            // Six free-text fields, all in the user's NATIVE language — the
            // token-per-sentence cost the 600 was never sized for.
            maxTokens: 1500,
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

    private static func systemPrompt(nativeLanguage: String) -> String {
        let nativeName = LanguageCatalog.englishName(nativeLanguage)
        return """
        The user just described a person they know — someone they'd practice
        speaking their target language with in a simulated dialogue. The description was
        spoken, so it may be casual, contain restarts, or trail off. Extract
        a structured profile.

        Write EVERY field in \(nativeName), the language the user spoke in.
        This profile is the user's own note about their own friend: they read
        it on the person's card and edit it by hand. Handing back an English
        translation of what they just said in \(nativeName) means they have to
        re-read and re-edit their own words in a foreign language. The name
        stays in the original script the user used.

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
        - relationship: a short label naming the type of relationship — the
          \(nativeName) equivalent of "Best friend", "Kita parent", "Senior at
          work", "College roommate". A few words, no more.
        - location: 1 short sentence on where they live, work, or spend time.
          Empty string "" if the user didn't say.
        - how_we_met: 1 sentence on how they met the user and roughly how
          long they've known each other. Empty string "" if unknown.
        - background: 2–3 dense sentences. Shared history, inside jokes, what
          they know about the user, anything specific that would make a
          dialogue feel real. Keep concrete details the user gave — don't
          generalize.
        - conversation_style: 1–2 sentences on how they talk — tempo,
          formality, humor, directness, energy.
        - common_topics: a short phrase — what the two of them usually end up
          talking about. Empty string "" if unclear.
        - Keep the user's own wording where you can. This is a transcription
          into fields, not a rewrite.
        - Don't invent facts the user didn't imply. Use empty strings ("")
          rather than fabricating for fields the user didn't touch.
        """
    }
}
