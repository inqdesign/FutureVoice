import Foundation

/// Every expression the app is asking you to study, from wherever it came.
///
/// THREE sources: phrases the learner said, phrases a Watch scene taught, and
/// phrases the fluent self used in a talk that the learner didn't
/// (`SessionSummary.expressionsOffered`). The last one is the newest and the
/// reason this type exists in its current shape — a call produces the app's
/// best material (in the learner's own voice, about their own situation) and
/// for a long time kept none of it: single words and four shadow lines
/// survived, the reusable chunks in between did not.
///
/// The first two used to live in two worlds. `VocabStore`
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
        /// Normalized identity, shared across every source.
        let key: String
        let origin: Origin
        /// Sort date — last used, when the scene that carries it was made, or
        /// when the talk it was heard in ended.
        let at: Date

        var id: String { key }

        enum Origin {
            /// The learner said it in a talk; `count` is how many times.
            case said(count: Int)
            /// It came with a Watch book's scene, named here.
            case scene(String)
            /// The fluent self said it in a talk, named here — material the
            /// learner has heard in their own voice but not yet produced.
            case heard(String)
        }

        var isFromScene: Bool {
            if case .scene = origin { return true }
            return false
        }
    }

    static func normalizedKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Everything, most recent first. Precedence when the same phrase arrives
    /// from more than one source: said-it wins over everything (having used it
    /// is the more interesting fact, and it carries the count the row shows),
    /// and heard-it wins over a scene (it is the more recent, more personal
    /// encounter).
    /// `sessions` defaults to every saved talk — the store keeps them in
    /// memory, and no caller has a different set in hand.
    static func all(scenarios: [Scenario],
                    sessions: [Session] = SessionStore.shared.load(),
                    store: VocabStore = .shared) -> [Item] {
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

        // Heard in a talk — overwrites a scene, loses to said-it below.
        // Archived talks drop out, the same way an archived scenario does:
        // putting a book away puts its material away.
        for session in sessions where session.archivedAt == nil {
            let title = (session.topic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let at = session.endedAt ?? session.startedAt
            for phrase in session.summary?.expressionsOffered ?? [] {
                let key = normalizedKey(phrase)
                guard !key.isEmpty else { continue }
                // Heard twice → the more recent talk names it, whatever order
                // the caller handed the sessions over in.
                if let existing = byKey[key], case .heard = existing.origin,
                   existing.at >= at { continue }
                byKey[key] = Item(text: phrase, key: key, origin: .heard(title), at: at)
            }
        }

        // Said-it entries overwrite whatever a scene or a talk contributed.
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
    static func toStudy(scenarios: [Scenario],
                        sessions: [Session] = SessionStore.shared.load(),
                        store: VocabStore = .shared) -> [Item] {
        all(scenarios: scenarios, sessions: sessions, store: store)
            .filter { !store.isKnownExpression($0.text) }
    }
}
