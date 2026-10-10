import XCTest
@testable import FutureVoice

/// The server's answer when the account's monthly voice allowance is spent
/// (2026-10-10). Its date moves every month, so it is read from the body.
final class VoiceQuotaTests: XCTestCase {
    func testSpentAllowanceCarriesItsDate() throws {
        let body = #"{"error":"voice_quota_full","message":"…","available_at":"2026-10-12T09:24:07.000Z"}"#
        let parsed = VoiceQuota.availableAt(inBody: body)
        XCTAssertNotNil(parsed)
        let date = try XCTUnwrap(parsed ?? nil)
        XCTAssertEqual(date.timeIntervalSince1970, 1791797047, accuracy: 1)
    }

    func testReservedAllowanceWithoutADateIsStillAQuotaAnswer() {
        let body = #"{"error":"voice_quota_reserved","message":"…","available_at":null}"#
        let parsed = VoiceQuota.availableAt(inBody: body)
        XCTAssertNotNil(parsed)                 // a quota answer…
        XCTAssertNil(parsed ?? nil)             // …that didn't say when
    }

    func testOtherFailuresAreNotQuotaAnswers() {
        XCTAssertNil(VoiceQuota.availableAt(inBody: #"{"error":"elevenlabs upstream error"}"#))
        XCTAssertNil(VoiceQuota.availableAt(inBody: "voice_limit_reached"))
    }

    func testErrorExposesTheDate() {
        let error: Error = ElevenLabsError.httpError(
            status: 503, body: #"{"error":"voice_quota_full","available_at":"2026-10-12T09:24:07Z"}"#)
        XCTAssertNotNil(error.voiceQuotaFull)
        XCTAssertNil(ElevenLabsError.insufficientCredits.voiceQuotaFull)
    }
}
