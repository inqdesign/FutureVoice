import SwiftUI

/// Voice-first conversation screen.
///
/// Designed like a phone call, not a chat app: a single dominant mic button,
/// a plain status line, and a one-line caption of the most recent dialogue.
/// Full transcript and session summary are accessed via sheets so this screen
/// stays focused on the act of speaking.
struct ConversationView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var player = AudioPlayer()

    @State private var topic = "Ordering coffee"
    @State private var turns: [Turn] = []
    @State private var phase: Phase = .idle
    @State private var error: String?
    @State private var summary: SessionSummary?
    @State private var showTranscript = false
    @State private var showTopicPicker = false

    private let userId = UUID()

    enum Phase: Equatable {
        case idle
        case listening      // mic open, recording user
        case thinking       // STT + Claude in flight
        case speaking       // fluent self is talking
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusArea
                Spacer(minLength: 0)
                micButton
                Spacer(minLength: 0)
                hintText
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle(topic)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showTopicPicker = true } label: {
                        Label("Topic", systemImage: "list.bullet")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showTranscript = true } label: {
                        Label("Transcript", systemImage: "text.alignleft")
                    }
                    .disabled(turns.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        Task { await endSession() }
                    } label: {
                        Text("End session")
                    }
                    .disabled(turns.isEmpty || phase != .idle)
                }
            }
            .sheet(isPresented: $showTopicPicker) {
                TopicPickerSheet(topic: $topic)
            }
            .sheet(isPresented: $showTranscript) {
                TranscriptSheet(turns: turns)
            }
            .sheet(item: summaryBinding) { s in
                SummarySheet(summary: s)
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .task {
                if turns.isEmpty { await openConversation() }
            }
        }
    }

    // MARK: - Status area

    private var statusArea: some View {
        VStack(spacing: 12) {
            Text(statusLabel)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            Text(captionLine)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .top)
        }
        .padding(.top, 24)
    }

    private var statusLabel: String {
        switch phase {
        case .idle:      return turns.isEmpty ? "Connecting" : "Your turn"
        case .listening: return "Listening"
        case .thinking:  return "Thinking"
        case .speaking:  return "Future self speaking"
        }
    }

    private var captionLine: String {
        if let last = turns.last { return last.transcript }
        return ""
    }

    // MARK: - Mic button

    private var micButton: some View {
        Button {
            Task { await handleMicTap() }
        } label: {
            ZStack {
                Circle()
                    .fill(.tint)
                    .opacity(micButtonOpacity)
                    .frame(width: 180, height: 180)
                    .scaleEffect(phase == .listening ? 1.05 : 1.0)
                    .animation(
                        phase == .listening
                            ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                            : .default,
                        value: phase
                    )

                Image(systemName: micSymbol)
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(Color(.systemBackground))
            }
        }
        .buttonStyle(.plain)
        .tint(micTint)
        .disabled(phase == .thinking || phase == .speaking)
        .accessibilityLabel(Text(statusLabel))
    }

    private var micSymbol: String {
        switch phase {
        case .listening: return "stop.fill"
        case .thinking:  return "ellipsis"
        case .speaking:  return "waveform"
        case .idle:      return "mic.fill"
        }
    }

    private var micTint: Color {
        switch phase {
        case .listening: return .red
        default:         return .accentColor
        }
    }

    private var micButtonOpacity: Double {
        (phase == .thinking || phase == .speaking) ? 0.4 : 1.0
    }

    // MARK: - Hint text

    private var hintText: some View {
        Group {
            switch phase {
            case .idle:
                Text(turns.isEmpty ? " " : "Tap to speak")
            case .listening:
                Text("Tap to send")
            case .thinking:
                ProgressView()
            case .speaking:
                Text(" ")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(height: 20)
    }

    // MARK: - Bindings

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    private var summaryBinding: Binding<SessionSummary?> {
        Binding(get: { summary }, set: { summary = $0 })
    }

    // MARK: - Flow

    private func handleMicTap() async {
        switch phase {
        case .idle:      await startRecording()
        case .listening: await stopAndSend()
        case .thinking, .speaking: break
        }
    }

    private func openConversation() async {
        guard let voiceId = appState.voiceCloneId else { return }
        phase = .thinking
        do {
            let opener = try await ClaudeClient.shared.send(
                system: systemPrompt(),
                messages: [.init(role: .user, content: "Open the conversation with a friendly first line, in \(appState.targetLanguage).")]
            )
            try await speakAndAppend(opener, voiceId: voiceId)
            phase = .idle
        } catch {
            self.error = error.localizedDescription
            phase = .idle
        }
    }

    private func startRecording() async {
        let mic = await recorder.requestPermission()
        let speech = await SpeechTranscriber.requestPermission()
        guard mic, speech else {
            error = "Microphone or speech permission denied."
            return
        }
        do {
            try recorder.start()
            phase = .listening
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stopAndSend() async {
        guard let url = recorder.stop() else { return }
        phase = .thinking
        do {
            let transcript = try await SpeechTranscriber().transcribe(
                audioURL: url,
                languageCode: appState.targetLanguage
            )
            turns.append(Turn(
                id: UUID(), role: .user, audioURL: url,
                transcript: transcript, durationMs: 0, timestamp: Date()
            ))

            guard let voiceId = appState.voiceCloneId else { phase = .idle; return }
            let reply = try await ClaudeClient.shared.send(
                system: systemPrompt(),
                messages: ConversationEngine.messages(from: turns)
            )
            try await speakAndAppend(reply, voiceId: voiceId)
            phase = .idle
        } catch {
            self.error = error.localizedDescription
            phase = .idle
        }
    }

    private func speakAndAppend(_ text: String, voiceId: String) async throws {
        let audio = try await ElevenLabsClient.shared.synthesize(voiceId: voiceId, text: text)
        turns.append(Turn(
            id: UUID(), role: .fluentSelf, audioURL: nil,
            transcript: text, durationMs: 0, timestamp: Date()
        ))
        phase = .speaking
        try player.play(audio) {
            Task { @MainActor in
                if phase == .speaking { phase = .idle }
            }
        }
    }

    private func endSession() async {
        guard !turns.isEmpty else { return }
        phase = .thinking
        do {
            let profile = appState.makeEmptyProfile(userId: userId)
            let systemP = ConversationEngine.summarySystemPrompt(
                targetLanguage: appState.targetLanguage,
                profile: profile
            )
            let transcript = ConversationEngine.formatTranscript(turns)
            let payload: ClaudeSummaryPayload = try await ClaudeClient.shared.sendJSON(
                system: systemP,
                messages: [.init(role: .user, content: transcript)],
                model: .opus47,
                maxTokens: 1024
            )
            summary = payload.toDomain()
            phase = .idle
        } catch {
            self.error = error.localizedDescription
            phase = .idle
        }
    }

    private func systemPrompt() -> String {
        ConversationEngine.conversationSystemPrompt(
            targetLanguage: appState.targetLanguage,
            nativeLanguage: appState.nativeLanguage,
            level: appState.proficiency,
            topPatterns: [],
            weakVocabAreas: [],
            topic: topic
        )
    }
}

// MARK: - Sheets

private struct TopicPickerSheet: View {
    @Binding var topic: String
    @Environment(\.dismiss) private var dismiss

    private let presets = [
        "Ordering coffee",
        "Small talk with a neighbor",
        "Job interview",
        "Asking for directions",
        "Talking about a movie",
        "Catching up with an old friend",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(presets, id: \.self) { preset in
                        Button {
                            topic = preset
                            dismiss()
                        } label: {
                            HStack {
                                Text(preset).foregroundStyle(.primary)
                                Spacer()
                                if preset == topic {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
                Section("Custom") {
                    TextField("Type a topic", text: $topic)
                }
            }
            .navigationTitle("Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct TranscriptSheet: View {
    let turns: [Turn]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(turns) { turn in
                VStack(alignment: .leading, spacing: 4) {
                    Text(turn.role == .user ? "You" : "Future self")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(turn.transcript)
                        .font(.body)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SummarySheet: View {
    let summary: SessionSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Note") {
                    Text(summary.overallNote)
                }
                if !summary.phrasesUsed.isEmpty {
                    Section("More natural alternatives") {
                        ForEach(summary.phrasesUsed) { phrase in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(phrase.userSaid)
                                    .foregroundStyle(.secondary)
                                Text(phrase.fluentAlternative)
                                    .font(.body)
                                Text(phrase.reason)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                if !summary.suggestedDrills.isEmpty {
                    Section("Drill next") {
                        ForEach(summary.suggestedDrills, id: \.self) { drill in
                            Text(drill)
                        }
                    }
                }
            }
            .navigationTitle("Session summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Identifiable conformance for sheet(item:)

extension SessionSummary: Identifiable {
    public var id: String { overallNote }
}
