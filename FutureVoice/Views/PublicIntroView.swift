import SwiftUI

/// Me → "Find people" — write and publish your own self-introduction into
/// the shared persona pool, so other learners can practice talking with
/// "you". What they meet is an AI playing this introduction in a STOCK
/// preset voice — never your cloned voice, and their talks never reach you.
///
/// The intro is written in the TARGET language on purpose: it doubles as the
/// persona's conversational substance and as writing practice for the
/// author. Density is the entry ticket — a one-liner can't carry a
/// conversation, so publishing unlocks at a minimum length.
struct PublicIntroView: View {
    @EnvironmentObject private var appState: AppState

    @State private var displayName = ""
    @State private var intro = ""
    @State private var location = ""
    @State private var occupation = ""
    @State private var interests = ""
    @State private var voicePresetId = VoicePreset.catalog.first!.id

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var publishedId: String?
    @State private var errorText: String?
    @State private var confirmingWithdraw = false

    /// A one-line hello can't carry a conversation — the pool only takes
    /// intros dense enough to talk to.
    private static let minIntroLength = 80

    private var trimmedIntro: String {
        intro.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canPublish: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && trimmedIntro.count >= Self.minIntroLength
            && !isSaving
    }

    private var languageName: String {
        LanguageCatalog.englishName(appState.targetLanguage)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $displayName)
            } footer: {
                Text(explain("The name other learners will see — first name or nickname is plenty."))
            }

            Section {
                TextEditor(text: $intro)
                    .frame(minHeight: 140)
                HStack {
                    Spacer()
                    Text("\(trimmedIntro.count) / \(Self.minIntroLength)")
                        .font(.caption2)
                        .foregroundStyle(trimmedIntro.count >= Self.minIntroLength ? .secondary : .tertiary)
                        .monospacedDigit()
                }
            } header: {
                Text("Introduction")
            } footer: {
                Text(explain("Write it in \(languageName) — it's what \"you\" will talk from, and writing it is practice too. The specific beats the polished: your job, your town, the thing you'd actually talk about for an hour."))
            }

            Section("Details") {
                TextField("City, country", text: $location)
                TextField("What you do", text: $occupation)
                TextField("Interests", text: $interests)
            }

            Section {
                Picker("Voice", selection: $voicePresetId) {
                    ForEach(VoicePreset.catalog) { v in
                        Text("\(v.displayName) — \(v.gender), \(v.accent)").tag(v.id)
                    }
                }
            } footer: {
                Text(explain("A stock voice that plays \"you\" — your cloned voice is never used, and nobody's talks with your persona are ever shown to you or anyone else."))
            }

            Section {
                Button {
                    Task { await publish() }
                } label: {
                    if isSaving {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else {
                        Text(publishedId == nil ? "Publish" : "Update")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canPublish)
                .listRowInsets(EdgeInsets())

                if publishedId != nil {
                    Button(role: .destructive) {
                        confirmingWithdraw = true
                    } label: {
                        Text("Take down").frame(maxWidth: .infinity)
                    }
                }
            } footer: {
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                } else if publishedId != nil {
                    Text(explain("You're in the pool — other \(languageName) learners can find and talk with your persona."))
                }
            }
        }
        .navigationTitle("Find people")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isLoading)
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
        .confirmationDialog(
            explain("Take your intro out of the pool? Learners who already met your persona keep their own past talks."),
            isPresented: $confirmingWithdraw, titleVisibility: .visible
        ) {
            Button("Take down", role: .destructive) {
                Task { await withdraw() }
            }
        }
    }

    private func load() async {
        defer { isLoading = false }
        if let mine = try? await PublicPersonaService.fetchMine(language: appState.targetLanguage) {
            publishedId = mine.id
            displayName = mine.display_name
            intro = mine.intro
            location = mine.location
            occupation = mine.occupation
            interests = mine.interests
            voicePresetId = mine.voice_preset_id
        } else {
            // Draft seeds from the profile the user already gave onboarding —
            // the intro itself stays theirs to write.
            displayName = appState.persona?.displayName ?? ""
            if let p = appState.persona {
                location = [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", ")
                occupation = p.occupation
                interests = p.interests.joined(separator: ", ")
            }
        }
    }

    private func publish() async {
        isSaving = true
        errorText = nil
        do {
            try await PublicPersonaService.publishMine(
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                intro: trimmedIntro,
                location: location.trimmingCharacters(in: .whitespaces),
                occupation: occupation.trimmingCharacters(in: .whitespaces),
                interests: interests.trimmingCharacters(in: .whitespaces),
                voicePresetId: voicePresetId,
                language: appState.targetLanguage)
            // From here on the user curates their own row — the launch-time
            // auto-sync from the onboarding profile must never overwrite it.
            UserDefaults.standard.set(true, forKey: PublicPersonaService.manualIntroKey)
            if publishedId == nil {
                publishedId = try? await PublicPersonaService.fetchMine(
                    language: appState.targetLanguage)?.id
            }
        } catch {
            errorText = explain("Couldn't publish — check your connection and try again.")
        }
        isSaving = false
    }

    private func withdraw() async {
        isSaving = true
        errorText = nil
        do {
            try await PublicPersonaService.withdrawMine(language: appState.targetLanguage)
            // Taking it down is as deliberate as publishing — stop the
            // auto-sync from quietly putting the row back next launch.
            UserDefaults.standard.set(true, forKey: PublicPersonaService.manualIntroKey)
            publishedId = nil
        } catch {
            errorText = explain("Couldn't take it down — check your connection and try again.")
        }
        isSaving = false
    }
}
