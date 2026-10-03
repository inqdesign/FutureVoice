import SwiftUI
import UIKit

/// iOS 26 pops a navigation page on a right swipe ANYWHERE in its content,
/// not just from the edge. A page whose content is itself swiped sideways
/// (the routine journal's day strip and day list) loses the learner's swipe
/// to a back navigation. This keeps the back swipe on the screen EDGE only,
/// for as long as the page is up.
private struct EdgeOnlyBackSwipe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ vc: Controller, context: Context) {}

    final class Controller: UIViewController {
        private weak var disabled: UIGestureRecognizer?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            disableContentPop()
        }

        // The hosting chain may not reach the navigation controller yet at
        // willAppear; try again once the page is on screen.
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            disableContentPop()
        }

        private func disableContentPop() {
            guard disabled == nil else { return }
            if #available(iOS 26.0, *),
               let g = navigationController?.interactiveContentPopGestureRecognizer, g.isEnabled {
                g.isEnabled = false
                disabled = g
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            disabled?.isEnabled = true
            disabled = nil
        }
    }
}

extension View {
    /// Back swipe from the screen edge only — see `EdgeOnlyBackSwipe`.
    func edgeOnlyBackSwipe() -> some View {
        background(EdgeOnlyBackSwipe().frame(width: 0, height: 0))
    }
}
