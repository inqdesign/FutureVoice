import SwiftUI
import UIKit

/// The Mac build (Mac Catalyst, Mac idiom). The app is designed for a phone,
/// and two things about that read wrong on a Mac, so the Mac fixes both here;
/// on the iPhone and iPad every function in this file is a no-op.
///
/// - **Size.** The Mac idiom draws with the Mac's own text sizes (body 13 pt,
///   captions 10 pt — measured 2026-10-25) and IGNORES Dynamic Type: no
///   content size category, SwiftUI `dynamicTypeSize` or trait override moves
///   them. So the whole page is ZOOMED instead (the window's root view, see
///   `MacWindow.zoomContent`), the way a browser zooms a page: 1.3× by default puts body text back at the
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

    /// Where a page hides the tab bar on the phone (a book, a list, a scene),
    /// the Mac keeps it: there the tabs are the window's own navigation in
    /// the title bar, and a book that hid them left no way to another tab
    /// (founder, 2026-10-27).
    static var tabBarOnPhoneOnly: Visibility { isMac ? .automatic : .hidden }

    static let zoomKey = "mac.zoom"
    /// The camera picked in View → Camera (its `uniqueID`); empty = automatic.
    static let cameraKey = "mac.camera"
    static let columnKey = "mac.columnWidth"

    static let zoomSteps: [CGFloat] = [1.0, 1.1, 1.2, 1.3, 1.45, 1.6, 1.8]
    static let defaultZoom = 3

    static func clampedZoomIndex(_ i: Int) -> Int { min(max(i, 0), zoomSteps.count - 1) }

    /// Review splits into shelves | open book from this page width on (zoomed
    /// points); the shelves keep the phone's width on the left.
    static let reviewSplitMinWidth: CGFloat = 860
    static let reviewShelfWidth: CGFloat = 400
    /// The column a split page may grow to, whatever Page Width says — two
    /// panes in a phone's width would be two cramped phones.
    static let splitColumnWidth: CGFloat = 1240

    /// How the tab on screen wants the column: Review splits and needs room,
    /// Speech reads like a page and is held narrow (founder, 2026-10-27), the
    /// rest take what View → Page Width says.
    enum ColumnMode { case normal, split, narrow }

    @MainActor
    final class Wide: ObservableObject {
        static let shared = Wide()
        @Published var mode: ColumnMode = .normal
    }

    /// Posted when a Mac window is resized or re-zoomed.
    static let windowDidResize = Notification.Name("futurevoice.macWindowDidResize")

    /// The height a page lays out against: the phone's screen, or on the Mac
    /// the window (in zoomed points). `UIScreen.main` on a Mac is the whole
    /// display, so a layout centred on it put the Talk ring below the window.
    @MainActor
    static var screenWidth: CGFloat {
        #if targetEnvironment(macCatalyst)
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow ?? ($0 as? UIWindowScene)?.windows.first }
            .first
        if let width = window?.bounds.width, width > 0 { return width / zoom }
        #endif
        return UIScreen.main.bounds.width
    }

    @MainActor
    static var screenHeight: CGFloat {
        #if targetEnvironment(macCatalyst)
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow ?? ($0 as? UIWindowScene)?.windows.first }
            .first
        // The window is in screen points; pages lay out after the zoom.
        if let height = window?.bounds.height, height > 0 { return height / zoom }
        #endif
        return UIScreen.main.bounds.height
    }

    static var zoom: CGFloat {
        // An Int as saved by the menu, or a launch argument's string (`-mac.zoom 0`).
        let raw = UserDefaults.standard.object(forKey: zoomKey)
        let stored = raw as? Int ?? (raw as? String).flatMap(Int.init) ?? defaultZoom
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
    @ObservedObject private var wide = MacLayout.Wide.shared

    private var width: CGFloat {
        let picked = (MacLayout.Column(rawValue: column) ?? .regular).width ?? .infinity
        switch wide.mode {
        case .normal: return picked
        // A split has two panes of its own to fill; the window is its column.
        case .split: return .infinity
        case .narrow: return min(picked, MacLayout.Column.narrow.width ?? picked)
        }
    }

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        // The column itself is applied as safe area (`MacWindow.insetColumn`).
        content
            .onAppear { MacWindow.columnWidth = width }
            .onChange(of: width) { _, now in MacWindow.columnWidth = now }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        #else
        content
        #endif
    }
}

extension View {
    /// The column the tab on screen wants on the Mac. Fed from the selected
    /// TAB, never a tab's own appear/disappear: a Mac tab switch never told
    /// Review it had gone, and Speech stayed at the split width.
    func macColumnMode(_ mode: MacLayout.ColumnMode) -> some View {
        #if targetEnvironment(macCatalyst)
        onAppear { MacLayout.Wide.shared.mode = mode }
            .onChange(of: mode) { _, now in MacLayout.Wide.shared.mode = now }
        #else
        self
        #endif
    }

    /// A row that scrolls sideways inside the column draws on past it, so
    /// its next card and every shadow reach the window's edge instead of
    /// stopping at the column's (Mac only).
    func macCarousel() -> some View {
        #if targetEnvironment(macCatalyst)
        scrollClipDisabled()
        #else
        self
        #endif
    }

    /// A pager is the column's own: a SwiftUI scroll view draws into the
    /// safe area the column is made of, so without this the next page sat in
    /// the window's margin (Mac only).
    func macPager() -> some View {
        #if targetEnvironment(macCatalyst)
        clipped()
        #else
        self
        #endif
    }

    /// Runs past the column to the window's edges — a map, nothing to read
    /// (Mac only).
    func macEdgeToEdge() -> some View {
        #if targetEnvironment(macCatalyst)
        ignoresSafeArea(.container, edges: .horizontal)
        #else
        self
        #endif
    }

    /// The Mac's centred column; nothing on the iPhone or iPad.
    func macPage() -> some View {
        modifier(MacPageModifier())
    }
}

/// View → zoom and page width, with the shortcuts every Mac reader knows.
struct MacViewCommands: Commands {
    @AppStorage(MacLayout.cameraKey) private var cameraId = ""
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
            // Which camera a speech take films with — a Mac often has several
            // (built-in, a display's, an iPhone, virtual ones). Takes effect
            // the next time the camera opens.
            Picker("Camera", selection: $cameraId) {
                Text("Automatic").tag("")
                ForEach(SpeechCamera.macCameras, id: \.uniqueID) { device in
                    Text(verbatim: device.localizedName).tag(device.uniqueID)
                }
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

    /// The page column, in zoomed points. Set by `macPage` from the tab on
    /// screen and View → Page Width.
    @MainActor static var columnWidth: CGFloat = .infinity {
        didSet {
            guard columnWidth != oldValue else { return }
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes { applyZoom(to: scene) }
        }
    }

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
        watchForRelayout()
        #endif
    }

    @MainActor private static var watching = false

    /// The zoom and the column are laid on what UIKit builds, and UIKit builds
    /// it late: at launch the tab controller doesn't exist yet and the title
    /// bar's inset is still 0, and becoming or leaving key re-lays the window
    /// without a resize. Measured: a launch that lost focus within a second
    /// came up with no column and the page under the title bar. So the layout
    /// is put back on every such edge, and a few times as the app settles.
    @MainActor
    private static func watchForRelayout() {
        #if targetEnvironment(macCatalyst)
        guard !watching else { return }
        watching = true
        let reapply = {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes { applyZoom(to: scene) }
        }
        for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification,
                     UIWindow.didBecomeKeyNotification, UIWindow.didResignKeyNotification,
                     UIWindow.didBecomeVisibleNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { reapply() }
                DispatchQueue.main.async { reapply() }
            }
        }
        for delay in [0.1, 0.4, 1.0, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { reapply() }
        }
        #endif
    }

    /// The scene's size is the window's size on screen, whatever UIKit last
    /// did to the window; the window lays out in that size divided by the zoom.
    @MainActor
    private static func applyZoom(to scene: UIWindowScene) {
        #if targetEnvironment(macCatalyst)
        for window in scene.windows { zoomContent(of: window) }
        #endif
    }

    /// Zooms what is INSIDE a window — its root view — never the window.
    /// A transformed UIWindow drew and hit-tested fine but AppKit could no
    /// longer place a menu over it: every dropdown in the app opened nothing
    /// (measured 2026-10-27: the same click opened the menu at 1.0× and did
    /// nothing at 1.3×). The window stays the size macOS gave it; its root
    /// view lays out in that size divided by the zoom and is scaled back up.
    @MainActor
    static func zoomContent(of window: UIWindow) {
        #if targetEnvironment(macCatalyst)
        if window.transform != .identity { window.transform = .identity }
        // The app's own window only — its SwiftUI root. Never the system's
        // text-input window, and never a sheet's window: on the Mac a sheet is
        // a window of its own whose root is the system's sheet container, and
        // scaling that stops every menu inside it (`MacSheets.zoomSheet`
        // zooms the sheet's page instead).
        guard let controller = window.rootViewController,
              String(describing: type(of: controller)).hasPrefix("UIHostingController"),
              let root = controller.viewIfLoaded else { return }
        let zoom = MacLayout.zoom
        let size = window.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        // A scaled root view gets NO safe area from the window (measured: the
        // window's top is the 52 pt title bar, the root's 0, and neither
        // `additionalSafeAreaInsets` nor a SwiftUI inset reached the UIKit
        // navigation bars), so the page slid up under the title bar. The root
        // is placed BELOW the title bar instead, so there is nothing to avoid.
        let top = window.safeAreaInsets.top
        let below = CGSize(width: size.width, height: max(1, size.height - top))
        let transform = CGAffineTransform(scaleX: zoom, y: zoom)
        let bounds = CGRect(origin: .zero, size: CGSize(width: below.width / zoom, height: below.height / zoom))
        let center = CGPoint(x: below.width / 2, y: top + below.height / 2)
        if root.transform != transform { root.transform = transform }
        if root.bounds != bounds { root.bounds = bounds }
        if root.center != center { root.center = center }
        insetColumn(of: controller, width: bounds.width)
        #endif
    }
}

#if targetEnvironment(macCatalyst)
extension MacWindow {
    /// The column is SAFE AREA on the tab controller, never a frame. A frame
    /// clipped every scroll view at the column's edge — card shadows, a
    /// carousel's next card, the Watch map — while a horizontal safe area
    /// centres nav bars, titles and rows on the column and lets every scroll
    /// view, background and map run to the window's edge.
    @MainActor
    static func insetColumn(of root: UIViewController, width: CGFloat) {
        let pad = max(0, ((width - columnWidth) / 2).rounded())
        func walk(_ vc: UIViewController) {
            if vc is UITabBarController {
                let insets = UIEdgeInsets(top: vc.additionalSafeAreaInsets.top, left: pad,
                                          bottom: vc.additionalSafeAreaInsets.bottom, right: pad)
                if vc.additionalSafeAreaInsets != insets { vc.additionalSafeAreaInsets = insets }
                return
            }
            vc.children.forEach(walk)
        }
        walk(root)
    }
}

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
        // SwiftUI's own sheets only. Everything else UIKit presents — menus,
        // pickers, share sheets — goes through `present` too, and forcing one
        // of those into a form sheet broke every dropdown in the app
        // (2026-10-27).
        guard String(describing: type(of: presented)).hasPrefix("PresentationHostingController") else {
            return false
        }
        switch presented.modalPresentationStyle {
        case .formSheet, .pageSheet: break
        default: return false
        }
        let window = presenter.viewIfLoaded?.window ?? presenter.view.window
        let zoom = MacLayout.zoom
        // The window is in screen points and the sheet hangs below its title
        // bar; the page inside lays out after the zoom.
        let room = window.map { ($0.bounds.height - $0.safeAreaInsets.top) / zoom - 24 } ?? maxHeight
        let height = min(maxHeight, max(420, room))
        presented.modalPresentationStyle = .formSheet
        // The sheet's window is sized in screen points, so ask for the zoomed size.
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
        zoomSheet(presented)
    }

    /// The sheet's own page is zoomed, never its window's root: that root is
    /// the system's sheet container, and scaling it stopped every menu inside
    /// the sheet from opening (measured 2026-10-27, the player's ⋯).
    @MainActor
    static func zoomSheet(_ presented: UIViewController) {
        guard let view = presented.viewIfLoaded, let host = view.superview else { return }
        let zoom = MacLayout.zoom
        let size = host.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let transform = CGAffineTransform(scaleX: zoom, y: zoom)
        let bounds = CGRect(origin: .zero, size: CGSize(width: size.width / zoom, height: size.height / zoom))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        if view.transform != transform { view.transform = transform }
        if view.bounds != bounds { view.bounds = bounds }
        if view.center != center { view.center = center }
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

#if targetEnvironment(macCatalyst)
/// The phone's glass buttons, as the phone draws them. On the Mac the system
/// `.glass` button style fills the whole button with the tint, so the Talk
/// tab's player, "Find a topic", the quiz face and the card bars came out as
/// solid blue discs (founder, 2026-10-27). This keeps the glass clear — the
/// same `glassEffect` the style uses — and colours only the label, the way
/// the phone does. Used in place of `.glass` under `#if macCatalyst` only.
struct MacGlassButtonStyle: ButtonStyle {
    var circle = false

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, circle: circle)
    }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let circle: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = circle ? AnyShape(Circle()) : AnyShape(Capsule())
            configuration.label
                .foregroundStyle(.tint)
                .padding(.horizontal, circle ? 10 : 14)
                .padding(.vertical, 10)
                .frame(minWidth: circle ? 50 : nil, minHeight: 44)
                .contentShape(shape)
                .modifier(Glass(shape: shape))
                .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
        }
    }

    private struct Glass: ViewModifier {
        let shape: AnyShape
        @Environment(\.colorScheme) private var colorScheme
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                // The same glass the phone's home buttons wear (`homeGlass`).
                content.glassEffect(homeGlass(colorScheme).interactive(), in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        }
    }
}
#endif
