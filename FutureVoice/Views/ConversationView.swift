import SwiftUI

/// Voice-first conversation screen, redesigned around a scrolling transcript
/// feed. The mic is small and lives at the bottom; the dominant content is
/// what the user and the fluent self just said — including a live partial
/// transcript while the user speaks, and a gentle inline correction chip
/// underneath each user turn when the LLM finds a more natural alternative.
struct ConversationView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var live = LiveTranscriber()
    @StateObject private var player = AudioPlayer()

    @State private var topic = "Ordering coffee"
    @State private var turns: [Turn] = []
    @State private var phase: Phase = .idle
    @State private var error: String?
    @State private var summary: SessionSummary?
    @State private var showTranscript = false
    @State private var showTopicPicker = false
    @State private var showHistory = false
    @State private var showDrills = false
    @State private var dueDrillCount = 0
    @State private var sessionId = UUID()
    @State private var sessionStartedAt = Date()
    @State private var didSaveCurrentSession = false

    private let userId = UUID()

    enum Phase: Equatable {
        case idle
        case listening      // mic open, partial STT streaming
        case thinking       // Gemini reply in flight
        case speaking       // ElevenLabs TTS playing
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                feed
                Divider().opacity(0.15)
                bottomBar
            }
            .background(Color(.systemBackground))
            .navigationTitle(topic)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showTopicPicker) {
                TopicPickerSheet(topic: $topic)
            }
            .sheet(isPresented: $showTranscript) {
                TranscriptSheet(turns: turns)
            }
            .sheet(isPresented: $showHistory) {
                HistorySheet()
            }
            .sheet(isPresented: $showDrills, onDismiss: refreshDueDrillCount) {
                DrillSheet()
            }
            .sheet(item: summaryBinding) { s in
                SummarySheet(summary: s, onStartNew: startNewSession)
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .task {
                refreshDueDrillCount()
                if turns.isEmpty { await openConversation() }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showTopicPicker = true } label: {
                Label("Topic", systemImage: "list.bullet")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showDrills = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "lightbulb.max")
                    if dueDrillCount > 0 {
                        Text("\(dueDrillCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(x: 8, y: -6)
                    }
                }
            }
            .accessibilityLabel(Text(dueDrillCount > 0 ? "Drills: \(dueDrillCount) due" : "Drills"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showHistory = true } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
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

    // MARK: - Feed

    private var feed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(turns) { turn in
                        TurnView(turn: turn).id(turn.id)
                    }
                    if phase == .listening {
                        PartialTurnView(text: live.transcript)
                            .id(Self.partialId)
                    } else if phase == .thinking && (turns.last?.role == .user) {
                        ThinkingIndicator()
                            .id(Self.partialId)
                    }
                    // Bottom spacer so the last line isn't hidden behind controls
                    Color.clear.frame(height: 8).id(Self.bottomId)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
            .onChange(of: turns.count) { _, _ in scroll(proxy) }
            .onChange(of: phase)       { _, _ in scroll(proxy) }
            .onChange(of: live.transcript) { _, _ in scroll(proxy) }
        }
    }

    private static let partialId = "partial-indicator"
    private static let bottomId  = "feed-bottom"

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(Self.bottomId, anchor: .bottom)
        }
    }

    // MARK: - Bottom bar (mic + level)

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if phase == .listening {
                LevelMeter(level: live.level)
                    .frame(height: 18)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
            }

            Button { Task { await handleMicTap() } } label: {
                ZStack {
                    Circle()
                        .fill(.tint)
                        .frame(width: 64, height: 64)
                        .opacity(micEnabled ? 1.0 : 0.4)
                        .scaleEffect(phase == .listening ? 1.06 : 1.0)
                        .animation(
                            phase == .listening
                                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                : .default,
                            value: phase
                        )
                    Image(systemName: micSymbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                }
            }
            .buttonStyle(.plain)
            .tint(micTint)
            .disabled(!micEnabled)
            .accessibilityLabel(Text(micA11yLabel))

            Text(micHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(height: 16)
                .animation(nil, value: phase)
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var micEnabled: Bool { phase == .idle || phase == .listening }
    private var micSymbol: String {
        switch phase {
        case .listening: return "checkmark"
        case .thinking:  return "ellipsis"
        case .speaking:  return "waveform"
        case .idle:      return "mic.fill"
        }
    }
    private var micTint: Color { phase == .listening ? .red : .accentColor }
    private var micA11yLabel: String {
        switch phase {
        case .idle:      return "Start speaking"
        case .listening: return "Send what you said"
        case .thinking:  return "Thinking"
        case .speaking:  return "Future self speaking"
        }
    }
    private var micHint: String {
        switch phase {
        case .idle:      return turns.isEmpty ? " " : "Tap to speak"
        case .listening: return "Tap to send"
        case .thinking:  return "Thinking…"
        case .speaking:  return "Listen…"
        }
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
            let opener = try await GeminiClient.shared.send(
                system: systemPrompt(),
                messages: [GeminiClient.Message(
                    role: .user,
                    content: "Open the conversation with a friendly first line, in \(appState.targetLanguage). One short sentence."
                )]
            )
            try await speakAndAppend(opener, voiceId: voiceId)
            phase = .idle
        } catch {
            self.error = error.localizedDescription
            phase = .idle
        }
    }

    private func startRecording() async {
        let granted = await LiveTranscriber.requestPermissions()
        guard granted else {
            error = "Microphone or speech permission denied."
            return
        }
        do {
            try live.start(locale: appState.targetLanguage)
            phase = .listening
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stopAndSend() async {
        let finalText = live.stop()
        phase = .thinking

        let userTurn = Turn(
            id: UUID(), role: .user, audioURL: nil,
            transcript: finalText, durationMs: 0, timestamp: Date(),
            suggestion: nil
        )
        turns.append(userTurn)
        didSaveCurrentSession = false

        guard let voiceId = appState.voiceCloneId else { phase = .idle; return }
        do {
            let reply = try await GeminiClient.shared.send(
                system: systemPrompt(),
                messages: ConversationEngine.geminiMessages(from: turns)
            )
            try await speakAndAppend(reply, voiceId: voiceId)
            phase = .idle

            // Fire-and-forget: check whether the user turn has a more natural rephrase.
            Task { await annotateUserTurn(id: userTurn.id) }
        } catch {
            self.error = error.localizedDescription
            phase = .idle
        }
    }

    private func speakAndAppend(_ text: String, voiceId: String) async throws {
        let audio = try await ElevenLabsClient.shared.synthesize(voiceId: voiceId, text: text)
        turns.append(Turn(
            id: UUID(), role: .fluentSelf, audioURL: nil,
            transcript: text, durationMs: 0, timestamp: Date(),
            suggestion: nil
        ))
        didSaveCurrentSession = false
        phase = .speaking
        try player.play(audio) {
            Task { @MainActor in
                if phase == .speaking { phase = .idle }
            }
        }
    }

    private func annotateUserTurn(id: UUID) async {
        guard let turn = turns.first(where: { $0.id == id }),
              !turn.transcript.isEmpty else { return }
        struct CorrectionPayload: Decodable {
            let has_issue: Bool
            let alternative: String?
            let reason: String?
        }
        let system = """
        You are a strict but warm language coach for \(appState.targetLanguage).
        Decide if the learner's sentence has a clear grammar, idiom, or naturalness issue.
        Reply with STRICT JSON only — no prose, no code fences:
        { "has_issue": true|false, "alternative": "...", "reason": "..." }
        - has_issue: false → omit "alternative" and "reason".
        - Otherwise keep "alternative" to a single natural rephrase, and "reason" under 12 words.
        - Be conservative — minor stylistic differences are NOT issues.
        """
        let payload: CorrectionPayload? = try? await GeminiClient.shared.sendJSON(
            system: system,
            messages: [GeminiClient.Message(role: .user, content: turn.transcript)],
            maxTokens: 200
        )
        guard let payload, payload.has_issue,
              let alt = payload.alternative, !alt.isEmpty,
              let reason = payload.reason, !reason.isEmpty else { return }

        if let idx = turns.firstIndex(where: { $0.id == id }) {
            turns[idx].suggestion = TurnSuggestion(alternative: alt, reason: reason)
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
            let payload: ClaudeSummaryPayload = try await GeminiClient.shared.sendJSON(
                system: systemP,
                messages: [GeminiClient.Message(role: .user, content: transcript)],
                maxTokens: 1024
            )
            let computed = payload.toDomain()
            summary = computed
            phase = .idle

            let session = Session(
                id: sessionId,
                userId: userId,
                targetLanguage: appState.targetLanguage,
                mode: .conversation,
                topic: topic,
                startedAt: sessionStartedAt,
                endedAt: Date(),
                turns: turns,
                summary: computed
            )
            SessionStore.shared.save(session)
            DrillStore.shared.ingest(summary: computed, turns: turns, sessionId: sessionId)
            didSaveCurrentSession = true
            refreshDueDrillCount()
        } catch {
            self.error = error.localizedDescription
            phase = .idle
        }
    }

    private func refreshDueDrillCount() {
        dueDrillCount = DrillStore.shared.dueCount()
    }

    private func startNewSession() {
        summary = nil
        sessionId = UUID()
        sessionStartedAt = Date()
        turns = []
        didSaveCurrentSession = false
        phase = .idle
        Task { await openConversation() }
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

private struct TurnView: View {
    let turn: Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(turn.role == .user ? "You" : "Future self")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(turn.transcript)
                .font(.title3)
                .foregroundStyle(turn.role == .user ? .primary : Color.accentColor)
            if turn.role == .user, let suggestion = turn.suggestion {
                SuggestionChip(suggestion: suggestion)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SuggestionChip: View {
    let suggestion: TurnSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
                .font(.footnote)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.alternative)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct PartialTurnView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? "Listening…" : text)
                .font(.title3)
                .foregroundStyle(.secondary)
                .italic(text.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThinkingIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7)
            Text("Future self is thinking…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            let barCount = 24
            let spacing: CGFloat = 4
            let barWidth = (geo.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let position = Float(i) / Float(barCount - 1)
                    let center: Float = 0.5
                    let distance = abs(position - center) * 2          // 0 at center, 1 at edges
                    let envelope = max(0.15, 1 - distance * distance)  // bell-ish
                    let height = CGFloat(max(0.08, level * envelope)) * geo.size.height
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: barWidth, height: height)
                        .opacity(0.5 + Double(level) * 0.5)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.08), value: level)
        }
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
                    if let s = turn.suggestion {
                        Text("→ \(s.alternative)")
                            .font(.footnote)
                            .foregroundStyle(.tint)
                    }
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
    let onStartNew: () -> Void
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
            .safeAreaInset(edge: .bottom) {
                Button {
                    onStartNew()
                } label: {
                    Label("Start a new conversation", systemImage: "arrow.uturn.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
    }
}

// MARK: - Identifiable conformance for sheet(item:)

extension SessionSummary: Identifiable {
    public var id: String { overallNote }
}
