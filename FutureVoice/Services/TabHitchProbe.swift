#if DEBUG
import QuartzCore
import Combine
import os

/// DEBUG-only: measures what a tab switch costs on the main thread.
/// `mark(tab)` on every selection change; the display link then logs how long
/// the first frame took to arrive and every frame gap over ~1.5 refresh
/// intervals in the next second. `-tabcycle 1` walks the tabs by itself so a
/// profiler can be attached without anyone tapping.
@MainActor
final class TabHitchProbe: NSObject {
    static let shared = TabHitchProbe()
    private let log = Logger(subsystem: "com.roro.futurevoice", category: "tab-hitch")
    private var link: CADisplayLink?
    private var markAt: CFTimeInterval = 0
    private var tab = ""
    private var last: CFTimeInterval = 0
    private var firstFrameLogged = true
    private var worst: Double = 0
    private var dropped = 0
    private var publishes = 0
    private var watch: AnyCancellable?

    /// Counts `AppState` publishes inside the window — each one re-evaluates
    /// every view that observes it, all four tabs included.
    func observe(_ object: some ObservableObject) {
        guard watch == nil else { return }
        watch = object.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            let now = CACurrentMediaTime()
            self.publishTimes.append(now)
            if self.publishTimes.count > 200 { self.publishTimes.removeFirst(100) }
            guard self.markAt > 0 else { return }
            let caller = Thread.callStackSymbols.dropFirst(2)
                .first { $0.contains("FutureVoice") && !$0.contains("TabHitch") && !$0.contains("Published") }
                .map { $0.split(separator: " ").dropFirst(3).joined(separator: " ").prefix(120) } ?? "?"
            print("[tab-hitch]   publish t=\(Int(now * 1000) % 100000) \(caller)")
        }
    }
    private var publishTimes: [CFTimeInterval] = []

    func mark(_ tab: String) {
        if link == nil {
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        markAt = CACurrentMediaTime()
        last = markAt
        self.tab = tab
        firstFrameLogged = false
        worst = 0
        dropped = 0
        publishes = 0
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        guard markAt > 0 else { return }
        let interval = l.duration > 0 ? l.duration : 1.0 / 60
        if !firstFrameLogged {
            firstFrameLogged = true
            let ms = (now - markAt) * 1000
            log.notice("→\(self.tab, privacy: .public) first frame \(Int(ms))ms")
            print("[tab-hitch] →\(tab) first frame \(Int(ms))ms")
        }
        let gap = now - last
        if gap > interval * 1.5 {
            dropped += Int(gap / interval) - 1
            worst = max(worst, gap * 1000)
            print("[tab-hitch]   \(tab) gap \(Int(gap * 1000))ms at +\(Int((now - markAt) * 1000))ms")
        }
        last = now
        if now - markAt > 1.0 {
            print("[tab-hitch] ←\(tab) summary worst \(Int(worst))ms dropped \(dropped) appState publishes \(publishTimes.filter { $0 > markAt - 0.3 && $0 < markAt + 1 }.count) (mark t=\(Int(markAt * 1000) % 100000))")
            markAt = 0
        }
    }
}
#endif
