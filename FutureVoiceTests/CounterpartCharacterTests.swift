import XCTest
@testable import FutureVoice

/// A cast call's character, by kind of person, and how the two address each
/// other (2026-09-28). Reported: a friend was voiced in polite speech, and a
/// public figure (BTS RM) opened every call on the same museum fact.
final class CounterpartCharacterTests: XCTestCase {

    private func person(kind: String? = "Friend") -> Counterpart {
        var c = Counterpart.empty
        c.name = "Boram"
        c.relationship = "College roommate"
        c.background = "We still argue about the dishes."
        c.relationshipKind = kind
        return c
    }

    private func block(_ c: Counterpart, _ lang: String = "ko") -> String {
        ConversationEngine.characterBlock(c, persona: nil, targetLanguage: lang,
                                          languageName: LanguageCatalog.englishName(lang))
    }

    func testOwnPersonIsNotANewAcquaintance() {
        let b = block(person())
        XCTAssertTrue(b.contains("ALREADY KNOW"))
        XCTAssertFalse(b.contains("new acquaintances"))
        XCTAssertTrue(b.contains("College roommate"), "the relationship must reach the call")
        XCTAssertTrue(b.contains("Your history together"), "the note is shared history, not a self-intro")
    }

    func testSetRegisterIsSpelledOutInTheTargetLanguage() {
        var c = person()
        c.myRegister = .casual
        c.theirRegister = .casual
        XCTAssertTrue(block(c, "ko").contains("반말"))
        XCTAssertTrue(block(c, "de").contains("du"))
    }

    func testUnsetOwnPersonLetsTheRelationshipDecide() {
        let b = block(person(kind: nil))
        XCTAssertTrue(b.contains("form of address your relationship"))
    }

    func testStrangerDefaultsToPolite() {
        var c = person(kind: nil)
        c.remoteId = "abc"
        let b = block(c)
        XCTAssertTrue(b.contains("new acquaintances"))
        XCTAssertTrue(b.contains("해요체"))
    }

    /// A public figure is its confirmed identity and nothing else — an old
    /// row's stored summary (the museums) must never reach the call.
    func testPublicFigureIsTheIdentityAlone() {
        var c = person(kind: "Public figure")
        c.isPublicFigure = true
        c.publicIdentity = "BTS RM · rapper"
        c.background = "Loves visiting art museums."
        c.commonTopics = "art exhibitions"
        let b = block(c)
        XCTAssertTrue(b.contains("BTS RM · rapper"))
        XCTAssertFalse(b.contains("museums"))
        XCTAssertFalse(b.contains("exhibitions"))
        XCTAssertFalse(b.contains("ALREADY KNOW"))
    }

    /// The measured correction prompts must not move for any call without a
    /// hand-set level (`scripts/correction-probe.py` numbers stand on them).
    func testCorrectionPromptsUnchangedWithoutASetLevel() {
        let base = ConversationEngine.correctionOnlyPrompt(targetLanguage: "ko", nativeLanguage: "en", level: .b1)
        XCTAssertEqual(base, ConversationEngine.correctionOnlyPrompt(
            targetLanguage: "ko", nativeLanguage: "en", level: .b1, counterpart: person()))
        var set = person()
        set.myRegister = .polite
        let withSet = ConversationEngine.correctionOnlyPrompt(
            targetLanguage: "ko", nativeLanguage: "en", level: .b1, counterpart: set)
        XCTAssertTrue(withSet.contains("EXCEPTION FOR THIS CALL"))
        // English has no form of address to get wrong.
        XCTAssertEqual(
            ConversationEngine.correctionOnlyPrompt(targetLanguage: "en", nativeLanguage: "ko", level: .b1),
            ConversationEngine.correctionOnlyPrompt(targetLanguage: "en", nativeLanguage: "ko", level: .b1, counterpart: set))
    }

    func testCloseKindsKnowTheLearnersLifeStrangersNever() {
        XCTAssertTrue(person(kind: "Friend").knowsLearnersLife)
        XCTAssertFalse(person(kind: "Manager").knowsLearnersLife)
        var stranger = person(kind: "Friend")
        stranger.remoteId = "abc"
        stranger.knowsMyLife = true
        XCTAssertFalse(stranger.knowsLearnersLife)
    }

    /// The encoder dropped `isPublicFigure` until 2026-09-28.
    func testRoundTripKeepsPublicFigureAndSpeech() throws {
        var c = person(kind: "Public figure")
        c.isPublicFigure = true
        c.publicIdentity = "BTS RM · rapper"
        c.myRegister = .polite
        c.theirRegister = .casual
        c.iCallThem = "남준 씨"
        c.knowsMyLife = false
        let back = try JSONDecoder().decode(Counterpart.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.isPublicFigure, true)
        XCTAssertEqual(back.publicIdentity, "BTS RM · rapper")
        XCTAssertEqual(back.myRegister, .polite)
        XCTAssertEqual(back.theirRegister, .casual)
        XCTAssertEqual(back.iCallThem, "남준 씨")
        XCTAssertEqual(back.knowsMyLife, false)
        XCTAssertEqual(back.relationshipKind, "Public figure")
    }
}
