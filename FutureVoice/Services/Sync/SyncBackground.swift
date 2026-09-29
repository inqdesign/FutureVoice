import BackgroundTasks
import Foundation

/// Sync while the app is closed. Two tasks, one pass each (`runSync` is
/// resumable, so either may be cut off anywhere):
///
/// - **refresh** — a short, frequent wake: pulls what the other device did
///   (so the tablet has the phone's talk before it is opened) and pushes
///   anything the foreground left behind. ~30 s; audio past that waits.
/// - **processing** — the long one, asked for only while items or audio are
///   still waiting. iOS runs it when the phone is idle, usually overnight on
///   a charger, and that is what carries a first sync's gigabyte of audio
///   without the learner holding the app open. Audio still obeys the
///   Wi-Fi-only toggle — the transport's operations carry it.
///
/// When either runs is iOS's choice, never ours; the foreground pass stays
/// the one that is guaranteed.
enum SyncBackground {
    static let refreshId = "com.roro.futurevoice.sync.refresh"
    static let processingId = "com.roro.futurevoice.sync.processing"

    /// Must run before launch finishes — iOS refuses a later registration.
    static func register() {
        for id in [refreshId, processingId] {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { task in
                MainActor.assumeIsolated { run(task) }
            }
        }
    }

    /// Asked for on every trip to the background. Resubmitting replaces the
    /// pending request of the same id, so this never piles up.
    @MainActor
    static func schedule() {
        let engine = SyncEngine.shared
        guard engine.isEnabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshId)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingId)
            return
        }
        let refresh = BGAppRefreshTaskRequest(identifier: refreshId)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(refresh)

        if engine.hasBackgroundWork {
            let processing = BGProcessingTaskRequest(identifier: processingId)
            processing.requiresNetworkConnectivity = true
            try? BGTaskScheduler.shared.submit(processing)
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingId)
        }
    }

    @MainActor
    private static func run(_ task: BGTask) {
        let engine = SyncEngine.shared
        engine.restoreLastUserIfNeeded()
        guard engine.isEnabled else {
            task.setTaskCompleted(success: true)
            return
        }
        // Completed exactly once: expiry and a pass finishing can race.
        var done = false
        func finish(_ success: Bool) {
            guard !done else { return }
            done = true
            schedule()
            task.setTaskCompleted(success: success)
        }
        let pass = Task { @MainActor in
            await engine.syncAndWait(kinds: nil)
            Analytics.capture("sync_background", [
                "task": task.identifier == processingId ? "processing" : "refresh",
                "left": engine.hasBackgroundWork,
            ])
            finish(true)
        }
        task.expirationHandler = {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    engine.cancelRunning()
                    pass.cancel()
                    finish(false)
                }
            }
        }
    }
}
