import SwiftUI

/// Scenarios home — a shelf of curriculum "books". Each scenario is a course:
/// a situation + who you talk to, filled with words, expressions, and shadow
/// lines to master. Tapping a card opens the book (ScenarioDetailView) —
/// progress, checklist, the Talk/Watch study actions, and past watches all
/// live there. Mastered or shelved books drop into the Archive at the bottom.
/// People (voice-cloned personas) are managed from the toolbar; they show up
/// as the "who" inside cards.
struct WatchTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingNewVoice = false
    @State private var showingNewScenario = false
    @State private var showingPeople = false
    @State private var talkScenario: Scenario?
    @State private var openScenario: Scenario?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var activeScenarios: [Scenario] { appState.scenarios.filter { !$0.isArchived } }
    private var archivedScenarios: [Scenario] { appState.scenarios.filter(\.isArchived) }

    var body: some View {
        NavigationStack {
            Group {
                if appState.scenarios.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Scenarios")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // People = manage your voice-cloned personas (not a create
                    // dupe — creating happens inside the builder / this sheet).
                    Button { showingPeople = true } label: {
                        Image(systemName: "person.2")
                    }
                    .accessibilityLabel("Your people")
                    Button { showingNewScenario = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New scenario")
                }
            }
            .sheet(isPresented: $showingNewVoice) {
                CounterpartVoiceIntakeView().environmentObject(appState)
            }
            .sheet(isPresented: $showingNewScenario) {
                ScenarioBuilderSheet(counterparts: appState.counterparts) { newScenario in
                    appState.saveScenario(newScenario)
                    // Go straight into the fresh book — the curriculum starts
                    // generating on open, so the user lands on a live page.
                    openScenario = newScenario
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
            .navigationDestination(item: $openScenario) { s in
                ScenarioDetailView(scenarioId: s.id)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(activeScenarios) { s in scenarioCard(s) }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)

            if !archivedScenarios.isEmpty { archiveSection }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Cards

    private func scenarioCard(_ s: Scenario) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                cardAvatar(s)
                Spacer()
                if s.isMastered {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3).foregroundStyle(.green)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.environment).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary).lineLimit(1)
                Text("with \(linkedPersonaName(s) ?? s.role)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.bottom, 8)
            cardProgress(s)
        }
        .padding(14)
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(Rectangle())
        .onTapGesture { openScenario = s }
        .contextMenu {
            Button { openScenario = s } label: { Label("Open", systemImage: "book") }
            Button { talkScenario = s } label: { Label("Talk now", systemImage: "mic.fill") }
            Button { appState.setScenarioArchived(id: s.id, true) } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Button(role: .destructive) { appState.deleteScenario(id: s.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Bottom strip of the card: curriculum progress once the book exists,
    /// or a "new book" hint before the first open generated it.
    @ViewBuilder
    private func cardProgress(_ s: Scenario) -> some View {
        if let c = s.curriculum, c.totalCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: c.progress)
                    .tint(s.isMastered ? .green : .accentColor)
                Text(s.isMastered ? "Mastered" : "\(c.masteredCount)/\(c.totalCount) mastered")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(s.isMastered ? .green : .secondary)
            }
        } else {
            Label("Open to start", systemImage: "book")
                .font(.caption2).foregroundStyle(.tint)
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

    // MARK: - Archive

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Archive")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 24)
            VStack(spacing: 0) {
                ForEach(archivedScenarios) { s in
                    Button { openScenario = s } label: { archivedRow(s) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { appState.setScenarioArchived(id: s.id, false) } label: {
                                Label("Unarchive", systemImage: "tray.and.arrow.up")
                            }
                            Button(role: .destructive) { appState.deleteScenario(id: s.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    if s.id != archivedScenarios.last?.id { Divider().padding(.leading, 56) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
            .padding(.horizontal, 18)
            Text("Finished books. They keep their progress — unarchive anytime.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.top, 2)
        }
    }

    private func archivedRow(_ s: Scenario) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s.isMastered ? "checkmark.seal.fill" : "archivebox")
                .font(.body)
                .foregroundStyle(s.isMastered ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.environment).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                Text("with \(linkedPersonaName(s) ?? s.role)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let c = s.curriculum, c.totalCount > 0 {
                Text("\(c.masteredCount)/\(c.totalCount)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
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

    private func linkedPersonaName(_ s: Scenario) -> String? {
        s.counterpartId.flatMap { id in appState.counterparts.first { $0.id == id }?.name }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Master a situation", systemImage: "book")
        } description: {
            Text("Build a scenario — where you are and who you're with. It becomes a course: words, expressions, and lines to master, with your fluent self as the study partner.")
        } actions: {
            Button("New scenario") { showingNewScenario = true }
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
