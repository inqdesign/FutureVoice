import SwiftUI

// Shared building blocks for the guided "tell me about…" intake flows —
// persona onboarding (`PersonaIntakeView`) and new-People
// (`CounterpartVoiceIntakeView`). Each flow walks fixed categories one card
// at a time; every category uses whichever input fits it best: plain text
// fields for short facts, chips for enumerable choices, speak-first (with a
// typing fallback) for narrative answers.

// MARK: - Step header

/// The big friendly question at the top of every intake card.
struct IntakeStepHeader: View {
    var question: String
    var detail: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(.title2.bold())
            if !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Hints card

/// "Worth mentioning" bullet card — tells the user what kind of detail makes
/// a good answer, without demanding any of it.
struct IntakeHints: View {
    var title: String = "Worth mentioning"
    var bullets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            ForEach(bullets, id: \.self) { b in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 7)
                    Text(b)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Chips

/// One capsule chip; selection styling shared by every intake chip grid.
struct IntakeChipLabel: View {
    var text: String
    var isOn: Bool

    var body: some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? Color(.systemBackground) : Color.primary)
            .background(Capsule().fill(isOn ? Color.accentColor : Color(.tertiarySystemFill)))
    }
}

/// Multi-select chip grid with an optional "add your own" free-text row.
/// Custom entries the user already picked show up as chips too.
struct ChipPickerField: View {
    var presets: [String]
    @Binding var selection: [String]
    var allowsCustom: Bool = true
    var addPrompt: String = "Add your own (comma-separated)"

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let all = presets + selection.filter { !presets.contains($0) }
            let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(all, id: \.self) { tag in
                    Button {
                        toggle(tag)
                    } label: {
                        IntakeChipLabel(text: tag, isOn: selection.contains(tag))
                    }
                    .buttonStyle(.plain)
                }
            }
            if allowsCustom {
                TextField(addPrompt, text: $draft)
                    .submitLabel(.done)
                    .onSubmit(mergeDraft)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onDisappear(perform: mergeDraft)   // fold unsubmitted text on Next
    }

    private func toggle(_ value: String) {
        if let idx = selection.firstIndex(of: value) {
            selection.remove(at: idx)
        } else {
            selection.append(value)
        }
    }

    private func mergeDraft() {
        let pieces = draft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for p in pieces where !selection.contains(p) { selection.append(p) }
        draft = ""
    }
}

// MARK: - Speak or type

/// Voice-first free-form answer for one category. The mic is the hero; a
/// "Type instead" toggle swaps to a plain TextField over the same binding —
/// voice is the default, never a requirement. Multiple takes append.
struct SpeakOrTypeField: View {
    @Binding var text: String
    @Binding var locale: String
    /// Flips true once any dictation lands in `text` — callers use it to
    /// decide whether the answer needs an LLM cleanup pass on finish.
    var usedVoice: Binding<Bool>? = nil
    var placeholder: String = "Tap the mic and just talk — wander, restart, change your mind. I'll sort it out."

    @StateObject private var live = LiveTranscriber()
    @State private var isRecording = false
    @State private var typing = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 10) {
            if typing {
                typingCard
            } else {
                voiceCard
            }

            Button {
                if isRecording { commitRecordingNow() }
                withAnimation { typing.toggle() }
            } label: {
                Label(typing ? "Talk instead" : "Type instead",
                      systemImage: typing ? "mic" : "keyboard")
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)

            if let e = error {
                Label(e, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear {
            if isRecording { commitRecordingNow() }
        }
    }

    // MARK: Cards

    private var displayText: String {
        let partial = live.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if isRecording, !partial.isEmpty {
            return text.isEmpty ? partial : text + "\n" + partial
        }
        return text
    }

    private var voiceCard: some View {
        VStack(spacing: 14) {
            Text(displayText.isEmpty ? placeholder : displayText)
                .font(.body)
                .foregroundStyle(displayText.isEmpty ? Color(.tertiaryLabel) : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await toggleMic() }
            } label: {
                ZStack {
                    Circle()
                        .fill(isRecording ? Color.red : Color.accentColor)
                        .frame(width: 64, height: 64)
                        .scaleEffect(isRecording ? 1.06 : 1.0)
                        .animation(
                            isRecording
                                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                : .default,
                            value: isRecording
                        )
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                }
            }
            .buttonStyle(.plain)

            if isRecording {
                HStack(spacing: 5) {
                    Circle().fill(.red).frame(width: 7, height: 7)
                    Text("Listening — tap to finish")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Text("I'll listen in")
                    Picker("Language", selection: $locale) {
                        Text("한국어").tag("ko")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var typingCard: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(4...10)
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Recording

    private func toggleMic() async {
        if isRecording {
            isRecording = false
            append(await live.stopAndFinalize())
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

    /// Synchronous commit for onDisappear / mode-toggle — skips the
    /// final-pass wait `stopAndFinalize` would do.
    private func commitRecordingNow() {
        isRecording = false
        append(live.stop())
    }

    private func append(_ heard: String) {
        let trimmed = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        text = text.isEmpty ? trimmed : text + "\n" + trimmed
        usedVoice?.wrappedValue = true
    }
}

// MARK: - Bottom bar

/// Back / Next bar shared by both intake flows. `isWorking` shows a spinner
/// in the primary button (parse pass at the end of a flow).
struct IntakeBottomBar: View {
    var backVisible: Bool
    var nextTitle: String
    var nextEnabled: Bool = true
    var isWorking: Bool = false
    var workingTitle: String = "Sorting it out…"
    var onBack: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if backVisible {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isWorking)
            }
            Button(action: onNext) {
                if isWorking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(workingTitle)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(nextTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!nextEnabled || isWorking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
