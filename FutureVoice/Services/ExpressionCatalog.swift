import Foundation

/// Every expression the app is asking you to study, from wherever it came.
///
/// There are two sources and they used to live in two worlds. `VocabStore`
/// holds phrases the learner ACTUALLY SAID (ingested from a talk's summary,
/// verified against their own turns). A Watch book's expressions are written
/// with its scene and stored on the `Scenario` — they never touched
/// `VocabStore`, so a book could show six expressions while the Expressions
/// page showed none of them, and the Practice tile counted none of them
/// either. The daily deck, meanwhile, already dealt both — so the same phrase
/// was study material in one place and invisible in another.
///
/// This is the one list. It deliberately does NOT copy scene expressions into
/// `VocabStore`: that store's rows carry "used N times", and a phrase from a
/// scene the learner hasn't spoken yet has been used zero times. Merging at
/// read time keeps both truths — what you've said, and what you've been given
/// to learn — and lets each row say which it is.
@MainActor
enum ExpressionCatalog {

    struct Item: Identifiable {
        /// Display text (scene expressions keep their casing; store keys are
        /// lowercased).
        let text: String
        /// Normalized identity, shared across both sources.
        let key: String
        let origin: Origin
        /// Sort date — last used, or when the scene that carries it was made.
        let at: Date

        var id: String { key }

        enum Origin {
            /// The learner said it in a talk; `count` is how many times.
            case said(count: Int)
            /// It came with a Watch book's scene, named here.
            case scene(String)
        }

        var isFromScene: Bool {
            if case .scene = origin { return true }
            return false
        }
    }

    static func normalizedKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Everything, most recent first. Said-it entries win when the same phrase
    /// appears in both — having used it is the more interesting fact, and it
    /// carries the count the row shows.
    static func all(scenarios: [Scenario], store: VocabStore = .shared) -> [Item] {
        var byKey: [String: Item] = [:]

        for scenario in scenarios where !scenario.isArchived {
            let title = scenario.environment.trimmingCharacters(in: .whitespacesAndNewlines)
            let at = scenario.lastUsedAt ?? scenario.createdAt
            for expression in scenario.curriculum?.expressions ?? [] {
                let key = normalizedKey(expression.text)
                guard !key.isEmpty, byKey[key] == nil else { continue }
                byKey[key] = Item(text: expression.text, key: key,
                                  origin: .scene(title), at: at)
            }
        }

        // Said-it entries overwrite whatever a scene contributed.
        for entry in store.expressionEntries() {
            let key = normalizedKey(entry.text)
            guard !key.isEmpty else { continue }
            byKey[key] = Item(text: entry.text, key: key,
                              origin: .said(count: entry.count), at: entry.lastAt)
        }

        return byKey.values.sorted { $0.at > $1.at }
    }

    /// The "to study" set — what the Practice tile counts and the page's
    /// default lens shows.
    static func toStudy(scenarios: [Scenario], store: VocabStore = .shared) -> [Item] {
        all(scenarios: scenarios, store: store)
            .filter { !store.isKnownExpression($0.text) }
    }
}
