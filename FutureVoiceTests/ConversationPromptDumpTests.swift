import XCTest
@testable import FutureVoice

/// Writes the LIVE conversation prompt to disk for `scripts/beginner-probe.py`
/// and `scripts/tutor-probe.py`
/// (2026-10-03), so the probe runs exactly what the app sends instead of a
/// reconstruction that can drift. Does nothing unless the runner passes
/// `TEST_RUNNER_PROMPT_DUMP_DIR` (xcodebuild hands `TEST_RUNNER_*` variables
/// to the test process without the prefix).
final class ConversationPromptDumpTests: XCTestCase {

    func testDumpPrompts() throws {
        guard let dir = ProcessInfo.processInfo.environment["PROMPT_DUMP_DIR"] else {
            throw XCTSkip("PROMPT_DUMP_DIR not set")
        }
        // The probes measure the default accent; a simulator that once had a
        // British voice would otherwise dump the variety rule into every prompt.
        // TEST_RUNNER_PROMPT_ACCENT=en-GB dumps as that learner instead.
        let defaults = UserDefaults.standard
        let savedAccent = defaults.string(forKey: VoiceAccentCatalog.storedAccentKey)
        defaults.set(ProcessInfo.processInfo.environment["PROMPT_ACCENT"],
                     forKey: VoiceAccentCatalog.storedAccentKey)
        defer { defaults.set(savedAccent, forKey: VoiceAccentCatalog.storedAccentKey) }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for lang in ["en", "ko", "ja", "de", "es"] {
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
                // Tutor mode, for `scripts/tutor-probe.py` (2026-10-13).
                let tutor = ConversationEngine.conversationSystemPrompt(
                    targetLanguage: lang,
                    nativeLanguage: lang == "ko" ? "en" : "ko",
                    level: level,
                    topPatterns: [],
                    weakVocabAreas: [],
                    topic: "",
                    tutor: true)
                try tutor.write(to: url.appendingPathComponent("\(lang)-\(level.rawValue)-tutor.txt"),
                                atomically: true, encoding: .utf8)
            }
        }
    }
}
