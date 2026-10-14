import AVFoundation
import Foundation

/// What a Speech camera take sends to iCloud, chosen by the learner
/// (Me → Devices → Speech videos). Off by default.
///
/// The camera's own file (`Documents/Speech/take-<id>.mov`, 1080p) never
/// travels. What travels is a COPY in `Documents/Speech/Synced/`:
/// - **standard** — re-encoded to 720p HEVC (`take-<id>.sd.mov`), a fraction
///   of the size, and downloaded by the other device as it appears;
/// - **original** — the camera's file itself, hard-linked so it costs no
///   space here (`take-<id>.hq.mov`), and downloaded by the other device only
///   when the learner taps for it (`BlobKind.onDemand`).
/// On standard, one take's original can still be sent from its page
/// (`sendOriginal`) — the "only when I need it in high quality" case.
///
/// A copy exists only while sync is on and a quality is picked; switching
/// either off deletes nothing, here or in iCloud ("turning sync off deletes
/// nothing" applies to the videos too). A video deleted on any device goes
/// everywhere: its take record says so, and `dropVideosNoLongerOnFile`
/// removes the files that went with it.
@MainActor
final class SpeechVideoSync: ObservableObject {
    static let shared = SpeechVideoSync()

    enum Quality: String, CaseIterable, Identifiable {
        case off, standard, original
        var id: String { rawValue }
    }

    private static let qualityKey = "futurevoice.sync.speechVideo"

    @Published var quality: Quality = Quality(rawValue: UserDefaults.standard.string(forKey: SpeechVideoSync.qualityKey) ?? "") ?? .off {
        didSet {
            UserDefaults.standard.set(quality.rawValue, forKey: Self.qualityKey)
            if quality != oldValue { ensureCopies() }
        }
    }

    /// Takes whose standard copy is being encoded right now.
    @Published private(set) var encoding: Set<UUID> = []
    private var queue: [URL] = []
    private var worker: Task<Void, Never>?

    // MARK: - Names

    static let folder = "Speech/Synced"

    static var directory: URL {
        SyncFiles.documents.appendingPathComponent(folder, isDirectory: true)
    }

    nonisolated static func standardName(_ id: UUID) -> String { "take-\(id.uuidString).sd.mov" }
    nonisolated static func originalName(_ id: UUID) -> String { "take-\(id.uuidString).hq.mov" }
    nonisolated static func copyNames(for id: UUID) -> [String] { [standardName(id), originalName(id)] }

    nonisolated static func isCopy(_ name: String) -> Bool {
        name.hasPrefix("take-") && (name.hasSuffix(".sd.mov") || name.hasSuffix(".hq.mov"))
    }

    nonisolated static func isOriginalCopy(_ name: String) -> Bool { name.hasSuffix(".hq.mov") }

    private static func copyURL(_ name: String) -> URL { directory.appendingPathComponent(name) }

    /// The camera's file, on the device that recorded it.
    private static func cameraURL(_ take: SpeechTake) -> URL? {
        guard let name = take.videoFilename else { return nil }
        let url = SpeechStore.mediaURL(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: copyURL(name).path)
    }

    // MARK: - What the take page shows

    /// The best picture this device holds: the camera's file, then the
    /// original's copy, then the standard one.
    static func playableURL(_ take: SpeechTake) -> URL? {
        if let camera = cameraURL(take) { return camera }
        for name in [originalName(take.id), standardName(take.id)] where exists(name) {
            return copyURL(name)
        }
        return nil
    }

    /// Recorded here (the camera's file is on this device).
    static func isRecordedHere(_ take: SpeechTake) -> Bool { cameraURL(take) != nil }

    static func hasOriginalHere(_ take: SpeechTake) -> Bool {
        cameraURL(take) != nil || exists(originalName(take.id))
    }

    static func hasStandardCopy(_ take: SpeechTake) -> Bool { exists(standardName(take.id)) }
    static func hasOriginalCopy(_ take: SpeechTake) -> Bool { exists(originalName(take.id)) }

    // MARK: - Making copies

    /// Brings every take recorded on this device up to the chosen quality.
    /// Cheap when there is nothing to do; called on foreground, after a new
    /// take, and when the setting moves.
    func ensureCopies() {
        guard quality != .off, SyncEngine.shared.isEnabled else { return }
        var linked = false
        for take in Self.allTakes() {
            guard let camera = Self.cameraURL(take) else { continue }
            switch quality {
            case .off:
                break
            case .standard:
                if !Self.exists(Self.standardName(take.id)), !queue.contains(camera) {
                    queue.append(camera)
                }
            case .original:
                if !Self.exists(Self.originalName(take.id)), Self.link(camera, as: Self.originalName(take.id)) {
                    linked = true
                }
            }
        }
        if linked { SyncEngine.noteChanged(.blobSpeechVideo) }
        startWorker()
    }

    /// Sends this take's original to iCloud — on standard quality, the one
    /// video the learner wants at full resolution on their other device.
    @discardableResult
    func sendOriginal(_ take: SpeechTake) -> Bool {
        guard let camera = Self.cameraURL(take) else { return false }
        guard Self.exists(Self.originalName(take.id)) || Self.link(camera, as: Self.originalName(take.id))
        else { return false }
        SyncEngine.noteChanged(.blobSpeechVideo)
        objectWillChange.send()
        return true
    }

    /// Removes the copies of a take whose video (or the take itself) was
    /// deleted on this device.
    static func removeCopies(of id: UUID) {
        var removed = false
        for name in copyNames(for: id) where exists(name) {
            try? FileManager.default.removeItem(at: copyURL(name))
            removed = true
        }
        if removed { SyncEngine.noteChanged(.blobSpeechVideo) }
    }

    /// After a pull: a take whose record no longer names a video had it
    /// deleted on the other device, so the camera's file and the copies go
    /// here too. A take still being put together is skipped — its record
    /// is written before its video is (`SpeechTakeSession`).
    func dropVideosNoLongerOnFile(lang: String?) {
        guard let lang else { return }
        let takes = SyncFiles.read([SpeechTake].self, at: SyncFiles.url("speech_takes.json", lang: lang),
                                   decoder: SyncFiles.storeDecoder, empty: []) ?? []
        let fm = FileManager.default
        for take in takes where take.videoFilename == nil && !SpeechStore.shared.videoPending.contains(take.id) {
            let camera = SyncFiles.documents.appendingPathComponent("Speech", isDirectory: true)
                .appendingPathComponent("take-\(take.id.uuidString).mov")
            if fm.fileExists(atPath: camera.path) { try? fm.removeItem(at: camera) }
            Self.removeCopies(of: take.id)
        }
    }

    private static func allTakes() -> [SpeechTake] {
        LanguageScope.enrolled.flatMap { lang in
            SyncFiles.read([SpeechTake].self, at: SyncFiles.url("speech_takes.json", lang: lang),
                           decoder: SyncFiles.storeDecoder, empty: []) ?? []
        }
    }

    /// A hard link: the same bytes under the name the sync carries, at no
    /// cost in space. A copy only if the volume refuses a link.
    private static func link(_ source: URL, as name: String) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = copyURL(name)
        if (try? fm.linkItem(at: source, to: dest)) != nil { return true }
        return (try? fm.copyItem(at: source, to: dest)) != nil
    }

    private func startWorker() {
        guard worker == nil, !queue.isEmpty else { return }
        worker = Task { [weak self] in
            while let self, !self.queue.isEmpty {
                let camera = self.queue.removeFirst()
                guard let id = Self.takeId(fromCamera: camera.lastPathComponent) else { continue }
                // The setting may have moved, or the video gone, while this
                // waited its turn.
                guard self.quality == .standard, FileManager.default.fileExists(atPath: camera.path) else { continue }
                self.encoding.insert(id)
                let name = Self.standardName(id)
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("speech-sd-\(UUID().uuidString).mov")
                let ok = await Self.encodeStandard(from: camera, to: temp)
                // Moved in whole, so the sync never uploads half a file — and
                // only if the take's video still exists.
                if ok, FileManager.default.fileExists(atPath: camera.path) {
                    try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                    try? FileManager.default.removeItem(at: Self.copyURL(name))
                    if (try? FileManager.default.moveItem(at: temp, to: Self.copyURL(name))) != nil {
                        var values = URLResourceValues()
                        values.isExcludedFromBackup = true
                        var url = Self.copyURL(name)
                        try? url.setResourceValues(values)
                        SyncEngine.noteChanged(.blobSpeechVideo)
                    }
                }
                try? FileManager.default.removeItem(at: temp)
                self.encoding.remove(id)
                Analytics.capture("speech_video_copy", ["ok": ok])
            }
            self?.worker = nil
        }
    }

    private static func takeId(fromCamera name: String) -> UUID? {
        guard name.hasPrefix("take-"), name.hasSuffix(".mov") else { return nil }
        return UUID(uuidString: String(name.dropFirst(5).dropLast(4)))
    }

    // MARK: - Standard encode

    /// Longest edge of the standard copy, and its video bitrate. 720p at
    /// 1.5 Mbit/s HEVC plus the voice is about 12 MB a minute — a face and a prompter read
    /// clearly at that size.
    nonisolated static let standardLongEdge: CGFloat = 1280
    nonisolated static let standardVideoBitrate = 1_500_000

    /// Re-encodes a take to the standard copy. HEVC where the device can,
    /// H.264 otherwise; the voice as AAC. False on any failure — the take
    /// then simply has no copy yet, and the next `ensureCopies` tries again.
    nonisolated static func encodeStandard(from source: URL, to output: URL) async -> Bool {
        let asset = AVURLAsset(url: source)
        guard let vTrack = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await vTrack.load(.naturalSize),
              let transform = try? await vTrack.load(.preferredTransform),
              natural.width > 0, natural.height > 0 else { return false }
        let aTrack = try? await asset.loadTracks(withMediaType: .audio).first
        let audioFormat = try? await aTrack?.load(.formatDescriptions).first

        let scale = min(1, standardLongEdge / max(natural.width, natural.height))
        func even(_ v: CGFloat) -> Int { max(2, Int((v * scale).rounded()) & ~1) }
        let width = even(natural.width), height = even(natural.height)

        try? FileManager.default.removeItem(at: output)
        guard let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: output, fileType: .mov) else { return false }

        let vOut = AVAssetReaderTrackOutput(track: vTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        vOut.alwaysCopiesSampleData = false
        guard reader.canAdd(vOut) else { return false }
        reader.add(vOut)

        func videoSettings(_ codec: AVVideoCodecType) -> [String: Any] {
            [AVVideoCodecKey: codec,
             AVVideoWidthKey: width,
             AVVideoHeightKey: height,
             AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: standardVideoBitrate]]
        }
        let settings = writer.canApply(outputSettings: videoSettings(.hevc), forMediaType: .video)
            ? videoSettings(.hevc) : videoSettings(.h264)
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        vIn.transform = transform
        vIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(vIn) else { return false }
        writer.add(vIn)

        var audio: (AVAssetReaderTrackOutput, AVAssetWriterInput)?
        if let aTrack, let audioFormat,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat)?.pointee {
            let channels = max(1, min(2, Int(asbd.mChannelsPerFrame)))
            let rate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 44_100
            let aOut = AVAssetReaderTrackOutput(track: aTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: rate,
            ])
            let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: rate,
            ])
            aIn.expectsMediaDataInRealTime = false
            if reader.canAdd(aOut), writer.canAdd(aIn) {
                reader.add(aOut)
                writer.add(aIn)
                audio = (aOut, aIn)
            }
        }

        guard reader.startReading(), writer.startWriting() else {
            reader.cancelReading()
            writer.cancelWriting()
            return false
        }
        writer.startSession(atSourceTime: .zero)

        let failed = Flag()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await pump(vOut, into: vIn, label: "speech-sd-video", failed: failed) }
            if let (aOut, aIn) = audio {
                group.addTask { await pump(aOut, into: aIn, label: "speech-sd-audio", failed: failed) }
            }
        }
        if failed.value || reader.status == .failed {
            writer.cancelWriting()
            return false
        }
        await writer.finishWriting()
        return writer.status == .completed
    }

    /// Copies one track's samples across until the reader runs dry.
    nonisolated private static func pump(_ output: AVAssetReaderTrackOutput, into input: AVAssetWriterInput,
                                         label: String, failed: Flag) async {
        let queue = DispatchQueue(label: label)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let buffer = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        cont.resume()
                        return
                    }
                    if !input.append(buffer) {
                        failed.set()
                        input.markAsFinished()
                        cont.resume()
                        return
                    }
                }
            }
        }
    }

    /// A failure seen on either track's queue.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false
        var value: Bool { lock.lock(); defer { lock.unlock() }; return raised }
        func set() { lock.lock(); raised = true; lock.unlock() }
    }
}
