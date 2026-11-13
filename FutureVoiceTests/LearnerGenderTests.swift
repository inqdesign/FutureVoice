import XCTest
@testable import FutureVoice

/// The learner's gender for French and Spanish sentences (2026-11-13).
final class LearnerGenderTests: XCTestCase {

    /// Only clearly low or clearly high voices are guessed.
    func testPitchGuessLeavesTheOverlapAlone() {
        XCTAssertEqual(LearnerGender.guess(fromPitch: 110), .male)
        XCTAssertEqual(LearnerGender.guess(fromPitch: 220), .female)
        XCTAssertNil(LearnerGender.guess(fromPitch: 165))
        XCTAssertNil(LearnerGender.guess(fromPitch: 150))
        XCTAssertNil(LearnerGender.guess(fromPitch: 185))
    }

    func testOnlyFrenchAndSpanishCare() {
        XCTAssertTrue(LearnerGender.matters(in: "fr"))
        XCTAssertTrue(LearnerGender.matters(in: "es"))
        for lang in ["en", "de", "ko", "ja", "zh"] {
            XCTAssertFalse(LearnerGender.matters(in: lang), lang)
            XCTAssertEqual(ConversationEngine.genderLine(lang, asFutureSelf: true, gender: .female), "", lang)
            XCTAssertNil(ConversationEngine.genderAboutLine(lang, gender: .female), lang)
        }
    }

    func testTheFutureSelfTakesTheirGender() {
        let fem = ConversationEngine.genderLine("fr", asFutureSelf: true, gender: .female)
        XCTAssertTrue(fem.contains("a woman") && fem.contains("contente"))
        let masc = ConversationEngine.genderLine("es", asFutureSelf: true, gender: .male)
        XCTAssertTrue(masc.contains("a man") && masc.contains("cansado"))
        let unsaid = ConversationEngine.genderLine("fr", asFutureSelf: true, gender: .unsaid)
        XCTAssertTrue(unsaid.contains("prefer not to say"))
        // Nothing on file: the measured neutral-until-shown line, unchanged.
        XCTAssertTrue(ConversationEngine.genderLine("fr", asFutureSelf: true, gender: nil)
            .contains("once they show it"))
        XCTAssertTrue(ConversationEngine.spanishGuard("es", asFutureSelf: true, accentId: nil, gender: nil)
            .contains("SPANISH, GENDER"))
    }

    /// A cast person hears it only as how to talk ABOUT the learner.
    func testACastPersonOnlyHearsAKnownGender() {
        XCTAssertTrue(ConversationEngine.genderLine("fr", asFutureSelf: false, gender: .female).contains("THE LEARNER"))
        XCTAssertEqual(ConversationEngine.genderLine("fr", asFutureSelf: false, gender: .unsaid), "")
        XCTAssertEqual(ConversationEngine.genderLine("es", asFutureSelf: false, gender: nil), "")
        XCTAssertFalse(ConversationEngine.spanishGuard("es", asFutureSelf: false, accentId: nil, gender: nil)
            .contains("GENDER"))
    }

    func testFreeTalkCarriesItAsAFact() {
        XCTAssertTrue(ConversationEngine.genderAboutLine("es", gender: .female)!.contains("a woman"))
        XCTAssertTrue(ConversationEngine.genderAboutLine("fr", gender: nil)!.contains("not known"))
    }

    /// Older builds must freeze the new settings, not tombstone them.
    func testTheSettingIsStampedAboveOlderBuilds() {
        XCTAssertEqual(SyncSchema.stamp(for: .defaults, key: LearnerGender.valueKey), 2)
        XCTAssertEqual(SyncSchema.stamp(for: .defaults, key: LearnerGender.sourceKey), 2)
        XCTAssertEqual(SyncSchema.stamp(for: .defaults, key: "futurevoice.speechSpeed"), 1)
        XCTAssertTrue(DefaultsKind.keys.contains(LearnerGender.valueKey))
    }
}
