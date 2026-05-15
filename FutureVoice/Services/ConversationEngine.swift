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
        topic: String
    ) -> String {
        let patterns = topPatterns.prefix(3).map { "- \($0.mistake) → \($0.correction) (\($0.context))" }
            .joined(separator: "\n")
        let weak = weakVocabAreas.isEmpty ? "—" : weakVocabAreas.joined(separator: ", ")

        return """
        You are the user's "fluent self" speaking \(targetLanguage).
        You sound natural, warm, and casual — like a slightly more confident version of them.

        About the user (learner profile):
        - Native language: \(nativeLanguage)
        - Proficiency: \(level.rawValue.uppercased())
        - Known recurring patterns to gently work around or surface:
        \(patterns.isEmpty ? "  (none yet — this is an early session)" : patterns)
        - Weak vocab areas: \(weak)

        Topic: \(topic)

        Rules:
        - Reply in \(targetLanguage) only.
        - 1–3 sentences per turn.
        - Match their level — don't use vocab far above \(level.rawValue.uppercased()).
        - If they make a mistake, do NOT correct mid-conversation.
          Just respond naturally. Corrections come in the post-session summary.
        - Ask follow-up questions to keep the conversation going.
        """
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

        Return STRICT JSON only — no prose, no code fences:
        {
          "phrases_used": [
            { "user_said": "...", "fluent_alternative": "...", "reason": "..." }
          ],
          "new_patterns_detected": [
            { "mistake": "...", "correction": "...", "context": "...", "frequency_hint": "rare|sometimes|often" }
          ],
          "suggested_drills": ["phrase 1", "phrase 2", "phrase 3"],
          "overall_note": "1-2 sentence encouraging note"
        }

        Rules:
        - Max 5 phrases_used. Pick the most teachable ones.
        - Max 3 suggested_drills.
        - Tone: warm, never condescending.
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
    let phrases_used: [Phrase]
    let new_patterns_detected: [Pattern]
    let suggested_drills: [String]
    let overall_note: String

    func toDomain(now: Date = Date()) -> SessionSummary {
        SessionSummary(
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
            overallNote: overall_note
        )
    }
}
