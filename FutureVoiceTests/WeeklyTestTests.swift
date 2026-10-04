import XCTest
@testable import FutureVoice

/// The weekly test's pure rules: how an answer is graded, how a blank and a
/// tile set are made, and which week a moment belongs to. Nothing here
/// touches the stores or the network.
@MainActor
final class WeeklyTestTests: XCTestCase {

    private func item(_ kind: WeeklyTestItem.Kind, answer: String, options: [String] = [],
                      prompt: String = "") -> WeeklyTestItem {
        WeeklyTestItem(id: UUID(), kind: kind, prompt: prompt, answer: answer, options: options)
    }

    // MARK: - Grading

    /// Case and trailing punctuation are the transcriber's, never the
    /// learner's — a choice must not fail on them.
    func testChoiceGradingIgnoresCaseAndPunctuation() {
        let gap = item(.gap, answer: "push back on")
        XCTAssertTrue(WeeklyTestEngine.isCorrect(gap, chosen: "Push back on."))
        XCTAssertFalse(WeeklyTestEngine.isCorrect(gap, chosen: "push back"))
    }

    /// A build is right only in the answer's order, with every tile and no
    /// decoy left in.
    func testBuildGradingIsOrderSensitive() {
        let card = item(.build, answer: "I really like it")
        XCTAssertTrue(WeeklyTestEngine.isCorrect(card, tiles: ["I", "really", "like", "it"]))
        XCTAssertFalse(WeeklyTestEngine.isCorrect(card, tiles: ["I", "like", "it", "really"]))
        XCTAssertFalse(WeeklyTestEngine.isCorrect(card, tiles: ["I", "really", "like"]))
        XCTAssertFalse(WeeklyTestEngine.isCorrect(card, tiles: ["I", "very", "really", "like", "it"]))
    }

    // MARK: - Making items

    /// Material in the learner's own language never becomes an item.
    func testItemsRequireTheTargetScript() {
        XCTAssertTrue(WeeklyTestEngine.isInTargetScript("Show me the clock once.", language: "en"))
        XCTAssertFalse(WeeklyTestEngine.isInTargetScript("한번 나올게 해줘 시계.", language: "en"))
        XCTAssertFalse(WeeklyTestEngine.isInTargetScript("Show me 시계", language: "en"))
        XCTAssertTrue(WeeklyTestEngine.isInTargetScript("시계를 보여 줘.", language: "ko"))
        XCTAssertTrue(WeeklyTestEngine.isInTargetScript("時計を見せて。", language: "ja"))
        XCTAssertFalse(WeeklyTestEngine.isInTargetScript("123 …", language: "en"))
    }

    func testBlankReplacesThePhraseOnce() {
        XCTAssertEqual(
            WeeklyTestEngine.blank("catch up on", in: "You can always Catch up on the unpacking later."),
            "You can always \(WeeklyTestEngine.blankMark) the unpacking later.")
        XCTAssertNil(WeeklyTestEngine.blank("end up", in: "Nothing here."))
    }

    /// Tiles hold every target word, add only words the learner's own version
    /// had, and never come out already in order.
    func testBuildTilesCarryTheTargetPlusDecoysFromTheSource() {
        var rng = WeeklyTestRandom(seed: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!)
        let tiles = WeeklyTestEngine.buildTiles(target: "I really like it", source: "I very like it", rng: &rng)
        let keys = tiles.map(WeeklyTestEngine.tileKey)
        for word in ["i", "really", "like", "it"] { XCTAssertTrue(keys.contains(word), word) }
        XCTAssertTrue(keys.contains("very"))
        XCTAssertEqual(tiles.count, 5)
        XCTAssertNotEqual(keys, ["i", "really", "like", "it", "very"].map { $0 })
    }

    /// A word the correction merely dropped is not a decoy; a word it
    /// replaced is.
    func testDecoysAreReplacedWordsOnly() {
        let replaced = WeeklyTestEngine.replacedWords(
            source: WordSplitter.words("I felt the intro section took too long."),
            target: WordSplitter.words("I felt like the intro took a bit too long."))
        XCTAssertFalse(replaced.contains("section"))        // omitted in passing
        XCTAssertEqual(WeeklyTestEngine.replacedWords(
            source: WordSplitter.words("I very like it"),
            target: WordSplitter.words("I really like it")), ["very"])
        XCTAssertEqual(WeeklyTestEngine.replacedWords(
            source: WordSplitter.words("I end up carrying most boxes myself."),
            target: WordSplitter.words("I ended up carrying most of the boxes myself.")), ["end"])
        var rng = WeeklyTestRandom(seed: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!)
        let tiles = WeeklyTestEngine.buildTiles(target: "I felt like the intro took a bit too long.",
                                                source: "I felt the intro section took too long.", rng: &rng)
        XCTAssertFalse(tiles.contains("section"))
        XCTAssertEqual(tiles.count, WordSplitter.count("I felt like the intro took a bit too long."))
    }

    func testSeededRandomIsDeterministic() {
        let id = UUID()
        var a = WeeklyTestRandom(seed: id), b = WeeklyTestRandom(seed: id)
        XCTAssertEqual([1, 2, 3, 4, 5].shuffled(using: &a), [1, 2, 3, 4, 5].shuffled(using: &b))
    }

    /// A near-miss is mostly right: only the misplaced tiles are marked, and
    /// the word that never arrived is named.
    func testTileCheckMarksOnlyWhatWentWrong() {
        let answer = "Considering it's only two weeks away from the launch."
        let laid = ["Exactly.", "it's", "Considering", "only", "two", "weeks", "from", "the", "launch."]
        let check = WeeklyTestEngine.tileCheck(tiles: laid, answer: answer)
        XCTAssertEqual(check.correct.count, laid.count)
        XCTAssertFalse(check.correct[0])                       // the decoy
        XCTAssertTrue(check.correct.filter { $0 }.count >= 6)  // most of it was right
        let words = WordSplitter.words(answer)
        let missing = zip(words, check.answerMatched).filter { !$0.1 }.map(\.0)
        XCTAssertTrue(missing.contains("away"))

        // Laid perfectly: every tile correct, nothing missing.
        let perfect = WeeklyTestEngine.tileCheck(tiles: words, answer: answer)
        XCTAssertTrue(perfect.correct.allSatisfy { $0 })
        XCTAssertTrue(perfect.answerMatched.allSatisfy { $0 })
    }

    // MARK: - Other scripts

    /// The active language decides how words are cut; flip it for a test and
    /// put it back.
    private func withActiveLanguage<T>(_ code: String, _ body: () throws -> T) rethrows -> T {
        let key = LanguageCatalog.targetLanguageDefaultsKey
        let saved = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(code, forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        return try body()
    }

    /// Japanese has no spaces: tiles are segments, the sentence is their
    /// plain join, and grading survives the round trip.
    func testJapaneseBuildTilesRoundTrip() {
        withActiveLanguage("ja") {
            var rng = WeeklyTestRandom(seed: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!)
            let target = "昨日は友達と映画を見ました。"
            let tiles = WeeklyTestEngine.buildTiles(target: target, source: "昨日友達と映画見た。", rng: &rng)
            XCTAssertGreaterThan(tiles.count, 3)
            let card = item(.build, answer: target)
            let inOrder = WordSplitter.words(target)
            XCTAssertTrue(WeeklyTestEngine.isCorrect(card, tiles: inOrder))
            XCTAssertFalse(WeeklyTestEngine.isCorrect(card, tiles: inOrder.reversed()))
            XCTAssertFalse(WeeklyTestEngine.sentence(fromTiles: inOrder).contains(" "))
            XCTAssertTrue(WeeklyTestEngine.isInTargetScript(target, language: "ja"))
        }
    }

    /// Korean writes spaces: whitespace tiles, punctuation riding on the word.
    func testKoreanBuildTilesAndBlank() {
        withActiveLanguage("ko") {
            var rng = WeeklyTestRandom(seed: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!)
            let target = "어제 친구랑 영화를 봤어요."
            let tiles = WeeklyTestEngine.buildTiles(target: target, source: "어제 친구 영화 봤어.", rng: &rng)
            XCTAssertTrue(tiles.contains("봤어요."))
            let card = item(.build, answer: target)
            XCTAssertTrue(WeeklyTestEngine.isCorrect(card, tiles: WordSplitter.words(target)))
            XCTAssertEqual(WeeklyTestEngine.blank("영화를", in: target), "어제 친구랑 \(WeeklyTestEngine.blankMark) 봤어요.")
            XCTAssertTrue(WeeklyTestEngine.isInTargetScript(target, language: "ko"))
            XCTAssertFalse(WeeklyTestEngine.isInTargetScript("I saw a movie.", language: "ko"))
        }
    }

    // MARK: - Schedule

    /// Saturday 10:00. A Wednesday belongs to the Saturday before it, and the
    /// next opening is the Saturday after.
    func testEveryMomentBelongsToTheLatestOpening() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let schedule = WeeklyTestSchedule(weekday: 7, hour: 10, minute: 0)
        let wednesday = cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
        let opening = schedule.currentOpening(now: wednesday, calendar: cal)
        let next = schedule.nextOpening(after: wednesday, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.day, .hour], from: opening).day, 19)
        XCTAssertEqual(cal.dateComponents([.day, .hour], from: opening).hour, 10)
        XCTAssertEqual(cal.dateComponents([.day], from: next).day, 26)
        // Saturday 09:59 is still the previous week; 10:00 opens the new one.
        let early = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 9, minute: 59))!
        XCTAssertEqual(cal.dateComponents([.day], from: schedule.currentOpening(now: early, calendar: cal)).day, 19)
        let onTime = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 10, minute: 0))!
        XCTAssertEqual(cal.dateComponents([.day], from: schedule.currentOpening(now: onTime, calendar: cal)).day, 26)
    }

    /// Two finished weeks back to back, then a gap: the streak is 2, and the
    /// unfinished current week doesn't break it.
    func testWeekStreakCountsFinishedWeeksBackFromNow() {
        let schedule = WeeklyTestSchedule(weekday: 7, hour: 10, minute: 0)
        let now = Date()
        let opening = schedule.currentOpening(now: now)
        let week: TimeInterval = 7 * 86_400
        func finished(_ at: Date) -> WeeklyTest {
            var t = WeeklyTest(id: UUID(), targetLanguage: "en", periodStart: at, periodEnd: at,
                               createdAt: at, items: [])
            t.finishedAt = at
            return t
        }
        let tests = [
            finished(opening.addingTimeInterval(-week + 3600)),
            finished(opening.addingTimeInterval(-2 * week + 3600)),
            finished(opening.addingTimeInterval(-4 * week + 3600)),   // gap before this one
        ]
        XCTAssertEqual(WeeklyTestStore.weekStreak(tests: tests, schedule: schedule, now: now), 2)
        // Finishing this week's test extends it to 3.
        let withNow = tests + [finished(now)]
        XCTAssertEqual(WeeklyTestStore.weekStreak(tests: withNow, schedule: schedule, now: now), 3)
        XCTAssertEqual(WeeklyTestStore.weekStreak(tests: [], schedule: schedule, now: now), 0)
    }

    /// The weekly paper's retakes span the last few weeks (it absorbed the
    /// monthly paper): every distinct miss once, newest first — and a miss a
    /// newer test asked again and got RIGHT never comes back.
    func testRetakesSpanRecentWeeksUntilAnsweredRight() {
        func finished(_ items: [WeeklyTestItem], wrong: Set<Int>, daysAgo: Double) -> WeeklyTest {
            let at = Date().addingTimeInterval(-daysAgo * 86_400)
            var t = WeeklyTest(id: UUID(), targetLanguage: "en", periodStart: at, periodEnd: at,
                               createdAt: at, items: items)
            for (i, it) in items.enumerated() {
                t.answers.append(WeeklyTestAnswer(itemId: it.id, given: "", correct: !wrong.contains(i), at: at))
            }
            t.finishedAt = at
            return t
        }
        let a = item(.meaning, answer: "chore", options: ["chore", "errand", "hobby", "shift"])
        let b = item(.gap, answer: "end up",
                     options: ["end up", "push back on", "catch up on", "walk you through"],
                     prompt: "Did you \(WeeklyTestEngine.blankMark) hiring movers?")
        let c = item(.build, answer: "I really like it", options: ["I", "like", "really", "it", "very"],
                     prompt: "I very like it")
        let d = item(.speak, answer: "Give yourself a day off.")
        // The paper is judged in ITS language, whatever the active one is.
        UserDefaults.standard.set("de", forKey: LanguageCatalog.targetLanguageDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: LanguageCatalog.targetLanguageDefaultsKey) }
        let week1 = finished([a, b, c], wrong: [0, 1, 2], daysAgo: 14)
        // Week 2 asked "chore" again and got it right, and missed d.
        let week2 = finished([item(.meaning, answer: "Chore", options: a.options), d], wrong: [1], daysAgo: 7)
        var rng = WeeklyTestRandom(seed: UUID())
        let items = WeeklyTestEngine.retakes(from: [week1, week2], limit: WeeklyTestEngine.maxRetake,
                                             excluding: [], language: "en", rng: &rng)
        XCTAssertEqual(Set(items.map(\.answer)), ["Give yourself a day off.", "end up", "I really like it"])
        XCTAssertEqual(items.first?.answer, "Give yourself a day off.")
        XCTAssertTrue(items.allSatisfy { $0.isRetake == true })
    }

    /// A monthly paper saved before 2026-10-05 must not become the
    /// weekly's window anchor — the week's material would shrink to those
    /// minutes and the week read as thin. The window starts at the last
    /// WEEKLY paper, and so does the store's pick.
    func testMonthlyPaperNeverAnchorsTheWeeklyWindow() {
        let now = Date()
        let weekly = WeeklyTest(id: UUID(), targetLanguage: "en",
                                periodStart: now.addingTimeInterval(-14 * 86_400),
                                periodEnd: now.addingTimeInterval(-7 * 86_400),
                                createdAt: now.addingTimeInterval(-7 * 86_400), items: [])
        let monthly = WeeklyTest(id: UUID(), targetLanguage: "en", kind: .monthly,
                                 periodStart: now.addingTimeInterval(-30 * 86_400),
                                 periodEnd: now.addingTimeInterval(-60),
                                 createdAt: now.addingTimeInterval(-60), items: [])
        XCTAssertEqual(WeeklyTestStore.latestWeekly([monthly, weekly])?.id, weekly.id)
        XCTAssertEqual(WeeklyTestStore.latestWeekly([weekly, monthly])?.id, weekly.id)
        XCTAssertNil(WeeklyTestStore.latestWeekly([monthly]))
        XCTAssertEqual(WeeklyTestEngine.window(lastTest: weekly, now: now).start, weekly.periodEnd)
        // Even handed the monthly directly, the engine falls back to a week,
        // never to the monthly's own build moment.
        let fromMonthly = WeeklyTestEngine.window(lastTest: monthly, now: now)
        XCTAssertEqual(fromMonthly.start.timeIntervalSince1970,
                       now.addingTimeInterval(-WeeklyTestEngine.defaultWindow).timeIntervalSince1970, accuracy: 1)
    }

    /// The next unanswered item, and none once every one is answered.
    func testNextItemWalksTheUnanswered() {
        let a = item(.meaning, answer: "chore"), b = item(.gap, answer: "end up")
        var test = WeeklyTest(id: UUID(), targetLanguage: "en", periodStart: Date(), periodEnd: Date(),
                              createdAt: Date(), items: [a, b])
        XCTAssertEqual(test.nextItem?.id, a.id)
        test.answers.append(WeeklyTestAnswer(itemId: a.id, given: "chore", correct: true, at: Date()))
        XCTAssertEqual(test.nextItem?.id, b.id)
        test.answers.append(WeeklyTestAnswer(itemId: b.id, given: "x", correct: false, at: Date()))
        XCTAssertNil(test.nextItem)
        XCTAssertEqual(test.score, 1)
    }
}
