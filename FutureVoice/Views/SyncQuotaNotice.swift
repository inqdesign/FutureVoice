import SwiftUI
import UIKit

/// Says, once, that iCloud is full and what that leaves unprotected
/// (see `SyncEngine.quotaFull`). A learner who turned sync on to keep their
/// practice safe has to be told the day it stops being safe — that is the
/// whole promise of the toggle. Shown as a system alert on top of whatever is
/// up, never during a call (it waits for the next pass or foreground), and the
/// same words stay in Me → Devices for as long as it lasts.
@MainActor
enum SyncQuotaNotice {
    static var title: String { explain("Your iCloud storage is full") }

    static func detail(_ scope: SyncEngine.QuotaScope) -> String {
        switch scope {
        case .audio:
            return explain("Your recordings aren't backed up to iCloud right now, so they're on this device only. If you delete the app on this device, they're deleted with it.")
        case .everything:
            return explain("New talks and recordings aren't backed up to iCloud right now, so they're on this device only. If you delete the app on this device, they're deleted with it.")
        }
    }

    static var howTo: String {
        explain("Free up space in Settings → your name → iCloud, and syncing picks up where it stopped.")
    }

    static func presentIfNeeded() {
        let engine = SyncEngine.shared
        guard engine.isEnabled, engine.quotaNoticePending, let scope = engine.quotaFull,
              !DailyCallScheduler.isLiveCall,
              UIApplication.shared.applicationState == .active,
              let top = TopPresenter.top(),
              !(top is UIAlertController) else { return }
        let alert = UIAlertController(title: title,
                                      message: detail(scope) + "\n\n" + howTo,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: explain("OK"), style: .default))
        top.present(alert, animated: true)
        engine.markQuotaNoticed()
        Analytics.capture("sync_quota_notice_shown", ["scope": scope.rawValue])
    }
}

/// The view controller on top of everything presented right now — for the
/// few things that must appear over a sheet or cover they don't own.
@MainActor
enum TopPresenter {
    static func top() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var vc = scene?.keyWindow?.rootViewController
        while let next = vc?.presentedViewController, !next.isBeingDismissed { vc = next }
        return vc
    }
}
