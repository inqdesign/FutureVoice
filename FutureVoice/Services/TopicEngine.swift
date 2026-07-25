import Foundation

/// Generates persona-grounded conversation topics via Gemini. The goal is to
/// surface situations the user would ACTUALLY encounter this week — not
/// textbook clichés like "ordering coffee" or "asking for directions". The
/// engine is intentionally aggressive about specificity: every suggestion
/// names a concrete moment so the avatar has something real to lean into.
enum TopicEngine {

    struct Payload: Decodable {
        struct Item: Decodable {
            let title: String
            let blurb: String
        }
        let topics: [Item]
    }

    /// Returns 5 specific scenarios grounded in the persona. Falls back to a
    /// small generic set if persona is empty (so we never block the picker).
    static func suggest(
        persona: UserPersona?,
        targetLanguage: String,
        count: Int = 5
    ) async throws -> [SuggestedTopic] {
        let system = systemPrompt(targetLanguage: targetLanguage, count: count)
        let userMessage = userMessage(persona: persona)

        do {
            let payload: Payload = try await GeminiClient.shared.sendJSON(
                system: system,
                messages: [GeminiClient.Message(role: .user, content: userMessage)],
                maxTokens: 800
            )
            return payload.topics.map { SuggestedTopic(title: $0.title, blurb: $0.blurb) }
        } catch {
            return fallback(persona: persona)
        }
    }

    // MARK: - Prompts

    private static func systemPrompt(targetLanguage: String, count: Int) -> String {
        """
        You generate language-practice scenarios for an advanced \(LanguageCatalog.englishName(targetLanguage)) learner.
        Given their persona, suggest \(count) SPECIFIC, REAL-LIFE situations they'd
        actually encounter THIS WEEK in their actual life. Avoid textbook clichés
        like "ordering coffee", "asking for directions", or "job interview" unless
        those genuinely fit the persona's situation.

        Each suggestion = a concrete moment with enough hook that a 5–10 minute
        natural conversation could flow from it. Reference their city, work,
        family, interests, or the situations they say they need the language for.

        GOOD examples:
        - "Bumping into another Kita parent at pickup who's also confused about
           the new schedule — vent and bond"
        - "Catching up with a startup friend who just shipped their first paying
           customer — celebrate without humble-bragging about your own thing"
        - "Talking to your Bavarian dentist's new English-speaking hygienist
           about why your jaw clicks when you chew"

        BAD examples:
        - "Talking to a parent" (too vague)
        - "Ordering food" (textbook generic)
        - "Discussing the weather" (no hook)

        Vary the scenarios across the persona's dimensions — don't have three
        about the same context.

        Return STRICT JSON only — no prose, no code fences:
        { "topics": [ { "title": "...", "blurb": "..." } ] }

        Rules:
        - title: ≤ 60 chars. The single sentence the user reads in the picker.
        - blurb: ≤ 140 chars. One-line extra context that doubles as the seed
          the avatar will use to open the conversation.
        - Both in English (it's a target-language app).
        """
    }

    private static func userMessage(persona: UserPersona?) -> String {
        guard let p = persona, p.isMinimallyComplete else {
            return "persona: (none set yet — pick neutral but life-like scenarios for a curious, advanced learner)"
        }
        var lines = ["persona:"]
        if !p.displayName.isEmpty { lines.append("- name: \(p.displayName)") }
        let place = [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", ")
        if !place.isEmpty {
            let stay = p.lengthOfStay.isEmpty ? "" : " (\(p.lengthOfStay))"
            lines.append("- lives in: \(place)\(stay)")
        }
        if !p.occupation.isEmpty { lines.append("- work: \(p.occupation)") }
        if !p.household.isEmpty { lines.append("- household: \(p.household)") }
        if !p.interests.isEmpty { lines.append("- interests: \(p.interests.joined(separator: ", "))") }
        if !p.situations.isEmpty {
            lines.append("- target-language situations they care about: \(p.situations.joined(separator: ", "))")
        }
        if !p.freeNotes.isEmpty { lines.append("- notes: \(p.freeNotes)") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Counterpart-grounded variant

    /// Generates scenarios anchored on the user-counterpart RELATIONSHIP, not
    /// just on the user's life. The counterpart's role + shared context drive
    /// where the two would realistically meet/interact (Kita pickup, birthday
    /// party, soccer Sunday, 1-on-1 at work, etc.).
    static func suggestForCounterpart(
        persona: UserPersona?,
        counterpart: Counterpart,
        targetLanguage: String,
        count: Int = 5
    ) async throws -> [SuggestedTopic] {
        let system = counterpartSystemPrompt(targetLanguage: targetLanguage, count: count)
        let userMsg = counterpartUserMessage(persona: persona, counterpart: counterpart)
        do {
            let payload: Payload = try await GeminiClient.shared.sendJSON(
                system: system,
                messages: [GeminiClient.Message(role: .user, content: userMsg)],
                maxTokens: 900
            )
            return payload.topics.map { SuggestedTopic(title: $0.title, blurb: $0.blurb) }
        } catch {
            return counterpartFallback(counterpart: counterpart)
        }
    }

    private static func counterpartSystemPrompt(targetLanguage: String, count: Int) -> String {
        """
        You generate \(count) realistic \(LanguageCatalog.englishName(targetLanguage))-language scenarios where
        the USER and a specific COUNTERPART would meet, interact, or talk —
        anchored on their actual relationship and shared life context.

        Think situations like:
          - "Bumping into them at Kita pickup, talking about the new teacher"
          - "At a kid's birthday party, killing time at the snack table"
          - "Sunday morning football, recovering between matches"
          - "Playdate at the playground while the kids run wild"
          - "1-on-1 with your manager about next quarter's priorities"
          - "Catching up over coffee after they got back from a trip"

        Match the COUNTERPART's role and how they know the user. Avoid
        textbook clichés ("ordering coffee") unless that fits this specific
        pair's actual life. Use shared context (background, common topics) so
        each scenario feels like THIS pair, not interchangeable.

        Return STRICT JSON only — no prose, no code fences:
        { "topics": [ { "title": "...", "blurb": "..." } ] }

        Rules:
        - title: ≤ 60 chars in English. Concrete moment with a hook.
        - blurb: ≤ 140 chars in English. One line of context that the avatar
          can use as a seed for the opening of the dialogue.
        - Vary scenarios across the relationship's natural surfaces — don't
          have three about the same setting.
        """
    }

    private static func counterpartUserMessage(persona: UserPersona?, counterpart: Counterpart) -> String {
        var lines = ["USER persona:"]
        if let p = persona, p.isMinimallyComplete {
            if !p.displayName.isEmpty { lines.append("- name: \(p.displayName)") }
            let place = [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", ")
            if !place.isEmpty { lines.append("- lives in: \(place)") }
            if !p.occupation.isEmpty { lines.append("- work: \(p.occupation)") }
            if !p.household.isEmpty { lines.append("- household: \(p.household)") }
            if !p.interests.isEmpty {
                lines.append("- interests: \(p.interests.joined(separator: ", "))")
            }
        } else {
            lines.append("- (sparse — pick neutral but believable contexts)")
        }
        lines.append("")
        lines.append("COUNTERPART persona:")
        lines.append("- name: \(counterpart.name)")
        if !counterpart.relationship.isEmpty {
            lines.append("- relationship: \(counterpart.relationship)")
        }
        if !counterpart.location.isEmpty {
            lines.append("- about them: \(counterpart.location)")
        }
        if !counterpart.howWeMet.isEmpty {
            lines.append("- how they met: \(counterpart.howWeMet)")
        }
        if !counterpart.background.isEmpty {
            lines.append("- shared context: \(counterpart.background)")
        }
        if !counterpart.conversationStyle.isEmpty {
            lines.append("- talks like: \(counterpart.conversationStyle)")
        }
        if !counterpart.commonTopics.isEmpty {
            lines.append("- common topics: \(counterpart.commonTopics)")
        }
        if !counterpart.freeNotes.isEmpty {
            lines.append("- notes: \(counterpart.freeNotes)")
        }
        return lines.joined(separator: "\n")
    }

    private static func counterpartFallback(counterpart: Counterpart) -> [SuggestedTopic] {
        [
            SuggestedTopic(title: "A quick catch-up with \(counterpart.name)",
                           blurb: "Open with what's been on your mind lately."),
            SuggestedTopic(title: "Something on your mind you've been meaning to bring up",
                           blurb: "Pick a real-life thing you'd actually want their take on.")
        ]
    }

    // MARK: - Category-grounded situations (scenario composer "Ideas" button)

    /// Generate diverse SPECIFIC situations inside a chosen category ("Cafe",
    /// "Travel", or the user's own keyword) — the AI replacement for the old
    /// hardcoded drill-down tree. Each is a concrete, ready-to-practice moment
    /// the learner can tap to fill the composer, then edit.
    static func suggestForCategory(
        category: String,
        persona: UserPersona?,
        targetLanguage: String,
        count: Int = 10
    ) async throws -> [SuggestedTopic] {
        let system = categorySystemPrompt(targetLanguage: targetLanguage, count: count)
        let userMsg = categoryUserMessage(category: category, persona: persona)
        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: userMsg)],
            maxTokens: 900
        )
        return payload.topics.map {
            SuggestedTopic(title: $0.title, blurb: $0.blurb, category: category)
        }
    }

    /// Classify a free-typed scenario into a CATEGORY, so custom input lands in
    /// the SAME (category + specific situation) structure the chip path builds.
    /// Reuses an existing category when one fits, else invents a short new one
    /// with a fitting icon — so a typed scenario never contradicts a stale
    /// category chip.
    struct CategoryResult: Decodable {
        let category: String
        let icon: String
        let isNew: Bool
        /// A tidy ≤6-word summary of the scenario for the card — NOT the raw
        /// prompt.
        let summary: String
    }

    static func categorize(
        text: String,
        existing: [String],
        iconOptions: [String],
        targetLanguage: String
    ) async throws -> CategoryResult {
        let system = """
        You sort a language-practice SCENARIO into a CATEGORY — a short place/theme
        bucket the app groups scenarios by — and give it a tidy title.

        Existing categories: \(existing.isEmpty ? "(none)" : existing.joined(separator: ", ")).

        Rules:
        - category: if one existing category clearly fits, return it EXACTLY,
          isNew=false. Otherwise invent a SHORT new one, 1–2 words, Title Case
          ("Interview", "Landlord", "Doctor", "Dating"), isNew=true.
        - icon: best-fitting SF Symbol name from THIS list only:
          \(iconOptions.joined(separator: ", ")). If nothing fits, "sparkles".
        - summary: a clean ≤6-word title of the SITUATION for a card
          ("Job interview practice", "Returning a jacket, no receipt"). NOT the
          user's raw words — a tidy paraphrase.

        Return STRICT JSON only — no prose, no code fences:
        { "category": "...", "icon": "...", "isNew": true, "summary": "..." }
        """
        return try await GeminiClient.shared.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: "scenario: \(text)")],
            maxTokens: 160
        )
    }

    /// Drill-down step: given the path the learner has picked so far (category,
    /// then narrowing choices), produce the NEXT level of options. Shallow
    /// paths get broad sub-areas; deeper paths get specific, concrete
    /// scenarios. Each option carries a chip label + a practiceable sentence.
    static func suggestForPath(
        path: [String],
        persona: UserPersona?,
        targetLanguage: String,
        count: Int = 8
    ) async throws -> [SuggestedTopic] {
        let system = pathSystemPrompt(targetLanguage: targetLanguage, count: count, depth: path.count)
        var lines = ["path: \(path.joined(separator: " > "))"]
        if let p = persona, p.isMinimallyComplete {
            if !p.occupation.isEmpty { lines.append("persona work: \(p.occupation)") }
            if !p.household.isEmpty { lines.append("persona household: \(p.household)") }
            let place = [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", ")
            if !place.isEmpty { lines.append("persona lives in: \(place)") }
        }
        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: lines.joined(separator: "\n"))],
            maxTokens: 900
        )
        return payload.topics.map { SuggestedTopic(title: $0.title, blurb: $0.blurb) }
    }

    private static func pathSystemPrompt(targetLanguage: String, count: Int, depth: Int) -> String {
        let levelGuidance = depth <= 1
            ? """
              The path is just the top CATEGORY. Return \(count) broad SUB-AREAS
              within it — the natural groupings a learner would drill into next.
              e.g. Travel → "at the airport", "at the hotel", "getting around",
              "eating out abroad", "an emergency", "border / immigration".
              These are still buckets, not one specific moment.
              """
            : """
              The path is already narrowed. Return \(count) SPECIFIC, concrete
              scenarios — each a real moment with a hook, varied across ordinary,
              awkward, transactional, and emotional beats. e.g. Travel > hotel →
              "room isn't ready", "noisy room at night", "extending my stay",
              "a charge I don't recognize", "asking for a late checkout".
              """
        return """
        You help an advanced \(LanguageCatalog.englishName(targetLanguage)) learner build a
        conversation scenario by drilling down one step at a time.

        \(levelGuidance)

        Return STRICT JSON only — no prose, no code fences:
        { "topics": [ { "title": "...", "blurb": "..." } ] }

        Rules:
        - title: a SHORT chip label, 2–4 words, no trailing punctuation.
        - blurb: ONE first-person sentence usable AS the scenario if the learner
          stops here — as specific as the current depth allows. ≤ 160 chars.
        - English. Maximize variety; no two nearly identical.
        """
    }

    private static func categorySystemPrompt(targetLanguage: String, count: Int) -> String {
        """
        You generate language-practice SCENARIOS for an advanced \(LanguageCatalog.englishName(targetLanguage)) learner.
        The user picked a category (a place or theme). Suggest \(count) SPECIFIC,
        varied scenarios that realistically happen inside that category — the
        kind of moment where a 3–8 minute conversation naturally unfolds.

        These render as short tappable CHIPS, so cover a WIDE spread of beats:
        ordinary, awkward, mildly difficult, social, transactional, emotional.
        For "Cafe" go well beyond "ordering coffee": "order came out wrong",
        "wifi is down", "run into an old colleague", "asking to keep a table
        while you step out", "the card reader won't work", "complimenting the
        barista's latte art". No two nearly identical.

        If a persona is given, tilt toward their real life, but stay clearly
        inside the chosen category.

        Return STRICT JSON only — no prose, no code fences:
        { "topics": [ { "title": "...", "blurb": "..." } ] }

        Rules:
        - title: a SHORT chip label, 2–5 words, lowercase-ish, no trailing
          punctuation ("order came out wrong", "asking for a recommendation").
        - blurb: ONE full first-person sentence that becomes the scenario when
          tapped ("At a cafe: my order came out wrong and I want to point it
          out politely and get it fixed."). ≤ 160 chars.
        - Both in English. Maximize variety across the \(count).
        """
    }

    private static func categoryUserMessage(category: String, persona: UserPersona?) -> String {
        var lines = ["category: \(category)"]
        if let p = persona, p.isMinimallyComplete {
            if !p.occupation.isEmpty { lines.append("persona work: \(p.occupation)") }
            if !p.household.isEmpty { lines.append("persona household: \(p.household)") }
            let place = [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", ")
            if !place.isEmpty { lines.append("persona lives in: \(place)") }
            if !p.interests.isEmpty { lines.append("persona interests: \(p.interests.joined(separator: ", "))") }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Fallback

    private static func fallback(persona: UserPersona?) -> [SuggestedTopic] {
        let city = persona?.city.isEmpty == false ? persona!.city : "your city"
        return [
            SuggestedTopic(title: "Catching up — a friend asks how your week's been",
                           blurb: "Open with what you actually did, not stock phrases."),
            SuggestedTopic(title: "Explaining what you do to someone you just met in \(city)",
                           blurb: "They're curious. Avoid jargon, find the human angle."),
            SuggestedTopic(title: "A small problem you need to politely raise",
                           blurb: "Something at work or in your neighborhood that bugs you.")
        ]
    }
}
