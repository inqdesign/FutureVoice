import XCTest
@testable import FutureVoice

/// The voice-slot ceiling is the one failure the user must never see as raw
/// upstream JSON: it lands at the exact moment the app is promising them their
/// own voice, and nothing they do can clear it. Classification is what decides
/// between the calm `VoiceCapacitySheet` and a red error line, so it's worth
/// pinning both wire shapes it can arrive in.
final class VoiceCapacityTests: XCTestCase {

    /// What our own Edge Function returns once deployed (429 + labelled body).
    func testEdgeFunctionCapacityLabelIsCapacity() {
        let body = #"{"error":"voice_capacity","message":"…","retry_after_seconds":600}"#
        XCTAssertTrue(ElevenLabsError.from(status: 429, body: body).isVoiceCapacityLimited)
    }

    /// What a build shipped AHEAD of the function deploy sees: ElevenLabs
    /// answers `/voices/add` with a 400 whose body nests the marker.
    func testRawUpstreamMarkerIsCapacity() {
        let body = #"{"detail":{"status":"voice_limit_reached","message":"You have reached your voice limit."}}"#
        let error = ElevenLabsError.from(status: 400, body: body)
        XCTAssertTrue(error.isVoiceCapacityLimited)
        XCTAssertTrue((error as Error).isVoiceCapacityLimited)
    }

    /// A bare 429 with no marker is still our ceiling — upstream throttling us
    /// is not something the user caused either.
    func testBareRateLimitIsCapacity() {
        XCTAssertTrue(ElevenLabsError.from(status: 429, body: "").isVoiceCapacityLimited)
    }

    /// Everything else keeps the raw body — it's the only diagnostic a beta
    /// tester can screenshot.
    func testOrdinaryFailureStaysHTTPError() {
        let error = ElevenLabsError.from(status: 500, body: "internal error")
        XCTAssertFalse(error.isVoiceCapacityLimited)
        guard case .httpError(let status, let body) = error else {
            return XCTFail("expected .httpError, got \(error)")
        }
        XCTAssertEqual(status, 500)
        XCTAssertEqual(body, "internal error")
    }

    /// The credit wall has its own copy and its own recovery (top up) — it
    /// must not be swallowed by the capacity sheet.
    func testInsufficientCreditsIsNotCapacity() {
        XCTAssertFalse(ElevenLabsError.insufficientCredits.isVoiceCapacityLimited)
    }
}
