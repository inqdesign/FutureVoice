import SwiftUI

/// Sheet showing all ended sessions, newest first. Tap to drill into the
/// full transcript and summary; swipe to delete.
struct HistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [Session] = []

    var body: some View {
        NavigationStack {
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
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                if !sessions.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
            }
            .onAppear { sessions = SessionStore.shared.load() }
        }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { sessions[$0].id }
        for id in ids { SessionStore.shared.delete(id: id) }
        sessions = SessionStore.shared.load()
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
            Text(session.topic ?? "Conversation")
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
    let session: Session

    var body: some View {
        List {
            if let summary = session.summary {
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
        .navigationTitle(session.topic ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
    }
}
