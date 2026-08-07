import Foundation
import Supabase

/// Reads conversation topics from the platform-wide news pool (the
/// `news-topics` Edge Function). Story generation happens SERVER-side at
/// most once per (category, day) for the whole platform — this client just
/// sends the user's interests and mixes what comes back. No credit charge.
enum NewsTopicEngine {

    struct ServerTopic: Decodable {
        let category: String
        let title: String
        let blurb: String
        /// Absent from pool rows cached before the facts field shipped.
        let facts: [String]?
    }
    private struct RequestPayload: Encodable {
        let categories: [String]
        let language: String
        let refresh: Bool
    }
    private struct ResponsePayload: Decodable {
        let topics: [ServerTopic]
        /// Categories the server is still generating. Absent on older
        /// deployments, which always answered fully-generated.
        let pending: [String]?
        /// A refresh actually started an extra batch (vs. the day's cap
        /// having stopped it) — so a bigger pool is on its way.
        let growing: Bool?
    }

    /// One fetch's worth of pool, plus whether more is still cooking
    /// server-side. A grounded batch takes ~10-30s, so the server answers
    /// with what it has and the caller polls for the rest.
    struct Pool {
        let topics: [SuggestedTopic]
        let pending: [String]
        let growing: Bool

        var isComplete: Bool { pending.isEmpty }
    }

    /// How many mixed topics the picker shows at once. The fetched POOL can
    /// be larger (server grows it on refresh) — the sheet rotates through it.
    static let maxShown = 6

    /// Poll cadence and ceiling while the server fills pending categories.
    /// 6 × 5s covers a slow grounded batch without hammering the function.
    static let pollInterval: Duration = .seconds(5)
    static let maxPolls = 6

    /// Fetch the day's topic pool. `refresh: true` asks the server to grow
    /// each category's pool by one more batch (capped server-side), so the
    /// refresh button actually surfaces NEW stories instead of re-reading
    /// the same daily cache.
    static func fetch(interests: [String], targetLanguage: String,
                      refresh: Bool = false) async throws -> Pool {
        let response: ResponsePayload = try await SupabaseProvider.shared.functions.invoke(
            "news-topics",
            options: FunctionInvokeOptions(
                body: RequestPayload(categories: interests, language: targetLanguage,
                                     refresh: refresh)
            )
        )
        // No cap here — return the full interleaved pool; display selection
        // (unseen-first, maxShown) happens in the sheet.
        return Pool(topics: interleaved(response.topics, cap: .max),
                    pending: response.pending ?? [],
                    growing: response.growing ?? false)
    }

    /// Round-robin across categories so the shown handful has variety —
    /// one story per interest first, then seconds, instead of three rocket
    /// stories before parenting ever appears.
    static func interleaved(_ items: [ServerTopic], cap: Int) -> [SuggestedTopic] {
        var byCategory: [String: [ServerTopic]] = [:]
        var order: [String] = []
        for item in items {
            if byCategory[item.category] == nil { order.append(item.category) }
            byCategory[item.category, default: []].append(item)
        }

        var out: [SuggestedTopic] = []
        var round = 0
        while out.count < cap {
            var added = false
            for category in order {
                guard let list = byCategory[category], round < list.count else { continue }
                out.append(SuggestedTopic(title: list[round].title, blurb: list[round].blurb,
                                          category: list[round].category,
                                          facts: list[round].facts))
                added = true
                if out.count >= cap { break }
            }
            if !added { break }
            round += 1
        }
        return out
    }
}
