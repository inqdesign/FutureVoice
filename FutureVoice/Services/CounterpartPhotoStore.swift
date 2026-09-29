import SwiftUI
import UIKit

/// A person's profile photo — one small square JPEG per `Counterpart`, keyed
/// by id, under `Documents/counterpart_photos/`. Same rules as the learner's
/// own avatar (`AvatarStore`) and the day card's photo: re-encoded on save
/// through `draw(in:)`, so EXIF and location never survive, and never more
/// pixels than a circle on screen needs. Local only: the file is not part of
/// the sync payload (a photo of someone the learner knows is theirs to keep
/// on this phone), so a second device shows initials until one is picked
/// there.
///
/// An ObservableObject with a version counter rather than a published
/// dictionary, so every `PersonBubble` refreshes the moment a photo changes
/// without the store holding decoded images for people not on screen.
@MainActor
final class CounterpartPhotoStore: ObservableObject {
    static let shared = CounterpartPhotoStore()

    @Published private(set) var version = 0

    private let dir: URL
    private var cache: [UUID: UIImage] = [:]

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("counterpart_photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func image(for id: UUID) -> UIImage? {
        if let hit = cache[id] { return hit }
        guard let img = UIImage(contentsOfFile: url(id).path) else { return nil }
        cache[id] = img
        return img
    }

    func hasPhoto(_ id: UUID) -> Bool {
        cache[id] != nil || FileManager.default.fileExists(atPath: url(id).path)
    }

    func save(_ picked: UIImage, for id: UUID) {
        let sized = picked.squarePhoto(maxSide: 512)
        guard let data = sized.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url(id), options: [.atomic])
        cache[id] = sized
        version += 1
    }

    func delete(for id: UUID) {
        try? FileManager.default.removeItem(at: url(id))
        cache[id] = nil
        version += 1
    }

    private func url(_ id: UUID) -> URL {
        dir.appendingPathComponent("\(id.uuidString).jpg")
    }
}

private extension UIImage {
    /// Aspect-fill into a square of side `min(maxSide, shorterEdge)`.
    /// `draw(in:)` bakes in orientation and writes a fresh bitmap.
    func squarePhoto(maxSide: CGFloat) -> UIImage {
        let side = min(size.width, size.height)
        let target = min(maxSide, max(side, 1))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            let scale = target / max(side, 1)
            let w = size.width * scale
            let h = size.height * scale
            draw(in: CGRect(x: (target - w) / 2, y: (target - h) / 2, width: w, height: h))
        }
    }
}
