import SwiftUI

/// Phase 1 conversation playground.
///
/// Loop:
///   1. Fluent self opens with a Claude-generated prompt → ElevenLabs TTS → play.
///   2. User taps "Hold to speak" → records → on-device STT → display transcript.
///   3. Loop back to Claude with the running history.
///   4. "End session" triggers the summary call and shows phrase feedback.
struct ConversationView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var player = AudioPlayer()

    @State private var topic = "Ordering coffee"
    @State private var turns: [Turn] = []
    @State private var isThinking = false
    @State private var error: String?
    @State private var summary: SessionSummary?

    private let userId = UUID()  // Phase 2: real user id from Supabase

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(turns) { turn in
                            TurnBubble(turn: turn)
                                .id(turn.id)
                        }
                        if isThinking {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Future self is thinking…").foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: turns.count) { _, _ in
                    if let last = turns.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            if let summary = summary {
                SummaryCard(summary: summary)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            controlBar
        }
        .task {
            if turns.isEmpty { await openConversation() }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Topic")
                    .font(.caption).foregroundStyle(.secondary)
                Text(topic).font(.headline)
            }
            Spacer()
            Button("End") { Task { await endSession() } }
                .disabled(turns.isEmpty || isThinking)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 16) {
            Button(action: { Task { recorder.isRecording ? await stopAndSend() : await startRecording() } }) {
                HStack(spacing: 10) {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    Text(recorder.isRecording ? "Send" : "Hold to speak")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(recorder.isRecording ? Color.red : Color.blue))
                .foregroundStyle(.white)
            }
            .disabled(isThinking || player.isPlaying)
        }
        .padding(20)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    // MARK: - Flow

    private func openConversation() async {
        guard let voiceId = appState.voiceCloneId else { return }
        isThinking = true
        defer { isThinking = false }
        do {
            let opener = try await ClaudeClient.shared.send(
                system: systemPrompt(),
                messages: [.init(role: .user, content: "Open the conversation with a friendly first line, in \(appState.targetLanguage).")]
            )
            try await speakAndAppend(opener, voiceId: voiceId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startRecording() async {
        let granted = await recorder.requestPermission() && (await SpeechTranscriber.requestPermission())
        guard granted else {
            error = "Microphone or speech permission denied."
            return
        }
        do {
            try recorder.start()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stopAndSend() async {
        guard let url = recorder.stop() else { return }
        isThinking = true
        defer { isThinking = false }

        do {
            let transcript = try await SpeechTranscriber().transcribe(
                audioURL: url,
                languageCode: appState.targetLanguage
            )
            let userTurn = Turn(
                id: UUID(),
                role: .user,
                audioURL: url,
                transcript: transcript,
                durationMs: 0,
                timestamp: Date()
            )
            turns.append(userTurn)

            guard let voiceId = appState.voiceCloneId else { return }
            let reply = try await ClaudeClient.shared.send(
                system: systemPrompt(),
                messages: ConversationEngine.messages(from: turns)
            )
            try await speakAndAppend(reply, voiceId: voiceId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func speakAndAppend(_ text: String, voiceId: String) async throws {
        let audio = try await ElevenLabsClient.shared.synthesize(voiceId: voiceId, text: text)
        let turn = Turn(id: UUID(), role: .fluentSelf, audioURL: nil, transcript: text, durationMs: 0, timestamp: Date())
        turns.append(turn)
        try player.play(audio)
    }

    private func endSession() async {
        guard !turns.isEmpty else { return }
        isThinking = true
        defer { isThinking = false }
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
            withAnimation { summary = payload.toDomain() }
        } catch {
            self.error = error.localizedDescription
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

// MARK: - Subviews

private struct TurnBubble: View {
    let turn: Turn

    var body: some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 40) }
            Text(turn.transcript)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18).fill(bubbleColor))
                .foregroundStyle(turn.role == .user ? Color.white : Color.primary)
            if turn.role != .user { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 16)
    }

    private var bubbleColor: Color {
        turn.role == .user ? Color.blue : Color(.secondarySystemBackground)
    }
}

private struct SummaryCard: View {
    let summary: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session note")
                .font(.headline)
            Text(summary.overallNote)
                .foregroundStyle(.secondary)

            if !summary.phrasesUsed.isEmpty {
                Divider()
                Text("More natural alternatives")
                    .font(.subheadline).bold()
                ForEach(summary.phrasesUsed) { phrase in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(phrase.userSaid)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        Text(phrase.fluentAlternative)
                            .foregroundStyle(.primary)
                        Text(phrase.reason)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if !summary.suggestedDrills.isEmpty {
                Divider()
                Text("Drill next")
                    .font(.subheadline).bold()
                ForEach(summary.suggestedDrills, id: \.self) { drill in
                    Text("• \(drill)")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}
