import XCTest
@testable import FutureVoice

/// Pins the sentence split (identical to the gateway's `CallSession.sentenceEnd`)
/// and the join: inner edges trimmed to the voice, one fixed gap between.
final class PacedSpeechTests: XCTestCase {
    func testSplitsEverySpacedAndCJKSentence() {
        XCTAssertEqual(PacedSpeech.sentences(in: "그거 힘들었겠다. 나도 그랬거든. 어떻게 했어?"),
                       ["그거 힘들었겠다.", "나도 그랬거든.", "어떻게 했어?"])
        XCTAssertEqual(PacedSpeech.sentences(in: "それは大変だったね。私も去年、似たことがあった。それで？"),
                       ["それは大変だったね。", "私も去年、似たことがあった。", "それで？"])
    }

    func testDoesNotCutAbbreviationsOrQuotedJapanese() {
        XCTAssertEqual(PacedSpeech.sentences(in: "Mr. Kim said hi! Ok"), ["Mr. Kim said hi!", "Ok"])
        XCTAssertEqual(PacedSpeech.sentences(in: "Wir gehen z.B. morgen. Gut?"),
                       ["Wir gehen z.B. morgen.", "Gut?"])
        XCTAssertEqual(PacedSpeech.sentences(in: "彼は「行く。」と言った。次"),
                       ["彼は「行く。」と言った。", "次"])
    }

    func testOneSentenceIsOne() {
        XCTAssertEqual(PacedSpeech.sentences(in: "Hey, how's it going?"), ["Hey, how's it going?"])
    }

    /// silence(a) + tone(b) + silence(c), 16 kHz.
    private func take(lead: Double, voice: Double, trail: Double) -> Data {
        let sr = 16000.0
        var samples = [Int16](repeating: 0, count: Int(lead * sr))
        samples += (0 ..< Int(voice * sr)).map { Int16(12000 * sin(Double($0) * 2 * .pi * 220 / sr)) }
        samples += [Int16](repeating: 0, count: Int(trail * sr))
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    func testJoinPutsOneFixedGapBetweenVoices() {
        let sr = 16000.0
        let a = take(lead: 0.10, voice: 0.5, trail: 0.40)
        let b = take(lead: 0.15, voice: 0.5, trail: 0.30)
        let joined = PacedSpeech.joined([a, b], sampleRate: sr)
        // First take's lead and last take's trail are kept as synthesized.
        let seconds = Double(joined.count / 2) / sr
        XCTAssertEqual(seconds, 0.10 + 0.5 + PacedSpeech.sentenceGapSeconds + 0.5 + 0.30, accuracy: 0.03)
        let span = PacedSpeech.voicedSpan(joined.subdata(in: Int(0.7 * sr) * 2 ..< Int(1.3 * sr) * 2),
                                          sampleRate: sr)
        XCTAssertNotNil(span)
    }
}
