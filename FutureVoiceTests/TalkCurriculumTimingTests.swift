import XCTest
@testable import FutureVoice

/// How long the widget refresh / Practice reload pays to rebuild EVERY talk
/// book. Printed, not asserted — the number is the point, and a threshold
/// would only flake on a loaded CI box.
///
/// 2026-09-23, simulator, before the per-text memo in `VocabStore` and the
/// allocation-free `normalized` / `sentences` / `count`: 517 ms cold,
/// 511 ms warm. After: ~230 ms cold, ~37 ms warm. The warm number is what a
/// tap on "I know" used to pay on the main thread before repainting.
final class TalkCurriculumTimingTests: XCTestCase {

    private func turn(_ text: String, role: TurnRole) -> Turn {
        Turn(id: UUID(), role: role, audioURL: nil, transcript: text,
             durationMs: 0, timestamp: Date(), suggestion: nil)
    }

    private func session(_ i: Int) -> Session {
        var turns: [Turn] = []
        for j in 0..<30 {
            turns.append(turn("Yeah, I have been doing the same chores every weekend lately and honestly the boiler keeps breaking down again number \(j) \(i).", role: .fluentSelf))
            turns.append(turn("I think I need to call the landlord about the heating and maybe sublet the room next month \(j).", role: .user))
        }
        return Session(id: UUID(), userId: UUID(), targetLanguage: "en",
                       mode: .conversation, topic: "Flat \(i)",
                       startedAt: Date().addingTimeInterval(-600),
                       endedAt: Date(), turns: turns, summary: nil)
    }

    @MainActor
    func testBuildAllBooksTiming() {
        let sessions = (0..<30).map(session)
        for pass in 0..<2 {
            let t0 = CFAbsoluteTimeGetCurrent()
            for s in sessions {
                _ = TalkCurriculum.build(session: s, proficiency: .b1,
                                         shadowAttempts: [], drillCards: [])
            }
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print("TIMING pass \(pass): 30 books in \(Int(ms)) ms")
        }
        let t = CFAbsoluteTimeGetCurrent()
        for s in sessions { _ = TalkCurriculum.shadowPicks(session: s, proficiency: .b1) }
        print("TIMING shadowPicks: \(Int((CFAbsoluteTimeGetCurrent() - t) * 1000)) ms")
    }
}
