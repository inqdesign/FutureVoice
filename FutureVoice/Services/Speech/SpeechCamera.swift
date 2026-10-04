@preconcurrency import AVFoundation
import ReplayKit
import SwiftUI
import UIKit

/// The front camera for a speech take. VIDEO ONLY, on purpose: the voice is
/// captured by the app's own mic path (`LiveTranscriber` + `AudioRecorder`,
/// voice processing, the worn mic wins), and an `AVCaptureSession` holding an
/// audio input would reconfigure the shared audio session under it. The two
/// are muxed into one movie after the take (`SpeechMediaMerger`).
@MainActor
final class SpeechCamera: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var isRunning = false
    @Published private(set) var denied = false

    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "com.roro.futurevoice.speech-camera")
    private var configured = false
    private var finished: CheckedContinuation<URL?, Never>?

    func start() async {
        guard !isRunning else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var granted = status == .authorized
        if status == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted else { denied = true; return }
        denied = false
        if !configured { configured = configure() }
        guard configured else { return }
        let session = session
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { session.startRunning(); cont.resume() }
        }
        isRunning = session.isRunning
    }

    func stop() {
        let session = session
        queue.async { session.stopRunning() }
        isRunning = false
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // The mic is ours; never let the capture session touch the audio
        // session the recognizer is running on.
        session.automaticallyConfiguresApplicationAudioSession = false
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        return true
    }

    func startRecording() -> URL? {
        guard isRunning, !output.isRecording else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("speech-\(UUID().uuidString).mov")
        output.startRecording(to: url, recordingDelegate: self)
        return url
    }

    /// Ends the movie and returns it once it is closed on disk.
    func stopRecording() async -> URL? {
        guard output.isRecording else { return nil }
        return await withCheckedContinuation { cont in
            finished = cont
            output.stopRecording()
        }
    }
}

extension SpeechCamera: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection], error: Error?) {
        // A movie stopped by us reports an error with "successfully finished"
        // set; only a file that genuinely failed is dropped.
        let ok = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        Task { @MainActor in
            self.finished?.resume(returning: ok ? outputFileURL : nil)
            self.finished = nil
        }
    }
}

/// The live preview. The one UIKit wrap on this screen — SwiftUI has no
/// capture preview.
struct SpeechCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Puts the take's voice under its picture. The movie and the WAV started
/// within a few milliseconds of each other; that offset is below what an eye
/// reads as out of sync, so they are laid on at zero.
enum SpeechMediaMerger {
    /// - Parameter videoLeadIn: seconds of the video before the voice
    ///   started (the screen recording begins before the countdown); cut off
    ///   so picture and voice start together.
    static func merge(video: URL, audio: URL, to output: URL, videoLeadIn: Double = 0) async -> Bool {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        guard let vTrack = try? await videoAsset.loadTracks(withMediaType: .video).first,
              let aTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first,
              let vDuration = try? await videoAsset.load(.duration),
              let aDuration = try? await audioAsset.load(.duration),
              let transform = try? await vTrack.load(.preferredTransform),
              let cv = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let ca = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return false }
        let lead = CMTime(seconds: max(0, videoLeadIn), preferredTimescale: 600)
        let duration = CMTimeMinimum(CMTimeSubtract(vDuration, lead), aDuration)
        guard duration.seconds > 0.5 else { return false }
        do {
            try cv.insertTimeRange(CMTimeRange(start: lead, duration: duration), of: vTrack, at: .zero)
            try ca.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: aTrack, at: .zero)
        } catch { return false }
        cv.preferredTransform = transform
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { return false }
        try? FileManager.default.removeItem(at: output)
        export.outputURL = output
        export.outputFileType = .mov
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        return export.status == .completed
    }
}

/// The whole take screen as one video — prompter on top, camera below,
/// exactly what the reader saw — through ReplayKit's in-app recording.
/// The screen recorder's own mic stays OFF: the voice is the app's capture
/// (voice processing, the worn mic), muxed in afterwards like the camera.
/// iOS asks the learner once before it records ("Allow screen recording?")
/// and again after a few minutes; a refusal falls back to the camera take.
@MainActor
enum SpeechScreenRecorder {
    static var isRecording: Bool { RPScreenRecorder.shared().isRecording }

    /// Starts recording. Returns when it actually started, or nil.
    static func start() async -> Date? {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable, !recorder.isRecording else { return nil }
        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false
        do {
            try await recorder.startRecording()
            return Date()
        } catch {
            return nil
        }
    }

    /// Stops and writes the movie; nil if nothing was recorded.
    static func stop() async -> URL? {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isRecording else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("speech-screen-\(UUID().uuidString).mp4")
        do {
            try await recorder.stopRecording(withOutput: url)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        } catch {
            return nil
        }
    }

    static func discard() {
        Task { if let url = await stop() { try? FileManager.default.removeItem(at: url) } }
    }
}
