import Foundation

/// Every word the app is asking you to study, from wherever it came — the
/// word-level twin of `ExpressionCatalog`, and for the same reason.
///
/// Two sources. `VocabStore.studying` is the notebook: words the learner
/// KEPT by hand. A Watch book's words are written with its scene and live on
/// the `Scenario`, never touching `VocabStore` — so a book could ask for six
/// words the library had never heard of.
///
/// The Practice tile's "To study" number is `toStudy(...).count`, and this is
/// the list the tile pushes. That is the whole point of the type: the number
/// and the page it opens are the same computation, so the count can always be
/// checked by looking. It used to open the CEFR cloud instead, which counts
/// something else entirely (known / total core vocabulary), and the tile's
/// number appeared nowhere on the page it led to.
///
/// Like the expression catalog it does NOT copy scene words into `VocabStore`:
/// a store record means "you used this", which a word from an unspoken scene
/// hasn't been. Merging at read time keeps both truths and lets each row say
/// which it is.
@MainActor
enum WordCatalog {

    struct Item: Identifiable {
        /// Display text — scene words keep their casing, notebook keys are
        /// lemmas (lowercase).
        let text: String
        /// Normalized identity, shared across both sources.
        let key: String
        let origin: Origin
        /// Sort date: when it was last used/marked, or when the scene that
        /// carries it was made. Nil for a kept word never used out loud.
        let at: Date?

        var id: String { key }

        enum Origin {
            /// In the notebook. `count` is how many times the learner has
            /// actually said it (0 = kept but not yet used).
            case kept(count: Int)
            /// It came with a Watch book's scene, named here.
            case scene(String)
            /// Straight from the core vocabulary pool — nothing personal about
            /// it yet. Only the All-words lens and whole-pool search mint these.
            case vocabulary
        }
    }

    /// Everything still to study, notebook first (newest kept at the top),
    /// then scene words by how recent their book is.
    ///
    /// A word marked known leaves on its own: `markKnown` removes it from
    /// `studying`, and a scene word with a `VocabStore` record is filtered
    /// out here — the same two rules the tile's count already used.
    static func toStudy(scenarios: [Scenario], store: VocabStore = .shared) -> [Item] {
        var seen = Set<String>()
        var kept: [Item] = []
        for word in store.studying {
            let key = word.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            let record = store.records[word]
            kept.append(Item(text: word, key: key,
                             origin: .kept(count: record?.count ?? 0),
                             at: record?.lastAt))
        }

        var fromScenes: [Item] = []
        for scenario in scenarios.sorted(by: { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) })
        where !scenario.isArchived {
            let title = scenario.environment.trimmingCharacters(in: .whitespacesAndNewlines)
            let at = scenario.lastUsedAt ?? scenario.createdAt
            for item in scenario.curriculum?.words ?? [] where item.masteredAt == nil {
                let key = item.text.lowercased()
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                // Both spellings, exactly as the tile counted them: the raw
                // text and its lemma. Either having a record means the learner
                // has already retired the word.
                guard store.state(of: VocabStore.lookupKey(for: item.text)) == nil,
                      store.state(of: key) == nil else { continue }
                fromScenes.append(Item(text: item.text, key: key,
                                       origin: .scene(title), at: at))
            }
        }

        return kept + fromScenes
    }

    /// The other lens: words the learner has retired. Self-marked known and
    /// used-in-a-talk are one pile here — both mean "not asking about it".
    static func known(store: VocabStore = .shared) -> [Item] {
        store.records
            .sorted { $0.value.lastAt > $1.value.lastAt }
            .map { Item(text: $0.key, key: $0.key,
                        origin: .kept(count: $0.value.count), at: $0.value.lastAt) }
    }
}
