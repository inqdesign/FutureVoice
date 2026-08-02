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
        recurringMistakes: [LearnerPattern] = [],
        // A scenario is a reusable template — re-watching writes a NEW take.
        // avoidTitles: earlier takes' titles, so the model picks a different
        // angle. runKey: distinguishes this take in the idempotency key
        // (still guards double-taps within one watch).
        avoidTitles: [String] = [],
        runKey: String? = nil
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
                    recurringMistakes: recurringMistakes,
                    avoidTitles: avoidTitles
                )
            )],
            maxTokens: sceneScale(for: proficiency).maxTokens,
            purpose: "scenario-curriculum",
            // v2: the scene-based schema — a v1 cached response (no turns)
            // would fail to decode under this Payload.
            idempotencyKey: runKey.map { "curriculum-v2:\(scenario.id.uuidString):\($0)" }
                ?? "curriculum-v2:\(scenario.id.uuidString)"
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

    /// Scene size scales with the learner's level: beginners get short,
    /// ownable turns; advanced learners get more turns and fuller sentences —
    /// depth the scene needs, not a fixed cap. Token budget scales with it.
    struct SceneScale {
        let turnRange: String     // e.g. "8 to 10"
        let turnStyle: String     // per-band sentence-length guidance
        let maxTokens: Int
    }

    static func sceneScale(for proficiency: CEFRLevel) -> SceneScale {
        switch proficiency {
        case .a1, .a2:
            return SceneScale(
                turnRange: "8 to 10",
                turnStyle: """
                Each turn is ONE short, simple sentence (roughly 5–10 words) —
                clear everyday phrasing the learner can fully own.
                """,
                maxTokens: 2200
            )
        case .b1, .b2:
            return SceneScale(
                turnRange: "8 to 12",
                turnStyle: """
                Each turn is 1–2 sentences, as long as the moment naturally
                calls for — never padded, never artificially clipped.
                """,
                maxTokens: 2800
            )
        case .c1, .c2:
            return SceneScale(
                turnRange: "10 to 14",
                turnStyle: """
                Each turn is 1–3 full sentences at natural native pacing —
                subordinate clauses, nuance, and follow-up questions welcome.
                Go deeper into the substance of the situation; an advanced
                learner should hear a conversation with real depth.
                """,
                maxTokens: 3600
            )
        }
    }

    private static func systemPrompt(targetLanguage: String, proficiency: CEFRLevel) -> String {
        let languageName = LanguageCatalog.englishName(targetLanguage)
        let scale = sceneScale(for: proficiency)
        return """
        You are a \(languageName) curriculum designer. Given ONE real-life
        scenario a learner (CEFR \(proficiency.rawValue.uppercased())) wants to master, write the SCENE
        for it: a naturalistic dialogue between the learner ("user") and the
        other person ("counterpart"), then extract the study content FROM that
        dialogue. The dialogue is the whole course — the learner watches it,
        studies its words and expressions, and shadows their own lines.

        Content rules:
        - turns: \(scale.turnRange), alternating naturally; either side can open.
          Real spoken \(languageName) — contractions, hedges, natural register.
          \(scale.turnStyle)
          The USER speaks as a confident, fluent version of the learner
          (slightly above \(proficiency.rawValue.uppercased()), never textbook-stiff). Every user turn must
          be a complete, speakable line — it will be shadowed ALOUD. No stage
          directions, brackets, or placeholders anywhere.
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
        recurringMistakes: [LearnerPattern],
        avoidTitles: [String] = []
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
            // Dictated by the user in their own language — context, not output.
            lines.append("  (the two lines above are the user's own note, in "
                         + "their native language — never let it change the "
                         + "language you write in)")
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
        let previous = avoidTitles.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !previous.isEmpty {
            lines.append("")
            lines.append("""
            The learner has already watched these takes of this scenario: \
            \(previous.map { "\"\($0)\"" }.joined(separator: ", ")). \
            Write a FRESH take — a different opening, complication, or beat \
            of the same situation, never a rephrase of a previous take.
            """)
        }
        return lines.joined(separator: "\n")
    }
}
