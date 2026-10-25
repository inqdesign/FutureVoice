import SwiftUI
import UIKit

/// The Mac build (Mac Catalyst, Mac idiom). The app is designed for a phone,
/// and two things about that read wrong on a Mac, so the Mac fixes both here;
/// on the iPhone and iPad every function in this file is a no-op.
///
/// - **Size.** The Mac idiom draws with the Mac's own text sizes (body 13 pt,
///   captions 10 pt — measured 2026-10-25) and IGNORES Dynamic Type: no
///   content size category, SwiftUI `dynamicTypeSize` or trait override moves
///   them. So the whole window is ZOOMED instead (`window.transform`), the
///   way a browser zooms a page: 1.3× by default puts body text back at the
///   phone's 17 pt, and ⌘+ / ⌘− / ⌘0 in the View menu change it. Measured
///   the same day: text stays sharp (it is drawn at the zoomed size, not
///   stretched), clicks land where they look, resizing the window reflows,
///   and because it is the window, every sheet, alert and full-screen cover
///   is zoomed with no change to any of them.
/// - **Width.** A phone page stretched across 1,700 pt is a line you read
///   across the screen, so the app's root is drawn in a centred column whose
///   width the View menu picks (Narrow · Medium · Wide · Full width).
///
/// The five tabs show as a segmented control in the title bar on their own —
/// that is how a Mac app switches pages, so there is no sidebar.
enum MacLayout {
    static var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    static let zoomKey = "mac.zoom"
    static let columnKey = "mac.columnWidth"

    static let zoomSteps: [CGFloat] = [1.0, 1.1, 1.2, 1.3, 1.45, 1.6, 1.8]
    static let defaultZoom = 3

    static func clampedZoomIndex(_ i: Int) -> Int { min(max(i, 0), zoomSteps.count - 1) }

    /// Posted when a Mac window is resized or re-zoomed.
    static let windowDidResize = Notification.Name("futurevoice.macWindowDidResize")

    /// The height a page lays out against: the phone's screen, or on the Mac
    /// the window (in zoomed points). `UIScreen.main` on a Mac is the whole
    /// display, so a layout centred on it put the Talk ring below the window.
    @MainActor
    static var screenHeight: CGFloat {
        #if targetEnvironment(macCatalyst)
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow ?? ($0 as? UIWindowScene)?.windows.first }
            .first
        if let height = window?.bounds.height, height > 0 { return height }
        #endif
        return UIScreen.main.bounds.height
    }

    static var zoom: CGFloat {
        let stored = UserDefaults.standard.object(forKey: zoomKey) as? Int ?? defaultZoom
        return zoomSteps[clampedZoomIndex(stored)]
    }

    /// How wide the page may grow, in zoomed points.
    enum Column: String, CaseIterable, Identifiable {
        case narrow, regular, wide, full
        var id: String { rawValue }

        var width: CGFloat? {
            switch self {
            case .narrow: 560
            case .regular: 720
            case .wide: 960
            case .full: nil
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .narrow: "Narrow"
            case .regular: "Medium"
            case .wide: "Wide"
            case .full: "Full width"
            }
        }
    }
}

private struct MacPageModifier: ViewModifier {
    @AppStorage(MacLayout.columnKey) private var column = MacLayout.Column.regular.rawValue

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
            .frame(maxWidth: (MacLayout.Column(rawValue: column) ?? .regular).width ?? .infinity)
            .frame(maxWidth: .infinity)
            // The pages' own ground, so the column reads as the page, not a panel.
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        #else
        content
        #endif
    }
}

extension View {
    /// The Mac's centred column; nothing on the iPhone or iPad.
    func macPage() -> some View {
        modifier(MacPageModifier())
    }
}

/// View → zoom and page width, with the shortcuts every Mac reader knows.
struct MacViewCommands: Commands {
    @AppStorage(MacLayout.zoomKey) private var zoomIndex = MacLayout.defaultZoom
    @AppStorage(MacLayout.columnKey) private var column = MacLayout.Column.regular.rawValue

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Zoom In") { setZoom(zoomIndex + 1) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(zoomIndex >= MacLayout.zoomSteps.count - 1)
            Button("Zoom Out") { setZoom(zoomIndex - 1) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(zoomIndex <= 0)
            Button("Actual Size") { setZoom(MacLayout.defaultZoom) }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Picker("Page Width", selection: $column) {
                ForEach(MacLayout.Column.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Divider()
        }
    }

    private func setZoom(_ index: Int) {
        zoomIndex = MacLayout.clampedZoomIndex(index)
        MacWindow.configure()
    }
}

/// The window: its zoom, a minimum size, and a first-launch size that fits the
/// column. macOS remembers the frame after that.
enum MacWindow {
    /// On screen, before the zoom.
    static let minimumSize = CGSize(width: 620, height: 680)
    private static let sizedKey = "mac.didSizeWindow"
    @MainActor private static var observed: [ObjectIdentifier: NSKeyValueObservation] = [:]

    @MainActor
    static func configure() {
        #if targetEnvironment(macCatalyst)
        let zoom = MacLayout.zoom
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.sizeRestrictions?.minimumSize = minimumSize
            // The tabs sit in the title bar; the app's name beside them is noise.
            scene.titlebar?.titleVisibility = .hidden
            if observed[ObjectIdentifier(scene)] == nil {
                observed[ObjectIdentifier(scene)] = scene.observe(\.effectiveGeometry) { _, _ in
                    Task { @MainActor in
                        NotificationCenter.default.post(name: MacLayout.windowDidResize, object: nil)
                    }
                }
            }
            for window in scene.windows {
                // `frame` is the window's size on screen whatever the current
                // transform is; the bounds are what the app lays out in.
                let onScreen = window.frame.size
                window.transform = CGAffineTransform(scaleX: zoom, y: zoom)
                window.bounds = CGRect(origin: .zero,
                                       size: CGSize(width: onScreen.width / zoom, height: onScreen.height / zoom))
            }
            if !UserDefaults.standard.bool(forKey: sizedKey) {
                UserDefaults.standard.set(true, forKey: sizedKey)
                let screen = scene.screen.bounds
                let size = CGSize(width: min(1100, screen.width - 80), height: min(900, screen.height - 80))
                scene.requestGeometryUpdate(.Mac(systemFrame: CGRect(
                    x: (screen.width - size.width) / 2, y: (screen.height - size.height) / 2,
                    width: size.width, height: size.height)))
            }
        }
        NotificationCenter.default.post(name: MacLayout.windowDidResize, object: nil)
        #endif
    }
}
