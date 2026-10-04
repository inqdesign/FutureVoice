@preconcurrency import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Makes the take's video: every camera frame is drawn into the take
/// screen's own layout — the rolling script on top, the camera card below —
/// and written to a movie. The app draws it, so iOS never asks to record the
/// screen (ReplayKit asked again every few minutes) and none of the buttons
/// is in the picture.
///
/// The script is rendered ONCE when the take starts, as three tall images of
/// the whole column — unread, read, and the current word's colour — and each
/// frame only crops and places them: the read part is everything above the
/// current word's line plus its line up to the word, exactly what the screen
/// colours. The scroll position and the current word arrive from the screen
/// (`setPrompter`), so the video moves with the prompter the reader saw.
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
        var topFade: CGFloat = 0.05
        var bottomFade: CGFloat = 0.14
    }

    /// The column rendered three ways, at `scale` pixels per point.
    struct Column: @unchecked Sendable {
        let unread: CGImage
        let read: CGImage
        let accent: CGImage
        let scale: CGFloat
    }

    /// The prompter at this instant, in column points.
    struct Prompter: Sendable {
        /// Column y drawn at the top of the prompter area.
        var offset: CGFloat = 0
        /// The current word's frame in the column.
        var word: CGRect = .zero
    }

    struct Result {
        let url: URL
        /// Host-clock seconds of the first frame.
        let firstFrameHost: Double
    }

    /// Output width in pixels; the layout's canvas is 9:16, so 1080×1920.
    static let width: CGFloat = 1080

    private let lock = NSLock()
    private var layout: Layout?
    private var column: (unread: CIImage, read: CIImage, accent: CIImage, scale: CGFloat)?
    private var prompter = Prompter()
    private var recording = false

    private let writeQueue = DispatchQueue(label: "com.roro.futurevoice.speech-compose")
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var firstPTS: CMTime?
    private var url: URL?
    private var failed = false
    private let context = CIContext(options: [.cacheIntermediates: false])

    /// The pixels-per-point the column must be rendered at for `layout`.
    static func scale(for layout: Layout) -> CGFloat {
        width / max(1, layout.canvas.width)
    }

    func prepare(layout: Layout, column: Column) {
        lock.withLock {
            self.layout = layout
            self.column = (CIImage(cgImage: column.unread), CIImage(cgImage: column.read),
                           CIImage(cgImage: column.accent), column.scale)
        }
    }

    func setPrompter(_ p: Prompter) {
        lock.withLock { prompter = p }
    }

    /// Frames from now on are written.
    func begin() {
        writeQueue.sync {
            writer = nil
            input = nil
            adaptor = nil
            firstPTS = nil
            failed = false
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("speech-take-\(UUID().uuidString).mov")
        }
        lock.withLock { recording = true }
    }

    /// One camera frame. Called on the camera's queue.
    func append(_ buffer: CMSampleBuffer) {
        lock.lock()
        let on = recording, layout = self.layout, column = self.column, prompter = self.prompter
        lock.unlock()
        guard on, let layout, let column, let camera = CMSampleBufferGetImageBuffer(buffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        let image = compose(camera: CIImage(cvPixelBuffer: camera), layout: layout,
                            column: column, prompter: prompter)
        writeQueue.sync { write(image, at: pts, layout: layout) }
    }

    func finish() async -> Result? {
        lock.withLock { recording = false }
        let (w, first, u, bad): (AVAssetWriter?, CMTime?, URL?, Bool) = writeQueue.sync {
            input?.markAsFinished()
            return (writer, firstPTS, url, failed)
        }
        guard let w, let first, let u, !bad, w.status == .writing else { return nil }
        await w.finishWriting()
        guard w.status == .completed else { return nil }
        return Result(url: u, firstFrameHost: first.seconds)
    }

    func cancel() {
        Task { if let r = await finish() { try? FileManager.default.removeItem(at: r.url) } }
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

    // MARK: - Drawing

    /// Core Image's origin is bottom-left; the layout's is top-left. `k` is
    /// output pixels per layout point.
    func compose(camera: CIImage,
                         layout: Layout,
                         column: (unread: CIImage, read: CIImage, accent: CIImage, scale: CGFloat),
                         prompter: Prompter) -> CIImage {
        let size = outputSize(layout)
        let k = size.width / max(1, layout.canvas.width)
        let H = size.height
        func px(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * k, y: H - r.maxY * k, width: r.width * k, height: r.height * k)
        }
        let full = CGRect(origin: .zero, size: size)
        let background = CIImage(color: CIColor(color: layout.background)).cropped(to: full)

        // The script. Column images are k pixels per point, origin bottom-left.
        let imgH = column.unread.extent.height
        let s = column.scale
        let w = prompter.word
        func colRect(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * s, y: imgH - r.maxY * s, width: r.width * s, height: r.height * s)
        }
        let white = CIImage(color: .white)
        let readMask = white.cropped(to: colRect(CGRect(x: 0, y: 0, width: 100_000, height: max(0, w.minY))))
            .composited(over: white.cropped(to: colRect(CGRect(x: 0, y: w.minY, width: max(0, w.minX), height: w.height))))
        var text = column.read.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: column.unread,
            kCIInputMaskImageKey: readMask,
        ])
        if w.width > 0 {
            text = column.accent.cropped(to: colRect(w)).composited(over: text)
        }
        // Column y = `offset` sits at the top of the prompter area.
        let area = px(layout.prompter)
        let tx = layout.prompter.minX * k
        let ty = H - (layout.prompter.minY - prompter.offset) * k - imgH
        text = text.transformed(by: CGAffineTransform(translationX: tx, y: ty)).cropped(to: area)

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

        // The camera card: aspect-fill, rounded corners.
        let card = px(layout.card)
        let cam = camera.extent
        let fill = max(card.width / cam.width, card.height / cam.height)
        let scaled = camera.transformed(by: CGAffineTransform(scaleX: fill, y: fill))
        let placed = scaled.transformed(by: CGAffineTransform(
            translationX: card.midX - scaled.extent.midX,
            y: card.midY - scaled.extent.midY)).cropped(to: card)
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
}
