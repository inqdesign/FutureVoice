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
        /// Public figures only: who the model settled on ("BTS Jimin ·
        /// singer"), for the learner to confirm.
        let identity: String?
    }

    /// `publicFigure`: the person is a celebrity, an athlete, an author —
    /// someone NOT in the learner's life. The parse then runs search-grounded
    /// and fills the profile from PUBLIC coverage (origin, work, recent
    /// activity with its year, how they speak in interviews) instead of from
    /// the learner's own notes, which for a stranger are about the learner,
    /// not the person. Same rule as every other stranger-facing surface: a
    /// preset voice, never a clone — that is the caller's job, this only
    /// writes text.
    static func parse(
        spokenDescription: String,
        languageHint: String,
        nativeLanguage: String = LanguageCatalog.currentNative,
        publicFigure: Bool = false
    ) async throws -> Counterpart {
        let system = systemPrompt(nativeLanguage: nativeLanguage, publicFigure: publicFigure)
        let today = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let userMsg = """
        language_hint: \(languageHint)
        \(publicFigure ? "today: \(today)\n" : "")spoken_description:
        \(spokenDescription)
        """

        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: userMsg)],
            // Grounding needs the full model; the plain parse stays on the
            // cheap tier it has always used.
            model: publicFigure ? .flash36 : .flashLite31,
            // Six free-text fields, all in the user's NATIVE language — the
            // token-per-sentence cost the 600 was never sized for.
            maxTokens: publicFigure ? 2500 : 1500,
            searchGrounding: publicFigure,
            purpose: "parse"
        )

        var c = Counterpart(
            name: payload.name,
            relationship: payload.relationship,
            location: payload.location ?? "",
            howWeMet: payload.how_we_met ?? "",
            background: payload.background,
            conversationStyle: payload.conversation_style,
            commonTopics: payload.common_topics ?? "",
            voicePresetId: VoicePreset.catalog.first!.id
        )
        if publicFigure {
            c.isPublicFigure = true
            c.publicIdentity = payload.identity?.trimmingCharacters(in: .whitespacesAndNewlines)
            c.factsRefreshedAt = Date()
        }
        return c
    }

    private static func systemPrompt(nativeLanguage: String, publicFigure: Bool) -> String {
        let nativeName = LanguageCatalog.englishName(nativeLanguage)
        if publicFigure { return publicFigurePrompt(nativeName: nativeName) }
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

    /// The public-figure variant. The learner's description is what THEY
    /// feel about this person; the profile comes from the open web.
    private static func publicFigurePrompt(nativeName: String) -> String {
        """
        The user named a PUBLIC FIGURE — a singer, an actor, an athlete, an \
        author, a politician — they want to practice speaking their target \
        language with, in a simulated conversation (a fan meeting, an \
        interview, a chance meeting). They are not in each other's lives. \
        Look the person up and write a profile from PUBLIC coverage.

        Write EVERY field in \(nativeName) — this is a card the user reads and \
        edits. Names stay in their usual script; product, album and team \
        names as they are written.

        Return STRICT JSON only — no prose, no code fences:
        {
          "identity": "...",
          "name": "...",
          "relationship": "...",
          "location": "...",
          "how_we_met": "...",
          "background": "...",
          "conversation_style": "...",
          "common_topics": "..."
        }

        Rules:
        - identity: who you settled on, in 3–6 words the user can confirm at a \
          glance — the group or field and the role ("BTS Jimin · singer", \
          "Son Heung-min · footballer"). If the name is ambiguous, pick the \
          most famous reading and say so here.
        - name: as the user said it.
        - relationship: how the USER relates to them, from what they said \
          ("fan since 2019", "I follow their films") — never how the person \
          relates to the user. A few words.
        - location: where they are from and where they are based now, 1 line.
        - how_we_met: how the user came to follow them, IF they said. Else "".
        - background: 3–4 dense sentences from public coverage — origin, what \
          they are known for, their most recent public activity WITH THE YEAR \
          (an album, a season, a film, a return from service), one or two \
          well-known facts fans bring up. Public facts only: nothing about \
          health, relationships, family or money unless it is the person's \
          own widely reported public statement. Nothing invented; if the \
          search finds little, say less.
        - conversation_style: 1–2 sentences on how they come across in \
          interviews and with fans — warmth, humour, energy, formality.
        - common_topics: a short phrase — what fans and interviewers actually \
          talk with them about.
        - Keep anything the user themselves said about why this person \
          matters to them: it belongs in `relationship` or `how_we_met`, not \
          in the person's background.
        """
    }
}
