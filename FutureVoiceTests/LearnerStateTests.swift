import XCTest
@testable import FutureVoice

/// The learner state (docs/personal-report-plan.md, step 3): the status rule,
/// the quote check every tagged verdict passes, and idempotency per talk.
final class LearnerStateTests: XCTestCase {

    private var dir: URL!
    private var store: LearnerStateStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("learner-state-\(UUID().uuidString)", isDirectory: true)
        let root = dir!
        store = LearnerStateStore(directory: { code in
            let d = root.appendingPathComponent(code, isDirectory: true)
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            return d
        })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private var map: LevelMap {
        guard let m = LevelMap.load("en") else {
            XCTFail("level_map_en.json is not in the app bundle")
            fatalError()
        }
        return m
    }

    // MARK: - Map

    func testEnglishMapLoadsAndOtherLanguagesStandDown() {
        XCTAssertEqual(map.grammar.count, 43)
        XCTAssertEqual(map.functions.count, 16)
        XCTAssertNotNil(LevelMap.load("en-GB"))
        XCTAssertNil(LevelMap.load("ko"))
        XCTAssertNil(LevelMap.load("de"))
    }

    // MARK: - Status rule

    func testStatusRule() {
        XCTAssertEqual(LearnerState.status(right: 0, wrong: 0, rightTalks: 0), .unseen)
        XCTAssertEqual(LearnerState.status(right: 1, wrong: 0, rightTalks: 1), .tried)
        // Plenty of right uses, but all in one talk: one lucky talk isn't command.
        XCTAssertEqual(LearnerState.status(right: 5, wrong: 0, rightTalks: 1), .tried)
        XCTAssertEqual(LearnerState.status(right: 3, wrong: 0, rightTalks: 2), .solid)
        XCTAssertEqual(LearnerState.status(right: 0, wrong: 1, rightTalks: 0), .shaky)
        // 75% right is under the bar; 80% is on it.
        XCTAssertEqual(LearnerState.status(right: 3, wrong: 1, rightTalks: 2), .shaky)
        XCTAssertEqual(LearnerState.status(right: 4, wrong: 1, rightTalks: 2), .solid)
    }

    // MARK: - Quote check

    func testNormalizationDropsFillersStuttersAndPunctuation() {
        XCTAssertEqual(LevelTagger.normalized("I am uh I am working on uh a new app."),
                       "i am working on a new app")
        XCTAssertEqual(LevelTagger.normalized("I I I went, um, to Busan!"), "i went to busan")
        XCTAssertEqual(LevelTagger.normalized("I’m fine"), "i'm fine")
    }

    func testQuoteMustBeTheLearners() {
        let lines = ["I am uh I am working on uh a new app.", "Yesterday I go to the office"]
        XCTAssertTrue(LevelTagger.isTheirs("I am working on a new app", in: lines))
        XCTAssertTrue(LevelTagger.isTheirs("yesterday I go to the office", in: lines))
        XCTAssertFalse(LevelTagger.isTheirs("I have been working on a new app", in: lines))
        XCTAssertFalse(LevelTagger.isTheirs("", in: lines))
        XCTAssertFalse(LevelTagger.isTheirs("uh um", in: lines))
    }

    func testVerifyDropsUnverifiedAndUnknownItems() {
        let evidence = ["Yesterday I go to Busan with my friends.", "I'm going to start a new project."]
        let payload = LevelTagger.Payload(grammar: [
            .init(id: "past_simple", right: 0, wrong: 1, wrongQuote: "Yesterday I go to Busan"),
            // The AI's sentence, not theirs.
            .init(id: "present_perfect_experience", right: 1, wrong: 0,
                  rightQuote: "Have you ever been to Busan"),
            .init(id: "going_to", right: 1, wrong: 0, rightQuote: "I'm going to start a new project"),
            .init(id: "not_on_the_map", right: 2, wrong: 0, rightQuote: "Yesterday I go to Busan"),
            // A right count whose wrong quote is missing: both must be theirs.
            .init(id: "will", right: 1, wrong: 1, rightQuote: "I'm going to start", wrongQuote: ""),
        ], functions: [
            .init(id: "past_event", quote: "I go to Busan with my friends"),
            .init(id: "plans", quote: "I will start a company"),
        ])
        let (items, dropped) = LevelTagger.verify(payload, map: map, evidence: evidence)
        XCTAssertEqual(Set(items.map(\.id)), ["past_simple", "going_to", "past_event"])
        XCTAssertEqual(dropped, 3)
        XCTAssertEqual(items.first { $0.id == "past_simple" }?.quotes.first?.right, false)
    }

    func testTranscriptKeepsOnlyEvidenceLines() {
        var drill = Turn(id: UUID(), role: .user, transcript: "I am a nurse.", durationMs: 0,
                         timestamp: Date())
        drill.tutorRole = .drill
        var misheard = Turn(id: UUID(), role: .user, transcript: "banana phone", durationMs: 0,
                            timestamp: Date())
        misheard.excludedFromScoring = true
        let turns = [
            Turn(id: UUID(), role: .fluentSelf, transcript: "What do you do?", durationMs: 0,
                 timestamp: Date()),
            Turn(id: UUID(), role: .user, transcript: "I work in hospital.", durationMs: 0,
                 timestamp: Date()),
            drill, misheard,
        ]
        XCTAssertEqual(LevelTagger.transcript(turns), "AI: What do you do?\nUSER: I work in hospital.")
        XCTAssertEqual(LevelTagger.evidenceLines(turns), ["I work in hospital."])
    }

    // MARK: - Idempotency

    private func tag(_ items: [LearnerState.ItemTag], fingerprint: String = "f1",
                     date: Date = Date()) -> LearnerState.SessionTag {
        .init(talkDate: date, taggedAt: Date(), fingerprint: fingerprint, mapVersion: map.version,
              items: items)
    }

    func testTaggingTheSameTalkTwiceDoesNotDoubleCount() {
        let id = UUID()
        let t = tag([.init(id: "past_simple", kind: .grammar, right: 2, wrong: 1,
                           quotes: [.init(text: "I go yesterday", right: false)])])
        store.record(t, sessionId: id, language: "en")
        store.record(t, sessionId: id, language: "en")
        let past = store.items(language: "en").first { $0.id == "past_simple" }
        XCTAssertEqual(past?.right, 2)
        XCTAssertEqual(past?.wrong, 1)
        XCTAssertEqual(past?.talks, 1)
        XCTAssertFalse(store.needsTagging(sessionId: id, fingerprint: "f1",
                                          mapVersion: map.version, language: "en"))
        // The talk grew: tagged again, and the new verdicts REPLACE the old.
        XCTAssertTrue(store.needsTagging(sessionId: id, fingerprint: "f2",
                                         mapVersion: map.version, language: "en"))
        store.record(tag([.init(id: "past_simple", kind: .grammar, right: 4, wrong: 0, quotes: [])],
                         fingerprint: "f2"), sessionId: id, language: "en")
        XCTAssertEqual(store.items(language: "en").first { $0.id == "past_simple" }?.right, 4)
    }

    func testStatePersistsAndAggregatesAcrossTalks() {
        let old = Date(timeIntervalSinceNow: -86_400 * 3)
        store.record(tag([.init(id: "past_simple", kind: .grammar, right: 1, wrong: 1,
                                quotes: [.init(text: "I go yesterday", right: false),
                                         .init(text: "I went home", right: true)])], date: old),
                     sessionId: UUID(), language: "en")
        store.record(tag([.init(id: "past_simple", kind: .grammar, right: 3, wrong: 0,
                                quotes: [.init(text: "we ate seafood", right: true)])]),
                     sessionId: UUID(), language: "en")
        // A fresh store reads the same file.
        let root = dir!
        let reread = LearnerStateStore(directory: { root.appendingPathComponent($0, isDirectory: true) })
        let past = reread.items(language: "en").first { $0.id == "past_simple" }!
        XCTAssertEqual(past.right, 4)
        XCTAssertEqual(past.wrong, 1)
        XCTAssertEqual(past.talks, 2)
        XCTAssertEqual(past.status, .solid)
        XCTAssertEqual(past.quotes.map(\.text), ["we ate seafood", "I go yesterday", "I went home"])
        // The file stores dates as ISO 8601, to the second.
        XCTAssertEqual(past.firstSeen?.timeIntervalSince1970 ?? 0, old.timeIntervalSince1970, accuracy: 1)
    }

    func testFailuresStopAfterTheLimitAndDeletedTalksAreForgotten() {
        let id = UUID()
        for _ in 0..<LearnerState.maxFailures { store.recordFailure(sessionId: id, language: "en") }
        XCTAssertFalse(store.needsTagging(sessionId: id, fingerprint: "f", mapVersion: map.version,
                                          language: "en"))
        let kept = UUID()
        store.record(tag([.init(id: "be", kind: .grammar, right: 1, wrong: 0, quotes: [])]),
                     sessionId: kept, language: "en")
        store.record(tag([.init(id: "can", kind: .grammar, right: 1, wrong: 0, quotes: [])]),
                     sessionId: UUID(), language: "en")
        store.forgetSessions(notIn: [kept], language: "en")
        XCTAssertEqual(store.state(language: "en").sessions.keys.sorted(), [kept.uuidString])
    }

    func testFailuresFromBeforeTheFixAreForgivenOnce() throws {
        let json = #"{"version":1,"sessions":{},"failures":{"talk":2}}"#
        let old = try JSONDecoder().decode(LearnerState.self, from: Data(json.utf8))
        XCTAssertEqual(old.failures["talk"], 2)
        var cleared = old.clearingOldFailures()
        XCTAssertTrue(cleared.failures.isEmpty)
        XCTAssertEqual(cleared.failuresEpoch, LearnerState.failuresEpoch)
        cleared.failures["talk"] = 1
        XCTAssertEqual(cleared.clearingOldFailures().failures["talk"], 1)
    }

    func testEveryTaggingRequestHasItsOwnKey() {
        let id = UUID()
        let first = LevelTagger.requestKey(sessionId: id, fingerprint: "f")
        XCTAssertNotEqual(first, LevelTagger.requestKey(sessionId: id, fingerprint: "f"))
        XCTAssertTrue(first.hasPrefix("level-tag:\(id.uuidString):f:"))
    }

    // MARK: - Prompt block

    func testPromptLinesOrderPrerequisitesFirstThenShakyBeforeUnseen() {
        XCTAssertEqual(store.promptLines(language: "en", level: .a2), "", "nothing tagged yet")
        XCTAssertEqual(store.promptLines(language: "ko", level: .a2), "", "no map")

        let id = UUID()
        store.record(tag([
            .init(id: "be", kind: .grammar, right: 3, wrong: 0, quotes: []),
            .init(id: "past_simple", kind: .grammar, right: 1, wrong: 2,
                  quotes: [.init(text: "I go yesterday", right: false)]),
            .init(id: "going_to", kind: .grammar, right: 1, wrong: 0,
                  quotes: [.init(text: "I'm going to start", right: true)]),
            .init(id: "introduce", kind: .function, right: 1, wrong: 0, quotes: []),
        ]), sessionId: id, language: "en")
        store.record(tag([.init(id: "be", kind: .grammar, right: 2, wrong: 0, quotes: [])],
                         fingerprint: "g"), sessionId: UUID(), language: "en")

        let text = store.promptLines(language: "en", level: .a2)
        let lines = text.components(separatedBy: "\n")
        XCTAssertLessThanOrEqual(lines.count, LearnerStateStore.maxPromptLines)
        XCTAssertTrue(lines[0].contains("level A2, next B1"))
        XCTAssertTrue(lines[1].hasPrefix("Solid: be: am / is / are"))
        let order = lines.filter { $0.hasPrefix("- ") }
        func at(_ id: String) -> Int { order.firstIndex { $0.contains("(\(id),") } ?? -1 }
        // Shaky first, with the learner's error.
        XCTAssertTrue(order[0].contains("past_simple") && order[0].contains("\"I go yesterday\""))
        XCTAssertLessThan(at("going_to"), at("present_perfect_experience"), "tried before unseen")
        // present perfect needs past simple, which is a gap: never before it.
        XCTAssertLessThan(at("past_simple"), at("present_perfect_experience"))
        XCTAssertLessThan(at("present_perfect_experience"), at("present_perfect_since_for"))
        // An unseen A1 item, below the current level, is not named.
        XCTAssertEqual(at("there_is"), -1)
        XCTAssertTrue(text.contains("Can do: introduce yourself"))
    }
}
