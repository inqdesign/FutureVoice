@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// The front camera for a speech take. VIDEO ONLY, on purpose: the voice is
/// captured by the app's own mic path (`LiveTranscriber` + `AudioRecorder`,
/// voice processing, the worn mic wins), and an `AVCaptureSession` holding an
/// audio input would reconfigure the shared audio session under it.
///
/// Frames go to `frameHandler` (on the camera's queue), where
/// `SpeechVideoComposer` draws the prompter over each one — the saved video
/// is the take screen, made by the app rather than recorded off the screen,
/// so iOS never asks to record the screen and no button is in the picture.
@MainActor
final class SpeechCamera: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var isRunning = false
    @Published private(set) var denied = false

    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.roro.futurevoice.speech-camera")
    private var configured = false
    private let handlerBox = FrameHandlerBox()

    /// Called for every frame, on the camera's queue. Frames are portrait
    /// and mirrored like the preview, stamped on the host clock.
    nonisolated var frameHandler: (@Sendable (CMSampleBuffer) -> Void)? {
        get { handlerBox.get() }
        set { handlerBox.set(newValue) }
    }

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
        session.sessionPreset = .hd1280x720
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
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
}

extension SpeechCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        frameHandler?(sampleBuffer)
    }
}

private final class FrameHandlerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (CMSampleBuffer) -> Void)?
    func get() -> (@Sendable (CMSampleBuffer) -> Void)? { lock.withLock { handler } }
    func set(_ h: (@Sendable (CMSampleBuffer) -> Void)?) { lock.withLock { handler = h } }
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
    /// - Parameter videoLeadIn: seconds the picture started BEFORE the voice
    ///   (the screen capture begins before the countdown) — cut from the
    ///   picture. Negative = the voice started first — cut from the voice.
    ///   Either way they start together.
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
        let vLead = CMTime(seconds: max(0, videoLeadIn), preferredTimescale: 600)
        let aLead = CMTime(seconds: max(0, -videoLeadIn), preferredTimescale: 600)
        let duration = CMTimeMinimum(CMTimeSubtract(vDuration, vLead), CMTimeSubtract(aDuration, aLead))
        guard duration.seconds > 0.5 else { return false }
        do {
            try cv.insertTimeRange(CMTimeRange(start: vLead, duration: duration), of: vTrack, at: .zero)
            try ca.insertTimeRange(CMTimeRange(start: aLead, duration: duration), of: aTrack, at: .zero)
        } catch { return false }
        cv.preferredTransform = transform
        // Passthrough first: the picture is already encoded, so it is copied,
        // not re-encoded — near-instant where a re-encode of a three-minute
        // take took tens of seconds. Re-encode only if passthrough refuses.
        for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality] {
            guard let export = AVAssetExportSession(asset: composition, presetName: preset) else { continue }
            try? FileManager.default.removeItem(at: output)
            export.outputURL = output
            export.outputFileType = .mov
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                export.exportAsynchronously { cont.resume() }
            }
            if export.status == .completed { return true }
        }
        return false
    }
}

