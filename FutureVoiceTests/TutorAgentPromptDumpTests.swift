import XCTest
@testable import FutureVoice

/// Writes the tutor chat's prompt (everything but the learner's own data)
/// for `scripts/tutor-agent-probe.py`, which supplies a fixture learner and
/// fixture lookup results. Skips unless `TEST_RUNNER_PROMPT_DUMP_DIR` is set.
@MainActor
final class TutorAgentPromptDumpTests: XCTestCase {
    func testDumpTutorAgentRules() throws {
        guard let dir = ProcessInfo.processInfo.environment["PROMPT_DUMP_DIR"] else {
            throw XCTSkip("PROMPT_DUMP_DIR not set")
        }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (native, target) in [("ko", "en"), ("en", "de"), ("ko", "ja")] {
            try TutorChat.rules(native: native, target: target)
                .write(to: url.appendingPathComponent("tutor-agent-\(native)-\(target).txt"),
                       atomically: true, encoding: .utf8)
        }
    }

    /// A reply with a bad button still yields the good one, and an unknown
    /// type never becomes a dead button.
    func testActionsDecodeLeniently() throws {
        let json = #"[{"type":"lesson","topic":"Why Lufthansa"},{"type":"teleport"},{"type":"review","label":"  "}]"#
        struct Lenient: Decodable {
            var action: TutorAction?
            init(from decoder: Decoder) throws { action = try? TutorAction(from: decoder) }
        }
        let decoded = try JSONDecoder().decode([Lenient].self, from: Data(json.utf8)).compactMap(\.action)
        XCTAssertEqual(decoded.map(\.type), [.lesson, .review])
        XCTAssertNil(decoded[1].label)
    }

    func testTodayRanksNowThenGoalThenRoutine() {
        let day = Calendar.current.startOfDay(for: Date())
        let now = day.addingTimeInterval(10 * 3600)
        func item(_ id: String, _ kind: StudyPlan.Kind, at h: Double, mins: Double = 10, progress: Double = 0) -> TutorBot.Item {
            let start = day.addingTimeInterval(h * 3600)
            return TutorBot.Item(id: id, kind: kind, title: id, start: start, anytime: false,
                                 progress: progress, end: start.addingTimeInterval(mins * 60))
        }
        var today = TutorBot.Today(day: day)
        today.items = [item("talk8", .talk, at: 8, progress: 1), item("review21", .review, at: 21)]
        let goal = TutorPick(id: "goal-read-x", kind: .goalReading, title: "Reading", why: "", action: .readNews(SuggestedTopic(title: "t", blurb: "b")))
        let ep = TutorPick(id: "ep-1", kind: .newEpisode, title: "Episode", why: "", action: .readNews(SuggestedTopic(title: "t", blurb: "b")))
        let ranked = TutorToday.ranked(today: today, picks: [ep, goal], now: now)
        XCTAssertEqual(ranked.map(\.id), ["p-goal-read-x", "r-review21", "p-ep-1", "r-talk8"])

        // Two routine blocks left: both come before a pick.
        var two = today
        two.items[0] = item("talk8", .talk, at: 8, progress: 0.5)
        XCTAssertEqual(TutorToday.ranked(today: two, picks: [ep], now: now).map(\.id).prefix(3),
                       ["r-review21", "r-talk8", "p-ep-1"])

        // A block whose time is on comes before everything.
        today.items.append(item("shadow10", .shadow, at: 9.9, mins: 20))
        XCTAssertEqual(TutorToday.ranked(today: today, picks: [ep, goal], now: now).first?.id, "r-shadow10")
    }
}
