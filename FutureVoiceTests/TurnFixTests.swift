import XCTest
@testable import FutureVoice

/// A turn is answered twice since 2026-09-27: `alternative` is the WHOLE turn
/// re-said, `fixes` are the grammar slips in it. Everything that used to read
/// `alternative` as "the correction" had to learn the difference, and each
/// test here pins one place that got it wrong on the first pass.
@MainActor
final class TurnFixTests: XCTestCase {

    private func withActiveLanguage<T>(_ code: String, _ body: () throws -> T) rethrows -> T {
        let key = LanguageCatalog.targetLanguageDefaultsKey
        let saved = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(code, forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        return try body()
    }

    private func payload(_ json: String) -> ConversationTurnPayload {
        try! JSONDecoder().decode(ConversationTurnPayload.self, from: Data(json.utf8))
    }

    private func turn(_ text: String, role: TurnRole = .user,
                      suggestion: TurnSuggestion? = nil, id: UUID = UUID()) -> Turn {
        Turn(id: id, role: role, audioURL: nil, transcript: text,
             durationMs: 0, timestamp: Date(), suggestion: suggestion)
    }

    // MARK: - The funnel

    /// A fix accuses the learner of saying `was`. One quoting words they never
    /// said is an invented mistake.
    func testAFixThatDoesNotQuoteTheLearnerIsDropped() {
        withActiveLanguage("en") {
            let said = "the landlord don't answer my calls and I am little bit frustrated"
            let s = payload("""
            {"reply":"","suggestion":{"alternative":"The landlord doesn't answer my calls, and I'm a little frustrated.",
             "reason":"flow","fixes":[
               {"was":"the landlord don't answer my calls","now":"the landlord doesn't answer my calls","why":"3rd person"},
               {"was":"she go to the shop yesterday","now":"she went to the shop yesterday","why":"invented"}]}}
            """).turnSuggestion(for: said)
            XCTAssertEqual(s?.fixes?.map(\.was), ["the landlord don't answer my calls"])
        }
    }

    /// A rewrite that changes nothing audible is dropped — but the fixes
    /// survive, and the line that carries them must still be the WHOLE turn.
    /// The first pass fell back to `fixes[0].now`, a lone clause, which the
    /// teleprompter then read in place of the turn: the reported bug again.
    func testANoOpRewriteFallsBackToTheWholeTurnWithFixesApplied() {
        withActiveLanguage("en") {
            let said = "we finish only at midnight and I have to unpack everything tomorrow"
            let s = payload("""
            {"reply":"","suggestion":{"alternative":"we finish only at midnight and I have to unpack everything tomorrow.",
             "reason":"","fixes":[{"was":"we finish only at midnight","now":"we only finished at midnight","why":"past"}]}}
            """).turnSuggestion(for: said)
            XCTAssertEqual(s?.alternative,
                           "we only finished at midnight and I have to unpack everything tomorrow")
        }
    }

    /// `fixes == nil` dates a record as written before the whole-turn
    /// contract, and the teleprompter demotes those. A clean turn under the
    /// new contract must therefore say `[]`, never nil.
    func testACleanTurnStillCarriesAnEmptyFixesArray() {
        withActiveLanguage("en") {
            let s = payload("""
            {"reply":"","suggestion":{"alternative":"Honestly, it's been a pretty rough week at work.",
             "reason":"more natural"}}
            """).turnSuggestion(for: "honestly this week was pretty rough in the work")
            XCTAssertNotNil(s?.fixes)
            XCTAssertEqual(s?.fixes?.isEmpty, true)
        }
    }

    // MARK: - The card a fix becomes

    /// A complete Korean clause is often two eojeol, and the matcher never
    /// credits under three tokens — so the card is widened to its sentence,
    /// with the fix applied, rather than minted as one that can never be
    /// marked used in a talk.
    func testAShortKoreanFixIsWidenedToItsSentence() {
        withActiveLanguage("ko") {
            let fix = TurnFix(was: "학교를 갔어", now: "학교에 갔어", why: "조사")
            let pair = DrillStore.cardPair(for: fix, in: "나는 어제 학교를 갔어. 너는?")
            XCTAssertEqual(pair.source, "나는 어제 학교를 갔어")
            XCTAssertEqual(pair.target, "나는 어제 학교에 갔어")
            XCTAssertTrue(CarryoverDetector.isCreditable(pair.target))
        }
    }

    func testAClauseSizedFixIsTheCardAsItIs() {
        withActiveLanguage("en") {
            let fix = TurnFix(was: "explain him the situation",
                              now: "explain the situation to him", why: "to + object")
            let pair = DrillStore.cardPair(for: fix, in: "so I will just send a message and explain him the situation.")
            XCTAssertEqual(pair.source, "explain him the situation")
            XCTAssertEqual(pair.target, "explain the situation to him")
        }
    }

    // MARK: - Adoption later in the call

    /// Nobody repeats a whole turn word for word, so matching `alternative`
    /// would credit no adoption ever again. The fix is what can be adopted —
    /// and a later line that repeats the mistake is not an adoption.
    func testAFixAdoptedLaterInTheCallIsCredited() {
        withActiveLanguage("en") {
            let fix = TurnFix(was: "explain him the situation",
                              now: "explain the situation to him", why: "to + object")
            let earned = turn("I will send a message and explain him the situation",
                              suggestion: TurnSuggestion(
                                alternative: "I'll send a message and explain the situation to him.",
                                reason: "", fixes: [fix]))
            let later = turn("okay so tomorrow I will explain the situation to him properly")
            let hits = CarryoverDetector.detect(in: [earned, later], cards: [],
                                                sessionId: UUID(), sessionStartedAt: Date())
            XCTAssertEqual(hits.filter { $0.source == .suggestion }.map(\.item),
                           ["explain the situation to him"])

            let repeated = turn("yes I will explain him the situation again tomorrow")
            let none = CarryoverDetector.detect(in: [earned, repeated], cards: [],
                                                sessionId: UUID(), sessionStartedAt: Date())
            XCTAssertTrue(none.filter { $0.source == .suggestion }.isEmpty)
        }
    }

    // MARK: - The Drill chapter

    /// Two fixes in one turn mint two cards under ONE turn id. Matched by
    /// turn, the first card to graduate mastered both items.
    func testOneGraduatedCardMastersOnlyItsOwnFix() {
        withActiveLanguage("en") {
            let turnId = UUID()
            let a = TurnFix(was: "the boiler is broken since we moved in",
                            now: "the boiler has been broken since we moved in", why: "perfect")
            let b = TurnFix(was: "the landlord don't answer my calls",
                            now: "the landlord doesn't answer my calls", why: "3rd person")
            let said = "the boiler is broken since we moved in and the landlord don't answer my calls"
            let session = Session(id: UUID(), userId: UUID(), targetLanguage: "en",
                                  mode: .conversation, topic: nil,
                                  startedAt: Date().addingTimeInterval(-300), endedAt: Date(),
                                  turns: [turn(said, suggestion: TurnSuggestion(
                                      alternative: "The boiler has been broken since we moved in, and the landlord doesn't answer my calls.",
                                      reason: "", fixes: [a, b]), id: turnId)],
                                  summary: nil)
            let graduated = DrillCard(sourcePhrase: a.was, targetPhrase: a.now, reason: "",
                                      createdAt: Date(), lastReviewedAt: Date(),
                                      nextReviewAt: .distantFuture, box: DrillStore.maxBox,
                                      sourceSessionId: session.id, sourceTurnId: turnId)
            let pending = DrillCard(sourcePhrase: b.was, targetPhrase: b.now, reason: "",
                                    createdAt: Date(), nextReviewAt: Date(), box: 1,
                                    sourceSessionId: session.id, sourceTurnId: turnId)
            let snap = TalkCurriculum.build(session: session, proficiency: .b1,
                                            shadowAttempts: [], drillCards: [graduated, pending])
            XCTAssertEqual(snap.corrections.map(\.text), [a.now, b.now])
            XCTAssertNotNil(snap.corrections[0].masteredAt)
            XCTAssertNil(snap.corrections[1].masteredAt,
                         "a sibling card graduating must not master this fix")
            // Ids: index 0 is the id every existing attempt carries.
            XCTAssertEqual(snap.corrections[0].id, TalkCurriculum.correctionId(for: turnId))
            XCTAssertNotEqual(snap.corrections[1].id, snap.corrections[0].id)
        }
    }
}
