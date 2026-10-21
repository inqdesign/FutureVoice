import SwiftUI

/// Margin notes under a sentence card's fluent line (`DrillView`,
/// `StudyDeckView`): one short line per change, at most three — the fixed
/// words, then why in a few native-language words. The marking itself is on
/// the learner's sentence (`cardProofread`) and needs no network; these
/// arrive when they're written, and if they can't be, the card's own reason
/// stands in. A card too small for them leaves them out whole (the cards'
/// own `ViewThatFits`).
struct CardCorrectionNotes: View {
    let said: String
    let fix: String
    let reason: String

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var cache = CorrectionExplanationCache.shared

    private var cacheKey: CorrectionExplanationCache.Key {
        .init(said: said, fix: fix, target: appState.targetLanguage, native: appState.nativeLanguage)
    }

    var body: some View {
        Group {
            if let changes = cache.explanations[cacheKey]?.changes {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(changes, id: \.self) { CorrectionNoteLine(change: $0, onCard: true) }
                }
            } else if cache.failed.contains(cacheKey), !reason.isEmpty {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // An empty Group draws nothing, and a view that isn't drawn
                // never runs its task.
                Color.clear.frame(height: 0)
            }
        }
        .task(id: cacheKey) { await cache.load(cacheKey, reason: reason) }
    }
}

/// One note: the fixed words, then the reason in a few words.
struct CorrectionNoteLine: View {
    let change: CorrectionExplanation.Change
    var onCard: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "pencil")
                .font(.caption2.weight(.bold))
                .foregroundStyle(onCard ? Color.white.opacity(0.72) : .secondary)
            (Text(change.now.isEmpty ? change.was : change.now)
                .fontWeight(.semibold)
                .strikethrough(change.now.isEmpty)
             + Text("  ")
             + Text(change.why)
                .foregroundStyle(onCard ? Color.white.opacity(0.85) : .secondary))
                .font(.footnote)
                .foregroundStyle(onCard ? Color.white : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One copy of each explanation in memory, so the top card and the same
/// card met again in one sitting share a single load.
@MainActor
final class CorrectionExplanationCache: ObservableObject {
    static let shared = CorrectionExplanationCache()

    struct Key: Hashable { let said, fix, target, native: String }

    @Published private(set) var explanations: [Key: CorrectionExplanation] = [:]
    @Published private(set) var failed: Set<Key> = []
    private var loading: Set<Key> = []

    func load(_ key: Key, reason: String) async {
        guard explanations[key] == nil, !loading.contains(key) else { return }
        if let hit = CorrectionExplainer.cached(said: key.said, fix: key.fix,
                                                target: key.target, native: key.native) {
            explanations[key] = hit
            return
        }
        loading.insert(key)
        defer { loading.remove(key) }
        do {
            explanations[key] = try await CorrectionExplainer.explain(
                said: key.said, fix: key.fix, reason: reason, target: key.target, native: key.native)
        } catch {
            if !Task.isCancelled { failed.insert(key) }
        }
    }
}
