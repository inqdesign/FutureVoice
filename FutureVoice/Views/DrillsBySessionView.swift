import SwiftUI

/// Browse drill cards grouped by the conversation they came from. Lets the
/// user "post-mortem" a single session — tap a row to walk that session's
/// cards in the regular swipe-deck (DrillView reused with .session filter).
struct DrillsBySessionView: View {
    @State private var sessions: [Session] = []
    @State private var allCards: [DrillCard] = []

    var body: some View {
        Group {
            if sessionsWithCards.isEmpty {
                ContentUnavailableView(
                    "No session cards yet",
                    systemImage: "tray",
                    description: Text("After you end a conversation, the corrections it surfaces show up here grouped by session.")
                )
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
                }
                .listStyle(.insetGrouped)
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

    private func cardCount(for id: UUID) -> Int {
        allCards.filter { $0.sourceSessionId == id }.count
    }

    private func reload() {
        sessions = SessionStore.shared.load()
        allCards = DrillStore.shared.load()
    }
}
