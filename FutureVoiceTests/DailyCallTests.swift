import XCTest
@testable import FutureVoice

/// The daily call's pure logic. Everything here runs with no network, no
/// notification centre and no disk — what's guarded is the handful of rules
/// that decide whether the phone rings at the right moment with something a
/// voice can actually say.
final class DailyCallTests: XCTestCase {

    // MARK: - Script sanitising

    /// A stage direction that survives into TTS gets READ OUT, which breaks
    /// the illusion in the first second. Strip both spellings models reach
    /// for.
    func testSanitizeStripsStageDirections() {
        let cleaned = VoicemailEngine.sanitize("*warmly* Hey! [pause] How did the interview go?")
        XCTAssertFalse(cleaned.contains("*"))
        XCTAssertFalse(cleaned.contains("["))
        XCTAssertEqual(cleaned, "Hey! How did the interview go?")
    }

    func testSanitizeCollapsesWhitespace() {
        XCTAssertEqual(VoicemailEngine.sanitize("  Hey.\n\n  You up?  "), "Hey. You up?")
    }

    /// The question is always the LAST sentence, so an over-budget script has
    /// to be cut at a sentence boundary rather than mid-word — a clipped
    /// script that loses its question is a notification, not a call.
    func testSanitizeTrimsAtSentenceBoundaryAndKeepsTheQuestion() {
        let long = String(repeating: "This is a filler sentence. ",
                          count: 40) + "So what happened?"
        let cleaned = VoicemailEngine.sanitize(long)
        XCTAssertLessThanOrEqual(cleaned.count, VoicemailEngine.maxScriptCharacters)
        XCTAssertTrue(".!?".contains(cleaned.last!),
                      "trimmed script must end on a sentence terminator, got: \(cleaned)")
    }

    func testSanitizeLeavesShortScriptsAlone() {
        let script = "Hey, that cafe line you tried yesterday — did you use it?"
        XCTAssertEqual(VoicemailEngine.sanitize(script), script)
    }

    // MARK: - Ringtone length

    /// iOS silently swaps a too-long notification sound for the default one,
    /// so the PCM is cut even when the character budget was somehow beaten.
    func testTrimEnforcesTheOSSoundCeiling() {
        let sampleRate = 22_050.0
        let fortySeconds = Data(count: Int(sampleRate * 40) * 2)
        let trimmed = VoicemailEngine.trim(pcm: fortySeconds, sampleRate: sampleRate,
                                           to: VoicemailEngine.maxVoicemailSeconds)
        XCTAssertEqual(trimmed.count, Int(sampleRate * VoicemailEngine.maxVoicemailSeconds) * 2)
    }

    func testTrimLeavesShortAudioUntouched() {
        let sampleRate = 22_050.0
        let tenSeconds = Data(count: Int(sampleRate * 10) * 2)
        XCTAssertEqual(
            VoicemailEngine.trim(pcm: tenSeconds, sampleRate: sampleRate,
                                 to: VoicemailEngine.maxVoicemailSeconds).count,
            tenSeconds.count)
    }

    // MARK: - Ringtone level

    /// A clone comes back quieter than a preset voice, and a ringtone under
    /// the room is a missed call. The gain rule must LIFT a quiet take —
    /// without wrapping the samples around on the way.
    func testLeveledBoostsAQuietTakeWithoutClipping() {
        let sampleRate = 22_050
        let quiet = pcm(amplitude: 0.03, seconds: 1, sampleRate: sampleRate)
        let leveled = VoicemailEngine.leveled(quiet)

        XCTAssertEqual(leveled.count, quiet.count, "sample count must not change")
        XCTAssertGreaterThan(peak(of: leveled), peak(of: quiet), "quiet take should be lifted")
        XCTAssertLessThanOrEqual(peak(of: leveled), 1.0)
    }

    func testLeveledHandlesSilenceWithoutCrashing() {
        let silence = Data(count: 4096)
        XCTAssertEqual(VoicemailEngine.leveled(silence), silence)
    }

    func testLeveledHandlesEmptyAudio() {
        XCTAssertEqual(VoicemailEngine.leveled(Data()), Data())
    }

    // MARK: - Fire time

    @MainActor
    func testNextFireDateIsTodayWhenTheHourHasNotPassed() throws {
        let cal = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(DateComponents(
            calendar: cal, year: 2026, month: 8, day: 10, hour: 6, minute: 0).date)

        let fire = try XCTUnwrap(
            DailyCallScheduler.nextFireDate(after: now, calendar: cal, hour: 8, minute: 0))

        XCTAssertEqual(cal.dateComponents([.day, .hour], from: fire).day, 10)
        XCTAssertEqual(cal.dateComponents([.day, .hour], from: fire).hour, 8)
    }

    /// Past the hour, the call belongs to tomorrow — never "immediately",
    /// which is how a relaunch at noon would otherwise ring in the user's
    /// hand.
    @MainActor
    func testNextFireDateRollsToTomorrowOnceTheHourHasPassed() throws {
        let cal = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(DateComponents(
            calendar: cal, year: 2026, month: 8, day: 10, hour: 12, minute: 30).date)

        let fire = try XCTUnwrap(
            DailyCallScheduler.nextFireDate(after: now, calendar: cal, hour: 8, minute: 0))

        XCTAssertGreaterThan(fire, now)
        XCTAssertEqual(cal.dateComponents([.day, .hour], from: fire).day, 11)
        XCTAssertEqual(cal.dateComponents([.day, .hour], from: fire).hour, 8)
    }

    // MARK: - Plan validity

    /// A language switch or a re-record must invalidate the standing plan —
    /// calling someone in a language they aren't practicing, or in a voice
    /// that is no longer theirs, is worse than not calling.
    func testPlanOnlyMatchesItsOwnLanguageAndVoice() {
        let plan = DailyCallPlan(
            id: UUID(), script: "Hey, how did it go?", language: "en",
            voiceId: "voice-a", scheduledFor: Date(),
            callbackCount: 0, createdAt: Date(), outcome: nil,
            endedAt: nil, heardAt: nil)

        XCTAssertTrue(plan.matches(language: "en", voiceId: "voice-a"))
        XCTAssertFalse(plan.matches(language: "de", voiceId: "voice-a"))
        XCTAssertFalse(plan.matches(language: "en", voiceId: "voice-b"))
        XCTAssertFalse(plan.matches(language: "en", voiceId: nil))
    }

    // MARK: - The missed-call trace

    /// The one behaviour that separates this from an alarm: a call nobody
    /// answered leaves its message behind. A dismissed alarm leaves nothing.
    func testUnansweredCallLeavesItsMessageWaiting() {
        XCTAssertTrue(plan(outcome: .missed).hasUnheardVoicemail)
        XCTAssertTrue(plan(outcome: .declined).hasUnheardVoicemail)
    }

    /// Answering IS hearing it — the voicemail becomes the talk's opening
    /// line, so the trace must not also sit on the home screen afterwards.
    func testAnsweredCallLeavesNoTrace() {
        XCTAssertFalse(plan(outcome: .answered, heard: true).hasUnheardVoicemail)
    }

    /// Played back from the missed-call row: the trace is spent. It's a trace,
    /// not a standing reminder — it must never accumulate into a guilt pile.
    func testPlayingTheMessageClearsTheTrace() {
        XCTAssertFalse(plan(outcome: .missed, heard: true).hasUnheardVoicemail)
    }

    /// A call still ringing (or still waiting to ring) is not a missed one.
    func testLiveCallIsNeitherSettledNorATrace() {
        let live = plan(outcome: nil)
        XCTAssertFalse(live.isSettled)
        XCTAssertFalse(live.hasUnheardVoicemail)
    }

    // MARK: - Helpers

    private func plan(outcome: DailyCallOutcome?, heard: Bool = false) -> DailyCallPlan {
        DailyCallPlan(
            id: UUID(), script: "Hey — how did it go?", language: "en",
            voiceId: "voice-a", scheduledFor: Date(), callbackCount: 0,
            createdAt: Date(), outcome: outcome,
            endedAt: outcome == nil ? nil : Date(),
            heardAt: heard ? Date() : nil)
    }

    /// 16-bit LE mono PCM at a fixed amplitude, as the streaming TTS delivers.
    private func pcm(amplitude: Float, seconds: Double, sampleRate: Int) -> Data {
        let n = Int(Double(sampleRate) * seconds)
        var samples = [Int16](repeating: 0, count: n)
        for i in 0..<n {
            let v = amplitude * sinf(Float(2 * Double.pi * 200 * Double(i) / Double(sampleRate)))
            samples[i] = Int16(max(-1, min(1, v)) * 32767)
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func peak(of pcm: Data) -> Float {
        let count = pcm.count / 2
        guard count > 0 else { return 0 }
        var samples = [Int16](repeating: 0, count: count)
        _ = samples.withUnsafeMutableBytes { pcm.copyBytes(to: $0, count: count * 2) }
        return samples.reduce(Float(0)) { max($0, abs(Float($1) / 32767)) }
    }
}
