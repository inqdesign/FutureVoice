import XCTest
@testable import FutureVoice

/// Korean phrases are credited on their own terms (2026-10-04): an eojeol
/// carries its particles and endings, so the English three-word floor left
/// most Korean expressions uncreditable, the recognizer's spacing broke
/// matches, and an expression saved in 반말 never ticked when it was said
/// with 요.
final class KoreanCarryoverTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("ko", forKey: LanguageCatalog.targetLanguageDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LanguageCatalog.targetLanguageDefaultsKey)
        super.tearDown()
    }

    private func turn(_ text: String) -> Turn {
        Turn(id: UUID(), role: .user, audioURL: nil, transcript: text,
             durationMs: 1000, timestamp: Date(), suggestion: nil)
    }

    func testShortExpressionsAreCreditable() {
        XCTAssertTrue(CarryoverDetector.isCreditable("잘 모르겠어"))
        XCTAssertTrue(CarryoverDetector.isCreditable("그러게"))
        XCTAssertFalse(CarryoverDetector.isCreditable("잘 가"))
    }

    func testPoliteEndingStillCreditsTheExpression() {
        XCTAssertNotNil(CarryoverDetector.firstMatch(of: "잘 모르겠어", in: [turn("음, 저도 잘 모르겠어요.")]))
    }

    func testRecognizerSpacingDoesNotMatter() {
        XCTAssertNotNil(CarryoverDetector.firstMatch(of: "할 수 있어", in: [turn("나도 할수있어")]))
    }

    func testDifferentWordsDoNotMatch() {
        XCTAssertNil(CarryoverDetector.firstMatch(of: "잘 모르겠어", in: [turn("잘 알겠어")]))
    }

    /// A correction card keeps the strict comparison: saying the mistake
    /// again is not using the fix.
    func testCorrectionRejectsTheMistake() {
        XCTAssertNil(CarryoverDetector.firstMatch(of: "학교에 가요", in: [turn("저는 학교에서 가요")],
                                                  rejectingMistake: "학교에서 가요"))
        XCTAssertNotNil(CarryoverDetector.firstMatch(of: "학교에 가요", in: [turn("내일 학교에 가요")],
                                                     rejectingMistake: "학교에서 가요"))
    }
}
