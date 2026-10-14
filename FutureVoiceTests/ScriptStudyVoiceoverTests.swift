import XCTest
@testable import FutureVoice

/// Speech script Study mode + "Hear it in my voice" (2026-10-14).
final class ScriptStudyVoiceoverTests: XCTestCase {

    // MARK: - Span verification

    private let paras = [
        "Have you ever had the perfect sentence in your head, only to watch it fall apart the moment you said it?",
        "Speaking is a skill, not just knowledge. It tends to let you down when it matters.",
        "Saying things aloud also helps them stick.",
    ]

    func testVerbatimSpansAreLocated() {
        let found = ScriptStudy.locate([
            .init(text: "fall apart", kind: .expression),
            .init(text: "only to", kind: .grammar),
            .init(text: "stick", kind: .word, lemma: "stick"),
        ], in: paras, spaced: true)
        XCTAssertEqual(found.map(\.text), ["fall apart", "only to", "stick"])
        XCTAssertEqual(found[0].paragraph, 0)
        XCTAssertEqual(found[2].paragraph, 2)
        let p0 = Array(paras[0])
        XCTAssertEqual(String(p0[found[0].offset ..< found[0].offset + found[0].length]), "fall apart")
    }

    func testSpanNotInTheScriptIsDropped() {
        let found = ScriptStudy.locate([
            .init(text: "falls apart", kind: .expression),      // rewritten
            .init(text: "let you down", kind: .expression),
        ], in: paras, spaced: true)
        XCTAssertEqual(found.map(\.text), ["let you down"])
    }

    func testWordBoundaryInSpacedLanguage() {
        // "art" is inside "apart" — never lit up there.
        let found = ScriptStudy.locate([.init(text: "art", kind: .word)], in: paras, spaced: true)
        XCTAssertTrue(found.isEmpty)
    }

    func testCaseFallbackKeepsTheScriptsSpelling() {
        let found = ScriptStudy.locate([.init(text: "saying things", kind: .expression)], in: paras, spaced: true)
        XCTAssertEqual(found.first?.text, "Saying things")
    }

    func testOverlappingSpansKeepTheFirst() {
        let found = ScriptStudy.locate([
            .init(text: "let you down", kind: .expression),
            .init(text: "you down when", kind: .expression),
        ], in: paras, spaced: true)
        XCTAssertEqual(found.map(\.text), ["let you down"])
    }

    func testUnspacedLanguageNeedsNoBoundary() {
        let found = ScriptStudy.locate([.init(text: "練習", kind: .word)],
                                       in: ["声に出して練習しよう。"], spaced: false)
        XCTAssertEqual(found.first?.offset, 5)
    }

    func testParagraphsSplitLikeThePrompter() {
        XCTAssertEqual(ScriptStudy.paragraphs("A b.\n\n  C d. \nE"), ["A b.", "C d.", "E"])
    }

    // MARK: - Cache keys

    func testStudyCacheKeyFollowsEveryInput() {
        let base = ScriptStudy.cacheKey(body: "Hello.", target: "en", native: "ko", level: "b1")
        XCTAssertEqual(base, ScriptStudy.cacheKey(body: " Hello.\n", target: "en-US", native: "ko", level: "B1"))
        XCTAssertNotEqual(base, ScriptStudy.cacheKey(body: "Hello!", target: "en", native: "ko", level: "b1"))
        XCTAssertNotEqual(base, ScriptStudy.cacheKey(body: "Hello.", target: "en", native: "ja", level: "b1"))
        XCTAssertNotEqual(base, ScriptStudy.cacheKey(body: "Hello.", target: "en", native: "ko", level: "b2"))
        XCTAssertNotEqual(base, ScriptStudy.cacheKey(body: "Hello.", target: "de", native: "ko", level: "b1"))
        XCTAssertEqual(base.count, 64)
    }

    func testVoiceoverFileKeyFollowsScriptVoiceAndSpeed() {
        let h = ScriptVoiceover.scriptHash("Hello.")
        let k = ScriptVoiceover.fileKey(scriptHash: h, voiceId: "v1", speedTag: "")
        XCTAssertNotEqual(k, ScriptVoiceover.fileKey(scriptHash: h, voiceId: "v2", speedTag: ""))
        XCTAssertNotEqual(k, ScriptVoiceover.fileKey(scriptHash: h, voiceId: "v1", speedTag: "s0.80"))
        XCTAssertNotEqual(k, ScriptVoiceover.fileKey(scriptHash: ScriptVoiceover.scriptHash("Hi."),
                                                     voiceId: "v1", speedTag: ""))
    }

    // MARK: - Idempotency key

    /// Charged once per (account, script text, voice): "sv1:" + 32 hex. Speed
    /// is NOT in it, so a speed change never charges again.
    func testChargeKeyShape() {
        let h = ScriptVoiceover.scriptHash("Hello.")
        let key = ScriptVoiceover.chargeKey(scriptHash: h, voiceId: "v1")
        XCTAssertTrue(key.hasPrefix("sv1:"))
        XCTAssertEqual(key.count, 36)
        XCTAssertTrue(key.dropFirst(4).allSatisfy { $0.isHexDigit })
        XCTAssertEqual(key, ScriptVoiceover.chargeKey(scriptHash: ScriptVoiceover.scriptHash(" Hello.\n"), voiceId: "v1"))
        XCTAssertNotEqual(key, ScriptVoiceover.chargeKey(scriptHash: h, voiceId: "v2"))
        // Fits the server's check (length 8…200).
        XCTAssertTrue((8 ... 200).contains(key.count))
    }

    // MARK: - Price

    /// minutes = ceil(audioSeconds × 3 / 60)
    func testChargeRounding() {
        XCTAssertEqual(ScriptVoiceover.chargeMinutes(audioSeconds: 40), 2)   // 120 s → exactly 2
        XCTAssertEqual(ScriptVoiceover.chargeMinutes(audioSeconds: 41), 3)   // 123 s → 3
        XCTAssertEqual(ScriptVoiceover.chargeMinutes(audioSeconds: 60), 3)
        XCTAssertEqual(ScriptVoiceover.chargeMinutes(audioSeconds: 80), 4)   // ceil(240/60) = 4
        XCTAssertEqual(ScriptVoiceover.chargeMinutes(audioSeconds: 80.5), 5)
        XCTAssertEqual(ScriptVoiceover.chargeMinutes(audioSeconds: 0), 0)
    }

    func testComposerQuotesThreeTimesTheLength() {
        XCTAssertEqual(ScriptVoiceover.quoteMinutes(targetSeconds: 60), 3)
        XCTAssertEqual(ScriptVoiceover.quoteMinutes(targetSeconds: 180), 9)
        XCTAssertEqual(ScriptVoiceover.quoteMinutes(targetSeconds: 300), 15)
        XCTAssertEqual(ScriptVoiceover.quoteMinutes(targetSeconds: 30), 2)
    }

    /// Never charged more than the number shown.
    func testChargeIsCappedAtTheQuote() {
        // A "1 min" script that came out 75 s: 4 min by the formula, 3 shown.
        XCTAssertEqual(ScriptVoiceover.cappedChargeMinutes(actualAudioSeconds: 75, quotedMinutes: 3), 3)
        // Shorter than estimated: the smaller real price.
        XCTAssertEqual(ScriptVoiceover.cappedChargeMinutes(actualAudioSeconds: 30, quotedMinutes: 3), 2)
        // Never zero.
        XCTAssertEqual(ScriptVoiceover.cappedChargeMinutes(actualAudioSeconds: 0.1, quotedMinutes: 3), 1)
    }

    func testScriptQuoteUsesTheReadingEstimate() {
        let text = Array(repeating: "word", count: 140).joined(separator: " ")   // 1 min at 140 wpm
        XCTAssertEqual(ScriptVoiceover.estimatedAudioSeconds(text: text, language: "en"), 60)
        XCTAssertEqual(ScriptVoiceover.quoteMinutes(text: text, language: "en"), 3)
    }

    // MARK: - Assembly

    func testJoinShiftsTimingsOntoTheJoinedAudio() {
        let rate = 1000.0
        func take(_ n: Int) -> [Float] {
            [Float](repeating: 0, count: 100) + [Float](repeating: 0.5, count: n) + [Float](repeating: 0, count: 100)
        }
        let a = (take(300), [WordTiming(word: "One.", startMs: 100, endMs: 400)])
        let b = (take(300), [WordTiming(word: "Two.", startMs: 100, endMs: 400)])
        let joined = ScriptVoiceoverAudio.join([a, b], rate: rate, endsParagraph: [false, true])
        // First take kept whole up to its voice + margin; the second starts
        // after the 0.42 s gap, trimmed to its voice.
        XCTAssertEqual(joined.timings.map(\.word), ["One.", "Two."])
        XCTAssertEqual(joined.timings[0].startMs, 100)
        let secondVoiceStart = joined.timings[1].startMs
        let firstVoiceEnd = joined.timings[0].endMs
        XCTAssertEqual(Double(secondVoiceStart - firstVoiceEnd), 420, accuracy: 20)
    }
}
