import SwiftUI
import UIKit

/// A DAY's card on disk: the photo (where the learner studied that day) and,
/// once the card has been made or the day is over, a FROZEN copy of its
/// numbers. One JPEG + one JSON per local day under `Documents/day_cards/`.
///
/// The snapshot is the collection's memory. The logs a card is drawn from are
/// pruned at 45 days and the streak rule can change, so a card read live
/// months later would lose its minutes or change its streak — and a card is
/// what that day WAS. `freeze` is called when a photo is taken, when the
/// card is shared, and for every past day on foreground (`freezePastDays`),
/// so yesterday's card is settled by the time anyone looks at it.
///
/// The photo is re-encoded through `UIGraphicsImageRenderer` on save, which
/// drops EXIF — including GPS. A share card must never carry the location it
/// was taken at; the photo IS the place, and that is as precise as it gets.
@MainActor
final class DayCardStore: ObservableObject {
    static let shared = DayCardStore()

    /// Bumped on every write so a page holding a rendered card can redraw.
    @Published private(set) var version = 0

    private let dir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("day_cards", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Snapshots

    func snapshot(for day: Date) -> DayCardData? {
        guard let data = try? Data(contentsOf: metaURL(day)) else { return nil }
        return try? JSONDecoder().decode(DayCardData.self, from: data)
    }

    func freeze(_ card: DayCardData) {
        guard card.hasActivity, let data = try? JSONEncoder().encode(card) else { return }
        try? data.write(to: metaURL(card.date), options: [.atomic])
        version += 1
    }

    /// Settle every past day of the last `AppUsageLog` window that has
    /// activity and no record yet. Idempotent and cheap: the session archive
    /// is decoded once, and a day with a snapshot is skipped without reading
    /// it. Today is never frozen here — it is still being lived.
    func freezePastDays(now: Date = Date(), calendar: Calendar = .current) {
        for back in 1...45 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: now) else { continue }
            guard !FileManager.default.fileExists(atPath: metaURL(day).path) else { continue }
            let card = DayCardData.make(day: day, calendar: calendar)
            if card.hasActivity { freeze(card) }
        }
    }

    /// Every day that has a record — a snapshot or a photo — newest first.
    /// This is the collection: days, not files.
    func recordedDays() -> [Date] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let days = Set(names.compactMap { name -> Date? in
            let stem = (name as NSString).deletingPathExtension
            return f.date(from: stem)
        })
        return days.sorted(by: >)
    }

    // MARK: - Photo

    func photo(for day: Date) -> UIImage? {
        UIImage(contentsOfFile: url(day).path)
    }

    func setPhoto(_ image: UIImage?, for day: Date) {
        if let image {
            let sized = image.cardSized(maxLongEdge: 2000)
            if let data = sized.jpegData(compressionQuality: 0.88) {
                try? data.write(to: url(day), options: [.atomic])
            }
        } else {
            try? FileManager.default.removeItem(at: url(day))
        }
        version += 1
    }

    private func url(_ day: Date) -> URL {
        dir.appendingPathComponent("\(AppUsageLog.dayKey(day)).jpg")
    }
    private func metaURL(_ day: Date) -> URL {
        dir.appendingPathComponent("\(AppUsageLog.dayKey(day)).json")
    }
}

private extension UIImage {
    /// Aspect-fit downscale so the longer edge is at most `maxLongEdge`.
    /// `draw(in:)` bakes in orientation and writes a fresh bitmap — no EXIF
    /// survives, which is the point (see the type comment).
    func cardSized(maxLongEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        let scale = min(1, maxLongEdge / max(longest, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
