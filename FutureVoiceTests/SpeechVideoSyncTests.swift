import AVFoundation
import XCTest
@testable import FutureVoice

/// The standard copy a Speech video sends to iCloud: built from a take shaped
/// like the camera's (1080×1920 picture + the 16 kHz mono voice, put together
/// by `SpeechMediaMerger`), it must keep both tracks, the length, and come out
/// at 720p and smaller.
final class SpeechVideoSyncTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("speech-sd-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testStandardCopyKeepsPictureAndVoiceAt720p() async throws {
        let seconds = 3.0
        let picture = dir.appendingPathComponent("picture.mov")
        let voice = dir.appendingPathComponent("voice.wav")
        let take = dir.appendingPathComponent("take.mov")
        let copy = dir.appendingPathComponent("take.sd.mov")
        try await writePicture(to: picture, seconds: seconds)
        try writeVoice(to: voice, seconds: seconds)
        let merged = await SpeechMediaMerger.merge(video: picture, audio: voice, to: take)
        XCTAssertTrue(merged)

        let ok = await SpeechVideoSync.encodeStandard(from: take, to: copy)
        XCTAssertTrue(ok)

        let asset = AVURLAsset(url: copy)
        let video = try await asset.loadTracks(withMediaType: .video).first
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        XCTAssertNotNil(video)
        XCTAssertNotNil(audio, "the voice survives the re-encode")
        let size = try await video!.load(.naturalSize)
        XCTAssertEqual(max(size.width, size.height), SpeechVideoSync.standardLongEdge)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, seconds, accuracy: 0.3)
        let source = try FileManager.default.attributesOfItem(atPath: take.path)[.size] as! Int
        let small = try FileManager.default.attributesOfItem(atPath: copy.path)[.size] as! Int
        XCTAssertLessThan(small, source)
    }

    func testOnlyTheCopiesAreCarried() {
        let id = UUID()
        XCTAssertTrue(SpeechVideoSync.isCopy(SpeechVideoSync.standardName(id)))
        XCTAssertTrue(SpeechVideoSync.isCopy(SpeechVideoSync.originalName(id)))
        XCTAssertFalse(SpeechVideoSync.isCopy("take-\(id.uuidString).mov"))
        XCTAssertTrue(SpeechVideoSync.isOriginalCopy(SpeechVideoSync.originalName(id)))
        XCTAssertFalse(SpeechVideoSync.isOriginalCopy(SpeechVideoSync.standardName(id)))
    }

    // MARK: - Fixtures

    /// Moving noise, so the encoder has real detail to spend bits on.
    private func writePicture(to url: URL, seconds: Double) async throws {
        let width = 1080, height = 1920, fps = 30
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var seed: UInt32 = 1
        for frame in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pb = buffer!
            CVPixelBufferLockBaseAddress(pb, [])
            let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt32.self)
            let count = CVPixelBufferGetBytesPerRow(pb) / 4 * height
            for i in stride(from: 0, to: count, by: 1) {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                base[i] = seed | 0xFF00_0000
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }

    /// The take's voice format: 16 kHz mono PCM WAV.
    private func writeVoice(to url: URL, seconds: Double) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatInt16, interleaved: true)
        let frames = AVAudioFrameCount(seconds * 16_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.int16ChannelData![0]
        for i in 0..<Int(frames) {
            samples[i] = Int16(sin(Double(i) * 2 * .pi * 220 / 16_000) * 8_000)
        }
        try file.write(from: buffer)
    }
}
