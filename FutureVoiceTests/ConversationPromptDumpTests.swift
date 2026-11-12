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
                // Tutor mode with a lesson on challenge 2, for the lesson probe
                // (2026-10-24): one plain, one just ticked, one finished.
                let lesson = TutorLesson(
                    id: UUID(), title: "Self-intro", titleTarget: "Introducing yourself",
                    language: lang,
                    challenges: [
                        .init(id: UUID(), goal: "name", task: "Say your name and where you're from",
                              example: "I'm Minji, and I'm from Busan.", doneAt: Date(), line: "I'm Minji, from Busan."),
                        .init(id: UUID(), goal: "work", task: "Say what you do for work or study",
                              example: "I work as a nurse at a hospital."),
                        .init(id: UUID(), goal: "whole", task: "Introduce yourself in one go: name, where you're from, what you do",
                              example: "Hi, I'm Minji. I'm from Busan, and I work as a nurse."),
                    ],
                    createdAt: Date())
                var afterTick = lesson
                afterTick.challenges[1].doneAt = Date()
                afterTick.challenges[1].line = "I work as an engineer at a car company."
                var finished = afterTick
                finished.challenges[2].doneAt = Date()
                finished.challenges[2].line = "Hi, I'm Minji. I'm from Busan, and I work as a nurse."
                finished.finishedAt = Date()
                for (name, l, ticked) in [("lesson", lesson, false), ("ticked", afterTick, true),
                                          ("done", finished, true)] as [(String, TutorLesson, Bool)] {
                    let p = ConversationEngine.conversationSystemPrompt(
                        targetLanguage: lang, nativeLanguage: lang == "ko" ? "en" : "ko",
                        level: level, topPatterns: [], weakVocabAreas: [], topic: "",
                        tutor: true, tutorLesson: l, tutorJustTicked: ticked)
                    try p.write(to: url.appendingPathComponent("\(lang)-\(level.rawValue)-tutor-\(name).txt"),
                                atomically: true, encoding: .utf8)
                }
                // The tutor judging a challenge's tries itself (2026-11-13),
                // plain and for a real goal.
                for (name, goal) in [("self", nil), ("self-goal", "interview: Lufthansa flight attendant at Munich, no date set")] as [(String, String?)] {
                    let p = ConversationEngine.conversationSystemPrompt(
                        targetLanguage: lang, nativeLanguage: lang == "ko" ? "en" : "ko",
                        level: level, topPatterns: [], weakVocabAreas: [], topic: "",
                        tutor: true, tutorLesson: lesson, tutorSelfJudges: true, tutorRealGoal: goal)
                    try p.write(to: url.appendingPathComponent("\(lang)-\(level.rawValue)-tutor-\(name).txt"),
                                atomically: true, encoding: .utf8)
                }
            }
        }
    }
}
