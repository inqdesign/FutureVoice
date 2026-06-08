import Foundation

/// Builds prompts for the "fluent self" conversation and the post-session summary.
///
/// Keeps prompt strings close to spec §7 so they can be iterated without touching transport code.
enum ConversationEngine {

    /// System prompt for an in-conversation turn.
    static func conversationSystemPrompt(
        targetLanguage: String,
        nativeLanguage: String,
        level: CEFRLevel,
        topPatterns: [LearnerPattern],
        weakVocabAreas: [String],
        topic: String,
        persona: UserPersona? = nil
    ) -> String {
        let patterns = topPatterns.prefix(3).map { "- \($0.mistake) → \($0.correction) (\($0.context))" }
            .joined(separator: "\n")
        let weak = weakVocabAreas.isEmpty ? "—" : weakVocabAreas.joined(separator: ", ")

        return """
        You're in a real-feeling SPOKEN \(targetLanguage) conversation with the user. \
        The point is for it to sound like two actual people talking — not a \
        language-class exchange. Read everything below, then talk like a real person.

        \(personaBlock(persona))

        Language profile:
        - Native language: \(nativeLanguage)
        - Proficiency: \(level.rawValue.uppercased())
        - Recurring patterns to be gently aware of:
        \(patterns.isEmpty ? "  (none yet — this is an early session)" : patterns)
        - Weak vocab areas: \(weak)

        Starting context: \(topic.isEmpty ? "open / casual catch-up" : topic)

        HOW TO TALK — read this carefully, this is the whole game:

        - This is SPOKEN, not written. Use contractions ("I'm", "you're", "don't"). \
          Drop fillers in occasionally where a real speaker would: "yeah", "well", \
          "I mean", "honestly", "you know", "uh", "hm". Not every turn — sparingly, \
          where it fits.
        - Keep responses SHORT. Most turns 1 sentence. Sometimes 2. Rarely 3. \
          Real conversation is lots of brief turns, not paragraphs.
        - VARY turn length. Sometimes the right response is just "yeah", "really?", \
          "huh", "mm-hm", or "oh god" — then let them keep talking. Other times \
          you go a bit longer.
        - REACT first, then respond. "Oh wow, yeah —" "Hmm." "Wait, really?" Open \
          with the human reaction, THEN say what you want to say.
        - DO NOT always end with a question. Statements + reactions pass the ball \
          too. Ending every turn with a question feels like an interview.
        - DON'T summarize what they just said back to them. Just respond.
        - Match their ENERGY. Excited → excited. Tired → relaxed. Frustrated → \
          empathetic. Don't be perpetually upbeat.
        - Reference the user's life naturally when it fits — never quiz them about \
          their own profile. The profile is for color, not for prompts.

        ROLE (if the starting context is in "environment=… | role=…" format):
        - Play that role as the OTHER person in the scene. The doctor. The \
          shopkeeper. The friend at the cafe. Don't narrate. Don't break character.
        - Open the conversation as that character actually would — short, in-scene, \
          first thing they'd say. Not "Welcome! How can I help you today?" unless \
          that's literally the role.
        - When no role is specified, you're a warm but real friend.

        WHAT YOU RECEIVE FROM THE USER:
        - The user's words come to you as TEXT, transcribed from their speech
          by iOS speech-to-text. You did NOT hear them with ears. STT
          sometimes mishears ("book" ↔ "food", "their" ↔ "there", etc.) and
          you have NO way to know what the audio actually was.
        - Therefore: NEVER claim YOU misheard, mis-listened, or made a
          hearing mistake. You cannot have. If a line seems off or doesn't
          fit the prior turn, the STT (not you) probably got a word wrong.
        - When the user's text seems off, ask naturally: "Wait — food? Or
          did you mean book?" or "Sorry, I missed that — could you say
          again?" Then continue from their answer.
        - DON'T silently rewrite the user's words to what you think they
          meant. Don't say "Oh, you want to discuss the *book*" when their
          text said food. Take their text at face value and ask if unsure.
        - When you ask a clarifier, keep it ONE short question — don't
          apologize at length.

        WHO YOU ARE — KNOWLEDGE:
        - You are the user's FUTURE self — a smarter, more well-read, more
          fluent version of them. You have read broadly. You've seen the
          films, heard the records, know the books, the historical figures,
          the recent news, the philosophy, the science.
        - When the user mentions ANY topic — a book, a film, a person, a
          place, an idea — you ENGAGE with substance. Share what you know
          about it. Have an opinion. Notice a theme. Mention a character.
          Make a connection to something else.

        NEVER do these — they make you sound dumber than the user:
          - "I haven't read it / haven't seen it / haven't heard of it"
          - "I'm not familiar with that"
          - "What's it about?" as your PRIMARY response to a well-known work
          - Vague deflections that throw the topic back without engaging

        INSTEAD do:
          - Say what struck you about the work — a character, an argument,
            a passage that stuck with you.
          - Take a position. "It's brilliant when X but the Y part felt off."
          - Connect to something adjacent. "It reminded me of [other work]
            because both…"
          - Ask follow-ups about THEIR take after sharing yours, not before.
          - The user being curious about a topic is a chance to talk ABOUT
            the topic, not to interview them about it.

        Role-play caveat: if a scenario role is set, you still know things
        — the role mostly governs TONE / FORMALITY / your relationship with
        the user, not your factual horizon. A doctor character can still
        have an opinion on a Rick Rubin book.

        STRICT:
        - Reply in \(targetLanguage) only.
        - Never correct the user mid-conversation. Corrections happen elsewhere.
        - Don't go above their proficiency (\(level.rawValue.uppercased())).
        """
    }

    /// Render the persona as a compact natural-language block to inject into
    /// system prompts. Returns a friendly fallback when no persona is set.
    static func personaBlock(_ persona: UserPersona?) -> String {
        guard let p = persona, p.isMinimallyComplete else {
            return "About the user: (no persona yet — keep things generic but warm)"
        }
        var lines = ["About the user (use these naturally, don't list them):"]
        if !p.displayName.isEmpty { lines.append("- Name: \(p.displayName)") }
        let place = [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", ")
        if !place.isEmpty {
            let stay = p.lengthOfStay.isEmpty ? "" : " (\(p.lengthOfStay))"
            lines.append("- Lives in: \(place)\(stay)")
        }
        if !p.occupation.isEmpty { lines.append("- Does: \(p.occupation)") }
        if !p.household.isEmpty { lines.append("- Household: \(p.household)") }
        if !p.interests.isEmpty { lines.append("- Interests: \(p.interests.joined(separator: ", "))") }
        if !p.englishSituations.isEmpty {
            lines.append("- Needs English most for: \(p.englishSituations.joined(separator: ", "))")
        }
        if !p.freeNotes.isEmpty { lines.append("- Notes: \(p.freeNotes)") }
        return lines.joined(separator: "\n")
    }

    /// System prompt for generating the post-session summary as strict JSON.
    static func summarySystemPrompt(targetLanguage: String, profile: LearnerProfile) -> String {
        let profileJSON = (try? String(
            data: JSONEncoder().encode(profile),
            encoding: .utf8
        )) ?? "{}"

        return """
        The user just finished a conversation in \(targetLanguage).
        You will be given the full transcript with role labels.

        Their existing learner profile:
        \(profileJSON)

        You will also be given a `metrics` JSON object with deterministic stats
        (word counts, type-token ratio, words-per-minute, suggestion rate, etc.).
        Ground your scores in those numbers — do not invent.

        Return STRICT JSON only — no prose, no code fences:
        {
          "phrases_used": [
            { "user_said": "...", "fluent_alternative": "...", "reason": "..." }
          ],
          "new_patterns_detected": [
            { "mistake": "...", "correction": "...", "context": "...", "frequency_hint": "rare|sometimes|often" }
          ],
          "suggested_drills": ["phrase 1", "phrase 2", "phrase 3"],
          "overall_note": "1-2 sentence encouraging note",
          "scorecard": {
            "vocabulary":     { "score": 0, "note": "..." },
            "grammar":        { "score": 0, "note": "..." },
            "expressiveness": { "score": 0, "note": "..." },
            "fluency":        { "score": 0, "note": "..." },
            "top_line":       "one-sentence holistic read of the session"
          }
        }

        Rules:
        - Max 5 phrases_used. Pick the most teachable ones.
        - Max 3 suggested_drills.
        - Tone: warm, never condescending.
        - Scorecard scoring rubric (each 0–100, calibrated to the user's CEFR
          level, NOT to native-speaker absolutes):
          * vocabulary: range + appropriateness. Reference type_token_ratio and
            unique_word_count. Penalize repetition.
          * grammar: 100 - (suggestion_rate * 100), then nudge ±15 based on
            severity of remaining errors.
          * expressiveness: idiom use, register fit for topic, sentence-shape
            variety. Pure judgment call.
          * fluency: anchor on words_per_minute (60–120 wpm = healthy for B1-B2)
            and self_correction_hits. If words_per_minute is 0, set fluency to
            -1 and note "no timing data".
        - Each axis note ≤ 18 words, concrete (cite a metric or a phrase).
        - top_line: one warm sentence that ties the highest + lowest axis together.
        """
    }

    /// Formats the running transcript for the summary user message.
    static func formatTranscript(_ turns: [Turn]) -> String {
        turns.map { turn in
            let label = turn.role == .user ? "USER" : "FLUENT_SELF"
            return "[\(label)] \(turn.transcript)"
        }.joined(separator: "\n")
    }

    /// Maps prior `Turn`s into the role-tagged Claude message history.
    static func messages(from turns: [Turn]) -> [ClaudeClient.Message] {
        turns.map { turn in
            ClaudeClient.Message(
                role: turn.role == .user ? .user : .assistant,
                content: turn.transcript
            )
        }
    }

    /// Maps prior `Turn`s into Gemini's `contents` history (user / model roles).
    /// `tail` caps the number of turns sent to Gemini — long conversations
    /// otherwise balloon input tokens (and bills) without adding much fidelity.
    /// 12 turns ≈ ~6 back-and-forth exchanges, plenty of context.
    static func geminiMessages(from turns: [Turn], tail: Int = 12) -> [GeminiClient.Message] {
        let recent = turns.suffix(tail)
        return recent.map { turn in
            GeminiClient.Message(
                role: turn.role == .user ? .user : .model,
                content: turn.transcript
            )
        }
    }
}

/// JSON shape returned by Claude for `SessionSummary`. Kept separate from the
/// domain model so we can decode `frequency_hint` strings before mapping.
struct ClaudeSummaryPayload: Decodable {
    struct Phrase: Decodable {
        let user_said: String
        let fluent_alternative: String
        let reason: String
    }
    struct Pattern: Decodable {
        let mistake: String
        let correction: String
        let context: String
        let frequency_hint: String
    }
    struct Axis: Decodable {
        let score: Int
        let note: String
    }
    struct Scorecard: Decodable {
        let vocabulary: Axis
        let grammar: Axis
        let expressiveness: Axis
        let fluency: Axis
        let top_line: String
    }
    let phrases_used: [Phrase]
    let new_patterns_detected: [Pattern]
    let suggested_drills: [String]
    let overall_note: String
    let scorecard: Scorecard?

    func toDomain(now: Date = Date()) -> SessionSummary {
        let card: SessionScorecard? = scorecard.map { sc in
            func axis(_ a: Axis) -> AxisScore {
                AxisScore(score: max(0, min(100, a.score)), note: a.note)
            }
            // Fluency rubric uses -1 to signal "no timing data". Surface that
            // by clamping back to 0 and rewriting the note, so the UI just
            // shows a friendly placeholder rather than a negative bar.
            let fluencyAxis: AxisScore
            if sc.fluency.score < 0 {
                fluencyAxis = AxisScore(score: 0, note: "Speak a bit more next session for a fluency read.")
            } else {
                fluencyAxis = axis(sc.fluency)
            }
            return SessionScorecard(
                vocabulary: axis(sc.vocabulary),
                grammar: axis(sc.grammar),
                expressiveness: axis(sc.expressiveness),
                fluency: fluencyAxis,
                pronunciation: nil,
                topLine: sc.top_line
            )
        }
        return SessionSummary(
            phrasesUsed: phrases_used.map {
                PhraseFeedback(userSaid: $0.user_said, fluentAlternative: $0.fluent_alternative, reason: $0.reason)
            },
            newPatternsDetected: new_patterns_detected.map {
                let freq: Int
                switch $0.frequency_hint.lowercased() {
                case "often":     freq = 5
                case "sometimes": freq = 2
                default:          freq = 1
                }
                return LearnerPattern(
                    mistake: $0.mistake,
                    correction: $0.correction,
                    context: $0.context,
                    frequency: freq,
                    lastSeenAt: now
                )
            },
            suggestedDrills: suggested_drills,
            overallNote: overall_note,
            scorecard: card
        )
    }
}
