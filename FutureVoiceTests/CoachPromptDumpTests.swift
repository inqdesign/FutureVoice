import XCTest
@testable import FutureVoice

/// Writes the LIVE coach-suggestion prompt (`CoachSuggester.system`) to disk
/// for `scripts/coach-probe.py` (2026-10-21), which runs it on 3.6-flash and
/// on Claude Haiku side by side. Does nothing unless the runner passes
/// `TEST_RUNNER_PROMPT_DUMP_DIR`.
final class CoachPromptDumpTests: XCTestCase {

    @MainActor
    func testDumpCoachPrompts() throws {
        guard let dir = ProcessInfo.processInfo.environment["PROMPT_DUMP_DIR"] else {
            throw XCTSkip("PROMPT_DUMP_DIR not set")
        }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for lang in ["en", "ko", "ja", "de", "es", "fr"] {
            for level in CEFRLevel.allCases {
                let prompt = CoachSuggester.system(target: lang, native: lang == "ko" ? "en" : "ko",
                                                   level: level, register: nil)
                try prompt.write(to: url.appendingPathComponent("coach-\(lang)-\(level.rawValue).txt"),
                                 atomically: true, encoding: .utf8)
            }
        }
    }
}
