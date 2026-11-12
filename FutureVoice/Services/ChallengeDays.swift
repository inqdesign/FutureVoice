import Foundation
import Supabase

/// One LOCAL day of a 100-day challenger: how long they talked and how many
/// speech takes they finished (program/RULES.md: a day = 4+ minutes of talk
/// AND one speech, by the date where they live). The server knows talk only
/// per UTC pool, and speech not at all, so the phone says both.
///
/// These two counts, the date, the time zone id, the platform and the app
/// version are ALL that leaves the phone here. No text, no audio, no score.
struct ChallengeDay: Equatable {
    /// `yyyy-MM-dd` in the phone's own calendar.
    var day: String
    var talkSeconds: Int
    var speechTakes: Int
}

/// The pure half: which days are sent, and whether anything changed.
enum ChallengeDayPlan {
    static let windowDays = 14
    /// A learner who is not in the program is asked about again this often.
    static let askAgainSeconds: TimeInterval = 24 * 3600
    /// After a failed call nothing is tried for this long: the RPC may not
    /// exist yet, and every store write lands on the trigger.
    static let retryAfterFailureSeconds: TimeInterval = 6 * 3600
    /// Someone known to be in the program is retried sooner.
    static let participantRetrySeconds: TimeInterval = 30 * 60

    /// The last `windowDays` local days that have either number, oldest
    /// first. `talkSeconds` is asked per local start-of-day; `speechAt` are
    /// the moments speech takes were saved.
    static func days(now: Date, calendar: Calendar, talkSeconds: (Date) -> Int,
                     speechAt: [Date]) -> [ChallengeDay] {
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"

        var takes: [Date: Int] = [:]
        for at in speechAt { takes[calendar.startOfDay(for: at), default: 0] += 1 }

        let today = calendar.startOfDay(for: now)
        var out: [ChallengeDay] = []
        for back in stride(from: windowDays - 1, through: 0, by: -1) {
            guard let d = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let talk = max(0, talkSeconds(d))
            let speech = takes[d] ?? 0
            guard talk > 0 || speech > 0 else { continue }
            out.append(.init(day: format.string(from: d), talkSeconds: talk, speechTakes: speech))
        }
        return out
    }

    /// What the server was last told. The same days with the same numbers
    /// in the same time zone are not sent again.
    static func fingerprint(_ days: [ChallengeDay], timeZone: String) -> String {
        ([timeZone] + days.map { "\($0.day):\($0.talkSeconds):\($0.speechTakes)" }).joined(separator: "|")
    }

    enum Step: Equatable {
        /// Nothing to do now.
        case wait
        /// The empty call: "am I a participant?"
        case ask
        /// Send the days.
        case send
    }

    static func step(participant: Bool?, askedAt: Date?, failedAt: Date?, sentFingerprint: String?,
                     fingerprint: String, now: Date) -> Step {
        func within(_ at: Date?, _ seconds: TimeInterval) -> Bool {
            guard let at else { return false }
            // A clock set back must not silence the uploader for good.
            let age = now.timeIntervalSince(at)
            return age >= 0 && age < seconds
        }
        if participant == true {
            if within(failedAt, participantRetrySeconds) { return .wait }
            return fingerprint == sentFingerprint ? .wait : .send
        }
        if within(failedAt, retryAfterFailureSeconds) { return .wait }
        if participant == false, within(askedAt, askAgainSeconds) { return .wait }
        return .ask
    }
}

/// Tells the server each local day's two numbers, for a challenger only.
/// Nothing on screen, nothing waits on it, and every failure is silent: the
/// RPC does not exist until the server's migration is applied.
@MainActor
enum ChallengeDays {
    private static let settleSeconds: UInt64 = 20
    private static var pending: Task<Void, Never>?
    private static var running = false

    /// Called beside `LearnerRecordUploader.schedule()`: after a call ends,
    /// after a speech take is saved, and when the app comes forward.
    nonisolated static func schedule() {
        Task { @MainActor in
            guard !isQuietRun else { return }
            pending?.cancel()
            pending = Task { @MainActor in
                try? await Task.sleep(nanoseconds: settleSeconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                pending = nil
                await run()
            }
        }
    }

    private static var isQuietRun: Bool {
        UserDefaults.standard.string(forKey: "capture") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    // MARK: - State, per app account

    private struct State: Codable {
        var participant: Bool?
        var askedAt: Date?
        var failedAt: Date?
        var sentFingerprint: String?
        /// The local day a failure was last reported to analytics.
        var failureReportedDay: String?
    }

    private static func stateKey(_ userId: String) -> String { "futurevoice.challengeDays.\(userId)" }

    private static func loadState(_ userId: String) -> State {
        UserDefaults.standard.data(forKey: stateKey(userId))
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    private static func save(_ state: State, _ userId: String) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey(userId))
        }
    }

    private struct Answer: Decodable {
        var participant: Bool
        var accepted: Int?
        var starts_on: String?
    }

    // MARK: - The pass

    private static func current(now: Date) -> [ChallengeDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(ChallengeDayPlan.windowDays - 1), to: today) ?? today
        let speech = ActivityEventLog.shared.events(from: start, to: now.addingTimeInterval(1))
            .filter { $0.kind == .speech }.map(\.at)
        // Every language's metered seconds for the day: the Home ring's number.
        return ChallengeDayPlan.days(now: now, calendar: calendar,
                                     talkSeconds: { TalkTimeLog.seconds(on: $0) }, speechAt: speech)
    }

    private static var platform: String {
        #if targetEnvironment(macCatalyst)
        "mac"
        #else
        "ios"
        #endif
    }

    private static func put(_ days: [ChallengeDay], timeZone: String) async throws -> Answer {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let body = AnyJSON.array(days.map { d in
            AnyJSON.object([
                "day": .string(d.day),
                "talk_seconds": .integer(d.talkSeconds),
                "speech_takes": .integer(d.speechTakes),
                "time_zone": .string(timeZone),
                "platform": .string(platform),
                "app_version": .string(version),
            ])
        })
        return try await SupabaseProvider.shared
            .rpc("challenge_days_put", params: ["p_days": body])
            .execute().value
    }

    private static func run() async {
        guard !running else { return }
        running = true
        defer { running = false }

        guard let user = try? await SupabaseProvider.shared.auth.session.user,
              !user.isAnonymous else { return }
        let userId = user.id.uuidString.lowercased()
        var state = loadState(userId)
        let now = Date()
        let timeZone = TimeZone.current.identifier
        let days = current(now: now)
        let fingerprint = ChallengeDayPlan.fingerprint(days, timeZone: timeZone)

        var step = ChallengeDayPlan.step(participant: state.participant, askedAt: state.askedAt,
                                         failedAt: state.failedAt, sentFingerprint: state.sentFingerprint,
                                         fingerprint: fingerprint, now: now)
        guard step != .wait else { return }
        do {
            if step == .ask {
                let answer = try await put([], timeZone: timeZone)
                state.participant = answer.participant
                state.askedAt = now
                state.failedAt = nil
                save(state, userId)
                guard answer.participant, fingerprint != state.sentFingerprint else { return }
                step = .send
            }
            // Nothing to say yet is still "sent": an empty window has an
            // empty fingerprint, and the call would be the question again.
            if !days.isEmpty {
                let answer = try await put(days, timeZone: timeZone)
                state.participant = answer.participant
                state.askedAt = now
            }
            state.failedAt = nil
            state.sentFingerprint = state.participant == true ? fingerprint : nil
            save(state, userId)
        } catch {
            guard !(error is CancellationError) else { return }
            state.failedAt = now
            // At most one event a day per account, whatever the trigger rate.
            let today = dayKey(now)
            if state.failureReportedDay != today {
                state.failureReportedDay = today
                Analytics.capture("challenge_days_failed",
                                  ["error": String(String(describing: error).prefix(120))])
            }
            save(state, userId)
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
