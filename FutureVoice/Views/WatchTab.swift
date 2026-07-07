import SwiftUI

/// Scenarios home — ONE unified grid of conversation cards. Each card is a
/// situation paired with who you talk to (a generic role or one of your own
/// personas); your fluent self is always the constant. Tapping a card starts
/// a Talk; the ▶ badge watches your fluent self play it out. "Create your
/// own" opens the builder. People (voice-cloned personas) are managed from
/// the toolbar; they show up as the "who" inside cards.
struct WatchTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingNewVoice = false
    @State private var showingNewScenario = false
    @State private var showingPeople = false
    @State private var talkScenario: Scenario?
    @State private var watchScenarioTarget: Scenario?

    private static let recentLimit = 5
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if appState.counterparts.isEmpty && appState.watchDialogues.isEmpty && appState.scenarios.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Scenarios")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                // People = manage your voice-cloned personas (not a create
                // dupe — creating happens inside the builder / this sheet).
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingPeople = true } label: {
                        Image(systemName: "person.2")
                    }
                    .accessibilityLabel("Your people")
                }
            }
            .sheet(isPresented: $showingNewVoice) {
                CounterpartVoiceIntakeView().environmentObject(appState)
            }
            .sheet(isPresented: $showingNewScenario) {
                ScenarioBuilderSheet(counterparts: appState.counterparts) { newScenario in
                    appState.saveScenario(newScenario)
                }
                .environmentObject(appState)
            }
            .sheet(isPresented: $showingPeople) {
                PeopleSheet(onNew: { showingPeople = false; showingNewVoice = true })
                    .environmentObject(appState)
            }
            .fullScreenCover(item: $talkScenario) { s in
                ConversationView(initialTopic: s.displayTitle, initialBlurb: s.promptBlurb)
                    .environmentObject(appState)
            }
            .navigationDestination(item: $watchScenarioTarget) { s in
                // Watch with the linked persona's real voice when set; else a
                // generic preset partner built from the role.
                let cp = s.counterpartId
                    .flatMap { id in appState.counterparts.first { $0.id == id } }
                    ?? ScenariosListSheet.watchCounterpart(for: s)
                WatchView(counterpart: cp,
                          customScenario: ScenariosListSheet.watchScenarioText(s))
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                createCard
                ForEach(appState.scenarios) { s in scenarioCard(s) }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)

            if !recentDialogues.isEmpty { recentSection }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var recentDialogues: [WatchDialogue] {
        Array(appState.watchDialogues.sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.recentLimit))
    }

    // MARK: - Cards

    private var createCard: some View {
        Button { showingNewScenario = true } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.5),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: 54, height: 54)
                    Image(systemName: "plus").font(.title2.weight(.semibold)).foregroundStyle(.tint)
                }
                Text("Create your own").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                Text("Situation + who").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).frame(height: 150)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.accentColor.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.accentColor.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
        }
        .buttonStyle(.plain)
    }

    private func scenarioCard(_ s: Scenario) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                HStack { cardAvatar(s); Spacer() }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 82)
                    .background(Color.accentColor.opacity(0.06))
                Button { watchScenarioTarget = s } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title3).foregroundStyle(.tint).padding(9)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Watch")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(s.displayTitle).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary).lineLimit(1)
                Text(cardSubtitle(s)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .frame(height: 150)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        .onTapGesture { talkScenario = s }
        .contextMenu {
            Button { talkScenario = s } label: { Label("Talk", systemImage: "mic.fill") }
            Button { watchScenarioTarget = s } label: { Label("Watch", systemImage: "play.fill") }
            Button(role: .destructive) { appState.deleteScenario(id: s.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func cardAvatar(_ s: Scenario) -> some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.18)).frame(width: 46, height: 46)
            if let name = linkedPersonaName(s) {
                Text(Self.initials(name)).font(.subheadline.weight(.bold)).foregroundStyle(.tint)
            } else {
                Image(systemName: Self.roleIcon(for: s.role)).font(.title3).foregroundStyle(.tint)
            }
        }
    }

    /// Subtitle: the persona's name if linked, else the note, else the role.
    private func cardSubtitle(_ s: Scenario) -> String {
        if let name = linkedPersonaName(s) { return "with \(name)" }
        let notes = s.notes.trimmingCharacters(in: .whitespaces)
        return notes.isEmpty ? "with \(s.role)" : notes
    }

    // MARK: - Recent watches

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent watches")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 24)
            VStack(spacing: 0) {
                ForEach(recentDialogues) { d in
                    let c = counterpart(for: d) ?? scenarioCounterpart(for: d)
                    NavigationLink {
                        WatchView(counterpart: c, savedDialogue: d).environmentObject(appState)
                    } label: {
                        dialogueRow(d, counterpart: c)
                    }
                    .buttonStyle(.plain)
                    if d.id != recentDialogues.last?.id { Divider().padding(.leading, 60) }
                }
            }
            .padding(.horizontal, 18)
            Text("Replays are free — the audio is already cached.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 12)
        }
    }

    private func dialogueRow(_ d: WatchDialogue, counterpart: Counterpart) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 40, height: 40)
                Text(Self.initials(counterpart.name))
                    .font(.caption.weight(.semibold)).foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(d.displayTitle).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                HStack(spacing: 5) {
                    Text(counterpart.name)
                    Text("·")
                    Text(d.createdAt, format: .dateTime.month(.abbreviated).day())
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    /// Role text → a representative SF Symbol for the card avatar.
    static func roleIcon(for role: String) -> String {
        let r = role.lowercased()
        switch true {
        case r.contains("doctor"), r.contains("nurse"):            return "stethoscope"
        case r.contains("manager"), r.contains("boss"):            return "briefcase.fill"
        case r.contains("colleague"):                              return "briefcase.fill"
        case r.contains("teacher"):                                return "graduationcap.fill"
        case r.contains("shop"), r.contains("service"), r.contains("agent"): return "bag.fill"
        case r.contains("friend"):                                 return "person.2.fill"
        case r.contains("family"), r.contains("kid"), r.contains("child"): return "figure.and.child.holdinghands"
        case r.contains("date"), r.contains("romantic"):           return "heart.fill"
        case r.contains("neighbor"):                               return "house.fill"
        case r.contains("stranger"):                               return "person.fill.questionmark"
        default:                                                   return "person.fill"
        }
    }

    private func counterpart(for d: WatchDialogue) -> Counterpart? {
        appState.counterparts.first { $0.id == d.counterpartId }
    }

    private func linkedPersonaName(_ s: Scenario) -> String? {
        s.counterpartId.flatMap { id in appState.counterparts.first { $0.id == id }?.name }
    }

    /// Rebuild a throwaway partner for a scenario watch (no saved Counterpart)
    /// from the name + voice stored on the dialogue, so it lists and replays.
    private func scenarioCounterpart(for d: WatchDialogue) -> Counterpart {
        var c = Counterpart.empty
        c.name = d.speakerName ?? d.scenarioTitle
        c.voicePresetId = d.voicePresetId ?? VoicePreset.catalog.first!.id
        return c
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Practice a conversation", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Build a situation — pick where you are and who you're with (a generic role or someone from your real life) — and start right away.")
        } actions: {
            Button("Create your own") { showingNewScenario = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Manage your voice-cloned personas — the "who" that can play any scenario.
private struct PeopleSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onNew: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onNew) {
                        Label("New person", systemImage: "plus.circle.fill")
                            .font(.body.weight(.medium))
                    }
                }
                if !appState.counterparts.isEmpty {
                    Section("Your people") {
                        ForEach(appState.counterparts) { c in
                            NavigationLink {
                                CounterpartDetailView(counterpart: c).environmentObject(appState)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 40, height: 40)
                                        Text(WatchTab.initials(c.name))
                                            .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(c.name).font(.body)
                                        Text(c.relationship).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            for i in idx { appState.deleteCounterpart(id: appState.counterparts[i].id) }
                        }
                    }
                } else {
                    Section {
                        Text("Add someone from your real life — their cloned voice can act out any scenario you build.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
