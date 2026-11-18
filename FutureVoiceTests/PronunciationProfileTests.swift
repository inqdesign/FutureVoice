import XCTest
@testable import FutureVoice

/// The pronunciation standing is read across takes (`PronunciationLedger`),
/// and a word Azure never heard is not a mispronounced word.
final class PronunciationProfileTests: XCTestCase {

    private func word(_ w: String, _ acc: Int?, error: String = "None",
                      phonemes: [(String, Int)] = []) -> PronunciationResult.Word {
        .init(word: w, accuracy: acc, error: error, offsetMs: 0, durationMs: 0,
              phonemes: phonemes.map { .init(phoneme: $0.0, accuracy: $0.1) })
    }

    private func result(_ words: [PronunciationResult.Word], accuracy: Int = 90, locale: String = "en-US")
    -> PronunciationResult {
        .init(score: 85, accuracy: accuracy, fluency: 80, completeness: 100, prosody: nil,
              locale: locale, recognized: "", words: words)
    }

    func testOmissionAndInsertionAreNeverMarked() {
        let r = result([
            word("a", 0, error: "Omission"),
            word("works", 99, error: "Insertion"),
            word("think", 94, phonemes: [("θ", 32), ("ɪ", 90), ("ŋ", 95)]),
            word("some", 40),
        ])
        XCTAssertEqual(r.weakWords.map(\.word), ["some", "think"])
        XCTAssertFalse(r.words[0].isMispronounced)
        XCTAssertFalse(r.words[0].isShaky)
        XCTAssertEqual(r.judgedWords.count, 2)
        XCTAssertEqual(r.soundScore, 90)
    }

    func testProfileAveragesSoundsAcrossTakesAndNeedsSamples() {
        var entries: [PronunciationEntry] = []
        for i in 0..<3 {
            let r = result([
                word("think", 80, phonemes: [("θ", 50 + i), ("ɪ", 95)]),
                word("this", 85, phonemes: [("ð", 40), ("ɪ", 90), ("s", 100)]),
                word("only", 55),
            ])
            entries.append(PronunciationEntry(id: UUID(), date: Date(), surface: "shadow", results: [r])!)
        }
        let p = PronunciationProfile.build(entries)
        XCTAssertEqual(p.takes, 3)
        XCTAssertEqual(p.meanAccuracy, 90)
        // θ: 3 samples < minSamples(4) → not a sound yet; ɪ: 6 samples at ~92.
        XCTAssertEqual(p.sounds.map(\.phoneme), ["ɪ"])
        XCTAssertTrue(p.weakSounds.isEmpty)
        // "only" low in three takes is a repeated low word.
        XCTAssertEqual(p.weakWords.map(\.word), ["only"])
    }

    func testTakeNoteNamesSoundsForEnglishAndRepeatedWordsElsewhere() {
        let en = result([
            word("think", 80, phonemes: [("θ", 40), ("ɪ", 95)]),
            word("thanks", 70, phonemes: [("θ", 45), ("æ", 90)]),
        ])
        let enEntry = PronunciationEntry(id: UUID(), date: Date(), surface: "shadow", results: [en])!
        XCTAssertEqual(PronunciationProfile.lowSounds(in: enEntry).map(\.phoneme), ["θ"])

        // German: no phoneme names, so a word is named only when it is low
        // across takes.
        let de1 = result([word("ich", 40, phonemes: [("", 40)]), word("gut", 95)], locale: "de-DE")
        let de2 = result([word("ich", 45, phonemes: [("", 45)]), word("gut", 50)], locale: "de-DE")
        let e1 = PronunciationEntry(id: UUID(), date: Date(), surface: "shadow", results: [de1])!
        let e2 = PronunciationEntry(id: UUID(), date: Date(), surface: "shadow", results: [de2])!
        let profile = PronunciationProfile.build([e1, e2])
        XCTAssertTrue(e2.phonemes.isEmpty, "an unnamed phoneme is no sample")
        XCTAssertEqual(profile.repeatedLowWords(in: e2).map(\.word), ["ich"])
    }

    func testEntryWeightsPiecesByJudgedWords() {
        let big = result((0..<9).map { word("w\($0)", 80) }, accuracy: 80)
        let small = result([word("x", 20)], accuracy: 20)
        let e = PronunciationEntry(id: UUID(), date: Date(), surface: "speech", results: [big, small])!
        XCTAssertEqual(e.accuracy, 74)
        XCTAssertEqual(e.words.count, 10)
    }

    func testSentenceEndInTrack() {
        let t = SpeechPrompterTrack(script: "Hello there. How are you?\" Fine", language: "en")
        XCTAssertTrue(t.endsSentence(at: 1))
        XCTAssertFalse(t.endsSentence(at: 2))
        XCTAssertTrue(t.endsSentence(at: 4))
        XCTAssertFalse(t.endsSentence(at: 5))
        XCTAssertFalse(t.endsSentence(at: 99))
    }

    /// A piece with nothing judged (the stop's 0.2 s tail, every script word
    /// omitted) is not a score of 0 for the take (2026-11-18).
    @MainActor func testPieceWithNothingJudgedIsLeftOut() {
        let heard = result([word("good", 90), word("morning", 88)], accuracy: 90)
        let tail = result([word("sunny", nil, error: "Omission"), word("weekend", nil, error: "Omission")],
                          accuracy: 0)
        XCTAssertEqual(SpeechTakeSession.pronunciation(of: [heard, tail])?.score, 90)
        XCTAssertNil(SpeechTakeSession.pronunciation(of: [tail]))
    }
}
