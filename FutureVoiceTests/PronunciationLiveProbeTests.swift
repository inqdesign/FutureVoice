import XCTest
@testable import FutureVoice

/// The pronunciation call's whole path against the LIVE function: the
/// app's own alternates, its request, its decoding and its verdict, on
/// recordings on disk. Skipped unless asked for:
///
///     TEST_RUNNER_PRON_LIVE=<cases.json> TEST_RUNNER_PRON_EMAIL=… TEST_RUNNER_PRON_PASSWORD=…
///
/// `cases.json`: `[{"wav": path, "text": …, "topic": "ko.asp", "language": "ko", "expect": "pass"|"not_yet", "note": …}]`
/// (16 kHz mono WAV). Prints one line per case and a count per language.
final class PronunciationLiveProbeTests: XCTestCase {
    private struct Case: Decodable {
        let wav: String
        let text: String
        let topic: String
        let language: String
        let expect: String
        let note: String?
    }

    func testLive() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["PRON_LIVE"], let email = env["PRON_EMAIL"], let password = env["PRON_PASSWORD"] else {
            throw XCTSkip("set TEST_RUNNER_PRON_LIVE to run")
        }
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        try await SupabaseProvider.shared.auth.signIn(email: email, password: password)
        var tally: [String: (ok: Int, n: Int)] = [:]
        var lines: [String] = []
        for c in cases {
            let wav = try Data(contentsOf: URL(fileURLWithPath: c.wav))
            let alternates = PronunciationContrast.alternates(for: c.text, topicId: c.topic)
            let (result, outcome) = await PronunciationAssessor.assess(
                wav: wav, reference: c.text, language: c.language, surface: "pron_call", alternates: alternates)
            let verdict = PronunciationJudge.verdict(result: result, line: .init(id: UUID(), text: c.text, focus: []),
                                                     said: "", phonemes: [], language: c.language)
            let name: String
            switch verdict {
            case .pass: name = "pass"
            case .notYet: name = "not_yet"
            case .notSmooth: name = "not_smooth"
            case .offScript: name = "off_script"
            case .unheard: name = "unheard"
            }
            let key = "\(c.language) \(c.topic) expect \(c.expect)"
            var t = tally[key] ?? (0, 0)
            t.n += 1
            if name == c.expect { t.ok += 1 }
            tally[key] = t
            let ref = (result?.referenceWords ?? []).map { "\($0.word):\($0.accuracy ?? -1)" }.joined(separator: " ")
            let alt = (result?.alternates ?? []).map { $0.words.map { "\($0.word):\($0.accuracy ?? -1)" }.joined(separator: " ") }
                .joined(separator: " || ")
            lines.append("PRON \(name == c.expect ? "ok  " : "MISS") \(c.language) \(c.topic) expect \(c.expect) got \(name) [\(outcome.rawValue)] \(c.note ?? "") | sent \(alternates) | ref \(ref) | alt \(alt)")
        }
        for l in lines { print(l) }
        for (k, t) in tally.sorted(by: { $0.key < $1.key }) { print("PRONSUM \(k): \(t.ok)/\(t.n)") }
        if let out = env["PRON_OUT"] {
            try lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        }
    }
}
