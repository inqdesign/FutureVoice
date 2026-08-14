import SwiftUI

/// Browse every line your fluent self has ever spoken — the lines from your
/// TALKS and the lines from the scenes you WATCHED — and tap any of them to
/// drop into a shadow-practice flow.
///
/// Scene lines used to be missing entirely: they live on a `Scenario`'s
/// curriculum, and this browser only ever read `SessionStore`. A Watch book
/// would show six lines to shadow that the shadow archive had never heard of.
/// They're merged in here rather than copied anywhere, and because a
/// curriculum item's id doubles as its synthetic `Turn.id`, attempts made from
/// either surface are the same attempts. Lives in its
/// own sheet (separate from `DrillSheet`'s SRS queue) because the two are
/// fundamentally different practice modes — corrections vs prosody reps.
/// Reusable body view. Parent (tab or sheet) supplies the NavigationStack.
struct ShadowBrowserView: View {
    @EnvironmentObject private var appState: AppState

    @State private var sessions: [Session] = []
    @State private var shadowTarget: ShadowTarget?
    /// One archive, two doors: lines still waiting for a first attempt
    /// (default) and lines you've actually shadow-practiced (≥1 recorded
    /// attempt). Every line is in exactly one.
    @State private var filter: ArchiveFilter = .toStudy

    enum ArchiveFilter: String, CaseIterable, Identifiable {
        case toStudy, practiced
        var id: String { rawValue }
        var label: String {
            switch self {
            case .toStudy: return "To study"
            case .practiced: return "Practiced"
            }
        }
    }

    /// Turn ids with at least one shadow attempt — "what have I practiced".
    private var practicedIds: Set<UUID> {
        Set(appState.shadowAttempts.map(\.turnId))
    }

    /// A Watch book's scene lines, as shadowable turns. Same id trick
    /// `ScenarioDetailView` uses, so an attempt here checks the book's line
    /// off too.
    private var sceneSections: [(scenario: Scenario, lines: [Turn])] {
        appState.scenarios
            .filter { !$0.isArchived }
            .compactMap { scenario in
                let lines = (scenario.curriculum?.shadowLines ?? []).map {
                    Turn(id: $0.id, role: .fluentSelf, audioURL: nil,
                         transcript: $0.text, durationMs: 0,
                         timestamp: scenario.lastUsedAt ?? scenario.createdAt,
                         suggestion: nil)
                }
                .filter { passes($0) }
                return lines.isEmpty ? nil : (scenario, lines)
            }
            .sorted { ($0.scenario.lastUsedAt ?? $0.scenario.createdAt)
                    > ($1.scenario.lastUsedAt ?? $1.scenario.createdAt) }
    }

    private func passes(_ turn: Turn) -> Bool {
        switch filter {
        case .toStudy: return !practicedIds.contains(turn.id)
        case .practiced: return practicedIds.contains(turn.id)
        }
    }

    struct ShadowTarget: Identifiable {
        let turn: Turn
        var id: UUID { turn.id }
    }

    var body: some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                // The split only means something once at least one line has
                // been practiced — until then everything is "to study".
                if !appState.shadowAttempts.isEmpty {
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
            + appState.scenarios.reduce(0) { $0 + ($1.curriculum?.shadowLines.count ?? 0) }
        if totalLines == 0 {
            ContentUnavailableView(
                "Nothing to shadow yet",
                systemImage: "waveform.badge.mic",
                description: Text(explain("Have a conversation or watch a scene, then come back to shadow any line your fluent self said."))
            )
        } else {
            List {
                // Watched scenes first — their lines are the ones a book is
                // currently asking for.
                ForEach(sceneSections, id: \.scenario.id) { section in
                    Section(header: sceneHeader(section.scenario)) {
                        ForEach(section.lines) { turn in
                            Button {
                                shadowTarget = ShadowTarget(turn: turn)
                            } label: {
                                ShadowRow(turn: turn, isSaved: appState.isLineSaved(turn.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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

    /// A scene's header names the book, so a line's origin is never a guess.
    private func sceneHeader(_ scenario: Scenario) -> some View {
        HStack {
            Label(scenario.environment, systemImage: "film")
                .lineLimit(1)
            Spacer()
            Text(relativeDate(scenario.lastUsedAt ?? scenario.createdAt))
                .foregroundStyle(.secondary)
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
