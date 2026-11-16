import UIKit

/// The speech app's cards are dark (2026-11-16, founder: graphite #1C1C1E),
/// and the challenge pictures were cut out of cream paper: the coloured
/// pencil breaks up at every edge, so a 1–2 px cream rim and the cream
/// between strokes show as light specks on a dark card. This is the cleanup
/// the speech teaser used for the same pictures on black
/// (`marketing/content/2026-11-14-speech-teaser`, its `defringe.py`), done on
/// the phone so every picture, bundled or fetched from R2, gets it with no
/// redraw and no upload:
///
///  1. small enclosed holes (paper the cut-out took for background) are given
///     back, in paper colour;
///  2. the outline is pulled 2 px inward, past the cream rim;
///  3. the new edge takes the colour from just inside the figure;
///  4. the edge is softened (a Gaussian, sigma 0.8).
///
/// nawana's cards stay cream/white and keep the pictures as they are.
enum ChallengeArtDefringe {
    static func clean(_ source: UIImage) -> UIImage? {
        guard let cg = source.cgImage else { return nil }
        let w = cg.width, h = cg.height, n = w * h
        guard w > 8, h > 8 else { return nil }
        var px = [UInt8](repeating: 0, count: n * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let drew: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }

        // Straight colour, and the figure as a mask.
        var r = [Float](repeating: 0, count: n), g = r, b = r
        var mask = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let a = Float(px[i * 4 + 3])
            if a > 0 {
                r[i] = Float(px[i * 4]) * 255 / a
                g[i] = Float(px[i * 4 + 1]) * 255 / a
                b[i] = Float(px[i * 4 + 2]) * 255 / a
            }
            mask[i] = a > 128
        }

        // 1. Holes: background pieces under 400 px that don't reach the border.
        var seen = [Bool](repeating: false, count: n)
        var stack: [Int] = []
        var piece: [Int] = []
        for start in 0..<n where !mask[start] && !seen[start] {
            piece.removeAll(keepingCapacity: true)
            stack.append(start); seen[start] = true
            var border = false
            while let i = stack.popLast() {
                piece.append(i)
                let x = i % w, y = i / w
                if x == 0 || y == 0 || x == w - 1 || y == h - 1 { border = true }
                if x > 0, !mask[i - 1], !seen[i - 1] { seen[i - 1] = true; stack.append(i - 1) }
                if x < w - 1, !mask[i + 1], !seen[i + 1] { seen[i + 1] = true; stack.append(i + 1) }
                if y > 0, !mask[i - w], !seen[i - w] { seen[i - w] = true; stack.append(i - w) }
                if y < h - 1, !mask[i + w], !seen[i + w] { seen[i + w] = true; stack.append(i + w) }
            }
            if !border && piece.count < 400 {
                for i in piece { mask[i] = true; r[i] = 238; g[i] = 234; b[i] = 222 }
            }
        }

        // 2. Pull the outline in; `deep` is where colour is trusted.
        let inner = erode(mask, w, h, times: 2)
        let deep = erode(inner, w, h, times: 3)
        let band = dilate(inner, w, h, times: 2)

        // 3. Everything in the band that isn't deep takes the colour of the
        // nearest deep pixel (a breadth-first spread from the deep region).
        var done = deep
        var front: [Int] = []
        for i in 0..<n where deep[i] { front.append(i) }
        var next: [Int] = []
        while !front.isEmpty {
            next.removeAll(keepingCapacity: true)
            for i in front {
                let x = i % w, y = i / w
                for j in [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1]
                where j >= 0 && band[j] && !done[j] {
                    done[j] = true; r[j] = r[i]; g[j] = g[i]; b[j] = b[i]; next.append(j)
                }
            }
            swap(&front, &next)
        }

        // 4. Soft edge: the pulled-in mask blurred, nothing outside the band.
        var alpha = [Float](repeating: 0, count: n)
        for i in 0..<n where inner[i] { alpha[i] = 1 }
        alpha = gaussian(alpha, w, h, sigma: 0.8)

        for i in 0..<n {
            let a = band[i] ? min(max(alpha[i], 0), 1) : 0
            px[i * 4] = UInt8(min(max(r[i] * a, 0), 255))
            px[i * 4 + 1] = UInt8(min(max(g[i] * a, 0), 255))
            px[i * 4 + 2] = UInt8(min(max(b[i] * a, 0), 255))
            px[i * 4 + 3] = UInt8(a * 255)
        }
        let out: CGImage? = px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: space, bitmapInfo: info)?.makeImage()
        }
        return out.map { UIImage(cgImage: $0, scale: source.scale, orientation: source.imageOrientation) }
    }

    /// Erosion with the 4-neighbour cross, like `ndimage.binary_erosion`.
    private static func erode(_ m: [Bool], _ w: Int, _ h: Int, times: Int) -> [Bool] {
        var cur = m
        for _ in 0..<times {
            var nxt = cur
            for y in 0..<h {
                for x in 0..<w {
                    let i = y * w + x
                    guard cur[i] else { continue }
                    if x == 0 || y == 0 || x == w - 1 || y == h - 1
                        || !cur[i - 1] || !cur[i + 1] || !cur[i - w] || !cur[i + w] { nxt[i] = false }
                }
            }
            cur = nxt
        }
        return cur
    }

    private static func dilate(_ m: [Bool], _ w: Int, _ h: Int, times: Int) -> [Bool] {
        var cur = m
        for _ in 0..<times {
            var nxt = cur
            for y in 0..<h {
                for x in 0..<w {
                    let i = y * w + x
                    guard !cur[i] else { continue }
                    if (x > 0 && cur[i - 1]) || (x < w - 1 && cur[i + 1])
                        || (y > 0 && cur[i - w]) || (y < h - 1 && cur[i + w]) { nxt[i] = true }
                }
            }
            cur = nxt
        }
        return cur
    }

    /// Separable Gaussian, edges clamped.
    private static func gaussian(_ src: [Float], _ w: Int, _ h: Int, sigma: Float) -> [Float] {
        let radius = Int((sigma * 4).rounded(.up))
        var k = (-radius...radius).map { exp(-Float($0 * $0) / (2 * sigma * sigma)) }
        let sum = k.reduce(0, +); k = k.map { $0 / sum }
        var tmp = [Float](repeating: 0, count: src.count), out = tmp
        for y in 0..<h {
            for x in 0..<w {
                var s: Float = 0
                for t in -radius...radius { s += src[y * w + min(max(x + t, 0), w - 1)] * k[t + radius] }
                tmp[y * w + x] = s
            }
        }
        for y in 0..<h {
            for x in 0..<w {
                var s: Float = 0
                for t in -radius...radius { s += tmp[min(max(y + t, 0), h - 1) * w + x] * k[t + radius] }
                out[y * w + x] = s
            }
        }
        return out
    }
}
