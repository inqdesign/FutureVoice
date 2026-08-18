import SwiftUI
import Supabase

/// One answer to "can this account pay for what this tap is about to start?",
/// shared by every surface that launches something metered — a call, a Watch
/// scene.
///
/// The rule is the server's, restated once on the client so it can be asked
/// BEFORE the spending starts: under the hard paywall an account with no
/// subscription and an empty pool cannot talk, so launching anyway is a trip
/// that can only end in a 402. The 402 arrives too late to be the answer to
/// the tap — by then the call screen is up, or (worse, on Watch) a whole
/// scene has been written and the learner watched it being written before
/// being told it isn't theirs to play. Asked here, the paywall IS the answer
/// to the tap, exactly like the Talk button's.
///
/// Gates on `needsSubscription` ONLY, and deliberately not on the daily cap:
/// that learner already paid, the answer is tomorrow rather than money (see
/// CLAUDE.md), and the client's copy of today's usage is stale often enough
/// that pre-judging it would refuse a call the server would have allowed.
/// Everywhere else the server stays the authority — this only skips the trips
/// that cannot succeed.
@MainActor
final class BillingGate: ObservableObject {
    static let shared = BillingGate()

    /// The last snapshot the gate fetched. Published so a view can draw
    /// chrome off the same fetch the decision was made from instead of
    /// running its own (ConversationHome's talk-time ring).
    @Published private(set) var account: AccountStatus?

    private var fetchedAt: Date?
    private var inFlight: Task<AccountStatus?, Never>?

    /// How long a snapshot answers for. Short — it decides whether someone
    /// gets to talk.
    private static let freshFor: TimeInterval = 60

    private init() {}

    /// True when the paywall is the honest answer to this tap.
    ///
    /// A "yes, they can pay" answer is given from cache without waiting: this
    /// sits on the tap path of the app's primary button, and a stale yes costs
    /// only the 402 that already has a handler. A "no" is never given from
    /// cache — a purchase or a redeemed invite that landed a minute ago must
    /// not be paywalled again, and the extra round trip is free on a path that
    /// was about to stop anyway.
    func blocks() async -> Bool {
        if let cached = account, !cached.needsSubscription {
            Task { await refreshIfStale() }
            return false
        }
        return await snapshot(force: account != nil)?.needsSubscription ?? false
    }

    /// The current snapshot, fetched when stale. Nil means "couldn't ask" —
    /// callers treat that as a pass, never as a refusal.
    @discardableResult
    func snapshot(force: Bool = false) async -> AccountStatus? {
        if !force, let account, !isStale { return account }
        if let inFlight { return await inFlight.value }
        let task = Task { await Self.load() }
        inFlight = task
        let fresh = await task.value
        inFlight = nil
        if let fresh {
            account = fresh
            fetchedAt = Date()
        }
        return fresh
    }

    /// Warm the snapshot so the next paid tap answers without a round trip.
    func warm() {
        Task { await refreshIfStale() }
    }

    /// Drop the cached answer — after anything that can change it (a
    /// purchase, a finished call).
    func invalidate() { fetchedAt = nil }

    /// Run `start`, or raise the paywall in its place. Every metered launch
    /// goes through here so the paywall lands on the tap rather than on top of
    /// a screen that has already started spending.
    ///
    /// `paywall` must belong to the view that is ON SCREEN when the tap
    /// happens: a sheet hosting a paid button owns its own paywall, because a
    /// sheet presented from underneath a sheet — or from one that is midway
    /// through dismissing — silently never appears.
    static func start(orShow paywall: Binding<Bool>, _ start: @escaping () -> Void) {
        Task { @MainActor in
            if await shared.blocks() { paywall.wrappedValue = true } else { start() }
        }
    }

    private var isStale: Bool {
        guard let fetchedAt else { return true }
        return Date().timeIntervalSince(fetchedAt) >= Self.freshFor
    }

    private func refreshIfStale() async {
        guard isStale else { return }
        await snapshot()
    }

    private static func load() async -> AccountStatus? {
        #if DEBUG
        // Screenshot captures run signed out; nothing here may block them.
        if UserDefaults.standard.string(forKey: "capture") != nil { return nil }
        #endif
        // No session is "couldn't ask", NOT "no plan". `AccountStatus.fetch()`
        // answers with its empty snapshot there, which reads as an account
        // holding nothing — and would paywall someone we merely failed to
        // identify.
        guard (try? await SupabaseProvider.shared.auth.session) != nil else { return nil }
        return await AccountStatus.fetch()
    }
}
