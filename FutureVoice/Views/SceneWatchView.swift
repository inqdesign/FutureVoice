import SwiftUI

/// The Watch EXECUTION surface — Home's Watch verb lands here and the scene
/// just plays, exactly like Talk lands straight in the call. No curriculum
/// checklist, no book chrome; that page (`ScenarioDetailView`) belongs to
/// Practice, where the material this watch produces is reviewed later.
///
/// If the subject's scene doesn't exist yet, it generates here once (the
/// same `ScenarioCurriculumEngine` call that fills the book), is persisted
/// onto the scenario, then plays — so watching IS what stocks Practice.
struct SceneWatchView: View {
    @EnvironmentObject private var appState: AppState
    let scenarioId: UUID

    @State private var generating = false
    @State private var generationError: String?

    private var scenario: Scenario? {
        appState.scenarios.first { $0.id == scenarioId }
    }

    var body: some View {
        Group {
            if let s = scenario, let c = s.curriculum, !(c.dialogue ?? []).isEmpty {
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

    /// One generation per subject — the result is persisted on the scenario,
    /// so the book in Practice and this player share the same scene forever.
    private func ensureCurriculum(force: Bool = false) async {
        guard let s = scenario, (s.curriculum?.dialogue ?? []).isEmpty,
              force || !generating else { return }
        guard !generating else { return }
        generating = true
        defer { generating = false }
        do {
            let counterpart = s.counterpartId.flatMap { id in
                appState.counterparts.first { $0.id == id }
            }
            let curriculum = try await ScenarioCurriculumEngine.generate(
                scenario: s,
                persona: appState.persona,
                counterpart: counterpart,
                proficiency: appState.proficiency,
                targetLanguage: appState.targetLanguage
            )
            guard var fresh = scenario else { return }
            fresh.curriculum = curriculum
            appState.saveScenario(fresh)
            appState.refreshScenarioMastery(id: scenarioId)
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
