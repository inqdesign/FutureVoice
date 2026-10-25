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
        MacSheets.install()
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.sizeRestrictions?.minimumSize = minimumSize
            // The tabs sit in the title bar; the app's name beside them is noise.
            scene.titlebar?.titleVisibility = .hidden
            if observed[ObjectIdentifier(scene)] == nil {
                // A live resize hands the window its new on-screen size as if
                // there were no zoom; put the zoom back on every step of it.
                observed[ObjectIdentifier(scene)] = scene.observe(\.effectiveGeometry) { scene, _ in
                    MainActor.assumeIsolated {
                        applyZoom(to: scene)
                        NotificationCenter.default.post(name: MacLayout.windowDidResize, object: nil)
                    }
                }
            }
            applyZoom(to: scene)
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

    /// The scene's size is the window's size on screen, whatever UIKit last
    /// did to the window; the window lays out in that size divided by the zoom.
    @MainActor
    private static func applyZoom(to scene: UIWindowScene) {
        #if targetEnvironment(macCatalyst)
        let zoom = MacLayout.zoom
        let onScreen = scene.coordinateSpace.bounds.size
        guard onScreen.width > 0, onScreen.height > 0 else { return }
        let transform = CGAffineTransform(scaleX: zoom, y: zoom)
        let bounds = CGRect(origin: .zero, size: CGSize(width: onScreen.width / zoom, height: onScreen.height / zoom))
        let center = CGPoint(x: onScreen.width / 2, y: onScreen.height / 2)
        for window in scene.windows {
            if window.transform != transform { window.transform = transform }
            if window.bounds != bounds { window.bounds = bounds }
            if window.center != center { window.center = center }
        }
        #endif
    }
}

#if targetEnvironment(macCatalyst)
/// Sheets at a phone's size. The Mac idiom's form sheet is small to begin
/// with, and the window zoom makes it smaller still (~360 × 310 pt at 1.3×),
/// so a deck or a word card built for a phone was squeezed into a stamp.
/// Every presentation goes through `present(_:animated:completion:)`, SwiftUI's
/// `.sheet` included, so one hook marks every sheet; SwiftUI then keeps
/// writing its own `preferredContentSize`, so the size is answered where it
/// is READ. Alerts, menus and popovers keep their own styles.
enum MacSheets {
    static let width: CGFloat = 480
    static let maxHeight: CGFloat = 860

    private static var installed = false
    fileprivate static var sizeKey: UInt8 = 0

    @MainActor
    static func install() {
        guard !installed else { return }
        installed = true
        swap(#selector(UIViewController.present(_:animated:completion:)),
             #selector(UIViewController.fv_macPresent(_:animated:completion:)))
        swap(#selector(getter: UIViewController.preferredContentSize),
             #selector(getter: UIViewController.fv_macPreferredContentSize))
    }

    private static func swap(_ a: Selector, _ b: Selector) {
        guard let original = class_getInstanceMethod(UIViewController.self, a),
              let replacement = class_getInstanceMethod(UIViewController.self, b) else { return }
        method_exchangeImplementations(original, replacement)
    }

    /// Marks a sheet for its phone size; true when it is one.
    @MainActor @discardableResult
    static func mark(_ presented: UIViewController, from presenter: UIViewController) -> Bool {
        switch presented.modalPresentationStyle {
        case .formSheet, .pageSheet, .automatic: break
        default: return false
        }
        let window = presenter.viewIfLoaded?.window ?? presenter.view.window
        let height = min(maxHeight, max(480, (window?.bounds.height ?? maxHeight) - 48))
        presented.modalPresentationStyle = .formSheet
        // The sheet's window is sized in screen points; the page inside it
        // is laid out after the zoom, so ask for the zoomed size.
        let zoom = MacLayout.zoom
        objc_setAssociatedObject(presented, &sizeKey,
                                 NSValue(cgSize: CGSize(width: width * zoom, height: height * zoom)),
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return true
    }

    /// A sheet on the Mac is its OWN window (a macOS sheet attached to the
    /// app's window, measured 2026-10-25), so it gets the window's zoom here
    /// — it doesn't inherit it, and its text came out at the Mac's 13 pt.
    /// And since macOS swallows clicks behind a sheet, a click outside can't
    /// close it: Esc does, under the swipe's own rule — never a sheet that is
    /// modal (`interactiveDismissDisabled` sets that, e.g. while recording) or
    /// whose delegate says no. On the phone many sheets are closed by a swipe
    /// alone; a sheet that needs a visible button on the Mac gets one itself
    /// (the player).
    @MainActor
    static func makeClosable(_ presented: UIViewController) {
        presented.addKeyCommand(UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [],
                                             action: #selector(UIViewController.fv_macCloseSheet)))
        guard let window = presented.viewIfLoaded?.window, window.transform == .identity else { return }
        let zoom = MacLayout.zoom
        let size = window.frame.size
        window.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        window.bounds = CGRect(origin: .zero, size: CGSize(width: size.width / zoom, height: size.height / zoom))
        window.center = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    @MainActor
    static func close(_ sheet: UIViewController) {
        // Esc reaches the sheet's own controller or anything presented above
        // it; close the topmost one.
        var top = sheet
        while let next = top.presentedViewController { top = next }
        guard !top.isBeingDismissed, !top.isModalInPresentation,
              let controller = top.presentationController else { return }
        if let delegate = controller.delegate,
           delegate.presentationControllerShouldDismiss?(controller) == false { return }
        // The same calls a swipe makes, so SwiftUI's `isPresented` follows.
        controller.delegate?.presentationControllerWillDismiss?(controller)
        top.dismiss(animated: true) {
            controller.delegate?.presentationControllerDidDismiss?(controller)
        }
    }
}

extension UIViewController {
    // Both are swapped with the originals by `MacSheets.install`, so the
    // calls inside them reach the originals.
    @objc fileprivate func fv_macPresent(_ presented: UIViewController, animated: Bool,
                                         completion: (() -> Void)?) {
        let isSheet = MacSheets.mark(presented, from: self)
        fv_macPresent(presented, animated: animated) {
            if isSheet { MacSheets.makeClosable(presented) }
            completion?()
        }
    }

    /// Esc on a sheet.
    @objc fileprivate func fv_macCloseSheet() {
        MacSheets.close(self)
    }

    @objc fileprivate var fv_macPreferredContentSize: CGSize {
        if let size = objc_getAssociatedObject(self, &MacSheets.sizeKey) as? NSValue {
            return size.cgSizeValue
        }
        return self.fv_macPreferredContentSize
    }
}
#endif

/// The review decks' cards are filed by DRAGGING them into a folder, which a
/// mouse does badly. On the Mac the keyboard does it: Space shows the back of
/// the card, 1–4 drop it into 10 min · Tomorrow · 3 days · Got it (the
/// folders' own order). Nothing on the iPhone or iPad.
private struct MacDeckKeys: ViewModifier {
    let reveal: () -> Void
    let file: (DrillBin) -> Void

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.background {
            ZStack {
                Button("") { reveal() }
                    .keyboardShortcut(.space, modifiers: [])
                ForEach(Array(DrillBin.allCases.enumerated()), id: \.element) { index, bin in
                    Button("") { file(bin) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
                }
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        #else
        content
        #endif
    }
}

extension View {
    func macDeckKeys(reveal: @escaping () -> Void, file: @escaping (DrillBin) -> Void) -> some View {
        modifier(MacDeckKeys(reveal: reveal, file: file))
    }
}

/// A scroll view a mouse can DRAG. On the Mac a scroll view moves only by
/// wheel or trackpad, which is right for a list and wrong for a map: the
/// Watch tab's people map (`PeopleSkyView`) is a 2-D scroll you grab and pull
/// on the phone, and a click-drag did nothing. Put this on the scroll view's
/// CONTENT; it finds the scroll view around it and moves it by the drag.
/// Clicks still reach what was clicked, and the wheel and trackpad scroll as
/// before. Nothing on the iPhone or iPad.
private struct MacDragToPan: UIViewRepresentable {
    /// Called when a drag starts — what a finger on the phone tells the
    /// scroll view's own phase (`.interacting`).
    var onBegin: () -> Void

    func makeUIView(context: Context) -> UIView {
        #if targetEnvironment(macCatalyst)
        let finder = Finder()
        finder.onBegin = onBegin
        return finder
        #else
        return UIView()
        #endif
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        #if targetEnvironment(macCatalyst)
        (uiView as? Finder)?.onBegin = onBegin
        #endif
    }

    #if targetEnvironment(macCatalyst)
    final class Finder: UIView {
        var onBegin: () -> Void = {}

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var view = superview
            while let v = view, !(v is UIScrollView) { view = v.superview }
            guard let scroll = view as? UIScrollView,
                  !(scroll.gestureRecognizers ?? []).contains(where: { $0 is Pan }) else { return }
            scroll.addGestureRecognizer(Pan(scroll: scroll) { [weak self] in self?.onBegin() })
        }
    }

    final class Pan: UIPanGestureRecognizer {
        private weak var scroll: UIScrollView?
        private var start: CGPoint = .zero
        private let onBegin: () -> Void

        init(scroll: UIScrollView, onBegin: @escaping () -> Void) {
            self.scroll = scroll
            self.onBegin = onBegin
            super.init(target: nil, action: nil)
            addTarget(self, action: #selector(moved))
            cancelsTouchesInView = true
        }

        @objc private func moved() {
            guard let scroll else { return }
            switch state {
            case .began:
                start = scroll.contentOffset
                onBegin()
            case .changed:
                let t = translation(in: scroll)
                let inset = scroll.adjustedContentInset
                let maxX = max(-inset.left, scroll.contentSize.width + inset.right - scroll.bounds.width)
                let maxY = max(-inset.top, scroll.contentSize.height + inset.bottom - scroll.bounds.height)
                scroll.contentOffset = CGPoint(x: min(max(start.x - t.x, -inset.left), maxX),
                                               y: min(max(start.y - t.y, -inset.top), maxY))
            default:
                break
            }
        }
    }
    #endif
}

extension View {
    /// Click-drag moves the enclosing scroll view on the Mac; nothing elsewhere.
    func macDragToPan(onBegin: @escaping () -> Void = {}) -> some View {
        #if targetEnvironment(macCatalyst)
        background(MacDragToPan(onBegin: onBegin).allowsHitTesting(false))
        #else
        self
        #endif
    }
}
