import SwiftUI

/// The "tell me more about you" ask, moved OUT of first-run onboarding to the
/// moment right after the first talk — when the user has just experienced a
/// generic conversation and the pitch ("richer persona = more real talks")
/// lands on lived evidence. Collects the three narrative persona fields the
/// intake flow deliberately skips: occupation, household, free notes. Each is
/// speak-first with a typing fallback; dictated answers get one Gemini polish
/// pass on save (`PersonaParser`), and a failed polish never blocks — raw
/// transcripts are still usable ground truth.
///
/// Presented once automatically (ConversationHome owns the trigger + the
/// once-ever flag); afterwards reachable any time from the Talk-home row and
/// Me → Profile.
struct PersonaDeepenSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var occupation = ""
    @State private var household = ""
    @State private var freeNotes = ""
    @State private var locale = "ko"
    @State private var workVoiced = false
    @State private var peopleVoiced = false
    @State private var extrasVoiced = false
    @State private var isSaving = false

    private var hasAnything: Bool {
        ![occupation, household, freeNotes]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    IntakeStepHeader(
                        question: "Make me sound more like you",
                        detail: "The more your fluent self knows about your life, the more real every talk feels — your work, your people, your quirks come up naturally instead of small talk about nowhere. Just talk — your native language is fine.")

                    field(title: "What do you do?",
                          text: $occupation,
                          usedVoice: $workVoiced,
                          placeholder: "Work, study, or your main project — what a typical day looks like")

                    field(title: "Who's in your daily life?",
                          text: $household,
                          usedVoice: $peopleVoiced,
                          placeholder: "Who you live with, kids, pets — people you end up talking about")

                    field(title: "Anything else?",
                          text: $freeNotes,
                          usedVoice: $extrasVoiced,
                          placeholder: "Quirks, goals, pet peeves — whatever helps me sound like you")
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("About you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Later") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Sorting it out…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!hasAnything || isSaving)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .onAppear {
                locale = appState.nativeLanguage
                // Editing (from the Talk-home row) starts from what's already
                // saved, not blank fields that would overwrite it with "".
                if let p = appState.persona {
                    occupation = p.occupation
                    household = p.household
                    freeNotes = p.freeNotes
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isSaving)
    }

    private func field(title: String, text: Binding<String>,
                       usedVoice: Binding<Bool>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            SpeakOrTypeField(
                text: text,
                locale: $locale,
                usedVoice: usedVoice,
                placeholder: placeholder)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var occ = occupation, house = household, notes = freeNotes
        // Only dictated answers go through the polish pass — typed text is
        // already deliberate; rewriting it would surprise the user.
        let voicedOccupation = workVoiced ? occ : ""
        let voicedHousehold = peopleVoiced ? house : ""
        let voicedNotes = extrasVoiced ? notes : ""
        if !(voicedOccupation.isEmpty && voicedHousehold.isEmpty && voicedNotes.isEmpty) {
            do {
                let polished = try await PersonaParser.polish(
                    occupation: voicedOccupation,
                    household: voicedHousehold,
                    freeNotes: voicedNotes,
                    languageHint: locale)
                if !voicedOccupation.isEmpty, !polished.occupation.isEmpty { occ = polished.occupation }
                if !voicedHousehold.isEmpty, !polished.household.isEmpty { house = polished.household }
                if !voicedNotes.isEmpty, !polished.free_notes.isEmpty { notes = polished.free_notes }
            } catch {
                // Keep the raw transcripts — never block the save on the polish.
            }
        }
        var persona = appState.persona ?? .empty
        persona.occupation = occ
        persona.household = house
        persona.freeNotes = notes
        appState.savePersona(persona)
        dismiss()
    }
}
