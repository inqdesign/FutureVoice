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

    struct ShadowTarget: Identifiable {
        let turn: Turn
        var id: UUID { turn.id }
    }

    var body: some View {
        content
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
                    let lines = session.turns.filter { $0.role == .fluentSelf }
                    if !lines.isEmpty {
                        Section(header: sectionHeader(for: session)) {
                            ForEach(lines) { turn in
                                Button {
                                    shadowTarget = ShadowTarget(turn: turn)
                                } label: {
                                    ShadowRow(turn: turn)
                                }
                                .buttonStyle(.plain)
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
            Text(session.topic ?? "Conversation")
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hasAudio ? "waveform" : "waveform.slash")
                .font(.subheadline)
                .foregroundStyle(hasAudio ? Color.accentColor : .secondary)
                .frame(width: 22)
            Text(turn.transcript)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer(minLength: 8)
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
