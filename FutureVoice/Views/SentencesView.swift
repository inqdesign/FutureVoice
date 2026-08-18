import SwiftUI

/// Every drill sentence in one flat list — the sentence-level twin of the
/// words and expressions pages. It used to group cards under the talk they
/// came from, which made a page titled "Sentences" read as a list of session
/// titles; the sentence itself is the row now, with the card's own coaching
/// note as its gloss. Tapping a row drills exactly that card.
struct SentencesView: View {
    @State private var allCards: [DrillCard] = []
    @State private var filter: Filter = .toStudy

    /// Same two lenses the word and expression lists use, for the same
    /// reason: a flat "520 cards" hides the only thing worth knowing — how
    /// much is still ahead of you. "Known" is box 5, the top of the ladder.
    enum Filter: String, CaseIterable, Identifiable {
        case toStudy, known
        var id: String { rawValue }
        var label: String {
            switch self {
            case .toStudy: return explain("To study")
            case .known:   return explain("Known")
            }
        }
        func matches(_ card: DrillCard) -> Bool {
            switch self {
            case .toStudy: return card.box < DrillStore.maxBox
            case .known:   return card.box >= DrillStore.maxBox
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if visibleCards.isEmpty {
                ContentUnavailableView(
                    filter == .toStudy ? "Nothing left to study" : "Nothing learned yet",
                    systemImage: filter == .toStudy ? "checkmark.circle" : "tray",
                    description: Text(filter == .toStudy
                        ? explain("Every sentence from your talks is at the top of the ladder. New ones arrive when you finish a conversation.")
                        : explain("A sentence lands here once it reaches the top of the review ladder."))
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(visibleCards) { card in
                            NavigationLink {
                                DrillView(source: .card(card.id))
                            } label: {
                                row(card)
                            }
                        }
                    } header: {
                        Text("\(visibleCards.count) sentences")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .onAppear { reload() }
    }

    private func row(_ card: DrillCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.targetPhrase)
                .font(.headline)
                .lineLimit(2)
            // The card's own coaching note — why this line, in the learner's
            // language. Cards without one (Watch "Save phrase") show what the
            // learner originally said instead; either way it's about the
            // sentence, not bookkeeping.
            if !card.reason.isEmpty {
                Text(card.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if !card.sourcePhrase.isEmpty {
                Text(card.sourcePhrase)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    /// Newest first — the sentence you minted this morning is the one you
    /// came looking for.
    private var visibleCards: [DrillCard] {
        allCards.filter { filter.matches($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func reload() {
        allCards = DrillStore.shared.load()
    }
}
