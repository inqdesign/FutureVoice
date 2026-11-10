@preconcurrency import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// How the script sits in a video made from a take, the learner's pick when
/// saving (2026-11-08, founder).
enum SpeechVideoStyle: String, CaseIterable {
    /// The camera as it was recorded, no script: nothing to make.
    case cameraOnly
    /// The camera fills the frame and the script rolls over it in white, as
    /// on the take's own replay.
    case fullScreen
    /// The take screen: script on the top half, the camera card below.
    case split
}

/// Records the take's camera, and where the script was on each moment of it
/// (2026-11-08, founder: keep the camera only, draw the script in code, and
/// make the video with the script when it is exported). A take used to be
/// composed as it was recorded, about 100 MB a minute, every take.
///
/// `exportFrame` is the composing half: every camera frame is drawn into the
/// take screen's own layout — the rolling script on top, the camera card
/// below — and written to a movie. The app draws it, so iOS never asks to
/// record the screen (ReplayKit asked again every few minutes) and none of
/// the buttons is in the picture.
///
/// The script is rendered ONCE, ahead of the take, as one tall image of the
/// whole column, and each frame only crops and places it. The scroll
/// position arrives from the screen (`setPrompter`), so the video moves with
/// the prompter the reader saw.
///
/// Frames carry their host-clock time; `Result.firstFrameHost` lines the
/// picture up with the voice, which is stamped on the same clock.
final class SpeechVideoComposer: @unchecked Sendable {

    /// Where things are on the take screen, in points, top-left origin.
    struct Layout: Sendable {
        var canvas: CGSize
        var prompter: CGRect
        var card: CGRect
        var cardRadius: CGFloat
        var background: UIColor
        /// The prompter's fades, as fractions of its height (the screen's mask).
        var topFade: CGFloat = 0.015
        var bottomFade: CGFloat = 0.14
        /// The camera is the whole frame and `card` is unused.
        var fullBleed = false

        /// The script where `standard` puts it, the camera behind everything.
        /// Same size as `standard`, so a replay's offsets land the same way.
        static func fullScreen(width: CGFloat) -> Layout {
            var layout = standard(width: width, background: .black)
            layout.fullBleed = true
            // The script runs to the very top of the picture here; without a
            // real fade a line stops there cut in half.
            layout.topFade = 0.08
            return layout
        }

        /// The video is 9:16 whatever the phone: the take screen's layout in
        /// a standard frame, script on the top half, the camera card on the
        /// bottom. Its width is the screen's, so the script wraps exactly as
        /// the reader saw it.
        static func standard(width: CGFloat, background: UIColor) -> Layout {
            let height = (width * 16 / 9).rounded()
            let half = height / 2
            return Layout(canvas: CGSize(width: width, height: height),
                          prompter: CGRect(x: 0, y: 0, width: width, height: half - 6),
                          card: CGRect(x: 12, y: half + 6, width: width - 24, height: half - 18),
                          cardRadius: 24, background: background)
        }
    }

    /// The column rendered at `scale` pixels per point.
    struct Column: @unchecked Sendable {
        let text: CGImage
        let scale: CGFloat
        /// Every word's box, in column points. Empty: nothing can be lit.
        var words: [CGRect] = []
        /// `SpeechPrompterRecord.unreadOpacity` for Core Image, which blends
        /// in linear light where SwiftUI blends in sRGB.
        var unreadAlpha: CGFloat = 1

        /// The boxes of the column already said: everything above the line
        /// being read, and that line up to where the reading has got.
        func lit(_ reached: SpeechPrompterRecord.Reached) -> [CGRect] {
            guard !words.isEmpty, reached.word > 0 || reached.fraction > 0 else { return [] }
            let index = min(reached.word, words.count - 1)
            let fraction = reached.word >= words.count ? 1 : CGFloat(reached.fraction)
            let word = words[index]
            let width = CGFloat(text.width) / scale
            return [CGRect(x: 0, y: 0, width: width, height: word.minY),
                    CGRect(x: 0, y: word.minY, width: word.minX + word.width * fraction, height: word.height)]
        }
    }

    /// The prompter at this instant, in column points.
    struct Prompter: Sendable {
        /// Column y drawn at the top of the prompter area.
        var offset: CGFloat = 0
        /// The parts of the column already said, the rest dimmed to
        /// `unreadAlpha`. nil: the whole script at full strength.
        var lit: [CGRect]? = nil
        var unreadAlpha: CGFloat = 1
    }

    struct Result {
        /// The camera movie.
        let url: URL
        /// Host-clock seconds of the first frame.
        let firstFrameHost: Double
        /// The prompter's position every `SpeechPrompterRecord.step` seconds
        /// from that first frame.
        let offsets: [Double]
    }

    /// Output width in pixels; the layout's canvas is 9:16, so 1080×1920.
    static let width: CGFloat = 1080

    private let lock = NSLock()
    private var layout: Layout?
    private var column: Column?
    private var prompter = Prompter()
    private var recording = false

    private let writeQueue = DispatchQueue(label: "com.roro.futurevoice.speech-compose")
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var firstPTS: CMTime?
    private var url: URL?
    private var failed = false
    private var rawWriter: AVAssetWriter?
    private var rawInput: AVAssetWriterInput?
    private var rawAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var rawFirstPTS: CMTime?
    private var rawURL: URL?
    private var rawSize: (Int, Int)?
    private var rawFailed = false
    private var offsets: [Double] = []
    private let context = CIContext(options: [.cacheIntermediates: false])

    /// The pixels-per-point the column must be rendered at for `layout`.
    static func scale(for layout: Layout) -> CGFloat {
        width / max(1, layout.canvas.width)
    }

    func prepare(layout: Layout, column: Column) {
        lock.withLock {
            self.layout = layout
            self.column = column
        }
    }

    func setPrompter(_ p: Prompter) {
        lock.withLock { prompter = p }
    }

    /// Frames from now on are written.
    func begin() {
        writeQueue.sync {
            rawWriter = nil
            rawInput = nil
            rawAdaptor = nil
            rawFirstPTS = nil
            rawSize = nil
            rawFailed = false
            offsets = []
            rawURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("speech-camera-\(UUID().uuidString).mov")
        }
        lock.withLock { recording = true }
    }

    /// One camera frame. Called on the camera's queue.
    func append(_ buffer: CMSampleBuffer) {
        lock.lock()
        let on = recording, offset = prompter.offset
        lock.unlock()
        guard on, let camera = CMSampleBufferGetImageBuffer(buffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        writeQueue.sync {
            writeCamera(camera, at: pts)
            guard let first = rawFirstPTS else { return }
            let slot = Int(CMTimeSubtract(pts, first).seconds / SpeechPrompterRecord.step)
            while offsets.count <= slot { offsets.append((Double(offset) * 2).rounded() / 2) }
        }
    }

    func finish() async -> Result? {
        lock.withLock { recording = false }
        let (w, first, u, bad, marks): (AVAssetWriter?, CMTime?, URL?, Bool, [Double]) = writeQueue.sync {
            rawInput?.markAsFinished()
            return (rawWriter, rawFirstPTS, rawURL, rawFailed, offsets)
        }
        guard let w, let first, let u, !bad, w.status == .writing else { return nil }
        await w.finishWriting()
        guard w.status == .completed else { return nil }
        return Result(url: u, firstFrameHost: first.seconds, offsets: marks)
    }

    func cancel() {
        Task { if let r = await finish() { try? FileManager.default.removeItem(at: r.url) } }
    }

    // MARK: - Exporting (the video with the script in it)

    func beginExport() {
        writeQueue.sync {
            writer = nil
            input = nil
            adaptor = nil
            firstPTS = nil
            failed = false
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("speech-export-\(UUID().uuidString).mov")
        }
    }

    /// One decoded camera frame, drawn with the script at `offset`. Blocks
    /// until the encoder can take it: an export has no frame to spare.
    func exportFrame(_ frame: CVPixelBuffer, at pts: CMTime, offset: CGFloat,
                     reached: SpeechPrompterRecord.Reached? = nil) {
        lock.lock()
        let layout = self.layout, column = self.column
        lock.unlock()
        guard let layout, let column else { return }
        let at = Prompter(offset: offset,
                          lit: column.words.isEmpty ? nil : reached.map(column.lit),
                          unreadAlpha: column.unreadAlpha)
        let image = compose(camera: CIImage(cvPixelBuffer: frame), layout: layout,
                            column: visible(column, layout: layout, prompter: at), prompter: at)
        while let waiting = writeQueue.sync(execute: { failed ? nil : input }), !waiting.isReadyForMoreMediaData {
            usleep(1_000)
        }
        writeQueue.sync { write(image, at: pts, layout: layout) }
    }

    func finishExport() async -> URL? {
        let (w, u, bad): (AVAssetWriter?, URL?, Bool) = writeQueue.sync {
            input?.markAsFinished()
            return (writer, url, failed)
        }
        guard let w, let u, !bad, w.status == .writing else { return nil }
        await w.finishWriting()
        return w.status == .completed ? u : nil
    }

    // MARK: - Writing (on writeQueue)

    private func outputSize(_ layout: Layout) -> CGSize {
        let h = (Self.width * layout.canvas.height / max(1, layout.canvas.width)).rounded()
        return CGSize(width: Self.width, height: h - h.truncatingRemainder(dividingBy: 2))
    }

    private func write(_ image: CIImage, at pts: CMTime, layout: Layout) {
        guard !failed else { return }
        let size = outputSize(layout)
        if writer == nil {
            guard let url, let w = try? AVAssetWriter(outputURL: url, fileType: .mov) else { failed = true; return }
            let i = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
            ])
            i.expectsMediaDataInRealTime = true
            let a = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: i, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ])
            guard w.canAdd(i) else { failed = true; return }
            w.add(i)
            guard w.startWriting() else { failed = true; return }
            w.startSession(atSourceTime: pts)
            writer = w
            input = i
            adaptor = a
            firstPTS = pts
        }
        guard let input, input.isReadyForMoreMediaData, let adaptor, let pool = adaptor.pixelBufferPool else { return }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let out else { return }
        context.render(image, to: out, bounds: CGRect(origin: .zero, size: size),
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        adaptor.append(out, withPresentationTime: pts)
    }

    /// The camera frame as it came, already upright and mirrored by the
    /// capture connection. Nothing is drawn, so this costs only the encoder.
    private func writeCamera(_ frame: CVPixelBuffer, at pts: CMTime) {
        guard !rawFailed else { return }
        let size = (CVPixelBufferGetWidth(frame), CVPixelBufferGetHeight(frame))
        if rawWriter == nil {
            guard let rawURL, let w = try? AVAssetWriter(outputURL: rawURL, fileType: .mov) else { rawFailed = true; return }
            // HEVC where the device can: 1080p in about the room H.264 needs
            // for 720p, so the better picture doesn't cost the phone's space.
            func settings(_ codec: AVVideoCodecType) -> [String: Any] {
                [AVVideoCodecKey: codec, AVVideoWidthKey: size.0, AVVideoHeightKey: size.1]
            }
            let i = AVAssetWriterInput(mediaType: .video,
                                       outputSettings: w.canApply(outputSettings: settings(.hevc), forMediaType: .video)
                                           ? settings(.hevc) : settings(.h264))
            i.expectsMediaDataInRealTime = true
            let a = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: i, sourcePixelBufferAttributes: nil)
            guard w.canAdd(i) else { rawFailed = true; return }
            w.add(i)
            guard w.startWriting() else { rawFailed = true; return }
            w.startSession(atSourceTime: pts)
            rawWriter = w
            rawInput = i
            rawAdaptor = a
            rawFirstPTS = pts
            rawSize = size
        }
        // A phone turned mid-take changes the frame's shape; the file keeps
        // the one it started with.
        guard let rawInput, rawInput.isReadyForMoreMediaData, let rawAdaptor,
              rawSize?.0 == size.0, rawSize?.1 == size.1 else { return }
        rawAdaptor.append(frame, withPresentationTime: pts)
    }

    // MARK: - Drawing

    /// Only the part of the column the prompter shows this frame, as
    /// CIImages placed where the full images would be. The full column of a
    /// three-minute script is ~40 MB an image; handing it to Core Image whole
    /// would send all of it to the GPU on every frame. `CGImage.cropping`
    /// shares the pixels, so this costs nothing to make.
    func visible(_ column: Column, layout: Layout,
                 prompter: Prompter) -> (text: CIImage, scale: CGFloat, fullHeight: CGFloat) {
        let s = column.scale
        let fullH = CGFloat(column.text.height)
        let top = max(0, (prompter.offset * s).rounded(.down))
        let height = min(fullH - top, (layout.prompter.height * s).rounded(.up) + 2)
        guard height > 0, let cropped = column.text.cropping(
            to: CGRect(x: 0, y: top, width: CGFloat(column.text.width), height: height)) else {
            return (.empty(), s, fullH)
        }
        // CGImage space is top-left; place the crop at its bottom-left
        // position in the full image's Core Image space.
        let placed = CIImage(cgImage: cropped)
            .transformed(by: CGAffineTransform(translationX: 0, y: fullH - top - height))
        return (placed, s, fullH)
    }

    /// Core Image's origin is bottom-left; the layout's is top-left. `k` is
    /// output pixels per layout point.
    func compose(camera: CIImage,
                         layout: Layout,
                         column: (text: CIImage, scale: CGFloat, fullHeight: CGFloat),
                         prompter: Prompter) -> CIImage {
        let size = outputSize(layout)
        let k = size.width / max(1, layout.canvas.width)
        let H = size.height
        func px(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * k, y: H - r.maxY * k, width: r.width * k, height: r.height * k)
        }
        let full = CGRect(origin: .zero, size: size)
        let background = layout.fullBleed
            ? scrimmed(filled(camera, to: full), in: full)
            : CIImage(color: CIColor(color: layout.background)).cropped(to: full)

        // The script. The column image is k pixels per point, origin bottom-left.
        let imgH = column.fullHeight
        var text = column.text
        // Column y = `offset` sits at the top of the prompter area.
        let area = px(layout.prompter)
        let tx = layout.prompter.minX * k
        let ty = H - (layout.prompter.minY - prompter.offset) * k - imgH
        text = text.transformed(by: CGAffineTransform(translationX: tx, y: ty)).cropped(to: area)
        if let lit = prompter.lit {
            let full = text
            text = full.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: prompter.unreadAlpha),
            ])
            for box in lit where !box.isEmpty {
                let placed = CGRect(x: tx + box.minX * k, y: ty + imgH - box.maxY * k,
                                    width: box.width * k, height: box.height * k)
                text = full.cropped(to: placed.intersection(area)).composited(over: text)
            }
        }

        // The prompter's top and bottom fades.
        let top = CIFilter.linearGradient()
        top.point0 = CGPoint(x: 0, y: area.maxY)
        top.point1 = CGPoint(x: 0, y: area.maxY - area.height * layout.topFade)
        top.color0 = CIColor.black
        top.color1 = CIColor.white
        let bottom = CIFilter.linearGradient()
        bottom.point0 = CGPoint(x: 0, y: area.minY)
        bottom.point1 = CGPoint(x: 0, y: area.minY + area.height * layout.bottomFade)
        bottom.color0 = CIColor.black
        bottom.color1 = CIColor.white
        var frame = background
        if let topImage = top.outputImage, let bottomImage = bottom.outputImage {
            let fade = topImage.applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: bottomImage,
            ]).cropped(to: area)
            frame = text.composited(over: background).applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: fade,
            ]).cropped(to: full)
        } else {
            frame = text.composited(over: background)
        }
        if layout.fullBleed { return frame }

        // The camera card: aspect-fill, rounded corners.
        let card = px(layout.card)
        let placed = filled(camera, to: card)
        let round = CIFilter.roundedRectangleGenerator()
        round.extent = card
        round.radius = Float(layout.cardRadius * k)
        round.color = .white
        if let mask = round.outputImage {
            frame = placed.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: frame,
                kCIInputMaskImageKey: mask,
            ]).cropped(to: full)
        } else {
            frame = placed.composited(over: frame)
        }
        return frame
    }

    /// The camera, aspect-filling `rect`.
    private func filled(_ camera: CIImage, to rect: CGRect) -> CIImage {
        let source = camera.extent
        let fill = max(rect.width / source.width, rect.height / source.height)
        let scaled = camera.transformed(by: CGAffineTransform(scaleX: fill, y: fill))
        return scaled.transformed(by: CGAffineTransform(
            translationX: rect.midX - scaled.extent.midX,
            y: rect.midY - scaled.extent.midY)).cropped(to: rect)
    }

    /// The darkening behind white script, the replay's own: black at 60%,
    /// 35% halfway, gone at 61% of the height. Core Image blends in linear
    /// light and SwiftUI in sRGB, so the same look takes `1 - (1 - a)^2.2`.
    private func scrimmed(_ image: CIImage, in full: CGRect) -> CIImage {
        func linear(_ a: CGFloat) -> CGFloat { 1 - pow(1 - a, 2.2) }
        let height = (full.height * 0.61).rounded()
        let middle = (full.maxY - height / 2).rounded()
        let bottom = full.maxY - height
        func band(from y0: CGFloat, _ a0: CGFloat, to y1: CGFloat, _ a1: CGFloat) -> CIImage {
            let gradient = CIFilter.linearGradient()
            gradient.point0 = CGPoint(x: 0, y: y0)
            gradient.point1 = CGPoint(x: 0, y: y1)
            gradient.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: a0)
            gradient.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: a1)
            return (gradient.outputImage ?? .empty())
                .cropped(to: CGRect(x: 0, y: y1, width: full.width, height: y0 - y1))
        }
        return band(from: full.maxY, linear(0.6), to: middle, linear(0.35))
            .composited(over: band(from: middle, linear(0.35), to: bottom, 0))
            .composited(over: image)
            .cropped(to: full)
    }
}

/// Makes the video with the script in it, from a camera-only take and its
/// record of how the script moved.
enum SpeechVideoExporter {
    /// The script drawn as one tall image, as it stood on the reader's screen.
    @MainActor
    static func column(for record: SpeechPrompterRecord, style: SpeechVideoStyle = .split) -> (layout: SpeechVideoComposer.Layout, column: SpeechVideoComposer.Column)? {
        // Over the camera the script is white, whatever the reader's screen was.
        let dark = record.dark || style == .fullScreen
        let scheme: ColorScheme = dark ? .dark : .light
        let background = UIColor.systemBackground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        let layout: SpeechVideoComposer.Layout = style == .fullScreen
            ? .fullScreen(width: CGFloat(record.width))
            : .standard(width: CGFloat(record.width), background: background)
        let scale = SpeechVideoComposer.scale(for: layout)
        let map = SpeechColumnMap()
        let renderer = ImageRenderer(content:
            SpeechPrompterColumn(track: SpeechPrompterTrack(script: record.text, language: record.language),
                                 cursor: 0, language: record.language, textSize: record.textSize,
                                 width: CGFloat(record.width), measures: false, map: map, onCurrentWord: { _ in })
                .environment(\.colorScheme, scheme))
        renderer.scale = scale
        renderer.isOpaque = false
        guard let text = renderer.cgImage else { return nil }
        // White text fades against a dark picture, black against a light one.
        let unread = SpeechPrompterRecord.unreadOpacity
        let unreadAlpha = dark ? pow(unread, 2.2) : 1 - pow(1 - unread, 2.2)
        return (layout, .init(text: text, scale: scale,
                              words: map.wordFrames(inset: 24, gap: CGFloat(record.textSize) * 0.9),
                              unreadAlpha: CGFloat(unreadAlpha)))
    }

    /// A temporary movie (the caller removes it), or nil if it couldn't be made.
    static func render(video: URL, record: SpeechPrompterRecord, style: SpeechVideoStyle,
                       progress: @escaping @Sendable (Double) -> Void) async -> URL? {
        guard let drawn = await column(for: record, style: style) else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            let asset = AVURLAsset(url: video)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let duration = try? await asset.load(.duration), duration.seconds > 0,
                  let reader = try? AVAssetReader(asset: asset) else { return nil }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { return nil }
            reader.add(output)
            guard reader.startReading() else { return nil }
            let composer = SpeechVideoComposer()
            composer.prepare(layout: drawn.layout, column: drawn.column)
            composer.beginExport()
            while !Task.isCancelled {
                let more: Bool = autoreleasepool {
                    guard let sample = output.copyNextSampleBuffer(),
                          let frame = CMSampleBufferGetImageBuffer(sample) else { return false }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    composer.exportFrame(frame, at: pts, offset: CGFloat(record.offset(at: pts.seconds)),
                                         reached: record.reached(at: pts.seconds))
                    progress(min(0.98, pts.seconds / duration.seconds))
                    return true
                }
                if !more { break }
            }
            reader.cancelReading()
            guard let silent = await composer.finishExport() else { return nil }
            defer { try? FileManager.default.removeItem(at: silent) }
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("speech-with-script-\(UUID().uuidString).mov")
            // The camera file's own sound: it is already in step with its picture.
            guard await SpeechMediaMerger.merge(video: silent, audio: video, to: out) else { return nil }
            return out
        }.value
    }
}
