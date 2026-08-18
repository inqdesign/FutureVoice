import SwiftUI
import PhotosUI

/// First-run persona collection — four light cards only: name, home, and the
/// two chip picks (interests feed the news rail, situations steer scenario
/// suggestions). The narrative "tell me about…" answers (occupation,
/// household, quirks) are deliberately NOT asked here — the first talk works
/// generic-but-warm, and `PersonaDeepenSheet` asks for the rich version right
/// after it, when the user has felt why it matters. Later edits happen in the
/// plain form (`PersonaOnboardingView`) from Me → Profile.
struct PersonaIntakeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable {
        case name, home, interests, situations
    }

    @State private var step: Step = .name
    @State private var persona: UserPersona = .empty

    /// Draft persistence: answers + current card survive an app kill, so a
    /// relaunch resumes where the user left off instead of re-asking the
    /// cards. Saved at every step transition, cleared on finish.
    private static let draftKey = "futurevoice.personaDraft"
    private static let draftStepKey = "futurevoice.personaDraftStep"
    @State private var avatarPick: PhotosPickerItem?
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
                    nextTitle: chrome("Next"),
                    nextEnabled: canAdvance,
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
        case .interests:  interestsStep
        case .situations: situationsStep
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: explain("What should I call you?"),
                detail: explain("We're building your fluent self — it'll speak in your own voice at the end of this. The more you share, the more it'll sound like you, not a textbook."))
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
                question: explain("Where's home these days?"),
                detail: explain("Real places make your conversations concrete — no small talk about nowhere."))
            VStack(spacing: 0) {
                TextField("City", text: $persona.city)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                CardDivider(inset: 14)
                TextField("Country", text: $persona.country)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                CardDivider(inset: 14)
                TextField("How long have you been there? (optional)", text: $persona.lengthOfStay)
                    .padding(14)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var interestsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: explain("What are you into?"),
                detail: explain("Tap what fits — these pick your news stories and fuel conversations."))
            ChipPickerField(
                presets: PersonaOnboardingView.interestPresets,
                selection: $persona.interests)
        }
    }

    private var situationsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            IntakeStepHeader(
                question: explain("What do you want to be able to do in \(LanguageCatalog.learnerName(appState.targetLanguage))?"),
                detail: explain("What you pick becomes your goal — practice aims at it."))
            ChipPickerField(
                presets: PersonaOnboardingView.situationPresets,
                selection: $persona.situations)
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
        if step == .situations {
            finish()
        } else {
            withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .situations }
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
        // A draft step from the old seven-card flow can point past the end —
        // clamp instead of silently restarting at card one.
        let raw = min(UserDefaults.standard.integer(forKey: Self.draftStepKey),
                      Step.allCases.count - 1)
        step = Step(rawValue: raw) ?? .name
        return true
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
        UserDefaults.standard.removeObject(forKey: Self.draftStepKey)
    }

    private func seed() {
        guard !didSeed else { return }
        didSeed = true
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

    private func finish() {
        appState.savePersona(persona)
        clearDraft()
        dismiss()   // no-op on first run; RootView swaps once persona != nil
    }
}
