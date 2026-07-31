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
                maxTokens: 800,
                purpose: "topics"
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
                maxTokens: 900,
                purpose: "topics"
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
            maxTokens: 900,
            purpose: "topics"
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
            // Pure classification (category + icon + short label) — utility
            // tier; the learner-facing idea GENERATION stays on the default.
            model: .flashLite31,
            maxTokens: 160,
            purpose: "topics"
        )
    }

    /// Drill-down step: given the path the learner has picked so far (category,
    /// then narrowing choices), produce the NEXT level of options. Shallow
    /// paths get broad sub-areas; deeper paths get specific, concrete
    /// scenarios. Each option carries a chip label + a practiceable sentence.
    static func suggestForPath(
        path: [String],
        persona: UserPersona?,
        counterpart: Counterpart? = nil,
        targetLanguage: String,
        count: Int = 6
    ) async throws -> [SuggestedTopic] {
        let system = pathSystemPrompt(targetLanguage: targetLanguage, count: count,
                                      depth: path.count, counterpart: counterpart)
        var lines = ["path: \(path.joined(separator: " > "))"]
        if let p = persona, p.isMinimallyComplete {
            if !p.occupation.isEmpty { lines.append("persona work: \(p.occupation)") }
            if !p.household.isEmpty { lines.append("persona household: \(p.household)") }
            let place = [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", ")
            if !place.isEmpty { lines.append("persona lives in: \(place)") }
        }
        if let c = counterpart {
            lines.append("")
            lines.append("COUNTERPART (the scene is WITH this person):")
            lines.append("- name: \(c.name)")
            if !c.relationship.isEmpty { lines.append("- relationship: \(c.relationship)") }
            if !c.howWeMet.isEmpty { lines.append("- how they met: \(c.howWeMet)") }
            if !c.background.isEmpty { lines.append("- shared context: \(c.background)") }
            if !c.commonTopics.isEmpty { lines.append("- common topics: \(c.commonTopics)") }
        }
        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: lines.joined(separator: "\n"))],
            // Chips are short. Output length IS the latency here — the learner
            // is staring at skeletons until the last token lands, so keep the
            // ceiling tight instead of letting the model ramble.
            maxTokens: 600,
            purpose: "topics"
        )
        return payload.topics.map { SuggestedTopic(title: $0.title, blurb: $0.blurb) }
    }

    // MARK: - Instant seeds (level 1 of the preset categories)

    /// Broad sub-areas for the built-in categories, shipped in the binary.
    ///
    /// Level 1 of the drill-down is generic by nature ("at the hotel", "at the
    /// checkout") — asking Gemini for it bought no personalization but cost
    /// every learner a multi-second wait right after their first tap. These
    /// render instantly; the model still writes level 2 (where the specific,
    /// persona-tilted moments live), and "More" re-asks it here too.
    ///
    /// Returns nil for anything not in the preset list (custom categories,
    /// counterpart-scoped paths) — those still go to the model.
    static func seedSubAreas(for category: String) -> [SuggestedTopic]? {
        seeds[category.lowercased()]
    }

    private static let seeds: [String: [SuggestedTopic]] = [
        "cafe": [
            .init(title: "ordering", blurb: "At a cafe: ordering what I actually want, with the changes I want, without pointing at the menu."),
            .init(title: "paying", blurb: "At a cafe: paying at the register when something about the payment doesn't go smoothly."),
            .init(title: "something's wrong", blurb: "At a cafe: my order isn't what I asked for and I want it fixed without making it awkward."),
            .init(title: "finding a seat", blurb: "At a cafe: it's packed and I have to ask about a free seat or share a table with someone."),
            .init(title: "chatting with staff", blurb: "At a cafe: a bit of real small talk with the barista while my drink is being made."),
            .init(title: "working from here", blurb: "At a cafe: asking about the wifi, a plug, or staying a while at my table.")
        ],
        "travel": [
            .init(title: "at the airport", blurb: "At the airport: check-in, security, or the gate — and a question I need answered fast."),
            .init(title: "at the hotel", blurb: "At the hotel front desk: sorting out my room, my stay, or something that isn't right."),
            .init(title: "getting around", blurb: "Getting around a city I don't know: tickets, directions, and the wrong stop."),
            .init(title: "eating out abroad", blurb: "Eating out in a place where I don't know the menu, the customs, or how ordering works."),
            .init(title: "border control", blurb: "At immigration: answering the officer's questions about my trip, calmly and clearly."),
            .init(title: "when it goes wrong", blurb: "Travel gone wrong: a delay, a lost bag, or a booking that doesn't exist.")
        ],
        "work": [
            .init(title: "in a meeting", blurb: "In a team meeting: making my point, answering questions, and handling pushback."),
            .init(title: "with my manager", blurb: "A one-on-one with my manager about something I actually need from them."),
            .init(title: "interviews", blurb: "An interview: walking through my experience and why I want this role."),
            .init(title: "with a client", blurb: "A call with a client: setting expectations and handling what they ask for."),
            .init(title: "small talk at work", blurb: "The unplanned work talk — kitchen, hallway, before the meeting starts."),
            .init(title: "difficult conversations", blurb: "At work: raising something uncomfortable with a colleague, professionally.")
        ],
        "health": [
            .init(title: "at the doctor", blurb: "At the doctor's office: describing what's wrong and answering their questions."),
            .init(title: "booking an appointment", blurb: "Booking a medical appointment and explaining how urgent it is."),
            .init(title: "at the pharmacy", blurb: "At the pharmacy: asking what to take, how to take it, and what's covered."),
            .init(title: "at the dentist", blurb: "At the dentist: describing the pain and understanding what they want to do."),
            .init(title: "insurance & paperwork", blurb: "Sorting out health insurance or a form nobody explains properly."),
            .init(title: "something urgent", blurb: "An urgent health moment where I have to explain the situation fast.")
        ],
        "shopping": [
            .init(title: "asking for help", blurb: "In a store: asking staff to help me find or choose the right thing."),
            .init(title: "trying things on", blurb: "In a store: sizes, fit, and asking for something different."),
            .init(title: "returns & refunds", blurb: "Returning something and dealing with a clerk who isn't keen to take it back."),
            .init(title: "at the checkout", blurb: "At the checkout: prices, discounts, or something ringing up wrong."),
            .init(title: "an online order", blurb: "An online order that arrived late, wrong, or damaged — and getting it sorted."),
            .init(title: "at the market", blurb: "At a market stall: asking what's good today and buying the right amount.")
        ],
        "social": [
            .init(title: "meeting someone new", blurb: "Meeting someone for the first time and getting past the opening two minutes."),
            .init(title: "catching up", blurb: "Catching up with someone I haven't seen in a while."),
            .init(title: "at a party", blurb: "At a party where I barely know anyone and have to join a conversation."),
            .init(title: "making plans", blurb: "Making plans with someone: suggesting, negotiating, and pinning down a time."),
            .init(title: "saying no", blurb: "Turning down an invitation or a favor without it getting weird."),
            .init(title: "something personal", blurb: "A conversation about something that actually matters to one of us.")
        ],
        "school": [
            .init(title: "in class", blurb: "In class: asking a question or saying I didn't follow something."),
            .init(title: "with a teacher", blurb: "Talking to a teacher one-on-one about my work or a problem I have."),
            .init(title: "group work", blurb: "Group work: dividing up the work and dealing with someone not pulling their weight."),
            .init(title: "admin & enrollment", blurb: "At the school office: enrollment, documents, or a deadline I need moved."),
            .init(title: "exams & deadlines", blurb: "Asking about an exam, a grade, or an extension I need."),
            .init(title: "around campus", blurb: "The everyday campus talk — before class, in the hallway, at lunch.")
        ],
        "phone": [
            .init(title: "booking something", blurb: "On the phone: booking an appointment or a table and confirming the details."),
            .init(title: "customer service", blurb: "On the phone with customer service about a problem they keep not fixing."),
            .init(title: "a bad connection", blurb: "On a call where I can't hear well and have to ask them to repeat things."),
            .init(title: "leaving a message", blurb: "Leaving a clear voicemail with everything they need to call me back."),
            .init(title: "canceling something", blurb: "Calling to cancel a contract or subscription while they talk me out of it."),
            .init(title: "an official call", blurb: "Calling an office, landlord, or utility about something I need resolved.")
        ]
    ]

    private static func pathSystemPrompt(targetLanguage: String, count: Int, depth: Int,
                                         counterpart: Counterpart? = nil) -> String {
        let withPerson = counterpart.map { c in
            """

            EVERY scenario is WITH \(c.name)\(c.relationship.isEmpty ? "" : " (\(c.relationship))") —
            a real moment the two of them would plausibly share, grounded in
            their relationship. The title/blurb should read as being with them
            ("catch up over coffee", "help \(c.name) move a couch"), NOT a generic
            stranger interaction. Write the blurb in the first person about that
            shared moment.
            """
        } ?? ""
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
        \(withPerson)
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
