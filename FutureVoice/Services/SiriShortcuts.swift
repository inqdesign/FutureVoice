import AppIntents
import Foundation

// Siri and the Shortcuts app (2026-11-05). Four things a learner might say
// out loud with the phone out of reach: call the fluent self, review, open
// the words, take the weekly test. Each one only OPENS the app at the place
// a widget or a push already opens it — through `DailyCallInbox.pendingURL`,
// the one door every `futurevoice://` link walks through — so nothing here
// changes data, spends talk time on its own, or skips `BillingGate`.
//
// These are the same App Intents Apple's Siri AI reads (developer preview in
// the 27.3 betas, 2026-11-03); on iOS 26 they work as App Shortcuts: the
// phrases below, Spotlight, the Shortcuts app, the Action button.

/// One `futurevoice://` link, opened in the foreground.
@MainActor
private func openLink(_ link: String) {
    guard let url = URL(string: link) else { return }
    DailyCallInbox.shared.pendingURL = url
}

struct StartTalkIntent: AppIntent {
    static var title: LocalizedStringResource = "Call my future self"
    static var description = IntentDescription("Start a free talk with your fluent self.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Analytics.capture("siri_intent", ["kind": "talk"])
        openLink("futurevoice://freetalk")
        return .result()
    }
}

struct StartReviewIntent: AppIntent {
    static var title: LocalizedStringResource = "Review my cards"
    static var description = IntentDescription("Open today's review deck.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Analytics.capture("siri_intent", ["kind": "review"])
        openLink("futurevoice://routine?kind=review")
        return .result()
    }
}

struct OpenWordsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open my words"
    static var description = IntentDescription("Open the words you are studying.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Analytics.capture("siri_intent", ["kind": "words"])
        openLink("futurevoice://vocab")
        return .result()
    }
}

struct OpenWeeklyTestIntent: AppIntent {
    static var title: LocalizedStringResource = "Take my weekly test"
    static var description = IntentDescription("Open this week's test.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Analytics.capture("siri_intent", ["kind": "weekly_test"])
        openLink("futurevoice://weeklytest")
        return .result()
    }
}

/// The phrases Siri listens for. Every phrase must name the app, and the
/// Korean (and other) phrases live in `AppShortcuts.xcstrings` — Siri
/// resolves them by the DEVICE language, like a permission alert.
struct NawanaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTalkIntent(),
            phrases: [
                "Call my future self in \(.applicationName)",
                "Start a talk in \(.applicationName)",
                "\(.applicationName) call",
            ],
            shortTitle: "Call my future self",
            systemImageName: "phone.fill"
        )
        AppShortcut(
            intent: StartReviewIntent(),
            phrases: [
                "Review my cards in \(.applicationName)",
                "Start my review in \(.applicationName)",
            ],
            shortTitle: "Review",
            systemImageName: "rectangle.stack.fill"
        )
        AppShortcut(
            intent: OpenWordsIntent(),
            phrases: [
                "Open my words in \(.applicationName)",
                "Show my words in \(.applicationName)",
            ],
            shortTitle: "My words",
            systemImageName: "character.book.closed.fill"
        )
        AppShortcut(
            intent: OpenWeeklyTestIntent(),
            phrases: [
                "Take my weekly test in \(.applicationName)",
            ],
            shortTitle: "Weekly test",
            systemImageName: "checkmark.seal.fill"
        )
    }
}
