import XCTest
@testable import FutureVoice

/// Writes the LIVE conversation prompt to disk for `scripts/beginner-probe.py`
/// (2026-10-03), so the probe runs exactly what the app sends instead of a
/// reconstruction that can drift. Does nothing unless the runner passes
/// `TEST_RUNNER_PROMPT_DUMP_DIR` (xcodebuild hands `TEST_RUNNER_*` variables
/// to the test process without the prefix).
final class ConversationPromptDumpTests: XCTestCase {

    func testDumpPrompts() throws {
        guard let dir = ProcessInfo.processInfo.environment["PROMPT_DUMP_DIR"] else {
            throw XCTSkip("PROMPT_DUMP_DIR not set")
        }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for lang in ["en", "ko", "ja", "de"] {
            for level in [CEFRLevel.a1, .a2, .b1] {
                for first in [false, true] {
                    let prompt = ConversationEngine.conversationSystemPrompt(
                        targetLanguage: lang,
                        nativeLanguage: lang == "ko" ? "en" : "ko",
                        level: level,
                        topPatterns: [],
                        weakVocabAreas: [],
                        topic: "",
                        firstMeeting: first)
                    let name = "\(lang)-\(level.rawValue)\(first ? "-first" : "").txt"
                    try prompt.write(to: url.appendingPathComponent(name), atomically: true, encoding: .utf8)
                }
            }
        }
    }
}
