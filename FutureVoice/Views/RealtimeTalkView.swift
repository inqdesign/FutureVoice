import SwiftUI

/// DEBUG-only call screen for the realtime gateway (`gateway/`).
///
/// Deliberately plain: this exists to answer "does it feel like a phone call
/// yet", so what it shows is the transcript, the state, and the number —
/// speech-end → voice, per turn, on screen while testing. It is NOT the
/// shipping Talk UI, and none of `ConversationView`'s surrounding machinery
/// (books, drills, metering, day cards) runs here.
struct RealtimeTalkView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var call = RealtimeTalkClient()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                Divider().opacity(0.15)
                footer
            }
            .navigationTitle("Realtime (beta)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { call.hangUp(); dismiss() }
                }
            }
            .task { await start() }
            .onDisappear { call.hangUp() }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(call.lines) { line in
                        DialogueLine(speaker: line.isUser ? .user : .other,
                                     name: line.isUser ? "You" : "Future self",
                                     scale: .call) {
                            Text(line.text)
                        } accessory: {
                            EmptyView()
                        }
                        .id(line.id)
                    }
                    if !call.partial.isEmpty {
                        DialogueLine(speaker: .user, name: "You", scale: .call) {
                            Text(call.partial).foregroundStyle(.secondary)
                        } accessory: {
                            EmptyView()
                        }
                        .id("partial")
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .onChange(of: call.lines.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: call.partial) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            ZStack {
                Futureself(mode: glowMode, level: call.level)
            }
            .frame(width: 156, height: 64)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))

            // A failure has to say WHAT failed and offer the way back in.
            // The first device test died on a bare "Connecting…" with the
            // reason only in a log nobody was reading.
            if case .failed(let message) = call.state {
                VStack(spacing: 8) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Try again") { Task { await start() } }
                        .buttonStyle(.bordered)
                }
            } else {
                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            // The measurement this whole path is for, on screen while testing.
            if let ms = call.lastLatencyMs {
                Text("speech → voice: \(ms) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ms < 2000 ? .green : .secondary)
            }
            // Mic diagnostics: a live bar plus the bytes that actually left
            // the phone. "It doesn't hear me" is two different bugs, and
            // these two numbers say which one it is without a cable.
            HStack(spacing: 8) {
                ProgressView(value: Double(call.level))
                    .progressViewStyle(.linear)
                    .frame(width: 90)
                Text("mic \(call.micBytesSent / 1024) KB")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(call.micBytesSent > 0 ? Color.secondary : Color.red)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }

    private var glowMode: Futureself.Mode {
        switch call.state {
        case .speaking:  return .speaking
        case .hearing:   return .listening
        case .listening: return .listening
        case .connecting: return .thinking
        default:         return .idle
        }
    }

    private var statusLine: String {
        switch call.state {
        case .idle:        return "Not connected"
        case .connecting:  return "Connecting…"
        case .listening:   return "Listening — just talk"
        case .hearing:     return "Hearing you"
        case .speaking:    return "Speaking — talk over it to interrupt"
        case .failed(let m): return m
        }
    }

    private func start() async {
        // `.failed` must be re-enterable — that is what the Try again button
        // is; only an in-progress call is left alone.
        switch call.state {
        case .idle, .failed: break
        default: return
        }
        // The learner's own clone when there is one; otherwise a preset, so
        // the path is testable before a clone exists — and the preset is also
        // the retry when the gateway refuses the clone (see `connect`).
        let preset = "NDTYOmYEjbDIVCKB35i3"
        await call.connect(
            voiceId: appState.voiceCloneId ?? preset,
            language: appState.targetLanguage,
            system: ConversationEngine.conversationSystemPrompt(
                targetLanguage: appState.targetLanguage,
                nativeLanguage: appState.nativeLanguage,
                level: appState.proficiency,
                topPatterns: appState.learnerProfile.recurringMistakes,
                weakVocabAreas: appState.learnerProfile.weakVocabAreas,
                topic: "",
                persona: appState.persona,
                counterpart: nil,
                newsFacts: [],
                firstMeeting: false)
            // The gateway speaks prose, not the {reply, suggestion} JSON of
            // the HTTP turn — no `turnOutputInstruction` here on purpose.
            + "\n\nSpeak in one to three short sentences. This is a live phone "
            + "call: never write JSON, never add labels, just say your line.",
            fallbackVoiceId: preset
        )
    }
}
