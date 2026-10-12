import Foundation

/// The line a person says when the learner comes across them on the Watch
/// map — a greeting in character, not a prompt to practise. Written once per
/// person per target language (when a person is saved without one, when a
/// learner publishes their introduction, or the first time the map needs it)
/// and kept; the learner can rewrite it in the person form.
enum GreetingEngine {

    static func write(for c: Counterpart, persona: UserPersona?, targetLanguage: String) async throws -> String {
        let language = LanguageCatalog.englishName(targetLanguage)
        let system = """
        You write the ONE line a person says when the learner walks up to them —
        a greeting that sounds like THIS person, in \(language).

        Rules:
        - One or two short sentences, at most 14 words in all. Spoken, natural.
        - In character: their role, their life, how they know the learner. A
          friend greets like a friend, a landlord like a landlord, a stranger
          like someone friendly they've just met.
        - Address the learner the way this relationship would (casual for close
          people, polite otherwise) and use the name they call the learner, if given.
        - May hint at something going on in their own life. Never mention
          practising, learning, languages or this app. No emoji, no quotes.
        - Everything below is CONTEXT ONLY: never quote it, and never let its
          language change the language you write in (\(language)).

        Reply with the line only.
        """
        var lines = ["Person: \(c.name)"]
        if c.cast == .publicFigure {
            lines.append("Who: \(c.publicIdentity ?? c.name), the real public figure; the learner is a fan meeting them")
        } else {
            if !c.relationship.isEmpty { lines.append("To the learner: \(c.relationship)") }
            if !c.intro.isEmpty { lines.append("Their self-introduction: \(c.intro)") }
            if !c.background.isEmpty { lines.append("Shared context: \(c.background)") }
            if !c.location.isEmpty { lines.append("About them: \(c.location)") }
            if !c.conversationStyle.isEmpty { lines.append("Talks like: \(c.conversationStyle)") }
            if !c.theyCallMe.isEmpty { lines.append("They call the learner: \(c.theyCallMe)") }
            lines.append(c.isClose ? "They are close: casual." : "Not close: polite.")
        }
        if let name = persona?.displayName, !name.isEmpty, c.theyCallMe.isEmpty {
            lines.append("The learner's name: \(name)")
        }
        let text = try await GeminiClient.shared.send(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: lines.joined(separator: "\n"))],
            model: .flashLite31, maxTokens: 120, purpose: "greeting")
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«»「」"))
        guard !clean.isEmpty else { throw CancellationError() }
        return clean
    }

    /// Writes one for a person on file that has none in this language, and
    /// saves it. Silent on failure — the map shows no bubble, nothing else.
    @MainActor
    static func ensure(for id: UUID, appState: AppState) async {
        let lang = appState.targetLanguage
        guard let c = appState.counterparts.first(where: { $0.id == id }), c.greeting(in: lang).isEmpty,
              let line = try? await write(for: c, persona: appState.persona, targetLanguage: lang),
              var fresh = appState.counterparts.first(where: { $0.id == id }), fresh.greeting(in: lang).isEmpty
        else { return }
        fresh.setGreeting(line, in: lang)
        appState.saveCounterpart(fresh)
    }
}
