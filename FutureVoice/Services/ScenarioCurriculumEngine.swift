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
        runKey: String? = nil,
        // Streaming taps: when either is set the scene STREAMS — the title
        // and each turn are handed over the moment they finish parsing, so
        // playback starts while the model is still writing the study tail.
        // The returned curriculum is still the full, final payload; callers
        // must persist from THAT, never from what the taps saw.
        onTitle: (@MainActor (String) -> Void)? = nil,
        onTurn: (@MainActor (DialogueEngineTurn) -> Void)? = nil
    ) async throws -> ScenarioCurriculum {
        let system = systemPrompt(targetLanguage: targetLanguage, proficiency: proficiency)
        let messages = [GeminiClient.Message(
            role: .user,
            content: userMessage(
                scenario: scenario,
                persona: persona,
                counterpart: counterpart,
                weakVocabAreas: weakVocabAreas,
                recurringMistakes: recurringMistakes,
                avoidTitles: avoidTitles
            )
        )]
        // v2: the scene-based schema — a v1 cached response (no turns)
        // would fail to decode under this Payload.
        let idempotencyKey = runKey.map { "curriculum-v2:\(scenario.id.uuidString):\($0)" }
            ?? "curriculum-v2:\(scenario.id.uuidString)"

        let payload: Payload
        if onTitle != nil || onTurn != nil {
            var sentTitle = false
            var sentTurns = 0
            payload = try await GeminiClient.shared.sendJSONStreamAccumulating(
                system: system,
                messages: messages,
                maxTokens: sceneMaxTokens,
                purpose: "scenario-curriculum",
                idempotencyKey: idempotencyKey,
                onPartial: { partial in
                    // onPartial replays the whole accumulated body each time;
                    // the counters make every emission exactly-once.
                    if !sentTitle,
                       let title = GeminiClient.completedStringField("title", in: partial) {
                        sentTitle = true
                        onTitle?(title)
                    }
                    let objects = GeminiClient.completedArrayObjects("turns", in: partial)
                    while sentTurns < objects.count {
                        let slice = objects[sentTurns]
                        sentTurns += 1
                        guard let data = String(slice).data(using: .utf8),
                              let item = try? JSONDecoder().decode(Payload.TurnItem.self, from: data)
                        else { continue }
                        onTurn?(DialogueEngineTurn(
                            speaker: item.speaker.lowercased() == "user" ? "user" : "counterpart",
                            text: item.text
                        ))
                    }
                }
            )
        } else {
            payload = try await GeminiClient.shared.sendJSON(
                system: system,
                messages: messages,
                maxTokens: sceneMaxTokens,
                purpose: "scenario-curriculum",
                idempotencyKey: idempotencyKey
            )
        }
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

    /// A scene is the SAME SIZE at every level, and the band changes only
    /// which WORDS and sentence shapes fill it — the rule the live call
    /// settled on 2026-08-20 (`ConversationEngine.SpeechScale`) and that
    /// Watch never followed. It arrived here on 2026-09-26 from two
    /// directions at once.
    ///
    /// **It read wrong in BOTH directions.** Size used to scale with the
    /// band: 8–10 turns of one 5–10 word sentence at A1/A2, up to 10–14
    /// turns of 1–3 full sentences at C1/C2. Reported the same day by the
    /// founder, after watching one of each: the A2 scene was too thin to
    /// hold a situation ("표면적"), the C1 scene too long to sit through.
    /// A learner does not need a SHORTER scene than a fluent one, they need
    /// an EASIER one — and a scene that can't carry the complication isn't
    /// easier, it's emptier.
    ///
    /// **And length is where the money is.** Measured on those two watches:
    /// 8 lines for $0.090 against 9 lines for $0.401 — ONE more line and
    /// 4.4x the ElevenLabs bill, because the band was expressed as length
    /// and a scene's cost is its characters. That made one scene from the
    /// plan's pool mean four different things depending on who played it,
    /// and put the $0.12-per-scene arithmetic `docs/launch-billing.md`
    /// prices on four times under at the top band.
    ///
    /// So: one middle length for everybody, and the band drives vocabulary
    /// and sentence shapes alone — read from `ConversationEngine.speechScale`
    /// rather than restated here, so there is ONE definition of what a band
    /// means and the call and the scene can't drift apart. Keep the count
    /// COUNTABLE for the same reason the call does: a qualitative ceiling
    /// loses to the concrete content rules around it.
    ///
    /// What is NOT band-dependent any more, and must stay that way: how much
    /// actually HAPPENS in the scene. The A2 complaint was about substance,
    /// and substance is now asked for at every level (see the systemPrompt's
    /// SUBSTANCE rule) — the band only decides how hard the words are.

    /// Turns in a scene, at EVERY level.
    ///
    /// **9–11 → 8–10 on 2026-09-26**, one turn shorter, for the cost reason
    /// above read forward instead of backward: a scene's bill IS its
    /// characters, so a tenth of the lines is a tenth of the money, and the
    /// measured scene was $0.124 against a plan that prices it at $0.12. One
    /// turn is the most that can come off without the scene stopping being a
    /// scene — the SUBSTANCE rule still has to fit (something happens, it is
    /// complicated, it resolves), and eight turns is four exchanges, which is
    /// the floor for that. Do not take a second one: below this the scene
    /// becomes the "표면적" A2 scene the range was widened to fix.
    static let sceneTurnRange = "8 to 10"

    /// How long one turn is, at EVERY level.
    static let sceneTurnStyle = """
        Each turn is 1–2 sentences — as long as the moment naturally calls
          for, never padded to reach the count and never clipped mid-thought.
          This is two people talking, not paragraphs read aloud.
        """

    /// One ceiling: the payload is the same size for every learner now.
    /// Sized well over a full scene plus its study lists, because gen-3
    /// spends thinking tokens out of the same budget and the failure is a
    /// lost call, not a shorter one.
    static let sceneMaxTokens = 3000

    private static func systemPrompt(targetLanguage: String, proficiency: CEFRLevel) -> String {
        let languageName = LanguageCatalog.englishName(targetLanguage)
        let band = ConversationEngine.speechScale(for: proficiency)
        return """
        You are a \(languageName) curriculum designer. Given ONE real-life
        scenario a learner (CEFR \(proficiency.rawValue.uppercased())) wants to master, write the SCENE
        for it: a naturalistic dialogue between the learner ("user") and the
        other person ("counterpart"), then extract the study content FROM that
        dialogue. The dialogue is the whole course — the learner watches it,
        studies its words and expressions, and shadows their own lines.

        WHOSE SITUATION IT IS — settle this before you write a line. The
        scenario is the learner's own, in the learner's own words, about the
        learner's own life. Whatever it names being done — thanking someone,
        apologizing, asking for a raise, sending a dish back, breaking news to
        a friend — the LEARNER ("user") is the one doing it, and the
        counterpart is the person on the OTHER side of it. Never cast the
        counterpart as the one performing the learner's move, and never swap
        the two: in "thanking the beta testers" the user thanks and the
        counterpart is thanked, not the reverse.

        Content rules:
        - turns: \(sceneTurnRange), alternating naturally. WHOEVER'S MOVE THE
          SCENARIO NAMES OPENS IT — when the learner is the one going in to do
          something, the FIRST turn is "user". The counterpart opens only when
          the situation is something that happens TO the learner (called in by
          the doctor, served at a counter, stopped by an official). When
          neither side owns the move (a catch-up, talking a story through),
          either may open.
          Real spoken \(languageName) — contractions, hedges, natural register.
          \(CoachingLanguage.breathPunctuation)
          \(sceneTurnStyle)
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

        SUBSTANCE — the same at EVERY level. Something has to actually HAPPEN:
        the specific thing the learner is going in to do, the complication it
        runs into, the question that is hard to answer, and how it lands. A
        beginner's scene is not a thinner scene — it is the same situation in
        easier words. Never fill the turns with greetings and pleasantries and
        stop before the difficult part; that part is the reason they are
        watching.

        WHAT \(proficiency.rawValue.uppercased()) CHANGES — the words and the sentence shapes, and
        nothing else. The scene is the same length and carries the same amount
        of substance for every learner; the band only decides how hard it is
        to say.
        - Vocabulary: \(band.vocabulary)
        - Sentence shapes: \(band.structure)

        Return STRICT JSON only — no prose, no code fences:
        {
          "turns": [ { "speaker": "user" | "counterpart", "text": "..." } ],
          "title": "...",
          "words": [ { "text": "...", "note": "...", "example": "..." } ],
          "expressions": [ { "text": "...", "note": "...", "example": "..." } ]
        }

        FIELD ORDER IS FIXED, and "turns" comes FIRST for a reason: playback
        starts on the first turn the moment it closes, while you are still
        writing the rest. Every character emitted before it — a title, a
        preamble, anything — is silence the learner sits through. Write the
        scene first and name it afterwards.
        """
    }

    /// A built-in character (see `StockPerson`) — cast by identity, never
    /// treated as a person the user described.
    private static func isBuiltin(_ c: Counterpart) -> Bool {
        c.remoteId?.hasPrefix("builtin:") ?? false
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
            // NOT labelled "where" — the composer takes one free line, and a
            // learner writes what they're going to DO at least as often as
            // where they'll be. Filed as a place, an action read as scenery
            // and the model handed it to whichever side it liked.
            lines.append("- what the learner is going in to do (their own words): \(scenario.environment)")
            let role = scenario.role.trimmingCharacters(in: .whitespaces)
            // Free-described situations carry no explicit partner — cast
            // whoever the situation implies (a landlord scene gets a
            // landlord, an interview gets an interviewer), never a default.
            lines.append(role.isEmpty
                ? "- talking to: infer the natural counterpart — the person on the OTHER side of what the learner is doing, never the one doing it"
                : "- talking to: \(role) — the other side of what the learner is doing, never the one doing it")
            if !scenario.notes.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("- context: \(scenario.notes)")
            }
        }
        // The learner's attached material, read once (`ScenarioBrief`). Two
        // sides, and they must stay on their sides: the other side's facts
        // and questions belong to the counterpart, the learner's facts to the
        // USER's lines. Handing the CV to the interviewer is the failure
        // this ordering exists to prevent.
        if let b = scenario.brief, b.hasContent {
            lines.append("")
            lines.append("material the learner attached for THIS situation (read once — facts only, never invent beyond them):")
            if !b.summary.isEmpty { lines.append("- about: \(b.summary)") }
            if !b.counterpartFacts.isEmpty {
                lines.append("- the OTHER side (this is who the counterpart is and what they want):")
                b.counterpartFacts.forEach { lines.append("    · \($0)") }
            }
            if !b.likelyQuestions.isEmpty {
                lines.append("- what the other side is likely to say or ask — use SOME of these, not all, and not in this order; a fresh take picks different ones:")
                b.likelyQuestions.forEach { lines.append("    · \($0)") }
            }
            if !b.learnerFacts.isEmpty {
                lines.append("- the LEARNER's own side (the user's lines draw on these; the counterpart may only know what such a person would plausibly have been sent):")
                b.learnerFacts.forEach { lines.append("    · \($0)") }
            }
            if !b.keyExpressions.isEmpty {
                lines.append("- expressions this situation calls for — work several into the dialogue naturally where they fit, and prefer them for the study lists: \(b.keyExpressions.joined(separator: " · "))")
            }
            lines.append("  (the notes above may be in the learner's native language — context only, never let it change the language you write in)")
        }
        if let c = counterpart, !isBuiltin(c) {
            lines.append("- the other person is \(c.name) (\(c.relationship))")
            if !c.background.isEmpty { lines.append("  shared context: \(c.background)") }
            // Their topics and manner: the hooks that make a scene belong to
            // THIS person. Without them every counterpart reads the same and
            // the scene drifts back to generic small talk.
            if !c.commonTopics.isEmpty { lines.append("  what they talk about: \(c.commonTopics)") }
            if !c.conversationStyle.isEmpty { lines.append("  how they talk: \(c.conversationStyle)") }
            // Dictated by the user in their own language — context, not output.
            lines.append("  (the lines above are the user's own note, in "
                         + "their native language — never let it change the "
                         + "language you write in)")
        } else {
            // A built-in character (or a legacy scenario with nobody attached,
            // which falls back to the default one) PLAYS the scene. Identity
            // only (name, temperament): the role stays whatever the situation
            // implies — the cast must never change WHAT the scene is.
            let stock = counterpart.map { StockPerson.by(voiceId: $0.voicePresetId) }
                ?? StockPerson.by(voiceId: scenario.voicePresetId)
            lines.append("- who PLAYS that counterpart: \(stock.identity). "
                         + "Use this name and temperament; their role, job and "
                         + "knowledge come from the situation above.")
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
        // The learner and the counterpart went in as two separate blocks with
        // nothing telling the model to cross them, so the scene's subject came
        // off one side at random. What two people who just met actually talk
        // about is the overlap.
        if let c = counterpart, !isBuiltin(c) {
            lines.append("")
            lines.append(CommonGround.block(learner: persona, counterpart: c))
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
