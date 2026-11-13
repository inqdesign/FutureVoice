import CryptoKit
import Foundation

/// A challenge's fluent reading to LISTEN to (2026-11-13, founder): one audio
/// file per challenge, in the one voice it was published with. The challenge
/// page opens on its first lines fading in; the script sheet plays it whole
/// with the words lighting up as it goes, and marks where the reader breathes
/// and where words run together.
///
/// Separate from the scoring references (`SpeechReferenceService`): those
/// keep only word times, in two voices, and the board is scored against them
/// unchanged. This is its own take, kept as audio in R2 by `speech-reference`
/// (`listen: true`), made once by whoever opens the challenge first.
struct SpeechListenAudio: Codable {
    var version: Int
    var gender: String
    var url: URL
    var words: [SpeechReference.Word]
}

enum SpeechListenService {
    /// Only challenges have one, and only in a language the reference is
    /// made for.
    static func available(for script: SpeechScript) -> Bool {
        script.isChallenge && SpeechReading.applies(to: script.language)
    }

    private static var directory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("speech_listen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func digest(_ script: SpeechScript) -> String {
        SHA256.hash(data: Data("\(script.language)|\(script.body)".utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    /// The reading's words and its audio on this phone (Caches: iOS may clear
    /// it, and the next open fetches it again). nil when there is none.
    static func load(_ script: SpeechScript) async -> (audio: SpeechListenAudio, file: URL)? {
        guard available(for: script) else { return nil }
        let key = digest(script)
        let meta = directory.appendingPathComponent("\(key).json")
        let file = directory.appendingPathComponent("\(key).wav")
        var audio = (try? Data(contentsOf: meta)).flatMap { try? JSONDecoder().decode(SpeechListenAudio.self, from: $0) }
        if audio == nil {
            audio = await fetch(script)
            if let audio, let data = try? JSONEncoder().encode(audio) { try? data.write(to: meta, options: .atomic) }
        }
        guard let audio else { return nil }
        if !FileManager.default.fileExists(atPath: file.path) {
            guard let (tmp, response) = try? await URLSession.shared.download(from: audio.url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            try? FileManager.default.removeItem(at: file)
            guard (try? FileManager.default.moveItem(at: tmp, to: file)) != nil else { return nil }
        }
        return (audio, file)
    }

    private static func fetch(_ script: SpeechScript) async -> SpeechListenAudio? {
        struct Body: Encodable {
            let text: String; let language: String; let listen = true; let challenge: String
        }
        let challenge = (script.challengeId ?? script.id).uuidString.lowercased()
        guard let base = Secrets.string(for: .supabaseURL),
              let endpoint = URL(string: base)?.appendingPathComponent("/functions/v1/speech-reference"),
              let headers = try? await SupabaseProvider.authorizedHeaders(),
              let body = try? JSONEncoder().encode(Body(text: script.body, language: String(script.language.prefix(2)),
                                                        challenge: challenge)) else { return nil }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, response) = try? await URLSession.edgeFunctionsBackground.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let audio = try? JSONDecoder().decode(SpeechListenAudio.self, from: data),
              !audio.words.isEmpty else { return nil }
        return audio
    }
}

/// The script as the read-along draws it: paragraphs of the words as written
/// (punctuation kept), each with when the fluent reader said it and what
/// follows it.
struct SpeechListenText {
    struct Token {
        let text: String
        /// When the reader starts and ends it, in seconds. A word the timing
        /// missed takes the end of the word before it.
        let start: Double
        let end: Double
        /// The reader takes a breath after it, where the script has no
        /// sentence end.
        var breath = false
        /// It runs into the next word with no break.
        var runsOn = false
    }

    let paragraphs: [[Token]]

    /// A stop this long or more is a breath (0.25 s: the calibration's own cut
    /// for a silence worth cutting at; my choice to reuse it here).
    static let breathSeconds = 0.25
    /// Words this close are said as one (no measurable gap). My choice.
    static let runOnSeconds = 0.03

    /// A word as written in the script (whitespace to whitespace, as the
    /// result page's marked script counts them), with when it was said.
    struct Display {
        let para: Int
        let text: String
        /// Seconds; nil when no timed word lined up with it.
        let time: (start: Double, end: Double)?
    }

    /// Lines timed words (Azure's, in ms) up with the script's written words.
    static func display(body: String, words: [SpeechReference.Word]) -> [Display] {
        let paragraphTexts = ScriptStudy.paragraphs(body)
        var written: [(para: Int, text: String, parts: [String])] = []
        for (p, para) in paragraphTexts.enumerated() {
            for raw in para.split(whereSeparator: { $0.isWhitespace }) {
                let text = String(raw)
                let parts = text.lowercased().replacingOccurrences(of: "’", with: "'")
                    .split { !($0.isLetter || $0.isNumber || $0 == "'") }
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
                    .filter { !$0.isEmpty }
                written.append((p, text, parts))
            }
        }
        let flat = written.flatMap(\.parts)
        let said = words.map { SpeechDelivery.core($0.w) }
        let match = SpeechDelivery.align(said, flat)
        var times = [(Double, Double)?](repeating: nil, count: flat.count)
        for (i, m) in match.enumerated() {
            if let m { times[m] = (Double(words[i].s) / 1000, Double(words[i].e) / 1000) }
        }
        var out: [Display] = []
        var cursor = 0
        for w in written {
            let range = cursor..<(cursor + w.parts.count)
            cursor += w.parts.count
            let timed = range.compactMap { times[$0] }
            if let first = timed.first, let last = timed.last {
                out.append(Display(para: w.para, text: w.text, time: (first.0, last.1)))
            } else {
                out.append(Display(para: w.para, text: w.text, time: nil))
            }
        }
        return out
    }

    init(body: String, words: [SpeechReference.Word]) {
        let paragraphTexts = ScriptStudy.paragraphs(body)
        var tokens: [(para: Int, token: Token)] = []
        var lastEnd = 0.0
        for d in Self.display(body: body, words: words) {
            let start = d.time?.start ?? lastEnd
            let end = d.time?.end ?? start
            lastEnd = end
            tokens.append((d.para, Token(text: d.text, start: start, end: end)))
        }
        for i in tokens.indices.dropLast() where tokens[i].para == tokens[i + 1].para {
            let gap = tokens[i + 1].token.start - tokens[i].token.end
            let tail = tokens[i].token.text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)]»"))
            let endsSentence = tail.last.map { ".!?…".contains($0) } ?? false
            let endsClause = tail.last.map { ",;:—–".contains($0) } ?? false
            if gap >= Self.breathSeconds, !endsSentence {
                tokens[i].token.breath = true
            } else if gap < Self.runOnSeconds, !endsSentence, !endsClause,
                      Self.links(tokens[i].token.text, into: tokens[i + 1].token.text) {
                tokens[i].token.runsOn = true
            }
        }
        var out = Array(repeating: [Token](), count: paragraphTexts.count)
        for t in tokens { out[t.para].append(t.token) }
        paragraphs = out
    }

    /// Words a fluent reader joins: a word ending in a consonant sound
    /// carried into one that starts with a vowel ("come‿a", "room‿at").
    /// Spelling stands in for sound, so it is a rule of thumb, not a
    /// measurement.
    static func links(_ word: String, into next: String) -> Bool {
        let a = SpeechDelivery.core(word), b = SpeechDelivery.core(next)
        guard let last = a.last, let first = b.first else { return false }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        guard vowels.contains(first) else { return false }
        // "come", "there's", "room": the sound before the next word is a
        // consonant. A final silent e after a consonant counts as one.
        if !vowels.contains(last) && last != "y" && last != "w" { return true }
        let letters = Array(a)
        return last == "e" && letters.count >= 3 && !vowels.contains(letters[letters.count - 2])
    }

    var duration: Double { paragraphs.last?.last?.end ?? 0 }

    /// The end of the first sentence that finishes at or after `seconds`:
    /// where the challenge page's intro fades out.
    func sentenceEnd(after seconds: Double) -> Double? {
        for t in paragraphs.joined() where t.end >= seconds {
            let tail = t.text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)]»"))
            if let c = tail.last, ".!?…".contains(c) { return t.end }
        }
        return nil
    }
}
