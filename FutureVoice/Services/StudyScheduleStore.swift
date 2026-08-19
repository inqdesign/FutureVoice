import Foundation

/// When each word / expression comes back to the deck — the same
/// "10 min · Tomorrow · 3 days" promise the sentence deck keeps via
/// `DrillStore`, kept here for items that live in `VocabStore` instead of a
/// card store. JSON-on-disk, language-scoped like every other learning record.
///
/// An item with no entry is due immediately (new material, or never snoozed).
/// Marking something known clears its entry — a known item has no return date.
///
/// The entry keeps the item's DISPLAY text alongside its return time: the key
/// is normalized (lowercased) for lookup, but a review session has to deal the
/// word back the way the learner saw it.
final class StudyScheduleStore: LanguageScopedStore {
    static let shared = StudyScheduleStore()

    enum Kind: String, Codable {
        case word
        case expression
    }

    struct Entry: Codable {
        var text: String
        var at: Date
    }

    /// One thing waiting to come back — what a review session deals from.
    struct DueItem: Identifiable, Hashable {
        let kind: Kind
        let text: String
        let at: Date
        var id: String { kind.rawValue + "|" + text.lowercased() }
    }

    private var fileURL: URL
    private let filename: String
    private var entries: [String: Entry]

    init(filename: String = "study-schedule.json") {
        self.filename = filename
        self.fileURL = LanguageScope.activeDirectory.appendingPathComponent(filename)
        self.entries = Self.read(from: fileURL)
    }

    func languageScopeDidChange() {
        fileURL = LanguageScope.activeDirectory.appendingPathComponent(filename)
        entries = Self.read(from: fileURL)
    }

    private static func read(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let typed = try? dec.decode([String: Entry].self, from: data) { return typed }
        // First-format files stored the date alone; recover them by taking the
        // display text from the key (lowercased, but never lost).
        if let flat = try? dec.decode([String: Date].self, from: data) {
            return flat.reduce(into: [:]) { out, pair in
                let text = pair.key.split(separator: "|", maxSplits: 1).last.map(String.init) ?? pair.key
                out[pair.key] = Entry(text: text, at: pair.value)
            }
        }
        return [:]
    }

    private func key(_ kind: Kind, _ text: String) -> String {
        kind.rawValue + "|" + text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// nil = due now (never scheduled).
    func nextReview(_ kind: Kind, _ text: String) -> Date? {
        entries[key(kind, text)]?.at
    }

    func isDue(_ kind: Kind, _ text: String, now: Date = Date()) -> Bool {
        guard let at = nextReview(kind, text) else { return true }
        return at <= now
    }

    func snooze(_ kind: Kind, _ text: String, until date: Date) {
        let display = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !display.isEmpty else { return }
        entries[key(kind, text)] = Entry(text: display, at: date)
        save()
    }

    func clear(_ kind: Kind, _ text: String) {
        guard entries.removeValue(forKey: key(kind, text)) != nil else { return }
        save()
    }

    /// Everything whose return time has arrived — what the review session
    /// deals, longest-waiting first (the 10-minute snooze from an hour ago
    /// comes before the one from a minute ago).
    func dueItems(now: Date = Date()) -> [DueItem] {
        entries.compactMap { key, entry -> DueItem? in
            guard entry.at <= now,
                  let kind = key.split(separator: "|").first.flatMap({ Kind(rawValue: String($0)) })
            else { return nil }
            return DueItem(kind: kind, text: entry.text, at: entry.at)
        }
        .sorted { $0.at < $1.at }
    }

    /// Everything still WAITING — the mirror image of `dueItems`, soonest
    /// first. Together the two cover every entry, so a deck's folders can
    /// show where a card actually went instead of only what this session
    /// happened to touch.
    func upcoming(now: Date = Date()) -> [DueItem] {
        entries.compactMap { key, entry -> DueItem? in
            guard entry.at > now,
                  let kind = key.split(separator: "|").first.flatMap({ Kind(rawValue: String($0)) })
            else { return nil }
            return DueItem(kind: kind, text: entry.text, at: entry.at)
        }
        .sorted { $0.at < $1.at }
    }

    /// Every scheduled return time — the shared review reminder folds these
    /// in with the drill cards' due dates.
    func allNextReviews() -> [Date] {
        entries.values.map(\.at)
    }

    #if DEBUG
    /// Capture-harness only: a screenshot run (and the UI tests that assert
    /// empty folders) must start from a clean schedule, and the store
    /// survives across launches on the same simulator.
    func removeAll() {
        entries = [:]
        save()
    }
    #endif

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
