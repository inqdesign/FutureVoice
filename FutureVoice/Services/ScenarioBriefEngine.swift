import Foundation
import UIKit
import UniformTypeIdentifiers

/// The bytes of a file the learner picked for a brief, held in MEMORY only
/// until the reading that uses them has run. The Files app hands the app a
/// security-scoped URL; the composer reads it once, right at the pick, and
/// parks the bytes here by source id so the reading (which runs a screen
/// later, in `SceneWatchView`) never has to reopen the file. Nothing is
/// written to disk — that is the whole point of reading from where the file
/// lives instead of importing it. A miss falls back to the source's bookmark.
@MainActor
final class BriefAttachmentCache {
    static let shared = BriefAttachmentCache()
    private var bytes: [UUID: (data: Data, mime: String)] = [:]

    func put(_ data: Data, mime: String, for id: UUID) { bytes[id] = (data, mime) }
    func take(_ id: UUID) -> (data: Data, mime: String)? { bytes[id] }
    func drop(_ id: UUID) { bytes[id] = nil }
}

/// Reads a picked file WHERE IT LIVES. `fileImporter` returns a URL the app
/// may open only inside `startAccessingSecurityScopedResource`; the bytes
/// come out, a bookmark goes into the brief for "Read again", and the URL is
/// released. No copy in the sandbox, ever.
enum ScenarioAttachmentReader {
    enum ReadError: LocalizedError {
        case tooLarge(Int)
        case unsupported(String)
        case unreadable
        case bookmarkStale

        var errorDescription: String? {
            switch self {
            case .tooLarge(let mb): return explain("That file is over \(mb) MB. Pick a smaller one.")
            case .unsupported(let ext): return explain("Can't read .\(ext) files yet. PDF, images and plain text work.")
            case .unreadable: return explain("Couldn't open that file.")
            case .bookmarkStale: return explain("That file moved or was deleted. Pick it again.")
            }
        }
    }

    static let maxBytes = GeminiClient.maxInlineBytes
    static let maxMB = maxBytes / (1024 * 1024)

    /// Types Gemini reads inline. Anything else (a .docx, a .pages) is
    /// refused with a message rather than uploaded and ignored.
    static let allowedTypes: [UTType] = [.pdf, .image, .plainText, .utf8PlainText, .text, .commaSeparatedText]

    struct Read {
        let source: ScenarioBrief.Source
        let data: Data
        let mime: String
    }

    /// Read a file the Files picker handed over. Runs inside the security
    /// scope and closes it before returning.
    static func read(pickedURL url: URL) throws -> Read {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let (data, mime) = try bytes(at: url)
        let bookmark = try? url.bookmarkData(options: .minimalBookmark,
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil)
        let kind: ScenarioBrief.Source.Kind = mime.hasPrefix("image/") ? .image : .file
        return Read(source: .init(kind: kind, label: url.lastPathComponent, bookmark: bookmark),
                    data: data, mime: mime)
    }

    /// Reopen a file from the bookmark a previous read left behind.
    static func read(bookmark: Data) throws -> (data: Data, mime: String) {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [],
                                 relativeTo: nil, bookmarkDataIsStale: &stale)
        else { throw ReadError.bookmarkStale }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try bytes(at: url)
    }

    /// A photo from the library or the camera: re-encoded as a JPEG of
    /// bounded size, which also drops EXIF and location.
    static func read(image: UIImage, label: String) -> Read? {
        let sized = image.briefSized(maxLongEdge: 1600)
        guard let data = sized.jpegData(compressionQuality: 0.85) else { return nil }
        return Read(source: .init(kind: .image, label: label), data: data, mime: "image/jpeg")
    }

    private static func bytes(at url: URL) throws -> (Data, String) {
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        guard allowedTypes.contains(where: { type.conforms(to: $0) }) else {
            throw ReadError.unsupported(url.pathExtension.isEmpty ? "?" : url.pathExtension)
        }
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw ReadError.unreadable
        }
        guard data.count <= maxBytes else { throw ReadError.tooLarge(maxMB) }
        if type.conforms(to: .image) {
            // HEIC and friends are not on Gemini's list; a JPEG always is.
            guard let img = UIImage(data: data),
                  let jpeg = img.briefSized(maxLongEdge: 1600).jpegData(compressionQuality: 0.85)
            else { throw ReadError.unreadable }
            return (jpeg, "image/jpeg")
        }
        if type.conforms(to: .pdf) { return (data, "application/pdf") }
        return (data, "text/plain")
    }
}

private extension UIImage {
    func briefSized(maxLongEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        let scale = min(1, maxLongEdge / max(longest, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// Fetches a linked page FROM THE PHONE and hands the model its text.
/// Gemini's own `url_context` fetcher is refused by the sites a situation
/// most often links to — measured 2026-10-01 on a LinkedIn job posting:
/// `URL_RETRIEVAL_STATUS_ERROR` with the URL tool alone and with search on
/// beside it, and the model never fell back to searching — while the same
/// URL fetched as a browser returns the whole posting. The learner's own
/// phone asking for a public page is what opening it in Safari does, so the
/// page is read here and `url_context` stays only for a page this cannot
/// read (a login wall, a script-only page, no network).
enum ScenarioLinkReader {
    /// Enough for any posting or listing; a page longer than this is mostly
    /// navigation and "similar jobs".
    static let maxCharacters = 30_000
    /// Under this, what came back is a wall or a shell, not the page.
    static let minCharacters = 300
    private static let maxBytes = 3 * 1024 * 1024
    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// The page's readable text, or nil when it could not be read.
    static func text(of link: String) async -> String? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
        else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Safari's own Accept, byte for byte: LinkedIn answers an unusual
        // one with its bot status (999) about half the time, measured.
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")
        if let lang = Locale.preferredLanguages.first {
            request.setValue(lang, forHTTPHeaderField: "Accept-Language")
        }
        var result = try? await URLSession.shared.data(for: request)
        // 999 is LinkedIn's "looks automated"; a second ask usually passes.
        if (result?.1 as? HTTPURLResponse)?.statusCode == 999 {
            try? await Task.sleep(nanoseconds: 800_000_000)
            result = try? await URLSession.shared.data(for: request)
        }
        guard let (data, response) = result,
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= maxBytes
        else { return nil }
        let mime = http.mimeType?.lowercased() ?? "text/html"
        guard mime.hasPrefix("text/") || mime.contains("html") || mime.contains("xml") else { return nil }
        guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }
        // A login wall answers 200 at its own address.
        if let final = http.url?.path.lowercased(),
           ["/authwall", "/login", "/signin", "/checkpoint"].contains(where: { final.hasPrefix($0) }) {
            return nil
        }
        let text = mime.contains("html") || mime.contains("xml") ? readable(html: raw) : raw
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minCharacters else { return nil }
        return String(trimmed.prefix(maxCharacters))
    }

    /// Title, description and the visible text of an HTML page, one block
    /// per line. Deliberately crude — the model reads it, and a model reads
    /// a page with its menus left in perfectly well; what it cannot read is
    /// script and markup.
    static func readable(html: String) -> String {
        var parts: [String] = []
        if let t = firstMatch(#"<title[^>]*>(.*?)</title>"#, in: html) {
            parts.append("Title: " + decode(t))
        }
        if let d = firstMatch(#"<meta[^>]+(?:name|property)=["'](?:og:)?description["'][^>]*content=["']([^"']*)["']"#, in: html) {
            parts.append("Description: " + decode(d))
        }
        var body = html
        for tag in ["script", "style", "noscript", "svg", "template", "head"] {
            body = body.replacingOccurrences(of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>", with: " ",
                                             options: [.regularExpression, .caseInsensitive])
        }
        body = body.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
        body = body.replacingOccurrences(
            of: "<(?:br|/p|/div|/li|/h[1-6]|/tr|/section|/article|/ul|/ol)\\b[^>]*>", with: "\n",
            options: [.regularExpression, .caseInsensitive])
        body = body.replacingOccurrences(of: "<li\\b[^>]*>", with: "\n• ",
                                         options: [.regularExpression, .caseInsensitive])
        body = body.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let lines = decode(body).components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "[ \\t\u{00A0}]+", with: " ", options: .regularExpression)
                     .trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "•" }
        parts.append(contentsOf: lines)
        return parts.joined(separator: "\n")
    }

    private static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s)
        else { return nil }
        let v = s[r].trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "rsquo": "’", "lsquo": "‘",
        "rdquo": "”", "ldquo": "“", "bull": "•", "middot": "·", "euro": "€",
    ]

    private static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        guard let re = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);") else { return s }
        var out = ""
        var last = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let whole = Range(m.range, in: s), let inner = Range(m.range(at: 1), in: s) else { continue }
            out += s[last..<whole.lowerBound]
            let name = String(s[inner])
            if name.hasPrefix("#x") || name.hasPrefix("#X"), let v = UInt32(name.dropFirst(2), radix: 16),
               let u = Unicode.Scalar(v) {
                out.unicodeScalars.append(u)
            } else if name.hasPrefix("#"), let v = UInt32(name.dropFirst()), let u = Unicode.Scalar(v) {
                out.unicodeScalars.append(u)
            } else if let r = named[name.lowercased()] {
                out += r
            } else {
                out += s[whole]
            }
            last = whole.upperBound
        }
        out += s[last...]
        return out
    }
}

/// ONE Gemini call turns a situation's attached material into a
/// `ScenarioBrief`. Links are read by the model itself (`url_context`), with
/// web search filling what a page would not give up (a login-walled posting
/// still has a company and a title); files ride inline. The call streams so
/// the board in `SceneWatchView` can tick as each section lands — the same
/// pattern as the wrap-up board, and the same rule: nothing is shown before
/// the model has actually written it.
enum ScenarioBriefEngine {

    /// What has landed so far, for the progress board. Counts are nil until
    /// their section has closed.
    struct Progress: Equatable {
        var sourcesRead: [Bool] = []       // one per source, in order
        var summary: Bool = false
        var counterpartFacts: Int? = nil
        var likelyQuestions: Int? = nil
        var learnerFacts: Int? = nil
        var keyExpressions: Int? = nil
    }

    private struct Payload: Decodable {
        struct SourceRead: Decodable {
            let index: Int
            let ok: Bool
            let detail: String?
        }
        let sources: [SourceRead]
        let summary: String
        let counterpart_facts: [String]
        let likely_questions: [String]
        let learner_facts: [String]
        let key_expressions: [String]
    }

    enum BriefError: LocalizedError {
        case nothingToRead
        var errorDescription: String? { explain("Nothing to read — attach a link or a file first.") }
    }

    /// Read every source on the brief and return it filled in. Bytes come
    /// from `BriefAttachmentCache` first, then from each source's bookmark;
    /// a file that can neither be found is marked `readOK = false` and the
    /// reading goes on with the rest.
    @MainActor
    static func read(
        scenario: Scenario,
        persona: UserPersona?,
        targetLanguage: String,
        nativeLanguage: String,
        onProgress: (@MainActor (Progress) -> Void)? = nil
    ) async throws -> ScenarioBrief {
        guard var brief = scenario.brief, brief.hasSources else { throw BriefError.nothingToRead }

        var files: [GeminiClient.Message.InlineFile] = []
        var fileLines: [String] = []
        var linkLines: [String] = []
        var pageTexts: [String] = []
        var unfetchedLinks = 0
        var total = 0
        for (i, src) in brief.sources.enumerated() {
            switch src.kind {
            case .link:
                if let text = await ScenarioLinkReader.text(of: src.label) {
                    linkLines.append("- source \(i + 1) (link, its page text is given below — do not open it): \(src.label)")
                    pageTexts.append("=== source \(i + 1) — page text of \(src.label) ===\n\(text)\n=== end of source \(i + 1) ===")
                } else {
                    linkLines.append("- source \(i + 1) (link): \(src.label)")
                    unfetchedLinks += 1
                }
            case .file, .image:
                var got = BriefAttachmentCache.shared.take(src.id)
                if got == nil, let bm = src.bookmark,
                   let read = try? ScenarioAttachmentReader.read(bookmark: bm) {
                    got = read
                }
                guard let got, total + got.data.count <= GeminiClient.maxInlineBytes else {
                    brief.sources[i].readOK = false
                    brief.sources[i].detail = explain("Couldn't open — pick it again")
                    fileLines.append("- source \(i + 1) (file, NOT ATTACHED — could not be opened): \(src.label)")
                    continue
                }
                total += got.data.count
                files.append(.init(mimeType: got.mime, base64Data: got.data.base64EncodedString()))
                fileLines.append("- source \(i + 1) (file, attached in order): \(src.label)")
            }
        }

        // Tools are for the links the phone could not read; a page whose
        // text is already in the message needs no fetcher.
        let hasLinks = unfetchedLinks > 0
        var user: [String] = ["situation (the learner's own words): \(scenario.environment)"]
        if let p = persona, p.isMinimallyComplete {
            var about: [String] = []
            if !p.occupation.isEmpty { about.append("work: \(p.occupation)") }
            let place = [p.city, p.country].filter { !$0.isEmpty }.joined(separator: ", ")
            if !place.isEmpty { about.append("lives in: \(place)") }
            if !about.isEmpty { user.append("learner: " + about.joined(separator: "; ")) }
        }
        user.append("")
        user.append("sources:")
        user.append(contentsOf: fileLines + linkLines)
        if hasLinks {
            user.append("")
            user.append("Open every link above that has no page text below with the URL tool and read it. If a page cannot be opened, "
                        + "search the web for what it names (the company and the position, the listing) "
                        + "and say in that source's `detail` that you read coverage instead of the page.")
        }
        if !pageTexts.isEmpty {
            user.append("")
            user.append("The page text below was fetched from the link as a browser sees it, menus and all. "
                        + "Read the posting or listing in it and ignore the site's navigation, ads and "
                        + "\"similar\" listings.")
            user.append(contentsOf: pageTexts)
        }
        user.append("")
        user.append("Today is \(ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])).")

        var message = GeminiClient.Message(role: .user, content: user.joined(separator: "\n"))
        message.inlineFiles = files

        let system = systemPrompt(targetLanguage: targetLanguage, nativeLanguage: nativeLanguage,
                                  sourceCount: brief.sources.count)
        let key = "brief-v1:\(scenario.id.uuidString):\(Int(Date().timeIntervalSince1970 / 60))"

        var progress = Progress(sourcesRead: brief.sources.map { _ in false })
        let onPartial: @MainActor (String) -> Void = { partial in
                guard let onProgress else { return }
                var p = progress
                let read = GeminiClient.completedArrayObjects("sources", in: partial)
                for slice in read {
                    if let data = String(slice).data(using: .utf8),
                       let item = try? JSONDecoder().decode(Payload.SourceRead.self, from: data),
                       item.index >= 1, item.index <= p.sourcesRead.count {
                        p.sourcesRead[item.index - 1] = true
                    }
                }
                if GeminiClient.completedStringField("summary", in: partial) != nil { p.summary = true }
                p.counterpartFacts = completedCount("counterpart_facts", in: partial) ?? p.counterpartFacts
                p.likelyQuestions = completedCount("likely_questions", in: partial) ?? p.likelyQuestions
                p.learnerFacts = completedCount("learner_facts", in: partial) ?? p.learnerFacts
                p.keyExpressions = completedCount("key_expressions", in: partial) ?? p.keyExpressions
                if p != progress {
                    progress = p
                    onProgress(p)
                }
        }

        // Tools on only when there is a link to open. If the tool call is
        // refused upstream (a model that lacks it, a page it cannot fetch),
        // the same request runs again on search alone, then with no tools —
        // the files still ride inline either way, and an unopened link is
        // reported as such rather than failing the whole reading.
        var attempts: [(search: Bool, url: Bool)] = hasLinks
            ? [(true, true), (true, false), (false, false)]
            : [(false, false)]
        var payload: Payload? = nil
        var lastError: Error? = nil
        while payload == nil, !attempts.isEmpty {
            let a = attempts.removeFirst()
            do {
                payload = try await GeminiClient.shared.sendJSONStreamAccumulating(
                    system: system,
                    messages: [message],
                    model: .flash36,
                    maxTokens: 4000,
                    purpose: "brief",
                    idempotencyKey: key + (a.url ? "" : (a.search ? ":s" : ":n")),
                    requestTimeout: 90,
                    searchGrounding: a.search,
                    urlContext: a.url,
                    onPartial: onPartial)
            } catch {
                lastError = error
                if attempts.isEmpty { throw error }
            }
        }
        guard let payload else { throw lastError ?? BriefError.nothingToRead }

        for read in payload.sources where read.index >= 1 && read.index <= brief.sources.count {
            let i = read.index - 1
            // A file the app could not open stays "not read" whatever the
            // model says about it — it never saw the bytes.
            if brief.sources[i].readOK {
                brief.sources[i].readOK = read.ok
                if let d = read.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
                    brief.sources[i].detail = d
                }
            }
        }
        brief.summary = payload.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        brief.counterpartFacts = clean(payload.counterpart_facts, max: 8)
        brief.likelyQuestions = clean(payload.likely_questions, max: 10)
        brief.learnerFacts = clean(payload.learner_facts, max: 8)
        brief.keyExpressions = clean(payload.key_expressions, max: 14)
        brief.readAt = Date()
        for src in brief.sources { BriefAttachmentCache.shared.drop(src.id) }
        onProgress?(Progress(sourcesRead: brief.sources.map { _ in true }, summary: true,
                             counterpartFacts: brief.counterpartFacts.count,
                             likelyQuestions: brief.likelyQuestions.count,
                             learnerFacts: brief.learnerFacts.count,
                             keyExpressions: brief.keyExpressions.count))
        return brief
    }

    private static func clean(_ list: [String], max: Int) -> [String] {
        var seen = Set<String>()
        return list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(max).map { $0 }
    }

    /// Number of closed string elements in a string array that has itself
    /// closed; nil while the array is still being written.
    private static func completedCount(_ name: String, in partial: String) -> Int? {
        guard let range = partial.range(of: "\"\(name)\"") else { return nil }
        guard let open = partial[range.upperBound...].firstIndex(of: "[") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var count = 0
        var i = open
        while i < partial.endIndex {
            let ch = partial[i]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false; if depth == 1 { count += 1 } }
            } else {
                switch ch {
                case "\"": inString = true
                case "[": depth += 1
                case "]":
                    depth -= 1
                    if depth == 0 { return count }
                default: break
                }
            }
            i = partial.index(after: i)
        }
        return nil
    }

    private static func systemPrompt(targetLanguage: String, nativeLanguage: String, sourceCount: Int) -> String {
        let target = LanguageCatalog.englishName(targetLanguage)
        let native = LanguageCatalog.englishName(nativeLanguage)
        return """
        A language learner is about to go into a real situation and has attached \
        material for it: a job posting and their CV, a listing, a letter, a \
        slide deck, a photo of a form. You read the material ONCE and write a \
        brief the app will use to simulate the situation — a scene in which a \
        fluent version of the learner handles it, and a live role-play call in \
        which the learner practices their side.

        TWO SIDES, KEPT APART. Sort every fact by whose it is:
        - the OTHER side (the company, the position, the landlord, the clinic): \
          who they are, what they want, how they talk, and what they will ASK. \
          A CV is never the other side's material.
        - the LEARNER's side (their CV, their portfolio, their letter): what \
          they have done, the numbers they can quote, the gaps they will be \
          asked about, what to prepare an answer for.
        Never hand the learner's facts to the other side to recite, and never \
        invent a fact that is in neither source. Where a link could not be \
        read and search gave only the company name, say so in `detail` and \
        keep the facts thin rather than guessed.

        OUTPUT LANGUAGE, FIELD BY FIELD:
        - `likely_questions` and `key_expressions` are MATERIAL — what will be \
          said out loud in the situation — so they are in \(target), natural \
          spoken register for this exact setting.
        - `summary`, `counterpart_facts`, `learner_facts` and every `detail` \
          are NOTES the learner reads, so they are in \(native). Keep proper \
          names, product names and numbers as they appear in the source.

        Return STRICT JSON only — no prose, no code fences — with the keys in \
        EXACTLY this order (the app reads progress off which key has closed):
        {
          "sources": [ { "index": 1, "ok": true, "detail": "..." } ],
          "summary": "...",
          "counterpart_facts": ["..."],
          "likely_questions": ["..."],
          "learner_facts": ["..."],
          "key_expressions": ["..."]
        }

        Rules:
        - sources: one entry per source, \(sourceCount) in total, in the order \
          given. ok=false when you could not read it. detail = ONE short \
          fragment saying what it is ("job posting · Berlin", "CV, 3 pages", \
          "listing, 2 rooms") — never a sentence about what you did.
        - summary: one line naming what this is about — the company and the \
          position, the flat and the street, the clinic and the visit.
        - counterpart_facts: 4–8 short lines. What the other side is, what \
          they are looking for, anything they state they care about.
        - likely_questions: 6–10 lines the other side would actually say or \
          ask in this situation, grounded in THEIR material. Vary the beats: \
          openers, follow-ups, the awkward one.
        - learner_facts: 3–8 short lines from the learner's OWN material: the \
          points worth bringing up, the numbers to quote, the gap or weak spot \
          to have an answer for, the overlap between their material and the \
          other side's.
        - key_expressions: 8–14 reusable chunks (2–6 words) this situation \
          calls for — collocations, softeners, the moves natives make here. \
          No full sentences, no single words.
        - Empty arrays are fine where a source did not give you the material. \
          Never pad.
        """
    }
}
