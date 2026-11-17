import XCTest
@testable import FutureVoice

/// "That wasn't me" (2026-11-17). The model's half is measured by
/// `scripts/misheard-probe.py`; this pins the code around it.
final class MisheardJudgeTests: XCTestCase {

    func testTheWordCheckCatchesHowLearnersSayIt() {
        for line in [
            "Excuse me, the six month is that you misheard because I was walking outside",
            "That was not me, that was someone on the street.",
            "그거 내가 한 말 아니야, 옆에 지나가던 사람 목소리야.",
            "三匹なんて言ってないよ。聞き間違いだよ。",
            "Das habe ich nicht gesagt, das war der Fernseher.",
            "Yo no dije eso, fue otra persona.",
            "Je n'ai pas dit ça.",
            "我没说这个，你听错了。",
        ] { XCTAssertTrue(MisheardJudge.mayRetract(line), line) }
    }

    func testAnOrdinaryLineIsNeverAskedAbout() {
        for line in [
            "I had lunch with my partner at a new restaurant.",
            "주말에 부산에 갔다 왔어.",
            "Ich war gestern im Kino.",
        ] { XCTAssertFalse(MisheardJudge.mayRetract(line), line) }
    }

    func testTheJudgeSeesEachLineWithItsReply() {
        let c = MisheardJudge.Candidate(turnId: UUID(), sessionId: UUID(),
                                        said: "She is here for six month.",
                                        reply: "Oh, your friend is here for six months?")
        let text = MisheardJudge.content(candidates: [c], newest: "That was not me.")
        XCTAssertTrue(text.contains("1. learner: \"She is here for six month.\""))
        XCTAssertTrue(text.contains("reply: \"Oh, your friend is here for six months?\""))
        XCTAssertTrue(text.contains("Newest line from the learner: \"That was not me.\""))
    }

    /// A line disowned mid-call reaches the summary labelled, never as [USER].
    func testADisownedLineIsLabelledForTheSummary() {
        func turn(_ role: TurnRole, _ text: String, out: Bool = false) -> Turn {
            var t = Turn(id: UUID(), role: role, audioURL: nil, transcript: text,
                         durationMs: 1000, timestamp: Date(), suggestion: nil)
            t.excludedFromScoring = out
            return t
        }
        let plain = ConversationEngine.formatTranscript([turn(.user, "I'm on my way home.")])
        XCTAssertEqual(plain, "[USER] I'm on my way home.")
        let flagged = ConversationEngine.formatTranscript([turn(.user, "She is here for six month.", out: true)])
        XCTAssertEqual(flagged, "[NOT_THE_USER] She is here for six month.")
    }
}
