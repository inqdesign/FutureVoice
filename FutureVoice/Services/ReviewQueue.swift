import Foundation

/// The one answer to "what is waiting to come back, right now" — shared by
/// the review reminder (which COUNTS it) and the review deck (which DEALS
/// it). They have to agree: a notification saying "2 items are back" that
/// opens onto an empty deck is worse than no notification at all.
///
/// The disagreement is real and not hypothetical: marking a word known from
/// the notebook, or an expression known from its card, retires the item
/// without touching its schedule entry. Those stale entries are pruned here,
/// so both callers see the same live queue.
@MainActor
enum ReviewQueue {

    /// Write a return time AND arm the reminder for it. Every deck resolves
    /// through here rather than touching the store directly: the promise and
    /// the thing that keeps it must not be separable, or a new entry point
    /// silently schedules items nothing will ever ring for.
    ///
    /// This is a foreground, contextual moment — the learner just asked to be
    /// shown something later — so it's also where permission gets requested.
    static func snooze(_ kind: StudyScheduleStore.Kind, _ text: String, for delay: TimeInterval) {
        let at = Date().addingTimeInterval(delay)
        StudyScheduleStore.shared.snooze(kind, text, until: at)
        let target = target(kind, text)
        Task {
            // Permission first (this is the contextual moment), then the
            // callback for THIS item — named, so the notification is about
            // the card the learner just put away rather than a pile.
            await DrillReminder.reschedule(allowPermissionPrompt: true)
            await ItemReminder.schedule(target, text: text, at: at)
        }
    }

    /// The item is known — drop its schedule, take back its callback, and
    /// re-aim the aggregate reminder at whatever is now earliest.
    static func retire(_ kind: StudyScheduleStore.Kind, _ text: String) {
        StudyScheduleStore.shared.clear(kind, text)
        ItemReminder.cancel(target(kind, text))
        Task { await DrillReminder.reschedule() }
    }

    private static func target(_ kind: StudyScheduleStore.Kind, _ text: String) -> ItemReminder.Target {
        switch kind {
        case .word:       return .word(text)
        case .expression: return .expression(text)
        }
    }

    /// Items whose return time has arrived, oldest promise first.
    static func dueItems(now: Date = Date()) -> [StudyDeckItem] {
        pruneRetired()
        return StudyScheduleStore.shared.dueItems(now: now)
            .map { StudyDeckItem(kind: $0.kind, text: $0.text) }
    }

    /// Every live return time — what the reminder picks its fire date from.
    static func returnDates() -> [Date] {
        pruneRetired()
        return StudyScheduleStore.shared.allNextReviews()
    }

    /// Forget the schedule for anything already retired. Idempotent.
    static func pruneRetired() {
        let store = StudyScheduleStore.shared
        let vocab = VocabStore.shared
        for item in store.dueItems(now: .distantFuture) where isRetired(item, vocab) {
            store.clear(item.kind, item.text)
        }
    }

    private static func isRetired(_ item: StudyScheduleStore.DueItem,
                                  _ vocab: VocabStore) -> Bool {
        switch item.kind {
        case .word:
            return vocab.state(of: VocabStore.lookupKey(for: item.text)) == .known
                || vocab.state(of: item.text.lowercased()) == .known
        case .expression:
            return vocab.isKnownExpression(item.text)
        }
    }
}
