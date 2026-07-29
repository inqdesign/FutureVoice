import SwiftUI

/// The Watch EXECUTION surface — Home's Watch verb lands here and the scene
/// just plays, exactly like Talk lands straight in the call. No curriculum
/// checklist, no book chrome; that page (`ScenarioDetailView`) belongs to
/// Practice, where the material this watch produces is reviewed later.
///
/// A scenario is a reusable TEMPLATE: opened with `freshTake` (Watch's "Your
/// scenarios"), this writes a NEW take of the situation every time — replaying
/// what a past take produced is Practice's job, not Watch's. The new take's
/// study material is absorbed into the scenario's book (mastery preserved),
/// so watching IS what stocks Practice. Without `freshTake` (first watch of a
/// just-minted scenario) it generates once and plays.
struct SceneWatchView: View {
    @EnvironmentObject private var appState: AppState
    let scenarioId: UUID
    /// True when opened from a saved-scenario card: generate a new take even
    /// though the book already has a scene.
    var freshTake: Bool = false

    @State private var generating = false
    @State private var generationError: String?
    /// Held until the fresh take lands so the OLD scene never flashes first.
    @State private var awaitingFresh: Bool
    /// One take per view instance — keeps double-tap idempotency within the
    /// watch while making each open a distinct generation.
    @State private var runKey = UUID().uuidString

    init(scenarioId: UUID, freshTake: Bool = false) {
        self.scenarioId = scenarioId
        self.freshTake = freshTake
        _awaitingFresh = State(initialValue: freshTake)
    }

    private var scenario: Scenario? {
        appState.scenarios.first { $0.id == scenarioId }
    }

    var body: some View {
        Group {
            if !awaitingFresh, let s = scenario, let c = s.curriculum, !(c.dialogue ?? []).isEmpty {
                WatchView(counterpart: watchCounterpart(for: s),
                          savedDialogue: sceneDialogue(s, c))
                    .environmentObject(appState)
            } else if let e = generationError {
                errorState(e)
            } else {
                loadingState
            }
        }
        .task { await ensureCurriculum() }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Writing this scene…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't write the scene", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") {
                generationError = nil
                Task { await ensureCurriculum(force: true) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Scene plumbing (same rules as the book page)

    /// First watch generates the book's scene; a `freshTake` open generates a
    /// NEW take of the template and absorbs it into the book — the latest
    /// scene plays, study items accumulate, mastery survives.
    private func ensureCurriculum(force: Bool = false) async {
        guard let s = scenario,
              awaitingFresh || (s.curriculum?.dialogue ?? []).isEmpty,
              force || !generating else { return }
        guard !generating else { return }
        generating = true
        defer { generating = false }
        do {
            let counterpart = s.counterpartId.flatMap { id in
                appState.counterparts.first { $0.id == id }
            }
            let hasScene = !(s.curriculum?.dialogue ?? []).isEmpty
            let curriculum = try await ScenarioCurriculumEngine.generate(
                scenario: s,
                persona: appState.persona,
                counterpart: counterpart,
                proficiency: appState.proficiency,
                targetLanguage: appState.targetLanguage,
                weakVocabAreas: appState.learnerProfile.weakVocabAreas,
                recurringMistakes: appState.learnerProfile.recurringMistakes,
                avoidTitles: hasScene ? [s.curriculum?.dialogueTitle ?? ""] : [],
                runKey: hasScene ? runKey : nil
            )
            guard var fresh = scenario else { return }
            if var book = fresh.curriculum, hasScene {
                book.absorb(curriculum)
                fresh.curriculum = book
            } else {
                fresh.curriculum = curriculum
            }
            appState.saveScenario(fresh)
            appState.refreshScenarioMastery(id: scenarioId)
            awaitingFresh = false
        } catch {
            generationError = error.localizedDescription
        }
    }

    /// The stored scene wrapped as a replayable WatchDialogue — playback is
    /// free (audio content-cache); nothing extra is persisted.
    private func sceneDialogue(_ s: Scenario, _ c: ScenarioCurriculum) -> WatchDialogue {
        WatchDialogue(
            counterpartId: s.counterpartId ?? UUID(),
            scenarioTitle: s.displayTitle,
            scenarioBlurb: "",
            title: c.dialogueTitle,
            turns: c.dialogue ?? [],
            speakerName: linkedPersonaName(s) ?? s.role,
            voicePresetId: watchCounterpart(for: s).voicePresetId
        )
    }

    private func linkedPersonaName(_ s: Scenario) -> String? {
        s.counterpartId.flatMap { id in appState.counterparts.first { $0.id == id }?.name }
    }

    private func watchCounterpart(for s: Scenario) -> Counterpart {
        s.counterpartId.flatMap { id in appState.counterparts.first { $0.id == id } }
            ?? ScenarioDetailView.syntheticCounterpart(for: s)
    }
}
