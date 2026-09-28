import SwiftUI

// The counterpart LIST moved into WatchTab (it owns the recent-dialogues +
// people layout now). This file keeps the shared add/edit form.

// MARK: - Form

struct CounterpartFormView: View {
    let initial: Counterpart?
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Counterpart
    /// The photo to save with this person on Save — seeded by the intake
    /// (which picked one before the person existed) or by the form's own
    /// photo control. nil + `removePhoto` = delete the one on file.
    @State private var pendingPhoto: UIImage?
    @State private var removePhoto = false
    @State private var refreshingFacts = false
    @State private var refreshError: String?

    init(initial: Counterpart?, photo: UIImage? = nil) {
        self.initial = initial
        _draft = State(initialValue: initial ?? .empty)
        _pendingPhoto = State(initialValue: photo)
    }

    /// The face the form shows right now: a just-picked photo, else the one
    /// on file, else nothing.
    private var shownPhoto: UIImage? {
        if let pendingPhoto { return pendingPhoto }
        if removePhoto { return nil }
        return CounterpartPhotoStore.shared.image(for: draft.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PersonPhotoButton(onImage: { pendingPhoto = $0; removePhoto = false },
                                          onRemove: shownPhoto == nil ? nil : { pendingPhoto = nil; removePhoto = true }) {
                            PersonPhotoCircle(image: shownPhoto, name: draft.name, size: 88)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    TextField("Relationship (e.g. Best friend, Kita parent, Manager)",
                              text: $draft.relationship)
                        .textInputAutocapitalization(.sentences)
                    Toggle("Public figure", isOn: Binding(
                        get: { draft.isPublicFigure == true },
                        set: { draft.isPublicFigure = $0 ? true : nil }))
                } header: {
                    Text("Who")
                } footer: {
                    Text(draft.isPublicFigure == true
                         ? explain("A public figure's profile comes from public coverage. Their voice is a preset, never their real one.")
                         : explain("Required. Everything below is optional but the more you fill in, the more the simulated dialogues feel like the real person."))
                }

                if draft.isPublicFigure == true {
                    // The whole profile of a public figure: WHO it is, for the
                    // learner to confirm. The model knows the rest.
                    Section {
                        HStack {
                            Text("Who")
                            Spacer()
                            if let who = draft.publicIdentity, !who.isEmpty {
                                Text(who).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                            } else if draft.factsRefreshedAt != nil {
                                Text("Not found").foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            Task { await lookUpAgain() }
                        } label: {
                            HStack {
                                Label("Look up again", systemImage: "magnifyingglass")
                                Spacer()
                                if refreshingFacts { ProgressView().controlSize(.small) }
                            }
                        }
                        .disabled(refreshingFacts || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    } header: {
                        Text("Who they are")
                    } footer: {
                        if let e = refreshError {
                            Text(e).foregroundStyle(.red)
                        } else if draft.publicIdentity?.isEmpty == false {
                            Text(explain("Calls draw on everything publicly known about them. Wrong person? Fix the name and look up again."))
                        } else if draft.factsRefreshedAt != nil {
                            Text(explain("Nobody public came up for that name. Check the spelling and look up again."))
                        } else {
                            Text(explain("Look up to find who they are, then confirm."))
                        }
                    }
                } else {
                    Section("About them") {
                        TextField("Where they live, what they do",
                                  text: $draft.location, axis: .vertical)
                            .lineLimit(1...4)
                    }

                    Section("Your history together") {
                        TextField("How you met (and how long)",
                                  text: $draft.howWeMet, axis: .vertical)
                            .lineLimit(1...3)
                        TextField("Shared context, memories, inside jokes",
                                  text: $draft.background, axis: .vertical)
                            .lineLimit(2...8)
                    }

                    Section("How they talk") {
                        TextField("Style (e.g. Direct, loves jokes / Formal, careful)",
                                  text: $draft.conversationStyle, axis: .vertical)
                            .lineLimit(1...3)
                        TextField("What you usually talk about",
                                  text: $draft.commonTopics, axis: .vertical)
                            .lineLimit(1...3)
                    }
                }

                Section {
                    registerPicker(explain("You talk to them"), selection: $draft.myRegister)
                    registerPicker(explain("They talk to you"), selection: $draft.theirRegister)
                    TextField("What you call them", text: $draft.iCallThem)
                    TextField("What they call you", text: $draft.theyCallMe)
                    if draft.cast == .ownPerson {
                        Toggle("Knows your life", isOn: Binding(
                            get: { draft.knowsLearnersLife },
                            set: { draft.knowsMyLife = $0 }))
                    }
                } header: {
                    Text("How you two talk")
                } footer: {
                    Text(draft.cast == .ownPerson
                         ? explain("Calls and scenes speak this way. Someone who knows your life knows what you've told your future self, the way a close friend would.")
                         : explain("Calls and scenes speak this way."))
                }

                Section("Voice") {
                    NavigationLink {
                        VoicePresetPickerView(selection: $draft.voicePresetId)
                            .environmentObject(appState)
                    } label: {
                        HStack {
                            Text("Voice")
                            Spacer()
                            Text(VoicePreset.by(id: draft.voicePresetId).displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if draft.isPublicFigure != true {
                    Section("Anything else") {
                        TextField("Free notes — quirks, recent events, anything that helps",
                                  text: $draft.freeNotes, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
            }
            .navigationTitle(initial == nil ? "New persona" : "Edit persona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        appState.saveCounterpart(draft)
                        if let pendingPhoto {
                            CounterpartPhotoStore.shared.save(pendingPhoto, for: draft.id)
                        } else if removePhoto {
                            CounterpartPhotoStore.shared.delete(for: draft.id)
                        }
                        dismiss()
                    }
                    .disabled(!draft.isMinimallyComplete)
                }
            }
        }
        // A swipe must never be the way this closes while it holds unsaved
        // work: it discards without asking, and for a NEW person it also
        // closes the intake behind it — everything the user said is gone.
        // Reported: a stray vertical drag in the voice picker dismissed the
        // whole form. Cancel stays, as the deliberate exit.
        .interactiveDismissDisabled(hasUnsavedWork)
    }

    /// One form-of-address row. "Automatic" is nil: the relationship decides,
    /// which is what every person made before the field existed does.
    private func registerPicker(_ title: String, selection: Binding<SpeechRegister?>) -> some View {
        Picker(title, selection: selection) {
            Text("Automatic").tag(SpeechRegister?.none)
            ForEach(SpeechRegister.allCases) { r in
                Text(r.term(in: appState.targetLanguage).map { "\(r.title) · \($0)" } ?? r.title)
                    .tag(SpeechRegister?.some(r))
            }
        }
    }

    /// A person not on file yet is unsaved by definition (the intake's
    /// parsed draft included); an existing one only once something changed.
    private var hasUnsavedWork: Bool {
        guard let initial,
              appState.counterparts.contains(where: { $0.id == initial.id })
        else { return true }
        return draft != initial || pendingPhoto != nil || removePhoto
    }

    /// Ask again WHO this name is — after the learner fixed a spelling, or
    /// when the first answer was the wrong person.
    private func lookUpAgain() async {
        refreshingFacts = true
        refreshError = nil
        defer { refreshingFacts = false }
        do {
            draft.publicIdentity = try await CounterpartParser.identifyPublicFigure(
                name: draft.name, nativeLanguage: appState.nativeLanguage)
            draft.factsRefreshedAt = Date()
        } catch {
            refreshError = error.localizedDescription
        }
    }
}

// MARK: - Voice picker with preview

/// Voice list where every row can be HEARD before it's chosen. The preview
/// line is spoken in the user's target language (that's what the counterpart
/// will actually speak) and cached in `PhraseAudioStore` per voice+text, so
/// each voice costs at most one synthesis ever — repeat listens are free.
struct VoicePresetPickerView: View {
    @Binding var selection: String
    @EnvironmentObject private var appState: AppState
    @StateObject private var player = AudioPlayer()
    @State private var loadingId: String?
    @State private var playingId: String?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(VoicePreset.catalog) { preset in
                    row(preset)
                }
            } footer: {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else {
                    Text(explain("Tap ▶ to hear a sample in \(LanguageCatalog.name(appState.targetLanguage, in: appState.nativeLanguage))."))
                }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }

    private func row(_ preset: VoicePreset) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await preview(preset) }
            } label: {
                if loadingId == preset.id {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: playingId == preset.id && player.isPlaying
                          ? "stop.circle.fill" : "play.circle")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 28, height: 28)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playingId == preset.id && player.isPlaying
                                ? "Stop preview" : "Preview \(preset.displayName)")

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.displayName)
                Text(preset.caption(in: appState.targetLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if selection == preset.id {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selection = preset.id }
    }

    private func preview(_ preset: VoicePreset) async {
        // Second tap on the playing row = stop.
        if playingId == preset.id, player.isPlaying {
            player.stop()
            playingId = nil
            return
        }
        player.stop()
        playingId = nil
        error = nil

        let text = Self.previewLine(for: appState.targetLanguage)
        loadingId = preset.id
        defer { loadingId = nil }
        do {
            let data: Data
            if let cached = PhraseAudioStore.shared.data(text: text, voiceId: preset.id,
                                                        allowLineage: false) {
                data = cached
            } else {
                data = try await ElevenLabsClient.shared.synthesize(
                    voiceId: preset.id, text: text, purpose: "voice_preview")
                _ = PhraseAudioStore.shared.save(data, text: text, voiceId: preset.id)
            }
            playingId = preset.id
            try player.play(data, source: "voice_preview") {
                playingId = nil
            }
        } catch {
            self.error = "Couldn't play the sample. Check your connection."
            playingId = nil
        }
    }

    /// One neutral greeting per target language — phrasings chosen to avoid
    /// speaker-gender agreement so any voice can say them naturally.
    ///
    /// The `<break>` is ElevenLabs' pause tag. The synthesizer pauses at
    /// punctuation only loosely, and measured on the Korean line the period
    /// after 반가워요 gave NO pause at all — the question ran straight on. The
    /// tag is spoken as silence (~0.5 s), never read out; this line is audio
    /// only, never drawn as text.
    static func previewLine(for languageCode: String) -> String {
        switch languageCode.split(separator: "-").first.map(String.init) ?? languageCode {
        case "es": return "¡Hola! Qué alegría verte. <break time=\"0.5s\" /> ¿Empezamos?"
        case "de": return "Hallo! Schön, dich zu sehen. <break time=\"0.5s\" /> Sollen wir anfangen?"
        case "fr": return "Bonjour ! Ça me fait plaisir de te voir. <break time=\"0.5s\" /> On commence ?"
        case "it": return "Ciao! Che bello vederti. <break time=\"0.5s\" /> Iniziamo?"
        case "pt": return "Oi! Que bom te ver. <break time=\"0.5s\" /> Vamos começar?"
        case "ja": return "こんにちは！会えてうれしいです。<break time=\"0.5s\" />始めましょうか？"
        case "ko": return "안녕하세요! 만나서 반가워요. <break time=\"0.5s\" /> 시작해 볼까요?"
        case "zh": return "你好！很高兴见到你。<break time=\"0.5s\" />我们开始吧？"
        default:   return "Hi! It's good to see you. <break time=\"0.5s\" /> Shall we get started?"
        }
    }
}
