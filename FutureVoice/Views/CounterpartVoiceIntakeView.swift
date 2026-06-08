import SwiftUI

/// Voice-first new-person flow. The user just talks (in their native language)
/// about someone they know; we transcribe, parse into a `Counterpart` draft
/// with Gemini, and push to the form prefilled so they can tweak + pick a
/// voice. Manual-form fallback is offered for users who prefer typing.
struct CounterpartVoiceIntakeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var live = LiveTranscriber()

    @State private var locale: String = "ko"   // overwritten in .onAppear from appState.nativeLanguage
    @State private var isRecording = false
    @State private var isParsing = false
    @State private var error: String?
    @State private var prefilled: Counterpart?
    @State private var showManualForm = false

    private let prompts: [String] = [
        "Their name — and what you actually call them",
        "How you know each other (where you met, how long)",
        "What they do, where they live, what they're into",
        "Shared context — inside jokes, recurring topics, recent events",
        "How they talk — direct, sarcastic, formal, playful?",
        "What they know (and don't know) about your life"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    promptsCard
                    transcriptCard
                    if let e = error {
                        Label(e, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 220)
            }
            .navigationTitle("Tell me about them")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if isRecording { _ = live.stop() }
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .sheet(item: $prefilled, onDismiss: { dismiss() }) { draft in
                CounterpartFormView(initial: draft)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showManualForm, onDismiss: { dismiss() }) {
                CounterpartFormView(initial: nil)
                    .environmentObject(appState)
            }
            .onAppear { locale = appState.nativeLanguage }
        }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speak — in your native language is fine")
                .font(.headline)
            Text("The more specific you are about who they are and how they talk, the more the simulated dialogues will feel like the real person.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var promptsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lightbulb")
                    .foregroundStyle(.tint)
                Text("Worth mentioning")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Language", selection: $locale) {
                    Text("한국어").tag("ko")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            ForEach(prompts, id: \.self) { p in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 7)
                    Text(p)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("What I heard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isRecording {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text("recording").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Text(live.transcript.isEmpty
                 ? "Tap the mic and start talking. Wander, restart, change your mind — we'll sort it out."
                 : live.transcript)
                .font(.body)
                .foregroundStyle(live.transcript.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Button { Task { await handleMic() } } label: {
                ZStack {
                    Circle()
                        .fill(isRecording ? Color.red : Color.accentColor)
                        .frame(width: 68, height: 68)
                        .scaleEffect(isRecording ? 1.06 : 1.0)
                        .animation(
                            isRecording
                                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                : .default,
                            value: isRecording
                        )
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                }
            }
            .buttonStyle(.plain)
            .disabled(isParsing)

            Button {
                Task { await parseAndContinue() }
            } label: {
                if isParsing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Sorting it out…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Continue").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(live.transcript.trimmingCharacters(in: .whitespaces).isEmpty
                      || isRecording || isParsing)

            Button("Fill the form manually instead") {
                showManualForm = true
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Actions

    private func handleMic() async {
        if isRecording {
            _ = live.stop()
            isRecording = false
            return
        }
        let granted = await LiveTranscriber.requestPermissions()
        guard granted else {
            error = "Microphone or speech permission denied."
            return
        }
        error = nil
        do {
            try live.start(locale: locale)
            isRecording = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func parseAndContinue() async {
        if isRecording { _ = live.stop(); isRecording = false }
        let text = live.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isParsing = true
        defer { isParsing = false }
        do {
            let draft = try await CounterpartParser.parse(
                spokenDescription: text,
                languageHint: locale
            )
            prefilled = draft
        } catch {
            self.error = "Couldn't parse: \(error.localizedDescription)"
        }
    }
}
