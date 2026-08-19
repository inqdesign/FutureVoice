import XCTest
@testable import FutureVoice

/// The fluent self's own record of the person it talks to — written into the
/// same profile the learner fills in by hand (`UserPersona.learnedNotes`).
///
/// The decoding half is the dangerous one: this file is what
/// `PersonaStore.load()` returns, and a nil there walks an existing user back
/// into first-run onboarding. Every persona already on a phone was written
/// before these fields existed.
final class PersonaMemoryTests: XCTestCase {

    private func decode(_ json: String) throws -> UserPersona {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(UserPersona.self, from: Data(json.utf8))
    }

    /// A persona written by a build that had never heard of learned notes.
    func testLegacyPersonaWithoutNotesDecodes() throws {
        let p = try decode("""
        {"displayName":"Eunggyu","city":"Munich","country":"Germany",
         "lengthOfStay":"3 years","occupation":"Solo founder","household":"",
         "interests":["AI"],"englishSituations":["Kita"],"freeNotes":"",
         "updatedAt":"2026-08-01T10:00:00Z"}
        """)
        XCTAssertEqual(p.displayName, "Eunggyu")
        XCTAssertEqual(p.situations, ["Kita"])
        XCTAssertTrue(p.learnedNotes.isEmpty)
        // Never met => the next free talk is the introduction.
        XCTAssertNil(p.metAt)
    }

    /// A half-written file must still come back as a persona rather than as
    /// nil — losing one field is not a reason to lose the profile.
    func testTruncatedPersonaStillDecodes() throws {
        let p = try decode(#"{"displayName":"Eunggyu"}"#)
        XCTAssertEqual(p.displayName, "Eunggyu")
        XCTAssertEqual(p.city, "")
        XCTAssertTrue(p.interests.isEmpty)
    }

    func testNotesRoundTrip() throws {
        var p = UserPersona.empty
        p.displayName = "Eunggyu"
        p.absorb(notes: [PersonaNote(text: "고양이 두 마리를 키운다",
                                     sessionId: UUID(), learnedAt: Date())])
        p.metAt = Date()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let back = try decode(String(data: try enc.encode(p), encoding: .utf8)!)
        XCTAssertEqual(back.learnedNotes.map(\.text), ["고양이 두 마리를 키운다"])
        XCTAssertNotNil(back.metAt)
    }

    /// The model re-tells the same fact with different punctuation every
    /// session; without this the profile fills with paraphrases of one line.
    func testAbsorbDropsWhatIsAlreadyKnown() {
        var p = UserPersona.empty
        let now = Date()
        p.absorb(notes: [PersonaNote(text: "화요일마다 클라이밍을 간다", learnedAt: now)])
        p.absorb(notes: [PersonaNote(text: "화요일마다  클라이밍을 간다.", learnedAt: now),
                         PersonaNote(text: "누나가 서울에 산다", learnedAt: now)])
        XCTAssertEqual(p.learnedNotes.count, 2)
        XCTAssertEqual(p.learnedNotes.last?.text, "누나가 서울에 산다")
    }

    /// Oldest fall off first: the block this feeds sits above the speaking
    /// rules in every conversation prompt.
    func testAbsorbKeepsNewestWithinLimit() {
        var p = UserPersona.empty
        p.absorb(notes: (0..<10).map { PersonaNote(text: "fact \($0)", learnedAt: Date()) },
                 limit: 4)
        XCTAssertEqual(p.learnedNotes.map(\.text), ["fact 6", "fact 7", "fact 8", "fact 9"])
    }

    /// A note with nothing but punctuation in it can never be matched against
    /// anything, and must not be stored.
    func testAbsorbSkipsUnmatchableNotes() {
        var p = UserPersona.empty
        p.absorb(notes: [PersonaNote(text: "—", learnedAt: Date())])
        XCTAssertTrue(p.learnedNotes.isEmpty)
    }

    /// `about_user` is the LAST field the summary writes, so a response cut
    /// off at the token ceiling loses it — and must lose nothing else.
    func testSummaryPayloadWithoutAboutUser() throws {
        let p = try JSONDecoder().decode(
            ClaudeSummaryPayload.self,
            from: Data(#"{"overall_note":"Good talk."}"#.utf8))
        XCTAssertTrue(p.about_user.isEmpty)
    }

    func testSummaryPayloadReadsAboutUser() throws {
        let p = try JSONDecoder().decode(
            ClaudeSummaryPayload.self,
            from: Data(#"{"overall_note":"x","about_user":["누나가 서울에 산다",""]}"#.utf8))
        XCTAssertEqual(p.about_user, ["누나가 서울에 산다", ""])
    }

    /// What the summary call is told not to hand back as a discovery.
    func testKnownFactsCoverTypedProfileAndNotes() {
        var p = UserPersona.empty
        p.city = "Munich"
        p.country = "Germany"
        p.occupation = "Solo founder"
        p.absorb(notes: [PersonaNote(text: "화요일마다 클라이밍을 간다", learnedAt: Date())])
        XCTAssertTrue(p.knownFacts.contains("Lives in Munich, Germany"))
        XCTAssertTrue(p.knownFacts.contains("Solo founder"))
        XCTAssertTrue(p.knownFacts.contains("화요일마다 클라이밍을 간다"))
    }
}
