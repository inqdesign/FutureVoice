import SwiftUI

/// Browse every fluent-self line your future self has ever spoken, grouped by
/// session, and tap any line to drop into a shadow-practice flow. Lives in its
/// own sheet (separate from `DrillSheet`'s SRS queue) because the two are
/// fundamentally different practice modes — corrections vs prosody reps.
/// Reusable body view. Parent (tab or sheet) supplies the NavigationStack.
struct ShadowBrowserView: View {
    @EnvironmentObject private var appState: AppState

    @State private var sessions: [Session] = []
    @State private var shadowTarget: ShadowTarget?
    /// One archive, three doors: everything / bookmarked / lines you've
    /// actually shadow-practiced (≥1 recorded attempt).
    @State private var filter: ArchiveFilter = .all

    enum ArchiveFilter: String, CaseIterable, Identifiable {
        case all, saved, practiced
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .saved: return "Saved"
            case .practiced: return "Practiced"
            }
        }
    }

    /// Turn ids with at least one shadow attempt — "what have I practiced".
    private var practicedIds: Set<UUID> {
        Set(appState.shadowAttempts.map(\.turnId))
    }

    private func passes(_ turn: Turn) -> Bool {
        switch filter {
        case .all: return true
        case .saved: return appState.isLineSaved(turn.id)
        case .practiced: return practicedIds.contains(turn.id)
        }
    }

    struct ShadowTarget: Identifiable {
        let turn: Turn
        var id: UUID { turn.id }
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if !appState.savedLines.isEmpty || !appState.shadowAttempts.isEmpty {
                    Picker("Filter", selection: $filter) {
                        ForEach(ArchiveFilter.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
            .sheet(item: $shadowTarget) { target in
                ShadowDrillView(
                    turn: target.turn,
                    targetLanguage: appState.targetLanguage
                )
                .environmentObject(appState)
            }
            .onAppear { sessions = SessionStore.shared.load() }
    }
}

/// Sheet wrapper — kept for any older entry point.
struct ShadowBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ShadowBrowserView()
                .navigationTitle("Shadow")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private extension ShadowBrowserView {

    @ViewBuilder
    private var content: some View {
        let totalLines = sessions.reduce(0) { $0 + $1.turns.filter { $0.role == .fluentSelf }.count }
        if totalLines == 0 {
            ContentUnavailableView(
                "Nothing to shadow yet",
                systemImage: "waveform.badge.mic",
                description: Text("Finish a conversation, then come back to shadow any line your fluent self said.")
            )
        } else {
            List {
                ForEach(sessions) { session in
                    let lines = session.turns.filter {
                        $0.role == .fluentSelf && passes($0)
                    }
                    if !lines.isEmpty {
                        Section(header: sectionHeader(for: session)) {
                            ForEach(lines) { turn in
                                Button {
                                    shadowTarget = ShadowTarget(turn: turn)
                                } label: {
                                    ShadowRow(turn: turn, isSaved: appState.isLineSaved(turn.id))
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        appState.toggleSavedLine(turn: turn, source: session.topic ?? "")
                                    } label: {
                                        Label(appState.isLineSaved(turn.id) ? "Unsave" : "Save",
                                              systemImage: appState.isLineSaved(turn.id) ? "bookmark.slash" : "bookmark")
                                    }
                                    .tint(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func sectionHeader(for session: Session) -> some View {
        HStack {
            Text(session.displayTitle)
            Spacer()
            Text(relativeDate(session.endedAt ?? session.startedAt))
                .foregroundStyle(.secondary)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func relativeDate(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct ShadowRow: View {
    let turn: Turn
    var isSaved: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hasAudio ? "waveform" : "waveform.slash")
                .font(.subheadline)
                .foregroundStyle(hasAudio ? Color.accentColor : .secondary)
                .frame(width: 22)
            Text(turn.transcript)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if isSaved {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var hasAudio: Bool {
        if turn.audioURL != nil { return true }
        return TurnAudioStore.shared.url(for: turn.id) != nil
    }
}
