import SwiftUI

/// Margin notes under a sentence card's fluent line (`DrillView`,
/// `StudyDeckView`): one short line per change — the fixed words, then why
/// in a few native-language words. The marking itself is on the learner's
/// sentence (`cardProofread`) and needs no network; these arrive when
/// they're written, and if they can't be, the card's own reason stands in.
///
/// The card has a fixed height, so it shows as many notes as FIT
/// (`ViewThatFits`) and the rest open in a sheet, never clipped.
struct CardCorrectionNotes: View {
    let said: String
    let fix: String
    let reason: String

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var cache = CorrectionExplanationCache.shared
    @State private var showingAll = false

    private var cacheKey: CorrectionExplanationCache.Key {
        .init(said: said, fix: fix, target: appState.targetLanguage, native: appState.nativeLanguage)
    }

    var body: some View {
        let changes = cache.explanations[cacheKey]?.changes
        ViewThatFits(in: .vertical) {
            if let changes {
                ForEach((1...max(min(changes.count, 3), 1)).reversed(), id: \.self) { shown in
                    notes(changes, shown: shown)
                }
                moreButton(changes.count)
            } else if cache.failed.contains(cacheKey), !reason.isEmpty {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Color.clear.frame(height: 0)
        }
        .task(id: cacheKey) { await cache.load(cacheKey, reason: reason) }
        .sheet(isPresented: $showingAll) {
            if let changes { CorrectionChangesSheet(changes: changes) }
        }
    }

    private func notes(_ changes: [CorrectionExplanation.Change], shown: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(changes.prefix(shown), id: \.self) { change in
                CorrectionNoteLine(change: change, onCard: true)
            }
            if shown < changes.count { moreButton(changes.count - shown) }
        }
    }

    private func moreButton(_ count: Int) -> some View {
        Button { showingAll = true } label: {
            Text("\(count) more")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
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

/// Every note, for a card that couldn't hold them all.
private struct CorrectionChangesSheet: View {
    let changes: [CorrectionExplanation.Change]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(changes, id: \.self) { CorrectionNoteLine(change: $0) }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

/// One copy of each explanation in memory, so the card's several
/// `ViewThatFits` candidates share a single load instead of each asking.
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
