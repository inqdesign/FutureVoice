import Foundation

/// Generates the course content ("book") for one scenario via Gemini — as ONE
/// scene: a naturalistic dialogue between the learner and the counterpart,
/// plus the words and expressions used in that exact dialogue. The study list
/// and what the user watches are the same material; shadow lines are the
/// learner's own turns, extracted in code. Runs ONCE per scenario — the
/// result is persisted onto the `Scenario` itself, and the idempotency key
/// keeps a double-tap from billing twice.
enum ScenarioCurriculumEngine {

    struct Payload: Decodable {
        struct Entry: Decodable {
            let text: String
            let note: String
            let example: String?
        }
        struct TurnItem: Decodable {
            let speaker: String
            let text: String
        }
        let title: String
        let turns: [TurnItem]
        let words: [Entry]
        let expressions: [Entry]
    }

    static func generate(
        scenario: Scenario,
        persona: UserPersona?,
        counterpart: Counterpart?,
        proficiency: CEFRLevel,
        targetLanguage: String,
        weakVocabAreas: [String] = [],
        recurringMistakes: [LearnerPattern] = []
    ) async throws -> ScenarioCurriculum {
        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: systemPrompt(targetLanguage: targetLanguage, proficiency: proficiency),
            messages: [GeminiClient.Message(
                role: .user,
                content: userMessage(
                    scenario: scenario,
                    persona: persona,
                    counterpart: counterpart,
                    weakVocabAreas: weakVocabAreas,
                    recurringMistakes: recurringMistakes
                )
            )],
            maxTokens: 2200,
            purpose: "scenario-curriculum",
            // v2: the scene-based schema — a v1 cached response (no turns)
            // would fail to decode under this Payload.
            idempotencyKey: "curriculum-v2:\(scenario.id.uuidString)"
        )
        let turns = payload.turns.map {
            DialogueEngineTurn(
                speaker: $0.speaker.lowercased() == "user" ? "user" : "counterpart",
                text: $0.text
            )
        }
        return ScenarioCurriculum(
            words: payload.words.map { .init(text: $0.text, note: $0.note, example: $0.example) },
            expressions: payload.expressions.map { .init(text: $0.text, note: $0.note, example: $0.example) },
            // Shadow material IS the learner's side of the scene — extracted
            // deterministically, not a separate LLM list.
            shadowLines: turns.filter { $0.speaker == "user" }
                .map { .init(text: $0.text, note: "") },
            dialogueTitle: payload.title,
            dialogue: turns
        )
    }

    // MARK: - Prompts

    private static func systemPrompt(targetLanguage: String, proficiency: CEFRLevel) -> String {
        let languageName = LanguageCatalog.englishName(targetLanguage)
        return """
        You are a \(languageName) curriculum designer. Given ONE real-life
        scenario a learner (CEFR \(proficiency.rawValue.uppercased())) wants to master, write the SCENE
        for it: a naturalistic dialogue between the learner ("user") and the
        other person ("counterpart"), then extract the study content FROM that
        dialogue. The dialogue is the whole course — the learner watches it,
        studies its words and expressions, and shadows their own lines.

        Content rules:
        - turns: 8 to 12, alternating naturally; either side can open. Each
          turn 1–2 sentences of real spoken \(languageName) — contractions,
          hedges, natural register. The USER speaks as a confident, fluent
          version of the learner (slightly above \(proficiency.rawValue.uppercased()), never textbook-stiff).
          Every user turn must be a complete, speakable line 6–16 words long —
          it will be shadowed ALOUD. No stage directions, brackets, or
          placeholders anywhere.
        - words: 8 single words or short compounds that APPEAR in the dialogue
          and a \(proficiency.rawValue.uppercased()) learner plausibly doesn't own yet. No filler like
          "hello" / "thanks". note = one short cue for when it comes up.
          example = the dialogue sentence that uses it (or a tight variant).
        - expressions: 6 multi-word chunks (2–6 words) that APPEAR VERBATIM in
          the dialogue — collocations, softeners, transactional moves natives
          actually use here. note = one short cue for when to reach for it.
          example = the dialogue sentence that uses it.
        - title: 2–5 words in \(languageName) naming what happens in THIS scene.
        - Everything specific to THIS scenario and persona — never generic
          textbook content. All content in \(languageName); notes in simple \(languageName).

        Return STRICT JSON only — no prose, no code fences:
        {
          "title": "...",
          "turns": [ { "speaker": "user" | "counterpart", "text": "..." } ],
          "words": [ { "text": "...", "note": "...", "example": "..." } ],
          "expressions": [ { "text": "...", "note": "...", "example": "..." } ]
        }
        """
    }

    private static func userMessage(
        scenario: Scenario,
        persona: UserPersona?,
        counterpart: Counterpart?,
        weakVocabAreas: [String],
        recurringMistakes: [LearnerPattern]
    ) -> String {
        var lines: [String]
        if scenario.isTopic == true {
            // Topic book: the "situation" is a discussion about something the
            // learner follows, not a transactional errand — frame it so the
            // scene is two people actually talking the story through.
            lines = ["scenario: a casual conversation about a topic the learner follows"]
            lines.append("- topic: \(scenario.environment)")
            lines.append("- talking with: \(scenario.role)")
            if !scenario.notes.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("- story context (facts from coverage — keep the dialogue consistent with these): \(scenario.notes)")
            }
        } else {
            lines = ["scenario:"]
            lines.append("- where: \(scenario.environment)")
            let role = scenario.role.trimmingCharacters(in: .whitespaces)
            // Free-described situations carry no explicit partner — cast
            // whoever the situation implies (a landlord scene gets a
            // landlord, an interview gets an interviewer), never a default.
            lines.append(role.isEmpty
                ? "- talking to: infer the natural counterpart for this situation"
                : "- talking to: \(role)")
            if !scenario.notes.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("- context: \(scenario.notes)")
            }
        }
        if let c = counterpart {
            lines.append("- the other person is \(c.name) (\(c.relationship))")
            if !c.background.isEmpty { lines.append("  shared context: \(c.background)") }
        }
        if let p = persona, p.isMinimallyComplete {
            lines.append("")
            lines.append("learner:")
            let place = [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", ")
            if !place.isEmpty { lines.append("- lives in: \(place)") }
            if !p.occupation.isEmpty { lines.append("- work: \(p.occupation)") }
            if !p.household.isEmpty { lines.append("- household: \(p.household)") }
            if !p.interests.isEmpty { lines.append("- interests: \(p.interests.joined(separator: ", "))") }
            if !p.situations.isEmpty {
                lines.append("- needs the language most for: \(p.situations.joined(separator: ", "))")
            }
            if !p.freeNotes.isEmpty { lines.append("- notes: \(p.freeNotes)") }
        }
        // Steer the study picks toward what this learner actually gets wrong,
        // so the book's words/expressions target known gaps — not generic ones.
        let weak = weakVocabAreas.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let mistakes = recurringMistakes.prefix(3)
            .map { "\($0.mistake) → \($0.correction)" }
        if !weak.isEmpty || !mistakes.isEmpty {
            lines.append("")
            lines.append("learner focus (bias study picks here where the scene allows, never force it):")
            if !weak.isEmpty { lines.append("- weak vocab areas: \(weak.joined(separator: ", "))") }
            if !mistakes.isEmpty { lines.append("- recurring mistakes: \(mistakes.joined(separator: "; "))") }
        }
        return lines.joined(separator: "\n")
    }
}
