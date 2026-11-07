import XCTest
@testable import FutureVoice

final class SpeechDeliveryTests: XCTestCase {
    private func word(_ w: String, _ startMs: Int, _ ms: Int = 300, error: String = "None",
                      sounds: [Int] = [95]) -> PronunciationResult.Word {
        .init(word: w, accuracy: sounds.min(), error: error, offsetMs: startMs, durationMs: ms,
              phonemes: sounds.map { .init(phoneme: "a", accuracy: $0, heard: nil) })
    }

    private func result(_ words: [PronunciationResult.Word], prosody: Int? = 90) -> PronunciationResult {
        .init(score: 90, accuracy: 95, fluency: 92, completeness: 100, prosody: prosody,
              locale: "en-US", recognized: "", words: words)
    }

    /// A pause mid-phrase counts; a pause after a comma or a full stop
    /// doesn't, and the sentence-end pause is left out of the reading pace.
    func testPausesArePlacedAgainstTheScript() {
        let piece = SpeechDelivery.Piece(
            reference: "Good morning, everyone. Welcome to the show",
            result: result([
                word("good", 0), word("morning", 300),
                word("everyone", 900),                    // after a comma: 0.3 s, fine
                word("welcome", 2200),                    // after a full stop: 1.0 s, not counted
                word("to", 2500), word("the", 3200),      // 0.4 s mid-phrase: counted
                word("show", 3500),
            ]))
        let d = SpeechDelivery.timing([piece], language: "en")
        XCTAssertEqual(d.midPauses, 1)
        XCTAssertEqual(d.midBoundaries, 4)   // good|morning, welcome|to, to|the, the|show
        XCTAssertEqual(d.prosody, 90)
    }

    /// An inserted word is dropped before lining up with the script; a
    /// piece whose words still don't match is not counted at all.
    func testInsertionsAreSkippedAndMismatchesLeftOut() {
        let lined = SpeechDelivery.Piece(reference: "one two three", result: result([
            word("one", 0), word("um", 300, error: "Insertion"), word("two", 700), word("three", 1000),
        ]))
        XCTAssertEqual(SpeechDelivery.timing([lined], language: "en").midPauses, 1)
        let off = SpeechDelivery.Piece(reference: "one two", result: result([
            word("one", 0), word("two", 300), word("three", 600),
        ]))
        XCTAssertNil(SpeechDelivery.timing([off], language: "en").midPauses)
    }

    func testWeakSoundsIsTheFifthPercentile() {
        let sounds = Array(repeating: 95, count: 39) + [20]
        let piece = SpeechDelivery.Piece(reference: "a", result: result([word("a", 0, sounds: sounds)]))
        XCTAssertEqual(SpeechDelivery.timing([piece], language: "en").weakSounds, 95)
        let worse = Array(repeating: 95, count: 9) + [20]
        let piece2 = SpeechDelivery.Piece(reference: "a", result: result([word("a", 0, sounds: worse)]))
        XCTAssertEqual(SpeechDelivery.timing([piece2], language: "en").weakSounds, 20)
    }

    /// A steady tone has no pitch movement; a glide of an octave spans most
    /// of one.
    func testPitchRangeFollowsTheVoice() {
        let rate = 16000.0
        func tone(_ hz: (Double) -> Double, seconds: Double) -> [Float] {
            var phase = 0.0
            return (0..<Int(seconds * rate)).map { i in
                phase += 2 * .pi * hz(Double(i) / rate) / rate
                return Float(0.5 * sin(phase) + 0.2 * sin(2 * phase))
            }
        }
        let flat = PitchTracker.stats(tone({ _ in 150 }, seconds: 2), rate: rate)
        XCTAssertNotNil(flat)
        XCTAssertLessThan(flat!.rangeSemitones, 0.5)
        let glide = PitchTracker.stats(tone({ t in 120 * pow(2, t / 2) }, seconds: 2), rate: rate)
        XCTAssertNotNil(glide)
        XCTAssertGreaterThan(glide!.rangeSemitones, 7)
        XCTAssertLessThan(glide!.rangeSemitones, 11)
    }
}
