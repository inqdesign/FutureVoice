import XCTest
@testable import FutureVoice

final class ShadowEngineTests: XCTestCase {

    func testPerfectMatchScores100() {
        let a = ShadowEngine.analyze(target: "hello world how are you",
                                     learner: "hello world how are you")
        XCTAssertEqual(a.score, 100)
        XCTAssertEqual(a.matchCount, 5)
        XCTAssertTrue(a.steps.allSatisfy { $0.op == .match })
    }

    func testCaseAndPunctuationInsensitive() {
        let a = ShadowEngine.analyze(target: "Hello, world!", learner: "hello world")
        XCTAssertEqual(a.score, 100)
    }

    func testEmptyLearnerScoresZero() {
        let a = ShadowEngine.analyze(target: "hello world", learner: "")
        XCTAssertEqual(a.score, 0)
        XCTAssertEqual(a.matchCount, 0)
        XCTAssertTrue(a.steps.allSatisfy { $0.op == .del })
    }

    func testSingleSubstitutionDetected() {
        let a = ShadowEngine.analyze(target: "I went to the bank",
                                     learner: "I go to the bank")
        XCTAssertEqual(a.matchCount, 4)
        // sqrt(4/5) * 100 ≈ 89
        XCTAssertEqual(a.score, 89)
        let subs = a.steps.filter { $0.op == .sub }
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs.first?.target, "went")
        XCTAssertEqual(subs.first?.learner, "go")
    }

    /// A script that spells a year the way it is said, read exactly: the
    /// transcriber writes "1911", and the plain spell-out of that is not
    /// what the script (or the reader) said.
    func testYearHeardAsDigitsMatchesItsSpokenForm() {
        let a = ShadowEngine.analyze(target: "in August of nineteen eleven, while the museum was closed",
                                     learner: "in August of 1911 while the museum was closed")
        XCTAssertTrue(a.steps.allSatisfy { $0.op == .match }, "\(a.steps)")
        XCTAssertEqual(a.score, 100)
    }

    func testNumbersMeetWhicheverSideWroteDigits() {
        for (target, learner) in [
            ("back in 1911 it was gone", "back in nineteen eleven it was gone"),
            ("it was nineteen oh five then", "it was 1905 then"),
            ("we sold one hundred and five tickets", "we sold 105 tickets"),
            ("we sold 105 tickets", "we sold one hundred and five tickets"),
            ("room one oh one is free", "room 101 is free"),
            ("twenty twenty-four was long", "2024 was long"),
            ("about 1911 people came", "about one thousand nine hundred eleven people came"),
        ] {
            let a = ShadowEngine.analyze(target: target, learner: learner)
            XCTAssertTrue(a.steps.allSatisfy { $0.op == .match }, "\(target) | \(learner): \(a.steps)")
        }
    }

    /// A transcriber writes "1000" for "a thousand" and for a bare
    /// "thousand" (a take read in pieces, cut after "eighty-six").
    func testThousandWrittenAsDigitsAddsNoOne() {
        for (target, learner) in [
            ("more than eighty-six thousand people, aged fifty-one to ninety",
             "more than eighty-six 1000 people aged fifty-one to 90"),
            ("about a thousand people came", "about 1000 people came"),
            ("a hundred and five tickets", "105 tickets"),
        ] {
            let a = ShadowEngine.analyze(target: target, learner: learner)
            XCTAssertTrue(a.steps.allSatisfy { $0.op == .match }, "\(target) | \(learner): \(a.steps)")
        }
        let wrong = ShadowEngine.analyze(target: "eighty-six thousand people", learner: "eighty-six 2000 people")
        XCTAssertFalse(wrong.steps.allSatisfy { $0.op == .match })
    }

    /// A different number is still a different number.
    func testWrongYearIsStillWrong() {
        let a = ShadowEngine.analyze(target: "in nineteen eleven", learner: "in 1912")
        XCTAssertFalse(a.steps.allSatisfy { $0.op == .match })
    }

    /// The transcriber's written shapes of what the reader said in words.
    func testWrittenFormsAreTheWordsSaid() {
        for (language, target, learner) in [
            ("en", "about one thousand five hundred people", "about 1,500 people"),
            ("en", "it costs five dollars", "it costs $5"),
            ("en", "just one dollar", "just $1"),
            ("en", "fifty percent of them", "50% of them"),
            ("en", "on the twenty-first of May", "on the 21st of May"),
            ("en", "the first time, the third try", "the 1st time, the 3rd try"),
            ("en", "in the nineteen sixties", "in the 1960s"),
            ("en", "back in the eighties", "back in the 80s"),
            ("en", "three point five million", "3.5 million"),
            ("en", "Doctor Smith and Mister Lee", "Dr. Smith and Mr. Lee"),
            ("en", "Dr. Smith is in", "Doctor Smith is in"),
            ("en", "at three thirty", "at 3:30"),
            ("de", "fünfzig Prozent der Leute", "50% der Leute"),
            ("de", "Das kostet fünf Euro", "Das kostet 5 €"),
            ("es", "el cincuenta por ciento", "el 50%"),
            ("ko", "오십 퍼센트예요", "50%예요"),
            ("ko", "천오백 원이에요", "1,500원이에요"),
        ] {
            let a = ShadowEngine.analyze(target: target, learner: learner, language: language)
            XCTAssertTrue(a.steps.allSatisfy { $0.op == .match }, "\(target) | \(learner): \(a.steps)")
        }
        // Each change stays inside its word, so the word map still lines up.
        let line = "It was $5 on the 21st, 50% off, says Dr. Lee of the 1960s"
        let words = line.split(separator: " ").map(String.init)
        let spans = ShadowEngine.tokenSpans(for: words)
        XCTAssertEqual(spans.last?.upperBound, ShadowEngine.analyze(target: line, learner: "").targetTokenCount)
        // Ordinary words are left alone.
        XCTAssertEqual(ShadowEngine.written("a hundred dreams, Mr Darcy", language: "en"),
                       "a hundred dreams, mister darcy")
    }

    func testGermanSpanishKoreanNumberReadings() {
        for (language, target, learner) in [
            ("de", "Das war neunzehnhundertelf in Paris", "Das war 1911 in Paris"),
            ("de", "Das war 1911 in Paris", "Das war neunzehnhundertelf in Paris"),
            ("de", "Ich bin einundzwanzig Jahre alt", "Ich bin 21 Jahre alt"),
            ("de", "Wir treffen uns um ein Uhr", "Wir treffen uns um 1 Uhr"),
            ("de", "Das kostet hundert Euro", "Das kostet 100 Euro"),
            ("es", "Tengo veintiún años", "Tengo 21 años"),
            ("es", "Quiero un café", "Quiero 1 café"),
            ("es", "Fue en mil novecientos once", "Fue en 1911"),
            ("es", "Hay doscientas personas", "Hay 200 personas"),
            ("ko", "세 시에 만나요", "3시에 만나요"),
            ("ko", "3시에 만나요", "세 시에 만나요"),
            ("ko", "저는 스무 살이에요", "저는 20살이에요"),
            ("ko", "사과 다섯 개 주세요", "사과 5개 주세요"),
            ("ko", "천구백십일 년에 사라졌어요", "1911년에 사라졌어요"),
            ("ja", "千九百十一年のことです", "1911年のことです"),
        ] {
            let a = ShadowEngine.analyze(target: target, learner: learner, language: language)
            XCTAssertTrue(a.steps.allSatisfy { $0.op == .match }, "\(target) | \(learner): \(a.steps)")
        }
        // 삼 시 for 세 시 is a slip, and stays one.
        let wrong = ShadowEngine.analyze(target: "세 시에 만나요", learner: "삼 시에 만나요", language: "ko")
        XCTAssertFalse(wrong.steps.allSatisfy { $0.op == .match })
    }

    /// A model-written target carries a typographic apostrophe; every
    /// recognizer writes the ASCII one. Both must expand to the same tokens
    /// or "I’m" against "I'm" is a substitution the learner never made.
    func testCurlyApostropheMatchesAsciiContraction() {
        let a = ShadowEngine.analyze(target: "I\u{2019}m building it, don\u{2019}t worry",
                                     learner: "I'm building it, don't worry")
        XCTAssertEqual(a.score, 100, "\(a.steps)")
        let b = ShadowEngine.analyze(target: "I\u{2019}m building it",
                                     learner: "I am building it")
        XCTAssertEqual(b.score, 100, "\(b.steps)")
    }

    func testInsertionAndDeletionOps() {
        let a = ShadowEngine.analyze(target: "the weather is nice today",
                                     learner: "the weather nice today actually")
        XCTAssertTrue(a.steps.contains { $0.op == .del && $0.target == "is" })
        XCTAssertTrue(a.steps.contains { $0.op == .ins && $0.learner == "actually" })
    }

    func testSqrtCurveSoftensBottom() {
        // 1 of 4 matched: raw 0.25 → curved 0.5 → 50, not 25.
        let a = ShadowEngine.analyze(target: "alpha beta gamma delta",
                                     learner: "alpha xx yy zz")
        XCTAssertEqual(a.score, 50)
    }

    // Korean is scored by eojeol (scripts/shadow-ko-probe.py, 2026-10-10).
    func testKoreanDroppedWordCostsAWord() {
        let a = ShadowEngine.analyze(target: "어제 친구랑 같이 영화를 봤어요.",
                                     learner: "어제 친구랑 영화를 봤어요", language: "ko")
        XCTAssertEqual(a.score, 89)   // 4 of 5 words; by syllable it read 92
    }

    func testKoreanWrongParticleFailsItsWord() {
        let a = ShadowEngine.analyze(target: "어제 친구랑 같이 영화를 봤어요.",
                                     learner: "어제 친구랑 같이 영화가 봤어요", language: "ko")
        XCTAssertEqual(a.score, 89)   // by syllable it read 96
    }

    func testKoreanSpacingIsStillTheRecognizers() {
        let a = ShadowEngine.analyze(target: "커피 한잔 할래?",
                                     learner: "커피 한 잔 할래", language: "ko")
        XCTAssertEqual(a.score, 100)
        let b = ShadowEngine.analyze(target: "커피 한 잔 할래?",
                                     learner: "커피 한잔할래", language: "ko")
        XCTAssertEqual(b.score, 100)
    }

    // Japanese gets the same word credit, words from the segmenter.
    func testJapaneseWrongParticleFailsItsWord() {
        let a = ShadowEngine.analyze(target: "昨日友達と映画を見ました。",
                                     learner: "昨日友達と映画が見ました", language: "ja")
        XCTAssertEqual(a.score, 94)   // 1 of 8 segmenter words; by character it read 96
    }

    func testJapaneseDroppedWordCostsAWord() {
        let a = ShadowEngine.analyze(target: "週末に時間があったらコーヒーでも飲もう。",
                                     learner: "週末に時間があったらコーヒー飲もう", language: "ja")
        XCTAssertLessThan(a.score, 94)   // by character it read 95
    }

    func testJapaneseScriptIsStillTheRecognizers() {
        XCTAssertEqual(ShadowEngine.analyze(target: "ちょっと待ってください。",
                                            learner: "ちょっと待ってください", language: "ja").score, 100)
        XCTAssertEqual(ShadowEngine.analyze(target: "nawana で毎日練習しています。",
                                            learner: "ナワナで毎日練習しています", language: "ja").score, 100)
    }

    func testKoreanExtraSpeechCountsAgainst() {
        let a = ShadowEngine.analyze(target: "학교 끝나고 갈 거야",
                                     learner: "학교 수업 끝나고 갈 거야", language: "ko")
        XCTAssertLessThan(a.score, 100)
        XCTAssertGreaterThan(a.score, 80)
    }
}

final class ScorecardMetricsTests: XCTestCase {

    private func turn(_ role: TurnRole, _ text: String, ms: Int = 0,
                      suggestion: TurnSuggestion? = nil) -> Turn {
        Turn(id: UUID(), role: role, audioURL: nil, transcript: text,
             durationMs: ms, timestamp: Date(), suggestion: suggestion)
    }

    func testWordsPerMinuteAndCounts() {
        // 6 user words over 6 seconds of speech = 60 wpm.
        let turns = [
            turn(.user, "one two three", ms: 3000),
            turn(.fluentSelf, "this should not count", ms: 9999),
            turn(.user, "four five six", ms: 3000),
        ]
        let m = ScorecardMetrics.compute(turns: turns)
        XCTAssertEqual(m.userTurnCount, 2)
        XCTAssertEqual(m.userWordCount, 6)
        XCTAssertEqual(m.uniqueWordCount, 6)
        XCTAssertEqual(m.wordsPerMinute, 60, accuracy: 0.01)
        XCTAssertEqual(m.typeTokenRatio, 1.0, accuracy: 0.001)
    }

    func testSuggestionRate() {
        let s = TurnSuggestion(alternative: "I went there", reason: "past tense")
        let turns = [
            turn(.user, "I go there yesterday", suggestion: s),
            turn(.user, "that was fun"),
        ]
        let m = ScorecardMetrics.compute(turns: turns)
        XCTAssertEqual(m.suggestionCount, 1)
        XCTAssertEqual(m.suggestionRate, 0.5, accuracy: 0.001)
    }

    func testNoTimingMeansZeroWpm() {
        let m = ScorecardMetrics.compute(turns: [turn(.user, "hello there", ms: 0)])
        XCTAssertEqual(m.wordsPerMinute, 0)
    }
}
