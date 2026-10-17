import Foundation

/// One voice change per 30 days after the first voice (2026-10-09).
///
/// It existed because the voice provider of the day capped how many voices
/// the account could add each month. The server removed the limit on
/// 2026-10-12 and now always answers "a change is available"; this stays so
/// a limit could come back without an app release. The server is
/// the judge (`voice_change_status`, `_shared/voice-changes.ts`); this is its
/// answer, read so every button that would make a voice can say so BEFORE the
/// learner spends a minute reading a script or half a minute waiting on takes.
struct VoiceChangeStatus: Equatable {
    /// Changes still allowed now (0 or 1).
    let left: Int
    /// When one comes back; nil while one is available.
    let nextAt: Date?

    var canChange: Bool { left > 0 }

    /// Said under a disabled control and as the server's refusal.
    static func againLine(_ nextAt: Date?) -> String {
        guard let nextAt else {
            return explain("You've already changed your voice in the last 30 days.")
        }
        let day = nextAt.formatted(.dateTime.month(.wide).day()
            .locale(Locale(identifier: LanguageCatalog.currentNative)))
        return explain("You can change your voice again from \(day).")
    }

    /// Added to every confirmation that would make a new voice.
    static var usesItLine: String {
        explain("You can change your voice once every 30 days, and this uses it.")
    }

    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        // Postgres' own text form ("2026-11-08 10:00:00.123+00").
        let p = DateFormatter()
        p.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd HH:mm:ss.SSSXXXXX",
                       "yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"] {
            p.dateFormat = format
            if let d = p.date(from: s) { return d }
        }
        return nil
    }
}
