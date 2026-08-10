import XCTest
@testable import FutureVoice

/// The streaming Watch scene plays turns out of JSON that is still being
/// written. `completedArrayObjects` decides which turns are safe to speak —
/// a half-written object must never leak, and a later array must never be
/// mistaken for this one.
final class SceneStreamTests: XCTestCase {

    func testYieldsOnlyClosedObjects() {
        let partial = #"{"title": "Ordering", "turns": [{"speaker": "user", "text": "Hi"}, {"speaker": "counterpart", "text": "Welcome"}, {"speaker": "user", "text": "Cou"#
        let objects = GeminiClient.completedArrayObjects("turns", in: partial)
        XCTAssertEqual(objects.count, 2)
        XCTAssertEqual(String(objects[0]), #"{"speaker": "user", "text": "Hi"}"#)
        XCTAssertEqual(String(objects[1]), #"{"speaker": "counterpart", "text": "Welcome"}"#)
    }

    func testEmptyUntilTheArrayOpens() {
        XCTAssertTrue(GeminiClient.completedArrayObjects("turns", in: #"{"title": "Ordering", "tur"#).isEmpty)
        XCTAssertTrue(GeminiClient.completedArrayObjects("turns", in: #"{"turns":"#).isEmpty)
        XCTAssertTrue(GeminiClient.completedArrayObjects("turns", in: #"{"turns": ["#).isEmpty)
    }

    /// Braces, brackets and escaped quotes INSIDE string values are content,
    /// not structure.
    func testStructureCharactersInsideStringsAreIgnored() {
        let partial = #"{"turns": [{"speaker": "user", "text": "He said \"go {now}\" [twice]"}, {"speaker":"#
        let objects = GeminiClient.completedArrayObjects("turns", in: partial)
        XCTAssertEqual(objects.count, 1)
        XCTAssertTrue(String(objects[0]).contains(#"\"go {now}\" [twice]"#))
    }

    /// The words array follows turns in the scene schema — its objects must
    /// not be counted as turns once the turns array has closed.
    func testStopsAtTheArraysOwnClose() {
        let partial = #"{"turns": [{"speaker": "user", "text": "Hi"}], "words": [{"text": "brew", "note": "n"}]"#
        let objects = GeminiClient.completedArrayObjects("turns", in: partial)
        XCTAssertEqual(objects.count, 1)
        XCTAssertEqual(String(objects[0]), #"{"speaker": "user", "text": "Hi"}"#)
        // And asking for the LATER array still finds its own elements.
        let words = GeminiClient.completedArrayObjects("words", in: partial)
        XCTAssertEqual(words.count, 1)
        XCTAssertTrue(String(words[0]).contains("brew"))
    }

    func testAbsentKeyYieldsNothing() {
        XCTAssertTrue(GeminiClient.completedArrayObjects("turns", in: #"{"title": "Ordering"}"#).isEmpty)
    }

    /// A slice must decode as the payload's turn shape — the engine feeds
    /// each one straight to JSONDecoder.
    func testSlicesAreDecodableJSON() throws {
        let partial = #"{"turns": [{"speaker": "user", "text": "Two flat whites, please."}, {"#
        let objects = GeminiClient.completedArrayObjects("turns", in: partial)
        XCTAssertEqual(objects.count, 1)
        struct TurnItem: Decodable { let speaker: String; let text: String }
        let item = try JSONDecoder().decode(TurnItem.self,
                                            from: Data(String(objects[0]).utf8))
        XCTAssertEqual(item.speaker, "user")
        XCTAssertEqual(item.text, "Two flat whites, please.")
    }

    /// Nested objects inside a turn (should the schema ever grow one) close
    /// at THEIR brace, not the turn's — depth tracking, not first-`}` wins.
    func testNestedObjectsStayInsideTheirElement() {
        let partial = #"{"turns": [{"speaker": "user", "meta": {"tone": "warm"}, "text": "Hi"}, {"spe"#
        let objects = GeminiClient.completedArrayObjects("turns", in: partial)
        XCTAssertEqual(objects.count, 1)
        XCTAssertTrue(String(objects[0]).hasSuffix(#""text": "Hi"}"#))
    }
}
