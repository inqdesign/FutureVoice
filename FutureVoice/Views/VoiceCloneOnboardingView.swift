import SwiftUI

/// First-run screen — and re-run from the Profile menu. The user reads a
/// short script aloud so ElevenLabs can clone their voice. iOS-native layout
/// only: nav title, Form sections, single primary action with a live meter.
struct VoiceCloneOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var recorder = AudioRecorder()

    @State private var status: Status = .idle
    @State private var error: String?
    @State private var startedAt: Date?
    @State private var elapsedSeconds: Double = 0
    @State private var ticker: Timer?

    /// ElevenLabs IVC quality climbs steeply up to ~60-90 seconds of speech.
    /// Under ~45s the clone sounds noticeably flatter, so that's our hard
    /// minimum; we still surface a "great clone unlocked" cue at 60s+.
    private static let minSeconds: Double = 45
    private static let recommendedSeconds: Double = 75

    enum Status: Equatable {
        case idle
        case recording
        case uploading
        case done
    }

    /// Phonetically varied so the clone has range — short and long vowels,
    /// hard consonants, rising and falling intonation. Read it like you mean
    /// it, not like a school recital.
    private let cloneScript = """
    Hi. I'm recording this so my fluent self can sound like me. I'm curious. I'm \
    patient. I want to sound like me — just a more confident version.

    Let me describe a moment from this week. The weather turned cooler than I \
    expected. I was walking and caught myself thinking in two languages at once — \
    one for what I saw, one for what I felt. Funny how that works.

    Now a few different shapes: "Could you actually repeat that?" "Wait — that's \
    not quite right." "Honestly, I'm not sure yet, but here's what I think." \
    "Oh, that's brilliant — say more."

    Okay. That should be enough. Talk to me soon.
    """

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Your fluent self will speak in this voice. Once you record, every reply you hear in the app sounds like you.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Why we need 30 seconds of your voice")
                }

                Section {
                    Text(cloneScript)
                        .font(.body)
                        .padding(.vertical, 4)
                } header: {
                    Text("Read this aloud, naturally")
                } footer: {
                    Text("Aim for 60–90 seconds in a quiet room. Vary your pitch a little — flat reading makes a flat clone.")
                }

                if status == .recording || elapsedSeconds > 0 {
                    Section {
                        HStack {
                            Text(elapsedText)
                                .font(.body.monospacedDigit())
                            Spacer()
                            Text(status == .recording ? "Recording" : "Stopped")
                                .font(.caption)
                                .foregroundStyle(status == .recording ? .red : .secondary)
                        }
                        levelMeter
                            .frame(height: 18)
                        if !recorder.inputDescription.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: micIcon)
                                    .foregroundStyle(isBadMic ? .orange : .secondary)
                                    .font(.caption)
                                Text(recorder.inputDescription)
                                    .font(.caption)
                                    .foregroundStyle(isBadMic ? .orange : .secondary)
                            }
                        }
                    } header: {
                        Text("Recording")
                    } footer: {
                        if isBadMic {
                            Text("Bluetooth headsets use low-quality 8 kHz mics. Disconnect AirPods and use the iPhone built-in mic for a faithful clone.")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if let error = error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Your voice")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .onDisappear { stopTicker() }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        VStack(spacing: 8) {
            Button(action: handleTap) {
                Label(label, systemImage: icon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(tint)
            .disabled(status == .uploading || (status == .recording && elapsedSeconds < 1))

            if status == .recording {
                if elapsedSeconds < Self.minSeconds {
                    Text("Keep going — \(Int(Self.minSeconds - elapsedSeconds))s more for a usable clone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if elapsedSeconds < Self.recommendedSeconds {
                    Text("Good. \(Int(Self.recommendedSeconds - elapsedSeconds))s more for the cleanest clone")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } else {
                    Text("Plenty for a great clone — stop whenever you're ready")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            } else if status == .uploading {
                ProgressView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var levelMeter: some View {
        GeometryReader { geo in
            let barCount = 20
            let spacing: CGFloat = 4
            let barWidth = (geo.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let position = Float(i) / Float(barCount - 1)
                    let envelope = max(0.15, 1 - abs(position - 0.5) * 2 * abs(position - 0.5) * 2)
                    let height = CGFloat(max(0.1, recorder.levels * envelope)) * geo.size.height
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: barWidth, height: height)
                        .opacity(status == .recording ? (0.4 + Double(recorder.levels) * 0.6) : 0.25)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.08), value: recorder.levels)
        }
    }

    private var icon: String {
        switch status {
        case .idle:      return "mic.fill"
        case .recording: return "stop.fill"
        case .uploading: return "arrow.up.circle"
        case .done:      return "checkmark.circle.fill"
        }
    }

    private var label: String {
        switch status {
        case .idle:      return "Start recording"
        case .recording: return elapsedSeconds >= Self.minSeconds ? "Stop & clone" : "Stop (early)"
        case .uploading: return "Cloning your voice…"
        case .done:      return "Done"
        }
    }

    private var tint: Color {
        switch status {
        case .recording: return .red
        case .done:      return .green
        default:         return .accentColor
        }
    }

    private var elapsedText: String {
        let s = Int(elapsedSeconds)
        return String(format: "%01d:%02d", s / 60, s % 60)
    }

    private var isBadMic: Bool {
        recorder.inputDescription.lowercased().contains("bluetooth")
    }

    private var micIcon: String {
        isBadMic ? "exclamationmark.triangle.fill" : "mic.fill"
    }

    // MARK: - Actions

    private func handleTap() {
        Task {
            do {
                switch status {
                case .idle:
                    let granted = await recorder.requestPermission()
                    guard granted else {
                        error = "Microphone access denied. Enable it in Settings."
                        return
                    }
                    error = nil
                    elapsedSeconds = 0
                    try recorder.start(quality: .voiceCloneHigh)
                    startedAt = Date()
                    startTicker()
                    status = .recording

                case .recording:
                    stopTicker()
                    guard let url = recorder.stop() else { return }
                    status = .uploading
                    let voiceId = try await ElevenLabsClient.shared.cloneVoice(
                        name: "Future Self — \(appState.targetLanguage.uppercased())",
                        sampleAudioURLs: [url]
                    )
                    appState.voiceCloneId = voiceId   // didSet persists to UserDefaults
                    // Best-effort cleanup of the previous clone (if this is a
                    // re-record). Fire and forget — user shouldn't wait on
                    // ElevenLabs housekeeping to see "Done".
                    Task { await appState.cleanupPreviousVoiceClone() }
                    status = .done

                case .uploading, .done:
                    break
                }
            } catch {
                self.error = error.localizedDescription
                status = .idle
                stopTicker()
            }
        }
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                guard let started = startedAt else { return }
                elapsedSeconds = Date().timeIntervalSince(started)
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
