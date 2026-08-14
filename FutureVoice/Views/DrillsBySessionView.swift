import SwiftUI

/// Browse drill cards grouped by the conversation they came from. Lets the
/// user "post-mortem" a single session — tap a row to walk that session's
/// cards in the regular swipe-deck (DrillView reused with .session filter).
struct DrillsBySessionView: View {
    @State private var sessions: [Session] = []
    @State private var allCards: [DrillCard] = []
    @State private var filter: Filter = .toStudy

    /// Same two lenses the expression list uses, for the same reason: a flat
    /// "520 cards" hides the only thing worth knowing — how much is still
    /// ahead of you. "Known" is box 5, the top of the Leitner ladder.
    enum Filter: String, CaseIterable, Identifiable {
        case toStudy, known
        var id: String { rawValue }
        var label: String {
            switch self {
            case .toStudy: return "To study"
            case .known:   return "Known"
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
            .padding(.bottom, 4)

            Group {
            if sessionsWithCards.isEmpty && scenarioCardCount == 0 {
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
                    ForEach(sessionsWithCards) { s in
                        NavigationLink {
                            DrillView(source: .session(s.id))
                                .navigationTitle(s.displayTitle)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            row(for: s)
                        }
                    }
                    // "Save phrase" cards from Watch dialogues have no source
                    // session — without this row they'd be invisible here.
                    if scenarioCardCount > 0 {
                        NavigationLink {
                            DrillView(source: .scenario)
                                .navigationTitle("From scenarios")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("From scenarios")
                                    .font(.body)
                                Text(scenarioCardCount == 1
                                     ? "1 phrase saved while watching"
                                     : "\(scenarioCardCount) phrases saved while watching")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            }
        }
        .onAppear { reload() }
    }

    private func row(for session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.displayTitle)
                .font(.body)
            HStack(spacing: 6) {
                Text(session.endedAt ?? session.startedAt, style: .relative)
                Text("·")
                Text("\(cardCount(for: session.id)) card\(cardCount(for: session.id) == 1 ? "" : "s")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var sessionsWithCards: [Session] {
        sessions
            .filter { cardCount(for: $0.id) > 0 }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
    }

    /// Cards in the current lens — everything below counts and lists from here.
    private var visibleCards: [DrillCard] {
        allCards.filter { filter.matches($0) }
    }

    private func cardCount(for id: UUID) -> Int {
        visibleCards.filter { $0.sourceSessionId == id }.count
    }

    private var scenarioCardCount: Int {
        visibleCards.filter { $0.sourceSessionId == nil }.count
    }

    private func reload() {
        sessions = SessionStore.shared.load()
        allCards = DrillStore.shared.load()
    }
}
