import AVKit
import Photos
import SwiftUI

/// One scored take: the overall score, the coach's notes, the recording, and
/// every measured number with what it was measured against.
struct SpeechResultView: View {
    let takeId: UUID
    /// The take as the prompter just made it — shown while the store catches
    /// up, and updated when the coach's notes land.
    var live: SpeechTake?

    @ObservedObject private var store = SpeechStore.shared
    @StateObject private var audio = AudioPlayer()
    @State private var player: AVPlayer?
    @State private var savedToPhotos = false
    @State private var photoError: String?
    @State private var confirmDeleteVideo = false

    private var take: SpeechTake? {
        let stored = store.takes.first { $0.id == takeId }
        if let live, stored?.coaching == nil, live.coaching != nil { return live }
        return stored ?? live
    }

    var body: some View {
        if let take, let script = store.script(id: take.scriptId) {
            content(take, script)
        } else {
            ContentUnavailableView("Take not found", systemImage: "waveform")
        }
    }

    private func content(_ take: SpeechTake, _ script: SpeechScript) -> some View {
        let m = take.metrics
        return List {
            Section {
                HStack(spacing: 18) {
                    Gauge(value: Double(m.overall), in: 0...100) {
                        EmptyView()
                    } currentValueLabel: {
                        Text("\(m.overall)").font(.title2.monospacedDigit().weight(.bold))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(SpeechScoreColor.color(m.overall))
                    .scaleEffect(1.3)
                    .frame(width: 80, height: 80)

                    VStack(alignment: .leading, spacing: 6) {
                        if let coaching = take.coaching {
                            Text(coaching.headline)
                                .font(.body.weight(.medium))
                        } else {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Writing feedback…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)

                if let tips = take.coaching?.tips, !tips.isEmpty {
                    ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                        Label(tip, systemImage: "arrow.forward.circle")
                            .font(.subheadline)
                    }
                }
            } header: {
                Text(script.title)
            }

            playbackSection(take)

            Section("Measured") {
                metricRow("Accuracy", icon: "text.badge.checkmark",
                          value: "\(m.accuracy)%", score: m.accuracy)
                metricRow("Pace", icon: "speedometer",
                          value: SpeechFormat.rate(m.rate, language: script.language),
                          detail: explain("Comfortable: \(m.rateLow)–\(m.rateHigh)"),
                          // Outside the band is never shown as good, however
                          // close: the band IS the target.
                          score: (m.rateLow...m.rateHigh).contains(m.rate) ? 100 : min(m.paceScore, 80))
                metricRow("Pauses", icon: "pause.circle",
                          value: explain("\(m.pausesAtBreaks) of \(m.breaks)"),
                          detail: m.hesitations > 0
                              ? explain("Breaths at sentence ends · long stops: \(m.hesitations)")
                              : explain("Breaths at sentence ends"),
                          score: m.pauseScore)
                metricRow("Fillers", icon: "ellipsis.bubble",
                          value: "\(m.fillers)", score: m.fillerScore)
                metricRow("Steady voice", icon: "waveform.path",
                          value: "\(m.steadiness)",
                          detail: explain("Holding your volume to the end of each sentence"),
                          score: m.steadiness)
            }

            if !m.missed.isEmpty {
                Section {
                    Text(m.missed.joined(separator: "  ·  "))
                        .font(.body)
                        .foregroundStyle(.red)
                } header: {
                    Text("Skipped or changed")
                }
            }

            Section {
                DisclosureGroup("What the mic heard") {
                    Text(take.transcript)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(Text(take.createdAt, format: .dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            player?.pause()
            audio.stop()
        }
        .confirmationDialog("Delete the video? Your voice and score stay.",
                            isPresented: $confirmDeleteVideo, titleVisibility: .visible) {
            Button("Delete video", role: .destructive) {
                player?.pause()
                player = nil
                store.deleteVideo(takeId: take.id)
            }
        }
        .alert("Couldn't save to Photos", isPresented: Binding(
            get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoError ?? "")
        }
    }

    @ViewBuilder
    private func playbackSection(_ take: SpeechTake) -> some View {
        if let video = take.videoFilename {
            Section {
                VideoPlayer(player: player)
                    // A screen take is phone-shaped, a camera take 3:4; the
                    // player letterboxes either inside a fixed height.
                    .frame(height: 480)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .onAppear {
                        if player == nil {
                            preparePlayback()
                            player = AVPlayer(url: SpeechStore.mediaURL(video))
                        }
                    }
                Button {
                    saveToPhotos(SpeechStore.mediaURL(video))
                } label: {
                    Label(savedToPhotos ? "Saved to Photos" : "Save to Photos",
                          systemImage: savedToPhotos ? "checkmark" : "square.and.arrow.down")
                }
                .disabled(savedToPhotos)
                Button(role: .destructive) {
                    confirmDeleteVideo = true
                } label: {
                    Label("Delete video", systemImage: "trash")
                }
            } footer: {
                Text("Videos stay on this phone and aren't backed up. Save the ones you want to keep.")
            }
        } else {
            Section {
                Button {
                    if audio.isPlaying { audio.stop() } else { playAudio(take) }
                } label: {
                    Label(audio.isPlaying ? "Stop" : "Play your take",
                          systemImage: audio.isPlaying ? "stop.fill" : "play.fill")
                }
            }
        }
    }

    private func metricRow(_ title: LocalizedStringKey, icon: String, value: String,
                           detail: String? = nil, score: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: icon)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(SpeechScoreColor.color(score))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func preparePlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: AudioSessionRouting.playbackOptions)
        try? session.setActive(true)
    }

    private func playAudio(_ take: SpeechTake) {
        guard let data = try? Data(contentsOf: SpeechStore.mediaURL(take.audioFilename)) else { return }
        try? audio.play(data, source: "speech_take")
    }

    private func saveToPhotos(_ url: URL) {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                photoError = explain("Photos access is off. Turn it on in Settings to save videos.")
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
                savedToPhotos = true
            } catch {
                photoError = error.localizedDescription
            }
        }
    }
}
