import XCTest
@testable import FutureVoice

/// The summary's coaching fields quote target-language words as `「"had"」`
/// with the inner quotes unescaped (every excerpt in the week of 2026-09-25).
/// `decodeRepairing` must read those, and must never touch a body that
/// already decodes.
final class GeminiJSONRepairTests: XCTestCase {
    private struct Phrase: Decodable, Equatable { let userSaid: String; let reason: String }
    private struct Body: Decodable, Equatable { let phrases: [Phrase]; let title: String }

    private func decode(_ s: String) throws -> Body {
        try GeminiClient.decodeRepairing(Body.self, from: Data(s.utf8))
    }

    func testReportedShapesDecode() throws {
        let cases: [(String, String)] = [
            (#"과거 일을 이야기할 때는 「"had"」처럼 과거형을 사용해요."#,
             "과거 일을 이야기할 때는 「\"had\"」처럼 과거형을 사용해요."),
            (#"현재완료 시제 「"have seen"」으로 표현하는 것이 자연스럽습니다."#,
             "현재완료 시제 「\"have seen\"」으로 표현하는 것이 자연스럽습니다."),
            (#"표준 용어는 「"research and development"」입니다."#,
             "표준 용어는 「\"research and development\"」입니다."),
        ]
        for (raw, expected) in cases {
            let json = """
            {
              "phrases": [
                {
                  "userSaid": "I have a good time",
                  "reason": "\(raw)"
                }
              ],
              "title": "Weekend"
            }
            """
            let body = try decode(json)
            XCTAssertEqual(body.phrases.first?.reason, expected)
            XCTAssertEqual(body.title, "Weekend")
        }
    }

    func testBareInteriorQuotesDecode() throws {
        let json = #"{"phrases":[{"userSaid":"x","reason":"say "went" here"}],"title":"t"}"#
        XCTAssertEqual(try decode(json).phrases.first?.reason, #"say "went" here"#)
    }

    func testValidJSONIsUntouched() throws {
        let json = #"{"phrases":[{"userSaid":"a, b","reason":"「\"had\"」 ok: yes"}],"title":"t"}"#
        XCTAssertNil(GeminiClient.repairingInteriorQuotes(json))
        XCTAssertEqual(try decode(json).phrases.first?.reason, "「\"had\"」 ok: yes")
    }

    func testUnrepairableThrowsOriginalError() {
        let json = #"{"phrases":[{"userSaid":"x""#
        XCTAssertThrowsError(try decode(json)) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("expected the decoder's own error, got \(error)")
            }
        }
    }
}
