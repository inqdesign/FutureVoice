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

    /// An inserted word is dropped before lining up with the script; the
    /// silence around it is not judged as one pause (the filler is counted
    /// on its own); a piece whose words still don't match is not counted.
    func testInsertionsAreSkippedAndMismatchesLeftOut() {
        let lined = SpeechDelivery.Piece(reference: "one two three", result: result([
            word("one", 0), word("um", 300, error: "Insertion"), word("two", 700), word("three", 1300),
        ]))
        let d = SpeechDelivery.timing([lined], language: "en")
        XCTAssertEqual(d.midPauses, 1)        // two|three, 0.3 s
        XCTAssertEqual(d.midBoundaries, 1)    // one|two is not judged
        let off = SpeechDelivery.Piece(reference: "alpha beta", result: result([
            word("one", 0), word("two", 300), word("three", 600),
        ]))
        XCTAssertNil(SpeechDelivery.timing([off], language: "en").midPauses)
    }

    /// A real script splits differently from Azure's words: a dash is its
    /// own token, a hyphenated word is two. They line up by content, a
    /// dash is a phrase boundary, and nothing is thrown away (2026-11-07:
    /// requiring equal counts skipped whole pieces, so a halting read got
    /// full marks for phrasing).
    func testDashesAndHyphensLineUp() {
        let piece = SpeechDelivery.Piece(
            reference: "We met — briefly — at a well-known café.",
            result: result([
                word("we", 0), word("met", 300),
                word("briefly", 1100),               // after a dash: 0.5 s, fine
                word("at", 1900),                    // after a dash: 0.5 s, fine
                word("a", 2200),
                word("well", 2900),                  // 0.4 s mid-phrase: counted
                word("known", 3200), word("café", 3500),
            ]))
        let d = SpeechDelivery.timing([piece], language: "en")
        XCTAssertEqual(d.midPauses, 1)
        XCTAssertEqual(d.midBoundaries, 5)   // we|met at|a a|well well|known known|café
        XCTAssertEqual(d.breaks.first?.before, "a")
    }

    /// A repeated or added word between script words is a stumble; at a
    /// piece's edge it is the cut, and a filler is counted elsewhere.
    func testStumblesAreInteriorInsertions() {
        let piece = SpeechDelivery.Piece(reference: "the quick brown fox jumps", result: result([
            word("so", 0, error: "Insertion"),       // before the first script word: the cut
            word("the", 300), word("quick", 600),
            word("quick", 900, error: "Insertion"),  // a repeat: a stumble
            word("um", 1200, error: "Insertion"),    // a filler: counted elsewhere
            word("brown", 1500), word("fox", 1800), word("jumps", 2100),
            word("over", 2400, error: "Insertion"),  // after the last: the cut
        ]))
        XCTAssertEqual(SpeechDelivery.timing([piece], language: "en").stumbles, ["quick"])
    }

    /// The founder's take, 2026-11-07: "the five-minute rule" read as "the
    /// five minutes rule". Azure files "five minutes" as added and
    /// "five-minute" as left out. That is one word said differently, not a
    /// stumble, and the 0.8 s it took is not a pause between "the" and
    /// "rule".
    func testAWordSaidDifferentlyIsNotAStumbleOrAPause() {
        let piece = SpeechDelivery.Piece(reference: "about the five-minute rule here", result: result([
            word("about", 0), word("the", 300),
            word("five", 600, error: "Insertion"), word("minutes", 900, error: "Insertion"),
            word("five-minute", 0, 0, error: "Omission"),
            word("rule", 1400), word("here", 1700),
        ]))
        let d = SpeechDelivery.timing([piece], language: "en")
        XCTAssertEqual(d.stumbles, [])
        XCTAssertEqual(d.midPauses, 0)
        XCTAssertTrue(d.breaks.isEmpty)
    }

    /// A read-back that lost words Azure heard gives way to Azure's text;
    /// one that kept them stands; with no Azure text nothing changes.
    func testShortReadBackGivesWayToAzure() {
        let azure = "And guess what? This morning I ran for half an hour and I didn't even notice."
        let lost = SpeechTakeSession.pieceText(readBack: "And guess what? This morning I went for",
                                               heard: azure, language: "en")
        XCTAssertEqual(lost?.text, azure)
        XCTAssertEqual(lost?.replaced, true)
        XCTAssertEqual(SpeechTakeSession.pieceText(readBack: "", heard: azure, language: "en")?.text, azure)
        let kept = SpeechTakeSession.pieceText(
            readBack: "And guess what, this morning I went for half an hour and I did not even notice.",
            heard: azure, language: "en")
        XCTAssertEqual(kept?.replaced, false)
        XCTAssertNil(SpeechTakeSession.pieceText(readBack: nil, heard: nil, language: "en"))
        XCTAssertEqual(SpeechTakeSession.pieceText(readBack: "hi", heard: "", language: "en")?.text, "hi")
    }

    /// Azure judged the piece against a script span that didn't cover the
    /// audio and wrote words out of that span: its text is no transcript,
    /// however short the read-back looks beside it.
    func testAzureTextFromAnUncoveredSpanNeverStandsIn() {
        let azure = "1000 people aged people 2025 in 2025 a nature a people aged people was people in the aging more looked looked the aging"
        let read = "thousand people aged fifty-one to ninety in twenty-seven"
        let kept = SpeechTakeSession.pieceText(readBack: read, heard: azure, insertions: 18, language: "en")
        XCTAssertEqual(kept?.text, read)
        XCTAssertEqual(kept?.replaced, false)
        XCTAssertNil(SpeechTakeSession.pieceText(readBack: "", heard: azure, insertions: 18, language: "en"))
        XCTAssertNil(SpeechTakeSession.pieceText(readBack: nil, heard: azure, insertions: 18, language: "en"))
        // A covered span (a few stray words at most) still stands in.
        XCTAssertEqual(SpeechTakeSession.pieceText(readBack: read, heard: azure, insertions: 3, language: "en")?.replaced, true)
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

final class SpeechRescoreCutTests: XCTestCase {
    private func wav(seconds: Double) -> Data {
        AudioLoudness.wavData(fromPCM16: Data(count: Int(seconds * 16_000) * 2), sampleRate: 16_000)
    }

    /// A stored take is cut where it was cut; the piece that opened during
    /// the countdown starts at the file's start.
    func testCutsFollowTheStoredStarts() {
        let cuts = SpeechRescore.cuts(ofWAV: wav(seconds: 60), startsMs: [-2292, 22_000, 44_500])
        XCTAssertEqual(cuts.map(\.startMs), [0, 22_000, 44_500])
        XCTAssertEqual(cuts.map { ($0.wav.count - 44) / 32 }, [22_000, 22_500, 15_500])
    }

    /// No stored cuts, or one too long to assess: windows instead.
    func testCutsFallBackToWindows() {
        XCTAssertGreaterThan(SpeechRescore.cuts(ofWAV: wav(seconds: 70), startsMs: nil).count, 1)
        let long = SpeechRescore.cuts(ofWAV: wav(seconds: 80), startsMs: [0, 40_000])
        XCTAssertTrue(long.allSatisfy { Double($0.wav.count - 44) / 32_000 <= 30 })
        XCTAssertEqual(long.map { ($0.wav.count - 44) / 2 }.reduce(0, +), 80 * 16_000)
    }
}
