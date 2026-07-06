import SwiftUI
import UIKit

/// The user's own profile photo. Sign in with Apple never returns an avatar
/// (Apple only shares name + email, and only on the first authorization), so
/// the picture is something the user picks themselves. Stored as one square
/// JPEG in Documents; a shared ObservableObject so every avatar on screen
/// refreshes the moment it changes.
@MainActor
final class AvatarStore: ObservableObject {
    static let shared = AvatarStore()

    @Published private(set) var image: UIImage?

    private let url: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("profile_avatar.jpg")
        image = UIImage(contentsOfFile: url.path)
    }

    /// Center-crop to a square and downscale before saving — an avatar never
    /// needs more than a small circle's worth of pixels.
    func save(_ picked: UIImage) {
        let sized = picked.squareAvatar(maxSide: 512)
        guard let data = sized.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url, options: [.atomic])
        image = sized
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
        image = nil
    }
}

private extension UIImage {
    /// Aspect-fill into a square of side `min(maxSide, shorterEdge)`. `draw(in:)`
    /// bakes in orientation, so no EXIF-rotation surprises.
    func squareAvatar(maxSide: CGFloat) -> UIImage {
        let side = min(size.width, size.height)
        let target = min(maxSide, side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            let scale = target / side
            let w = size.width * scale
            let h = size.height * scale
            draw(in: CGRect(x: (target - w) / 2, y: (target - h) / 2, width: w, height: h))
        }
    }
}

/// A circular profile avatar: the user's photo when set, otherwise their
/// initials, otherwise a neutral SF Symbol. Reused in the home header and
/// the persona editor so they always agree.
struct ProfileAvatar: View {
    @ObservedObject private var store = AvatarStore.shared
    var initials: String = ""
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let img = store.image {
                Image(uiImage: img).resizable().scaledToFill()
            } else if !trimmedInitials.isEmpty {
                Text(trimmedInitials)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemFill))
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    /// Up to two initials from the display name ("Eunggyu Lee" → "EL").
    private var trimmedInitials: String {
        let parts = initials.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}
