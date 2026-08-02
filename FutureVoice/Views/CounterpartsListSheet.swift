import SwiftUI

// The counterpart LIST moved into WatchTab (it owns the recent-dialogues +
// people layout now). This file keeps the shared add/edit form.

// MARK: - Form

struct CounterpartFormView: View {
    let initial: Counterpart?
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Counterpart

    init(initial: Counterpart?) {
        self.initial = initial
        _draft = State(initialValue: initial ?? .empty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    TextField("Relationship (e.g. Best friend, Kita parent, Manager)",
                              text: $draft.relationship)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Who")
                } footer: {
                    Text(explain("Required. Everything below is optional but the more you fill in, the more the simulated dialogues feel like the real person."))
                }

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

                Section("Anything else") {
                    TextField("Free notes — quirks, recent events, anything that helps",
                              text: $draft.freeNotes, axis: .vertical)
                        .lineLimit(2...6)
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
                        dismiss()
                    }
                    .disabled(!draft.isMinimallyComplete)
                }
            }
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
                    Text(explain("Tap ▶ to hear a sample in \(LanguageCatalog.englishName(appState.targetLanguage))."))
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
                Text("\(preset.gender) · \(preset.accent) · \(preset.description)")
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
            if let cached = PhraseAudioStore.shared.data(text: text, voiceId: preset.id) {
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
    static func previewLine(for languageCode: String) -> String {
        switch languageCode.split(separator: "-").first.map(String.init) ?? languageCode {
        case "es": return explain("¡Hola! Qué alegría verte. ¿Empezamos?")
        case "de": return explain("Hallo! Schön, dich zu sehen. Sollen wir anfangen?")
        case "fr": return explain("Bonjour ! Ça me fait plaisir de te voir. On commence ?")
        case "it": return explain("Ciao! Che bello vederti. Iniziamo?")
        case "pt": return explain("Oi! Que bom te ver. Vamos começar?")
        case "ja": return "こんにちは！会えてうれしいです。始めましょうか？"
        case "ko": return "안녕하세요! 만나서 반가워요. 시작해 볼까요?"
        case "zh": return "你好！很高兴见到你。我们开始吧？"
        default:   return explain("Hi! It's good to see you. Shall we get started?")
        }
    }
}
