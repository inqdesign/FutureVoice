import Foundation
import UserNotifications

/// JSON-on-disk store for weekly tests, one file per language, mirroring
/// `WeeklyReportStore`. A test is minted once per opening (see
/// `WeeklyTestSchedule`) and then only ever gains answers.
final class WeeklyTestStore: LanguageScopedStore {
    static let shared = WeeklyTestStore()

    private var fileURL: URL
    private let filename: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "weekly-tests.json") {
        self.filename = filename
        self.fileURL = LanguageScope.activeDirectory.appendingPathComponent(filename)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    func languageScopeDidChange() {
        fileURL = LanguageScope.activeDirectory.appendingPathComponent(filename)
    }

    /// Newest first.
    func load() -> [WeeklyTest] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? decoder.decode([WeeklyTest].self, from: data)
        else { return [] }
        return list.sorted { $0.createdAt > $1.createdAt }
    }

    func latest() -> WeeklyTest? { load().first }

    /// The newest weekly paper — the one a new week is built after. The
    /// store also holds monthly papers, and `first` is whichever was built
    /// last.
    static func latestWeekly(_ tests: [WeeklyTest]) -> WeeklyTest? {
        tests.sorted { $0.createdAt > $1.createdAt }.first { !$0.isMonthly }
    }

    func save(_ test: WeeklyTest) {
        var all = load()
        all.removeAll { $0.id == test.id }
        all.append(test)
        write(all)
    }

    #if DEBUG
    /// Capture runs start from an empty week.
    func removeAll() { write([]) }

    /// Dev tool: forget the paper(s) minted since `opening`, weekly and
    /// monthly, so the week can be taken again. Earlier weeks stay.
    func removeCurrentWeek(opening: Date) {
        write(load().filter { $0.createdAt < opening })
    }
    #endif

    private func write(_ list: [WeeklyTest]) {
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        SyncEngine.noteChanged(.weeklyTest)
    }

    /// Weeks in a row with a finished test, counting back from the current
    /// opening (which counts only once its test is finished). Openings are
    /// the schedule's — a week is Saturday to Saturday if that is the day
    /// the learner picked, not Monday to Sunday.
    static func weekStreak(tests: [WeeklyTest], schedule: WeeklyTestSchedule, now: Date = Date()) -> Int {
        let finished = tests.filter { !$0.isMonthly }.compactMap(\.finishedAt)
        guard !finished.isEmpty else { return 0 }
        var start = schedule.currentOpening(now: now)
        var streak = 0
        let week: TimeInterval = 7 * 86_400
        // The current week is still running: skip it unless already done.
        if !finished.contains(where: { $0 >= start && $0 < start + week }) {
            start = start.addingTimeInterval(-week)
        }
        while finished.contains(where: { $0 >= start && $0 < start + week }) {
            streak += 1
            start = start.addingTimeInterval(-week)
        }
        return streak
    }
}

// MARK: - Settings

/// When the test opens each week, and whether the phone says so. Device-local
/// on purpose, like the daily call: two synced devices must not both ring.
@MainActor
final class WeeklyTestSettings: ObservableObject {
    static let shared = WeeklyTestSettings()

    private let defaults = UserDefaults.standard
    private static let weekdayKey = "futurevoice.weeklyTest.weekday"
    private static let hourKey = "futurevoice.weeklyTest.hour"
    private static let minuteKey = "futurevoice.weeklyTest.minute"
    private static let reminderKey = "futurevoice.weeklyTest.reminder"
    private static let soundsKey = "futurevoice.weeklyTest.sounds"
    /// The opening whose build came back too thin, so the tab doesn't rebuild
    /// on every appearance until material arrives or the week turns.
    private static let thinOpeningKey = "futurevoice.weeklyTest.thinOpening"

    /// Gregorian weekday, 1 = Sunday … 7 = Saturday. Default Saturday: the
    /// weekend is when the week can be looked back on.
    @Published var weekday: Int { didSet { defaults.set(weekday, forKey: Self.weekdayKey) } }
    @Published var hour: Int { didSet { defaults.set(hour, forKey: Self.hourKey) } }
    @Published var minute: Int { didSet { defaults.set(minute, forKey: Self.minuteKey) } }
    /// A local notification at the opening. Off until the learner turns it
    /// on — it needs notification permission, and asking is a moment.
    @Published var reminderOn: Bool { didSet { defaults.set(reminderOn, forKey: Self.reminderKey) } }
    /// The answer sounds. On by default; the silent switch mutes them anyway.
    @Published var soundsOn: Bool { didSet { defaults.set(soundsOn, forKey: Self.soundsKey) } }

    private init() {
        let d = UserDefaults.standard
        weekday = d.object(forKey: Self.weekdayKey) as? Int ?? 7
        hour = d.object(forKey: Self.hourKey) as? Int ?? 10
        minute = d.object(forKey: Self.minuteKey) as? Int ?? 0
        reminderOn = d.bool(forKey: Self.reminderKey)
        soundsOn = d.object(forKey: Self.soundsKey) as? Bool ?? true
    }

    var schedule: WeeklyTestSchedule { WeeklyTestSchedule(weekday: weekday, hour: hour, minute: minute) }

    /// The opening time as a Date on an arbitrary day, for a DatePicker.
    var timeOfDay: Date {
        get {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
        set {
            let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = c.hour ?? 10
            minute = c.minute ?? 0
        }
    }

    func markThin(opening: Date) { defaults.set(opening.timeIntervalSince1970, forKey: Self.thinOpeningKey) }
    func isThin(opening: Date) -> Bool {
        defaults.double(forKey: Self.thinOpeningKey) == opening.timeIntervalSince1970
    }
    func clearThin() { defaults.removeObject(forKey: Self.thinOpeningKey) }
}

// MARK: - Schedule

/// The weekly opening: one weekday and time. Every moment belongs to exactly
/// one week, the one that opened most recently — so a test taken on Tuesday
/// is still "this week's", and the next one opens on the chosen day.
struct WeeklyTestSchedule: Equatable {
    var weekday: Int
    var hour: Int
    var minute: Int

    /// The most recent opening at or before `now`. The backward search is
    /// strict, so it starts a second past `now` — at 10:00:00 sharp the
    /// opening is now, not last week's.
    func currentOpening(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let components = DateComponents(hour: hour, minute: minute, weekday: weekday)
        return calendar.nextDate(after: now.addingTimeInterval(1), matching: components,
                                 matchingPolicy: .nextTime, direction: .backward) ?? now
    }

    /// The first opening strictly after `now`.
    func nextOpening(after now: Date = Date(), calendar: Calendar = .current) -> Date {
        let components = DateComponents(hour: hour, minute: minute, weekday: weekday)
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(7 * 86_400)
    }

    /// The week's state, from the tests on file.
    enum State: Equatable {
        /// No test yet this week; tap builds one.
        case ready
        /// Built and part-way through.
        case inProgress(WeeklyTest)
        /// Finished this week; the next opens at the date.
        case done(WeeklyTest, next: Date)
        /// This week's build found too little material.
        case thin(next: Date)
    }

    @MainActor
    func state(tests: [WeeklyTest], settings: WeeklyTestSettings, now: Date = Date()) -> State {
        let opening = currentOpening(now: now)
        let next = nextOpening(after: now)
        if let test = tests.first(where: { !$0.isMonthly && $0.createdAt >= opening }) {
            return test.isFinished ? .done(test, next: next) : .inProgress(test)
        }
        if settings.isThin(opening: opening) { return .thin(next: next) }
        return .ready
    }

    // MARK: Monthly

    /// The monthly paper's state. It opens with the FIRST weekly opening of
    /// each calendar month and collects the wrong answers of every weekly
    /// test finished since the previous month's first opening — the month
    /// that just ended, in the learner's own week rhythm.
    enum MonthlyState: Equatable {
        /// Nothing to collect (no month behind us, or too little wrong in it).
        case none
        /// Wrong answers are waiting; tap builds the paper from `sources`.
        case ready(sources: [WeeklyTest])
        case inProgress(WeeklyTest)
        case done(WeeklyTest)
    }

    /// The first opening in the calendar month that `currentOpening` falls in.
    func monthOpening(now: Date = Date(), calendar: Calendar = .current) -> Date {
        var opening = currentOpening(now: now, calendar: calendar)
        let month = calendar.dateComponents([.year, .month], from: opening)
        while true {
            let previous = opening.addingTimeInterval(-7 * 86_400)
            guard calendar.dateComponents([.year, .month], from: previous) == month else { return opening }
            opening = previous
        }
    }

    func monthlyState(tests: [WeeklyTest], now: Date = Date(), calendar: Calendar = .current) -> MonthlyState {
        let opening = monthOpening(now: now, calendar: calendar)
        if let test = tests.first(where: { $0.isMonthly && $0.createdAt >= opening }) {
            return test.isFinished ? .done(test) : .inProgress(test)
        }
        // The month behind this opening: from the previous month's first
        // opening up to this one.
        let previousOpening = monthOpening(now: opening.addingTimeInterval(-1), calendar: calendar)
        let sources = tests.filter { test in
            guard !test.isMonthly, let finished = test.finishedAt else { return false }
            return finished >= previousOpening && finished < opening
        }
        let wrong = Set(sources.flatMap { test in
            let missed = Set(test.answers.filter { !$0.correct }.map(\.itemId))
            return test.items.filter { missed.contains($0.id) }.map(WeeklyTestEngine.itemKey)
        })
        return wrong.count >= WeeklyTestEngine.minItems ? .ready(sources: sources) : .none
    }
}

// MARK: - Reminder

/// One local notification at the next opening — the moment the week turns,
/// "Your week" is ready and the test opens (2026-09-30).
///
/// NOT repeating, on purpose: the body carries this week's real numbers, and
/// they are right at fire time because every one of them is written in the
/// app, and every trip to the background re-writes this request. A learner
/// who never comes back gets one, not one a week.
@MainActor
enum WeeklyTestReminder {
    static let requestId = "futurevoice.weekly-test"
    static let categoryId = "futurevoice.weekly-test"
    /// userInfo flag: the tap opens the week's cards rather than the test.
    static let recapKey = "recap"

    static func reschedule(now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestId])
        let settings = WeeklyTestSettings.shared
        guard settings.reminderOn else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let fire = settings.schedule.nextOpening(after: now)
        let content = makeContent(now: now)
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: requestId, content: content,
                                                    trigger: trigger))
    }

    /// After a permission prompt someone else raised (onboarding's daily-call
    /// step): arm the reminder if iOS said yes, and switch the wish OFF if it
    /// said no, so the goals sheet's toggle never claims a notice that can't
    /// ring.
    static func settleAfterPermission() async {
        let settings = WeeklyTestSettings.shared
        guard settings.reminderOn else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .authorized || status == .provisional {
            await reschedule()
        } else {
            settings.reminderOn = false
        }
    }

    /// What the notice says, from the week in progress — the numbers are
    /// every one written in the app, so at fire time they are the week's.
    static func makeContent(now: Date = Date()) -> UNMutableNotificationContent {
        let week = WeekRecapBuilder.thisWeek(now: now)
        let talkSeconds = week.talkSeconds
        let active = week.daysActive

        let content = UNMutableNotificationContent()
        if active > 0 {
            content.title = chrome("Your week is ready")
            content.body = talkSeconds >= 60
                ? explain("\(talkSeconds / 60) min of talk over \(active) days. See how it went, then take the test.")
                : explain("You showed up \(active) days. See how it went, then take the test.")
            content.userInfo = [recapKey: true]
        } else {
            content.title = chrome("Your weekly test is ready")
            content.body = explain("A few minutes, made from this week's talks.")
        }
        content.sound = .default
        content.categoryIdentifier = categoryId
        return content
    }

    #if DEBUG
    /// Developer: the same notice, ten seconds from now, so the wiring —
    /// words, tap, landing — is seen on a phone without waiting a week.
    static func fireTest() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        let content = makeContent()
        // The week-in-progress may be empty on a dev install; the test
        // always exercises the recap path.
        content.userInfo = [recapKey: true]
        try? await center.add(UNNotificationRequest(
            identifier: requestId + ".test", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)))
    }
    #endif
}
