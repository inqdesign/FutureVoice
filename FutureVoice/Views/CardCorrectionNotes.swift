import SwiftUI

/// The back of a sentence card, under the fluent line: every change as
/// "what you said → what to say" and why, on the decks' accent slab
/// (`DrillView`, `StudyDeckView`). Falls back to the card's own short reason
/// while the explanation is written, and for good if it can't be.
///
/// The card has a fixed height and a small phone can't hold three
/// explanations under a long sentence, so the card shows as many as FIT
/// (`ViewThatFits`) and the rest open in a sheet — never clipped off the
/// card's edge.
struct CardCorrectionNotes: View {
    let said: String
    let fix: String
    let reason: String

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var cache = CorrectionExplanationCache.shared
    @State private var showingAll = false

    private static let secondary = Color.white.opacity(0.72)

    private var cacheKey: CorrectionExplanationCache.Key {
        .init(said: said, fix: fix, target: appState.targetLanguage, native: appState.nativeLanguage)
    }

    var body: some View {
        let changes = cache.explanations[cacheKey]?.changes
        ViewThatFits(in: .vertical) {
            if let changes {
                ForEach((0...min(changes.count, 3)).reversed(), id: \.self) { shown in
                    notes(changes, shown: shown)
                }
            } else {
                fallback
            }
            seeAllButton(label: "See what changed")
        }
        .task(id: cacheKey) { await cache.load(cacheKey, reason: reason) }
        .sheet(isPresented: $showingAll) {
            if let changes { CorrectionChangesSheet(changes: changes) }
        }
    }

    private func notes(_ changes: [CorrectionExplanation.Change], shown: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            caption
            VStack(alignment: .leading, spacing: 14) {
                ForEach(changes.prefix(shown), id: \.self) { change in
                    CorrectionChangeRow(change: change, onCard: true)
                }
            }
            if shown < changes.count {
                seeAllButton(label: "\(changes.count - shown) more")
            }
        }
    }

    private var fallback: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption
            if !reason.isEmpty {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(Self.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if cache.loading.contains(cacheKey) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini).tint(.white)
                    Text("Explaining…")
                }
                .font(.footnote)
                .foregroundStyle(Self.secondary)
            }
        }
    }

    private var caption: some View {
        Text("What changed")
            .font(.caption)
            .foregroundStyle(Self.secondary)
    }

    private func seeAllButton(label: LocalizedStringKey) -> some View {
        Button { showingAll = true } label: {
            Label(label, systemImage: "text.magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(cache.explanations[cacheKey] == nil)
    }
}

/// One change: what they said struck out → what to say, then why.
struct CorrectionChangeRow: View {
    let change: CorrectionExplanation.Change
    /// On the accent slab (white text) or in an ordinary list.
    var onCard: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !change.was.isEmpty {
                    Text(change.was)
                        .strikethrough()
                        .foregroundStyle(onCard ? Color.white.opacity(0.72) : .secondary)
                }
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(onCard ? Color.white.opacity(0.72) : .secondary)
                Text(change.now.isEmpty ? "—" : change.now)
                    .fontWeight(.semibold)
                    .foregroundStyle(onCard ? Color.white : .primary)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            Text(change.why)
                .font(.subheadline)
                .foregroundStyle(onCard ? Color.white.opacity(0.9) : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Every change, for a card that couldn't hold them all.
private struct CorrectionChangesSheet: View {
    let changes: [CorrectionExplanation.Change]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(changes, id: \.self) { change in
                CorrectionChangeRow(change: change)
                    .padding(.vertical, 4)
            }
            .navigationTitle("What changed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// One copy of each explanation in memory, so the card's several
/// `ViewThatFits` candidates (and the deck's card behind it) share a single
/// load instead of each asking.
@MainActor
final class CorrectionExplanationCache: ObservableObject {
    static let shared = CorrectionExplanationCache()

    struct Key: Hashable { let said, fix, target, native: String }

    @Published private(set) var explanations: [Key: CorrectionExplanation] = [:]
    @Published private(set) var loading: Set<Key> = []

    func load(_ key: Key, reason: String) async {
        guard explanations[key] == nil, !loading.contains(key) else { return }
        if let hit = CorrectionExplainer.cached(said: key.said, fix: key.fix,
                                                target: key.target, native: key.native) {
            explanations[key] = hit
            return
        }
        loading.insert(key)
        defer { loading.remove(key) }
        if let got = try? await CorrectionExplainer.explain(said: key.said, fix: key.fix, reason: reason,
                                                            target: key.target, native: key.native) {
            explanations[key] = got
        }
    }
}
