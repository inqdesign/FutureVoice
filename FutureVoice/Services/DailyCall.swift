import Foundation

/// How a call ended. The distinction is the whole point of tracking it: an
/// alarm you dismiss leaves nothing behind, but a call carries a fact about
/// what the other person's attempt ran into — and the NEXT call is written
/// from that fact (`VoicemailEngine.Context.lastOutcome`). A caller who
/// remembers you were busy yesterday is a person; one who opens identically
/// every morning is a timer.
enum DailyCallOutcome: String, Codable {
    /// Picked up. The talk started.
    case answered
    /// They saw it ring and sent it away. A decision, not an absence.
    case declined
    /// Rang out with nobody there. Detected after the fact, on next launch.
    case missed
}

/// The daily call from the fluent self — the app's habit anchor.
///
/// Nobody opens a language app because a streak counter asks them to; they
/// answer a phone that rings. Korean 전화영어 runs on exactly that mechanic, and
/// its biggest churn reason is the embarrassment of stumbling in front of a
/// stranger. Here the caller IS the learner, so only the schedule's pull is
/// left.
///
/// What makes this read as a CALL rather than an alarm is not the screen — iOS
/// reserves the incoming-call UI for CallKit and nothing else gets it. It is
/// that somebody is on the other end: the ring is a phone ringing, the script
/// is grounded in the last talk, and a call that goes unanswered leaves a trace
/// instead of evaporating. An alarm announces a time; this announces a person.
struct DailyCallPlan: Codable, Equatable, Identifiable {
    var id: UUID
    /// What the fluent self says. Always ends in a question — an unanswered
    /// question is the whole pull; a statement is just another notification.
    /// TARGET language: the learner hears it and answers it out loud.
    var script: String
    /// The language `script` was written for. A language switch invalidates
    /// the plan rather than calling in a language they aren't practicing.
    var language: String
    /// The clone that spoke it. After a re-record the audio is the learner's
    /// PREVIOUS voice — cheap to regenerate, and "that sounds like me" is the
    /// one thing this call sells.
    var voiceId: String?
    var scheduledFor: Date
    /// How many times the caller has tried again today. Capped — see
    /// `DailyCallScheduler.maxCallbacks`.
    var callbackCount: Int
    var createdAt: Date
    /// nil while the call is still live (pending, or ringing back).
    var outcome: DailyCallOutcome?
    var endedAt: Date?
    /// Set once the learner has actually HEARD the voicemail. A missed call
    /// whose message is still unplayed is what the Talk tab surfaces — the
    /// "someone tried to reach you" trace an alarm can never leave.
    var heardAt: Date?

    var isSettled: Bool { outcome != nil }
    /// A call that went unanswered and whose message is still sitting there.
    var hasUnheardVoicemail: Bool {
        heardAt == nil && (outcome == .missed || outcome == .declined)
    }

    /// Whether this plan can still ring for `language` in `voiceId`. A
    /// mismatch isn't an error — it means the world moved and the plan should
    /// be rewritten before it fires.
    func matches(language: String, voiceId: String?) -> Bool {
        self.language == language && self.voiceId == voiceId
    }
}

/// One finished call, kept so the next one can be written knowing how the last
/// few went. Deliberately small — this is the caller's memory, not an archive.
struct DailyCallRecord: Codable, Equatable {
    var date: Date
    var outcome: DailyCallOutcome
    /// How many times they had to ring back before it settled.
    var callbacks: Int
}

/// Disk + defaults for the daily call. Deliberately NOT language-scoped: only
/// one call is ever pending, and the plan carries its own `language` so a
/// switch invalidates it instead of leaving a second one queued in the old
/// language's directory.
@MainActor
final class DailyCallStore {
    static let shared = DailyCallStore()

    // MARK: - Settings

    private static let enabledKey = "futurevoice.dailyCall.enabled"
    private static let hourKey = "futurevoice.dailyCall.hour"
    private static let minuteKey = "futurevoice.dailyCall.minute"

    /// Off until the learner turns it on. A cloned voice calling unannounced
    /// on day one is a support ticket, not a feature.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    /// Hour of day (0–23) the call comes in. Defaults to 08:00 — before the
    /// day fills up, which is when a five-minute call actually happens.
    var hour: Int {
        get {
            guard UserDefaults.standard.object(forKey: Self.hourKey) != nil else { return 8 }
            return min(23, max(0, UserDefaults.standard.integer(forKey: Self.hourKey)))
        }
        set { UserDefaults.standard.set(min(23, max(0, newValue)), forKey: Self.hourKey) }
    }

    var minute: Int {
        get { min(59, max(0, UserDefaults.standard.integer(forKey: Self.minuteKey))) }
        set { UserDefaults.standard.set(min(59, max(0, newValue)), forKey: Self.minuteKey) }
    }

    // MARK: - The ring

    /// A fixed asset compiled into the app, and that is not an aesthetic
    /// choice — it's the only thing that plays.
    ///
    /// AlarmKit and `UNNotificationSound` both accept a named sound, but on
    /// iOS 26 a file written at RUNTIME (the only kind an app can put in
    /// `Library/Sounds`) is silently ignored and the default plays instead;
    /// only bundle resources work. The voicemail is generated per learner per
    /// day, so it can never be one. A ringtone is identical for everyone, so
    /// it can — and a phone that rings and *then* has someone talk on it is
    /// what a call actually is. The voice arrives the instant they answer.
    static let ringtoneFilename = "ringtone.wav"

    // MARK: - Plan

    private let planURL: URL
    private let historyURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// Double optional: `.none` = never read from disk, `.some(nil)` = read,
    /// there is no plan. Without it every "is there a plan?" check on a fresh
    /// install re-hits the filesystem.
    private var cachedPlan: DailyCallPlan??
    private var cachedHistory: [DailyCallRecord]?

    /// How many finished calls the caller remembers. Enough to notice a run of
    /// silence, short enough that it stays a memory rather than a record.
    private static let historyLimit = 14

    init(planFilename: String = "daily_call.json",
         historyFilename: String = "daily_call_history.json") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.planURL = docs.appendingPathComponent(planFilename)
        self.historyURL = docs.appendingPathComponent(historyFilename)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    func load() -> DailyCallPlan? {
        if let cachedPlan { return cachedPlan }
        let plan = (try? Data(contentsOf: planURL)).flatMap {
            try? decoder.decode(DailyCallPlan.self, from: $0)
        }
        cachedPlan = .some(plan)
        return plan
    }

    func save(_ plan: DailyCallPlan) {
        cachedPlan = .some(plan)
        guard let data = try? encoder.encode(plan) else { return }
        try? data.write(to: planURL, options: .atomic)
    }

    /// Drop the plan — the learner turned the call off, or switched language.
    /// History survives: the caller's memory of them shouldn't reset just
    /// because the schedule did.
    func clear() {
        cachedPlan = .some(nil)
        try? FileManager.default.removeItem(at: planURL)
    }

    // MARK: - History (the caller's memory)

    /// Finished calls, newest first.
    func history() -> [DailyCallRecord] {
        if let cachedHistory { return cachedHistory }
        let loaded = (try? Data(contentsOf: historyURL)).flatMap {
            try? decoder.decode([DailyCallRecord].self, from: $0)
        } ?? []
        cachedHistory = loaded
        return loaded
    }

    func record(_ record: DailyCallRecord) {
        var all = [record] + history()
        if all.count > Self.historyLimit { all = Array(all.prefix(Self.historyLimit)) }
        cachedHistory = all
        guard let data = try? encoder.encode(all) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }

    /// Consecutive unanswered calls, most recent first — the caller's sense of
    /// "I haven't reached you in a while". Stops at the first pickup.
    func consecutiveUnanswered() -> Int {
        history().prefix { $0.outcome != .answered }.count
    }
}
