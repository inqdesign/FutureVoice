import SwiftUI

/// First-run screen — and re-run from the Profile menu. The user reads a
/// short script aloud so ElevenLabs can clone their voice. iOS-native layout
/// only: nav title, Form sections, single primary action with a live meter.
struct VoiceCloneOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var preview = AudioPlayer()

    @State private var status: Status = .idle
    @State private var error: String?
    @State private var startedAt: Date?
    @State private var elapsedSeconds: Double = 0
    @State private var ticker: Timer?
    /// Recording captured this session, awaiting the user's review (listen +
    /// quality check) before we commit to cloning.
    @State private var recordedSampleURL: URL?
    @State private var quality: AudioSampleQuality?

    /// ElevenLabs IVC quality climbs steeply up to ~60-90 seconds of speech.
    /// We keep the whole flow on that 60–90 range the footer promises: the
    /// countdown targets 60s (usable), 75s is the sweet spot, 90s auto-stops.
    private static let minSeconds: Double = 60
    private static let recommendedSeconds: Double = 75
    /// Hard cap — auto-stop here. Well past the 75s sweet spot and far under
    /// ElevenLabs' 11 MB upload limit (~130s at 16-bit/44.1k mono).
    private static let maxSeconds: Double = 90

    enum Status: Equatable {
        case idle
        case recording
        case reviewing   // recorded; user can listen + see quality before cloning
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

    And honestly, here's why I'm doing this. I want to look back in a year and \
    hear how far I've come. Small steps — one call today, one tomorrow, one the \
    day after. Some days it'll feel slow. Some days it'll just click. Either \
    way, I keep showing up. That's the whole trick, isn't it? Keep talking, \
    keep going, and let it all add up.

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
                    Text("Why we need a minute of your voice")
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Use your iPhone's built-in mic — a closet is ideal")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Take your AirPods (or any Bluetooth earbuds) OUT first. Their mics record at low 8 kHz \u{201C}phone-call\u{201D} quality, so the clone ends up sounding nothing like you. For the cleanest result, step inside a clothes closet and record there — the clothes soak up echo like a real vocal booth. You only do this once, so make it count.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "iphone")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Before you start")
                }

                Section {
                    Text(cloneScript)
                        .font(.body)
                        .padding(.vertical, 4)
                } header: {
                    Text("Read this aloud, naturally")
                } footer: {
                    Text("Aim for 60–90 seconds somewhere quiet — a clothes closet is best. Vary your pitch a little — flat reading makes a flat clone.")
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

                if status == .reviewing {
                    reviewSection
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

    // MARK: - Review (listen + quality)

    @ViewBuilder
    private var reviewSection: some View {
        Section {
            Button {
                togglePreview()
            } label: {
                Label(preview.isPlaying ? "Stop" : "Listen to your recording",
                      systemImage: preview.isPlaying ? "stop.circle.fill" : "play.circle.fill")
            }
        } header: {
            Text("Review")
        } footer: {
            Text("Hear how you sound before cloning. We boost the level on upload, so a quiet take is fine — clarity matters more than loudness.")
        }

        if let q = quality {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: q.rating.symbol)
                        .foregroundStyle(ratingTint(q.rating))
                    Text(q.rating.label)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("\(Int(q.durationSeconds))s")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ForEach(q.issues, id: \.self) { issue in
                    Label(issue, systemImage: "circle.fill")
                        .labelStyle(BulletLabelStyle())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Quality")
            }
        }
    }

    private func ratingTint(_ r: AudioSampleQuality.Rating) -> Color {
        switch r {
        case .good: return .green
        case .okay: return .orange
        case .poor: return .red
        }
    }

    private func togglePreview() {
        if preview.isPlaying {
            preview.stop()
            return
        }
        guard let url = recordedSampleURL, let data = try? Data(contentsOf: url) else { return }
        try? preview.play(data)
    }

    // MARK: - Action bar

    @ViewBuilder
    private var actionBar: some View {
        if status == .reviewing {
            HStack(spacing: 12) {
                Button {
                    reRecord()
                } label: {
                    Label("Re-record", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button {
                    useThisVoice()
                } label: {
                    Label("Use this voice", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        } else {
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
        case .reviewing: return "waveform"
        case .uploading: return "arrow.up.circle"
        case .done:      return "checkmark.circle.fill"
        }
    }

    private var label: String {
        switch status {
        case .idle:      return "Start recording"
        case .recording: return elapsedSeconds >= Self.minSeconds ? "Stop & review" : "Stop (early)"
        case .reviewing: return "Review"
        case .uploading: return "Cloning your voice…"
        case .done:      return "Done"
        }
    }

    private var tint: Color {
        switch status {
        case .recording: return elapsedSeconds >= Self.recommendedSeconds ? .green : .red
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
                    stopAndReview()

                case .reviewing, .uploading, .done:
                    break
                }
            } catch {
                self.error = error.localizedDescription
                status = .idle
                stopTicker()
            }
        }
    }

    /// Confirm the reviewed recording: persist the raw sample for later
    /// re-generation, then normalize + upload to ElevenLabs.
    private func useThisVoice() {
        guard let url = recordedSampleURL else { return }
        preview.stop()
        status = .uploading
        // Keep the original so the clone can be regenerated later without
        // recording again (Settings → Voice).
        VoiceSampleStore.shared.save(from: url)
        Task {
            do {
                try await appState.regenerateVoiceClone(fromSampleAt: url)
                status = .done   // RootView swaps away once voiceCloneId is set
            } catch {
                self.error = error.localizedDescription
                status = .reviewing
            }
        }
    }

    private func reRecord() {
        preview.stop()
        recordedSampleURL = nil
        quality = nil
        elapsedSeconds = 0
        error = nil
        status = .idle
    }

    /// Stop recording and move to the review step. Shared by the manual
    /// Stop tap and the automatic stop at `maxSeconds`.
    private func stopAndReview() {
        stopTicker()
        guard let rawURL = recorder.stop() else { status = .idle; return }
        // Don't clone yet — let the user listen and see the quality check
        // first, then confirm with "Use this voice".
        recordedSampleURL = rawURL
        quality = AudioSampleQuality.analyze(url: rawURL)
        status = .reviewing
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                guard let started = startedAt else { return }
                elapsedSeconds = Date().timeIntervalSince(started)
                if status == .recording, elapsedSeconds >= Self.maxSeconds {
                    HapticEngine.success()   // cue that recording auto-stopped at the cap
                    stopAndReview()
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

/// Indented bullet for the per-issue list in the quality section.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 4))
            configuration.title
        }
    }
}
