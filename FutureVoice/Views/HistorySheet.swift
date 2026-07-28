import SwiftUI

/// Sheet showing all ended sessions, newest first. Tap to drill into the
/// full transcript and summary; swipe to delete.
/// Reusable body view — parent supplies NavigationStack + title.
struct HistoryView: View {
    @State private var sessions: [Session] = []

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "clock",
                    description: Text("Tap End session after a conversation and it'll show up here.")
                )
            } else {
                List {
                    ForEach(sessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            HistoryRow(session: session)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
            }
        }
        .onAppear { sessions = SessionStore.shared.load() }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { sessions[$0].id }
        for id in ids { SessionStore.shared.delete(id: id) }
        sessions = SessionStore.shared.load()
    }
}

/// Sheet wrapper — kept for backward compat. Main app uses `HistoryView`
/// from `MeTab` directly.
struct HistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            HistoryView()
                .navigationTitle("History")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private struct HistoryRow: View {
    let session: Session
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.displayTitle)
                .font(.headline)
            Text(Self.relative.localizedString(
                for: session.endedAt ?? session.startedAt,
                relativeTo: Date()
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            if let note = session.summary?.overallNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Detail view for one stored session. Native iOS List grouping.
struct SessionDetailView: View {
    @EnvironmentObject private var appState: AppState
    /// State so misheard-turn exclusions made in the grammar review update
    /// the score and slip count in place.
    @State private var session: Session

    init(session: Session) {
        _session = State(initialValue: session)
    }

    var body: some View {
        List {
            if let summary = session.summary {
                if let card = summary.scorecard {
                    Section("Nutrition") {
                        ScorecardView(scorecard: card, grammarIssues: summary.grammarIssues,
                                      userTurns: session.turns.filter { $0.role == .user },
                                      sessionId: session.id,
                                      onSessionUpdated: {
                                          session = $0
                                          appState.reassessAfterEvidenceChange(in: $0)
                                      })
                            .padding(.vertical, 6)
                    }
                }
                Section("Note") {
                    Text(summary.overallNote)
                }
                if !summary.phrasesUsed.isEmpty {
                    Section("More natural alternatives") {
                        ForEach(summary.phrasesUsed) { phrase in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(phrase.userSaid).foregroundStyle(.secondary)
                                Text(phrase.fluentAlternative)
                                Text(phrase.reason)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                if !summary.suggestedDrills.isEmpty {
                    Section("Drill next") {
                        ForEach(summary.suggestedDrills, id: \.self) { Text($0) }
                    }
                }
            }
            Section("Transcript") {
                ForEach(session.turns) { turn in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(turn.role == .user ? "You" : "Future self")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(turn.transcript)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
