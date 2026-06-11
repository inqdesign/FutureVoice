import Foundation

/// Turns the user's onboarding interests into conversation topics grounded
/// in CURRENT news, via Gemini's Google Search tool. The blurb is fed
/// straight into the conversation system prompt as starting context, so it
/// must stay factual — facts from the search results only, no embellishment.
enum NewsTopicEngine {

    private struct Payload: Decodable {
        struct Item: Decodable {
            let title: String
            let blurb: String
        }
        let topics: [Item]
    }

    static func suggest(
        interests: [String],
        targetLanguage: String,
        now: Date = Date()
    ) async throws -> [SuggestedTopic] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let payload: Payload = try await GeminiClient.shared.sendJSON(
            system: systemPrompt(targetLanguage: targetLanguage),
            messages: [GeminiClient.Message(
                role: .user,
                content: "Today is \(fmt.string(from: now)). Interests: \(interests.joined(separator: ", "))"
            )],
            maxTokens: 1200,
            searchGrounding: true
        )
        return payload.topics.map { SuggestedTopic(title: $0.title, blurb: $0.blurb) }
    }

    private static func systemPrompt(targetLanguage: String) -> String {
        """
        Use Google Search to find 4 recent news stories (published within the
        last 7 days, each from a different story) matching the user's
        interests. The user is a \(targetLanguage) learner who will discuss
        one of them in conversation practice.

        Return STRICT JSON only — no prose, no code fences:
        { "topics": [ { "title": "...", "blurb": "..." } ] }

        - title: how a friend would bring the story up in \(targetLanguage),
          ≤ 10 words ("Did you see the news about …?" energy, not a headline).
        - blurb: 1–2 sentences of plain facts from the search results — what
          happened, who, when. Nothing that isn't in the sources: no
          speculation, no color, no invented details.
        """
    }
}
