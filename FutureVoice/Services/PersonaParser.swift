import Foundation

/// Cleans up the answers the user DICTATED during persona onboarding. Unlike
/// `CounterpartParser` (one blob → many fields), each answer here was already
/// collected per category, so this is a polish pass — same field in, same
/// field out: drop restarts and filler, keep every concrete detail, land on
/// compact English the conversation prompt can use as ground truth.
enum PersonaParser {

    struct Polished: Decodable {
        let occupation: String
        let household: String
        let free_notes: String
    }

    /// Pass "" for any field the user typed (or skipped) — it comes back ""
    /// and the caller keeps what it had.
    static func polish(
        occupation: String,
        household: String,
        freeNotes: String,
        languageHint: String
    ) async throws -> Polished {
        let userMsg = """
        language_hint: \(languageHint)
        occupation_answer:
        \(occupation)

        household_answer:
        \(household)

        free_notes_answer:
        \(freeNotes)
        """
        return try await GeminiClient.shared.sendJSON(
            system: systemPrompt(),
            messages: [GeminiClient.Message(role: .user, content: userMsg)],
            maxTokens: 500,
            purpose: "parse"
        )
    }

    private static func systemPrompt() -> String {
        """
        While setting up a language-practice app, the user answered profile
        questions BY VOICE: what they do (occupation), who is in their daily
        life (household), and anything else about themselves (free notes).
        Spoken answers may be in their native language, casual, with restarts
        or trailing thoughts.

        Rewrite each answer as clean, compact English profile text. First
        person is implied — phrases like "Solo founder of an AI app for
        parents", not "I am a solo founder…".

        Return STRICT JSON only — no prose, no code fences:
        {
          "occupation": "...",
          "household": "...",
          "free_notes": "..."
        }

        Rules:
        - Keep every concrete detail the user gave; drop only filler,
          restarts, and repetition. Don't invent or generalize.
        - Proper names stay in the script the user used (보람 stays 보람).
        - 1–2 dense sentences per field, max.
        - An empty answer stays an empty string "".
        """
    }
}
