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
            from: Data(#"""
            {"overall_note":"x","about_user":[
               {"text":"누나가 서울에 산다","private":true},
               {"text":"주말마다 등산을 한다","private":false},
               {"text":""}]}
            """#.utf8))
        XCTAssertEqual(p.about_user.map(\.text), ["누나가 서울에 산다", "주말마다 등산을 한다", ""])
        XCTAssertEqual(p.about_user.map(\.isPrivate), [true, false, true])
    }

    /// A model that ignores the `{text, private}` schema still returns bare
    /// strings — the shape this field had until 2026-09-15. They must decode,
    /// and they must land PRIVATE: a line nobody judged is hidden, never shown.
    func testSummaryPayloadReadsLegacyStringAboutUser() throws {
        let p = try JSONDecoder().decode(
            ClaudeSummaryPayload.self,
            from: Data(#"{"overall_note":"x","about_user":["누나가 서울에 산다"]}"#.utf8))
        XCTAssertEqual(p.about_user.map(\.text), ["누나가 서울에 산다"])
        XCTAssertEqual(p.about_user.map(\.isPrivate), [true])
    }

    /// Same rule one layer down: an object that omits the key is private.
    func testAboutUserWithoutPrivateKeyIsPrivate() throws {
        let p = try JSONDecoder().decode(
            ClaudeSummaryPayload.self,
            from: Data(#"{"overall_note":"x","about_user":[{"text":"아들이 둘이다"}]}"#.utf8))
        XCTAssertEqual(p.about_user.map(\.isPrivate), [true])
    }

    /// Every note already on a learner's phone predates the lock and has no
    /// key for it. Decoding must keep the note AND hide it — the field lands
    /// in `UserPersona`'s lenient decoder, where a throw empties the whole
    /// notebook.
    func testPersonaNoteWithoutPrivacyKeyDecodesAsPrivate() throws {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let notes = try dec.decode([PersonaNote].self, from: Data(#"""
        [{"id":"6B6D6B4C-1111-4444-8888-000000000001","text":"뮌헨에 15년째 산다",
          "learnedAt":"2026-08-20T10:00:00Z"}]
        """#.utf8))
        XCTAssertEqual(notes.map(\.text), ["뮌헨에 15년째 산다"])
        XCTAssertTrue(notes[0].isPrivate)
    }

    /// The ONLY set any stranger-facing surface may read: the text of an
    /// "all" line, the GIST of a "gist" line, nothing of a "nothing" one —
    /// and nothing of a "gist" line whose gist is missing.
    func testStrangerLinesFollowTheRung() {
        var p = UserPersona.empty
        p.absorb(notes: [
            PersonaNote(text: "주말마다 이자르 강변에서 달린다", learnedAt: Date(), share: .all),
            PersonaNote(text: "유치원생 딸이 하나 있다", learnedAt: Date(), share: .gist,
                        gist: "어린 아이를 키우는 부모"),
            PersonaNote(text: "아이가 적응을 힘들어해 걱정이 많다", learnedAt: Date(), share: .nothing,
                        gist: "아이가 있다"),
            PersonaNote(text: "회사 자금이 빠듯하다", learnedAt: Date(), share: .gist, gist: nil),
        ])
        XCTAssertEqual(p.strangerLines, ["주말마다 이자르 강변에서 달린다", "어린 아이를 키우는 부모"])
    }

    /// The intro is written from standing facts only: an unlocked `now` line
    /// is small talk for a live call, not part of who someone is.
    func testStrangerFactsLeaveOutNews() {
        var p = UserPersona.empty
        p.absorb(notes: [
            PersonaNote(text: "혼자 앱을 만든다", learnedAt: Date(), share: .all, kind: .fact),
            PersonaNote(text: "아이 등교시키러 가는 길이었다", learnedAt: Date(), share: .all, kind: .now),
            PersonaNote(text: "유치원생 딸이 하나 있다", learnedAt: Date(), share: .gist, kind: .fact,
                        gist: "어린 아이를 키우는 부모"),
        ])
        XCTAssertEqual(p.strangerLines.count, 3)
        XCTAssertEqual(p.strangerFacts, ["혼자 앱을 만든다", "어린 아이를 키우는 부모"])
    }

    /// What the composer is given is exactly the stranger set — a `nothing`
    /// line is absent from the prompt, a `gist` line is there as its gist —
    /// and the cache key moves with the inputs and nothing else.
    @MainActor
    func testComposerReadsOnlyTheStrangerSet() {
        var p = UserPersona.empty
        p.displayName = "Eunggyu"
        p.occupation = "Solo founder"
        p.city = "Munich"
        p.absorb(notes: [
            PersonaNote(text: "회사 자금이 빠듯하다", learnedAt: Date(), share: .nothing, gist: "사업을 한다"),
            PersonaNote(text: "유치원생 딸이 하나 있다", learnedAt: Date(), share: .gist, gist: "어린 아이를 키우는 부모"),
            PersonaNote(text: "주말마다 달린다", learnedAt: Date(), share: .all),
        ])
        let s = PublicIntroComposer.sources(p, language: "en")
        XCTAssertEqual(s.facts, ["어린 아이를 키우는 부모", "주말마다 달린다"])
        let prompt = PublicIntroComposer.prompt(s)
        XCTAssertFalse(prompt.contains("자금"))
        XCTAssertFalse(prompt.contains("유치원생"))
        XCTAssertTrue(prompt.contains("어린 아이를 키우는 부모"))
        XCTAssertTrue(prompt.contains("Solo founder"))

        let again = PublicIntroComposer.sources(p, language: "en")
        XCTAssertEqual(s.key, again.key)
        XCTAssertNotEqual(s.key, PublicIntroComposer.sources(p, language: "de").key)
        p.learnedNotes[2].share = .nothing
        XCTAssertNotEqual(s.key, PublicIntroComposer.sources(p, language: "en").key)

        // The fallback is the old composition minus nothing the rungs hide.
        let fb = PublicIntroComposer.fallback(s)
        XCTAssertTrue(fb.hasPrefix("Solo founder"))
        XCTAssertFalse(fb.contains("자금"))
    }

    /// One write per set of inputs: a paragraph on file for these exact
    /// inputs is what `current` returns, and a changed input drops it.
    @MainActor
    func testComposerCacheFollowsTheInputs() {
        PublicIntroComposer.clear()
        defer { PublicIntroComposer.clear() }
        var p = UserPersona.empty
        p.occupation = "Solo founder"
        let s = PublicIntroComposer.sources(p, language: "en")
        XCTAssertEqual(PublicIntroComposer.current(p, language: "en"), PublicIntroComposer.fallback(s))
        PublicIntroComposer.save("I build apps on my own.", for: s)
        XCTAssertEqual(PublicIntroComposer.current(p, language: "en"), "I build apps on my own.")
        XCTAssertEqual(PublicIntroComposer.current(p, language: "ko"), PublicIntroComposer.fallback(PublicIntroComposer.sources(p, language: "ko")))
        p.occupation = "Founder"
        XCTAssertNil(PublicIntroComposer.cached(for: PublicIntroComposer.sources(p, language: "en")))
    }

    /// A note from before the rungs — the two-way lock of 2026-09-15, locked
    /// OR unlocked — lands on `nothing` (2026-09-25): the unlocked ones were
    /// written as episodes by that day's prompt and carried no gist, and
    /// they went out in full. And a build from before the rungs must never
    /// read a gist line as unlocked, so `isPrivate` is not written back.
    func testLegacyLockMapsOntoShare() throws {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let notes = try dec.decode([PersonaNote].self, from: Data(#"""
        [{"text":"a","learnedAt":"2026-08-20T10:00:00Z","isPrivate":true},
         {"text":"b","learnedAt":"2026-08-20T10:00:00Z","isPrivate":false},
         {"text":"c","learnedAt":"2026-08-20T10:00:00Z","share":"gist","gist":"g","isPrivate":false}]
        """#.utf8))
        XCTAssertEqual(notes.map(\.share), [.nothing, .nothing, .gist])
        let enc = JSONEncoder()
        let out = String(data: try enc.encode(notes[2]), encoding: .utf8)!
        XCTAssertFalse(out.contains("isPrivate"))
        XCTAssertTrue(out.contains("\"share\":\"gist\""))
    }

    /// The summary payload's new shape, and its fallbacks: `share` wins,
    /// then the old `private` boolean, then nothing.
    func testSummaryPayloadReadsShareAndGist() throws {
        let p = try JSONDecoder().decode(
            ClaudeSummaryPayload.self,
            from: Data(#"""
            {"overall_note":"x","about_user":[
               {"text":"유치원생 딸이 하나 있다","heard":"I dropped my daughter off at Kita","share":"gist","gist":"어린 아이를 키우는 부모","why":"가족"},
               {"text":"주말마다 달린다","private":false},
               {"text":"자금이 빠듯하다"}]}
            """#.utf8))
        XCTAssertEqual(p.about_user.map(\.share), [.gist, .all, .nothing])
        XCTAssertEqual(p.about_user[0].gist, "어린 아이를 키우는 부모")
        XCTAssertEqual(p.about_user[0].heard, "I dropped my daughter off at Kita")
        XCTAssertEqual(p.about_user[0].why, "가족")
    }

    /// Only a CHANGED rung is a correction, and the list is capped.
    func testShareCorrectionsRecordOnlyHandMoves() {
        var before = UserPersona.empty
        before.absorb(notes: [
            PersonaNote(text: "a", learnedAt: Date(), share: .nothing),
            PersonaNote(text: "b", learnedAt: Date(), share: .all),
        ])
        var after = before
        after.learnedNotes[0].share = .gist
        after.recordShareCorrections(from: before.learnedNotes)
        XCTAssertEqual(after.shareCorrections.count, 1)
        XCTAssertEqual(after.shareCorrections[0].text, "a")
        XCTAssertEqual(after.shareCorrections[0].from, .nothing)
        XCTAssertEqual(after.shareCorrections[0].to, .gist)
        for _ in 0..<12 {
            var again = after
            again.learnedNotes[1].share = again.learnedNotes[1].share == .all ? .nothing : .all
            again.recordShareCorrections(from: after.learnedNotes)
            after = again
        }
        XCTAssertEqual(after.shareCorrections.count, UserPersona.maxShareCorrections)
    }

    /// What the summary call is told not to hand back as a discovery. The
    /// remembered lines are NOT in here: they go to the same call separately,
    /// numbered, because those are the ones it may also update.
    func testKnownFactsCoverTypedProfileAndNotes() {
        var p = UserPersona.empty
        p.city = "Munich"
        p.country = "Germany"
        p.occupation = "Solo founder"
        p.absorb(notes: [PersonaNote(text: "화요일마다 클라이밍을 간다", learnedAt: Date())])
        XCTAssertTrue(p.knownFacts.contains("Lives in Munich, Germany"))
        XCTAssertTrue(p.knownFacts.contains("Solo founder"))
        XCTAssertFalse(p.knownFacts.contains("화요일마다 클라이밍을 간다"))
    }

    /// The whole privacy guarantee in one assertion: what a stranger's phone
    /// speaks as "you" is work, town, situations and the UNLOCKED remembered
    /// lines — and nothing the learner wrote for their own fluent self.
    /// Until 2026-09-15 this paragraph carried `household` and `freeNotes`,
    /// and it was published on first launch without the author ever seeing it.
    @MainActor
    func testComposedIntroLeavesPrivateFieldsAndLockedNotesBehind() {
        PublicIntroComposer.clear()
        var p = UserPersona.empty
        p.displayName = "Eunggyu"
        p.city = "Munich"
        p.country = "Germany"
        p.lengthOfStay = "15 years"
        p.occupation = "Solo founder"
        p.household = "Wife and two boys, 5 and 7"
        p.freeNotes = "Thinking about moving back next year."
        p.situations = ["Kita / school"]
        p.absorb(notes: [
            PersonaNote(text: "주말마다 이자르 강변에서 달린다", learnedAt: Date(), share: .all),
            PersonaNote(text: "유치원생 딸이 하나 있다", learnedAt: Date(), share: .gist,
                        gist: "어린 아이를 키우는 부모"),
            PersonaNote(text: "자금 압박이 있다", learnedAt: Date(), share: .nothing),
        ])
        let intro = PublicPersonaService.composedIntro(p, language: "en")
        XCTAssertTrue(intro.contains("Solo founder"))
        XCTAssertTrue(intro.contains("Munich"))
        XCTAssertTrue(intro.contains("Kita / school"))
        XCTAssertTrue(intro.contains("주말마다 이자르 강변에서 달린다"))
        XCTAssertTrue(intro.contains("어린 아이를 키우는 부모"))
        XCTAssertFalse(intro.contains("유치원생"))
        XCTAssertFalse(intro.contains("Wife"))
        XCTAssertFalse(intro.contains("moving back"))
        XCTAssertFalse(intro.contains("자금 압박"))
    }
}
