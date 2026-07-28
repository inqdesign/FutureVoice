import SwiftUI
import PhotosUI

/// First-run persona collection, one guided card per category. Each category
/// uses the input that fits it: typed fields for name/city, chips for
/// interests/situations, speak-first (with a typing fallback) for the
/// narrative answers. Dictated answers get one Gemini polish pass on finish
/// (`PersonaParser`); a failed polish never blocks onboarding — raw
/// transcripts are still usable ground truth. Later edits happen in the
/// plain form (`PersonaOnboardingView`) from Me → Profile.
struct PersonaIntakeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable {
        case name, home, work, people, interests, situations, extras
    }

    @State private var step: Step = .name
    @State private var persona: UserPersona = .empty

    /// Draft persistence: answers + current card survive an app kill, so a
    /// relaunch resumes where the user left off instead of re-asking seven
    /// cards. Saved at every step transition, cleared on finish.
    private static let draftKey = "futurevoice.personaDraft"
    private static let draftStepKey = "futurevoice.personaDraftStep"
    @State private var locale = "ko"
    @State private var workVoiced = false
    @State private var peopleVoiced = false
    @State private var extrasVoiced = false
    @State private var avatarPick: PhotosPickerItem?
    @State private var isFinishing = false
    @State private var didSeed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        stepContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity))
                }
                .scrollDismissesKeyboard(.interactively)
                .animation(.snappy, value: step)
                IntakeBottomBar(
                    backVisible: true,
                    // Voice clone follows this flow now, so the last card is a
                    // "Next", not the app entrance.
                    nextTitle: "Next",
                    nextEnabled: canAdvance,
                    isWorking: isFinishing,
                    onBack: {
                        if step == .name {
                            // Cross-stage back: reopen the quick-answer setup.
                            // Answers survive — the draft here, appState there.
                            saveDraft()
                            appState.setupComplete = false
                        } else {
                            withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .name }
                            saveDraft()
                        }
                    },
                    onNext: advance
                )
            }
            .navigationTitle("About you")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: seed)
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .name:       nameStep
        case .home:       homeStep
        case .work:       workStep
        case .people:     peopleStep
        case .interests:  interestsStep
        case .situations: situationsStep
        case .extras:     extrasStep
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: "What should I call you?",
                detail: "Your fluent self wants to know you. The more you share, the more I'll sound like a version of you — not a textbook.")
            VStack(spacing: 16) {
                PhotosPicker(selection: $avatarPick, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileAvatar(initials: persona.displayName, size: 88)
                        Image(systemName: "pencil.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                TextField("Your name", text: $persona.displayName)
                    .textInputAutocapitalization(.words)
                    .font(.title3)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .onChange(of: avatarPick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    AvatarStore.shared.save(img)
                }
            }
        }
    }

    private var homeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: "Where's home these days?",
                detail: "Real places make your conversations concrete — no small talk about nowhere.")
            VStack(spacing: 0) {
                TextField("City", text: $persona.city)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                Divider().padding(.leading, 14)
                TextField("Country", text: $persona.country)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                Divider().padding(.leading, 14)
                TextField("How long have you been there? (optional)", text: $persona.lengthOfStay)
                    .padding(14)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var workStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: "What do you do?",
                detail: "Just talk — your native language is fine. I'll sort it out.")
            IntakeHints(bullets: [
                "Your work, study, or main project",
                "What a typical day looks like",
                "Anything you're building or learning right now"
            ])
            SpeakOrTypeField(
                text: $persona.occupation,
                locale: $locale,
                usedVoice: $workVoiced,
                placeholder: "e.g. Solo founder of an AI app for parents")
        }
    }

    private var peopleStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: "Who's in your daily life?",
                detail: "The cast of your everyday stories. Skip if you like.")
            IntakeHints(bullets: [
                "Who you live with — names welcome",
                "Kids, partner, pets",
                "People you end up talking about a lot"
            ])
            SpeakOrTypeField(
                text: $persona.household,
                locale: $locale,
                usedVoice: $peopleVoiced,
                placeholder: "e.g. Wife and 4yo daughter at Kita")
        }
    }

    private var interestsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: "What are you into?",
                detail: "Tap what fits — these become conversation fuel.")
            ChipPickerField(
                presets: PersonaOnboardingView.interestPresets,
                selection: $persona.interests)
        }
    }

    private var situationsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: "When do you most need \(LanguageCatalog.englishName(appState.targetLanguage))?",
                detail: "So practice aims at moments that actually happen to you.")
            ChipPickerField(
                presets: PersonaOnboardingView.situationPresets,
                selection: $persona.situations)
        }
    }

    private var extrasStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: "Anything else I should know?",
                detail: "Quirks, goals, pet peeves — whatever helps me sound like you. Totally optional.")
            SpeakOrTypeField(
                text: $persona.freeNotes,
                locale: $locale,
                usedVoice: $extrasVoiced,
                placeholder: "Anything that helps me sound like you")
        }
    }

    // MARK: - Flow

    private var canAdvance: Bool {
        switch step {
        case .name: return !persona.displayName.trimmingCharacters(in: .whitespaces).isEmpty
        case .home: return !persona.city.trimmingCharacters(in: .whitespaces).isEmpty
        default:    return true
        }
    }

    private func advance() {
        if step == .extras {
            Task { await finish() }
        } else {
            withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .extras }
            saveDraft()
        }
    }

    // MARK: - Draft persistence

    private func saveDraft() {
        if let data = try? JSONEncoder().encode(persona) {
            UserDefaults.standard.set(data, forKey: Self.draftKey)
        }
        UserDefaults.standard.set(step.rawValue, forKey: Self.draftStepKey)
    }

    @discardableResult
    private func restoreDraft() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.draftKey),
              let draft = try? JSONDecoder().decode(UserPersona.self, from: data) else { return false }
        persona = draft
        step = Step(rawValue: UserDefaults.standard.integer(forKey: Self.draftStepKey)) ?? .name
        return true
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
        UserDefaults.standard.removeObject(forKey: Self.draftStepKey)
    }

    private func seed() {
        guard !didSeed else { return }
        didSeed = true
        locale = appState.nativeLanguage
        // A draft from an interrupted run wins — resume where the user left
        // off instead of re-asking from card one. No draft but a saved
        // persona (cross-stage Back from the voice-clone step) → edit that.
        if !restoreDraft(), let saved = PersonaStore.shared.load() {
            persona = saved
        }
        // Seed the name from what Apple gave us at sign-in, so the user isn't
        // retyping something we already know. They can edit it.
        if persona.displayName.isEmpty,
           let appleName = UserDefaults.standard.string(forKey: AuthService.appleNameKey) {
            persona.displayName = appleName
        }
        #if DEBUG
        // Screenshot harness: `-intakeStep <n>` jumps to a card with stand-in data.
        if let raw = UserDefaults.standard.string(forKey: "intakeStep"),
           let i = Int(raw), let s = Step(rawValue: i) {
            persona.displayName = "Eunggyu"
            persona.city = "Munich"
            step = s
        }
        #endif
    }

    private func finish() async {
        isFinishing = true
        defer { isFinishing = false }
        // Only dictated answers go through the polish pass — typed text is
        // already deliberate; rewriting it would surprise the user.
        let voicedOccupation = workVoiced ? persona.occupation : ""
        let voicedHousehold = peopleVoiced ? persona.household : ""
        let voicedNotes = extrasVoiced ? persona.freeNotes : ""
        if !(voicedOccupation.isEmpty && voicedHousehold.isEmpty && voicedNotes.isEmpty) {
            do {
                let polished = try await PersonaParser.polish(
                    occupation: voicedOccupation,
                    household: voicedHousehold,
                    freeNotes: voicedNotes,
                    languageHint: locale)
                if !voicedOccupation.isEmpty, !polished.occupation.isEmpty {
                    persona.occupation = polished.occupation
                }
                if !voicedHousehold.isEmpty, !polished.household.isEmpty {
                    persona.household = polished.household
                }
                if !voicedNotes.isEmpty, !polished.free_notes.isEmpty {
                    persona.freeNotes = polished.free_notes
                }
            } catch {
                // Keep the raw transcripts — never block onboarding on the polish.
            }
        }
        appState.savePersona(persona)
        clearDraft()
        dismiss()   // no-op on first run; RootView swaps once persona != nil
    }
}
