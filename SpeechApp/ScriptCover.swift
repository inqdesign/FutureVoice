import UIKit

/// A cover picture for one of the learner's OWN scripts (2026-11-16, founder:
/// "when a user makes their own script, we should also create a cover
/// image"). Drawn once, when the script is made, by `speech-cover` in the
/// same coloured-pencil style as the challenge pictures; the cream it comes
/// on is cut to alpha here and the result cleaned for the dark card
/// (`ChallengeArtDefringe`), exactly as a challenge picture is.
///
/// Kept on the phone only: `Documents/Speech/covers/<script id>.png`, the
/// finished picture, so it is never cut or cleaned twice. Not synced (another
/// device shows the script's kind instead). A script whose picture failed is
/// tried again on the next launch (`pending.json`), never twice in one.
///
/// `ChallengeArt.image(for:)` asks this first for any id, so every place a
/// challenge draws its picture (card, detail, calendar) draws a cover too.
enum ScriptCover {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var images: [UUID: UIImage] = [:]
    nonisolated(unsafe) private static var tried: Set<UUID> = []

    static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Speech/covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString.lowercased()).png")
    }

    private static var pendingURL: URL { directory.appendingPathComponent("pending.json") }

    /// Memory only: safe on every frame.
    static func image(for id: UUID) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return images[id]
    }

    /// Decodes every cover on disk. Run with the challenge pictures at launch.
    static func prepare() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "png" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            lock.lock(); let have = images[id] != nil; lock.unlock()
            if have { continue }
            guard let img = UIImage(contentsOfFile: url.path) else { continue }
            let ready = img.preparingForDisplay() ?? img
            lock.lock(); images[id] = ready; lock.unlock()
        }
    }

    /// Draws a cover for a script that has none. A challenge, the bundled
    /// sample and a script already drawn (or tried this launch) are left alone.
    @MainActor
    static func ensure(_ script: SpeechScript) {
        guard !script.isChallenge, !script.isBuiltIn else { return }
        let id = script.id
        lock.lock()
        let skip = images[id] != nil || tried.contains(id)
        if !skip { tried.insert(id) }
        lock.unlock()
        if skip || FileManager.default.fileExists(atPath: file(id).path) { return }
        markPending(id, true)
        let gender = LearnerGender.current == .male ? "male" : "female"
        let request = Request(title: script.title, summary: script.summary,
                              body: String(script.body.prefix(1500)),
                              language: script.language, gender: gender)
        Task.detached(priority: .utility) {
            let outcome = await fetch(request)
            switch outcome {
            case .drawn(let png):
                guard let finished = finish(png), let data = finished.pngData() else {
                    Analytics.capture("speech_cover", ["outcome": "unreadable"])
                    return
                }
                try? data.write(to: file(id), options: .atomic)
                let ready = finished.preparingForDisplay() ?? finished
                lock.lock(); images[id] = ready; lock.unlock()
                await MainActor.run {
                    markPending(id, false)
                    ChallengeArt.arrivals.count += 1
                    Analytics.capture("speech_cover", ["outcome": "drawn"])
                }
            case .refused:
                // Not entitled: nothing to retry until they are.
                await MainActor.run { markPending(id, false) }
                Analytics.capture("speech_cover", ["outcome": "refused"])
            case .failed(let code):
                Analytics.capture("speech_cover", ["outcome": "failed", "status": code])
            }
        }
    }

    /// The scripts whose picture didn't arrive last time, tried once more.
    @MainActor
    static func resume(_ scripts: [SpeechScript]) {
        let pending = loadPending()
        guard !pending.isEmpty else { return }
        for script in scripts where pending.contains(script.id) { ensure(script) }
    }

    @MainActor
    static func remove(id: UUID) {
        try? FileManager.default.removeItem(at: file(id))
        lock.lock(); images[id] = nil; lock.unlock()
        markPending(id, false)
    }

    // MARK: - Network

    private struct Request: Encodable {
        let title: String, summary: String, body: String, language: String, gender: String
    }

    private enum Outcome { case drawn(Data), refused, failed(Int) }

    private static func fetch(_ request: Request) async -> Outcome {
        struct Reply: Decodable { let cover: String }
        guard let base = Secrets.string(for: .supabaseURL),
              let endpoint = URL(string: base)?.appendingPathComponent("/functions/v1/speech-cover"),
              let headers = try? await SupabaseProvider.authorizedHeaders(),
              let body = try? JSONEncoder().encode(request) else { return .failed(0) }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = body
        // A picture takes 20–60 s to draw.
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, response) = try? await URLSession.edgeFunctionsLong.data(for: req),
              let http = response as? HTTPURLResponse else { return .failed(0) }
        if http.statusCode == 402 { return .refused }
        guard http.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let png = Data(base64Encoded: reply.cover) else { return .failed(http.statusCode) }
        return .drawn(png)
    }

    // MARK: - Pending

    @MainActor
    private static func markPending(_ id: UUID, _ on: Bool) {
        var set = loadPending()
        if on { set.insert(id) } else { set.remove(id) }
        if let data = try? JSONEncoder().encode(Array(set)) { try? data.write(to: pendingURL, options: .atomic) }
    }

    private static func loadPending() -> Set<UUID> {
        guard let data = try? Data(contentsOf: pendingURL),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return [] }
        return Set(ids)
    }

    // MARK: - Cut and clean

    /// The cream cut to alpha, then cleaned for the dark card.
    static func finish(_ png: Data) -> UIImage? {
        guard let raw = UIImage(data: png), let keyed = keyBackground(raw) else { return nil }
        return ChallengeArtDefringe.clean(keyed) ?? keyed
    }

    /// The challenge pictures' cut: the paper is whatever colour the border
    /// is, flooded inward while a pixel stays within `near` of it, so cream
    /// INSIDE the figure (a shirt, a sock) stays opaque; the 2 px next to the
    /// paper fade by how far their colour is from it.
    static func keyBackground(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
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

        // The paper's colour: the median of the border.
        var rs: [Int] = [], gs: [Int] = [], bs: [Int] = []
        func sample(_ i: Int) { rs.append(Int(px[i * 4])); gs.append(Int(px[i * 4 + 1])); bs.append(Int(px[i * 4 + 2])) }
        for x in 0..<w { sample(x); sample((h - 1) * w + x) }
        for y in 0..<h { sample(y * w); sample(y * w + w - 1) }
        func median(_ a: [Int]) -> Int { a.sorted()[a.count / 2] }
        let pr = median(rs), pg = median(gs), pb = median(bs)
        func dist(_ i: Int) -> Int {
            max(abs(Int(px[i * 4]) - pr), abs(Int(px[i * 4 + 1]) - pg), abs(Int(px[i * 4 + 2]) - pb))
        }
        let near = 10

        var paper = [Bool](repeating: false, count: n)
        var stack: [Int] = []
        stack.reserveCapacity(n / 4)
        func seed(_ i: Int) { if !paper[i] && dist(i) < near { paper[i] = true; stack.append(i) } }
        for x in 0..<w { seed(x); seed((h - 1) * w + x) }
        for y in 0..<h { seed(y * w); seed(y * w + w - 1) }
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            if x > 0 { seed(i - 1) }
            if x < w - 1 { seed(i + 1) }
            if y > 0 { seed(i - w) }
            if y < h - 1 { seed(i + w) }
        }

        // Distance (in px, up to 2) from the paper, for the ramp.
        var edge = [UInt8](repeating: 3, count: n)
        for i in 0..<n where paper[i] { edge[i] = 0 }
        for pass in 1...2 {
            for i in 0..<n where edge[i] > UInt8(pass) {
                let x = i % w, y = i / w
                let p = UInt8(pass - 1)
                if (x > 0 && edge[i - 1] == p) || (x < w - 1 && edge[i + 1] == p)
                    || (y > 0 && edge[i - w] == p) || (y < h - 1 && edge[i + w] == p) {
                    edge[i] = UInt8(pass)
                }
            }
        }

        for i in 0..<n {
            let a: Float
            if paper[i] { a = 0 }
            else if edge[i] <= 2 { a = min(1, max(0.25, Float(dist(i) - near) / 40)) }
            else { continue }
            // Premultiplied: scale colour with alpha.
            px[i * 4] = UInt8(Float(px[i * 4]) * a)
            px[i * 4 + 1] = UInt8(Float(px[i * 4 + 1]) * a)
            px[i * 4 + 2] = UInt8(Float(px[i * 4 + 2]) * a)
            px[i * 4 + 3] = UInt8(255 * a)
        }

        let out: CGImage? = px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: space, bitmapInfo: info)?.makeImage()
        }
        return out.map { UIImage(cgImage: $0, scale: image.scale, orientation: .up) }
    }
}
