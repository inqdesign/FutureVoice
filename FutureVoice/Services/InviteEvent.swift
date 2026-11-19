import Foundation
import StoreKit
import Supabase
import UIKit

/// The friend-invite event (2026-11-19): a friend who subscribes makes the
/// next month half price for both.
///
/// Nothing about it is compiled in. The size (percent, months), whether it
/// is on, which store offer carries it and EVERY WORD on its banner, sheets
/// and share message come from the server (`invite_event_state`), so the
/// founder changes any of it without a build (`scripts/invite-event.py`). A
/// fetch that fails, or an event that is off, draws nothing at all.
struct InviteEventState: Decodable {
    struct Reward: Decodable, Identifiable {
        let id: UUID
        let role: String
        let status: String
        let percent: Int
        let months: Int
    }

    var enabled = false
    var percent = 50
    var months = 1
    var announceVersion = 0
    var texts: [String: [String: String]] = [:]
    var canInvite = false
    var code: String?
    var invited = false
    var store: String?
    var appleProductId: String?
    var appleOfferId: String?
    var renewsAt: Date?
    var claimable: UUID?
    var rewards: [Reward] = []

    static let off = InviteEventState()

    init() {}

    enum CodingKeys: String, CodingKey {
        case enabled, percent, months, texts, code, invited, store, claimable, rewards
        case announceVersion = "announce_version"
        case canInvite = "can_invite"
        case appleProductId = "apple_product_id"
        case appleOfferId = "apple_offer_id"
        case renewsAt = "renews_at"
    }

    /// Lenient on purpose: an event that is off answers `{enabled: false}`
    /// and nothing else, and a field added later must not blank the banner.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        percent = (try? c.decode(Int.self, forKey: .percent)) ?? 50
        months = (try? c.decode(Int.self, forKey: .months)) ?? 1
        announceVersion = (try? c.decode(Int.self, forKey: .announceVersion)) ?? 0
        texts = (try? c.decode([String: [String: String]].self, forKey: .texts)) ?? [:]
        canInvite = (try? c.decode(Bool.self, forKey: .canInvite)) ?? false
        code = try? c.decode(String.self, forKey: .code)
        invited = (try? c.decode(Bool.self, forKey: .invited)) ?? false
        store = try? c.decode(String.self, forKey: .store)
        appleProductId = try? c.decode(String.self, forKey: .appleProductId)
        appleOfferId = try? c.decode(String.self, forKey: .appleOfferId)
        claimable = try? c.decode(UUID.self, forKey: .claimable)
        rewards = (try? c.decode([Reward].self, forKey: .rewards)) ?? []
        if let raw = try? c.decode(String.self, forKey: .renewsAt) {
            renewsAt = Self.date(raw)
        }
    }

    private static func date(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}

@MainActor
final class InviteEvent: ObservableObject {
    static let shared = InviteEvent()

    /// Where this account stands, which decides what the banner says.
    enum Phase: Equatable {
        /// Nothing to draw: the event is off or could not be read.
        case off
        /// A half-price month is waiting for the subscriber's own yes (the
        /// App Store asks them, on its redeem page).
        case claim
        /// A half-price month is on its way: taken here, or applied by the
        /// web store with no tap.
        case applied(auto: Bool)
        /// Came through a friend's invite, not subscribed yet.
        case invited
        /// A subscriber who can invite.
        case invite
        /// No plan yet: the offer is read first, subscribing is the button.
        case needsPlan
    }

    @Published private(set) var state = InviteEventState.off
    /// The discounted and the regular price of the claimable month, as the
    /// App Store prints them. Nil where the store has not answered.
    @Published private(set) var offerPrice: String?
    @Published private(set) var fullPrice: String?
    @Published var claiming = false
    @Published var claimError: String?

    private static let seenAnnounceKey = "futurevoice.inviteEvent.seenAnnounce"
    private static let offeredClaimKey = "futurevoice.inviteEvent.offeredClaim"

    var phase: Phase {
        guard state.enabled else { return .off }
        if state.claimable != nil {
            // Only the App Store can be taken from here. A web subscriber's
            // month is applied by the server; one bought on another store
            // is taken in that store's app.
            if state.store == "apple", state.appleOfferId != nil { return .claim }
        }
        if state.rewards.contains(where: { $0.status == "claimed" }) {
            return .applied(auto: state.store == "stripe")
        }
        if state.invited && !state.canInvite { return .invited }
        return state.canInvite ? .invite : .needsPlan
    }

    /// How many half-price months are still waiting behind the current one.
    var monthsWaiting: Int { state.rewards.filter { $0.status == "ready" }.count }

    #if DEBUG
    /// The simulator preview: a state made up on the spot, never fetched.
    func seedDemo(_ state: InviteEventState, offerPrice: String?, fullPrice: String?) {
        self.state = state
        self.offerPrice = offerPrice
        self.fullPrice = fullPrice
    }
    #endif

    // MARK: - Reading

    func refresh() async {
        #if DEBUG
        // Developer → Preview invite event: the made-up state stays until it
        // is switched off, whatever the server says.
        if let phase = UserDefaults.standard.string(forKey: InviteEventDemo.phaseKey), phase != "off" {
            InviteEventDemo.seed(phase: phase)
            return
        }
        #endif
        guard (try? await SupabaseProvider.shared.auth.session) != nil else {
            state = .off
            return
        }
        do {
            let fresh: InviteEventState = try await SupabaseProvider.shared
                .rpc("invite_event_state")
                .execute()
                .value
            state = fresh
            await loadPrices()
        } catch {
            // A database without the event (an older server) or no network:
            // nothing is drawn, which is the same as the event being off.
            state = .off
        }
    }

    /// Before there is an account (the Welcome screen's code field): the
    /// event's size and words alone, which anyone may read.
    func loadPublicIfNeeded() async {
        guard !state.enabled else { return }
        struct Row: Decodable {
            let enabled: Bool
            let percent: Int
            let months: Int
            let texts: [String: [String: String]]
        }
        guard let rows: [Row] = try? await SupabaseProvider.shared
            .from("invite_event")
            .select("enabled, percent, months, texts")
            .limit(1)
            .execute()
            .value,
              let row = rows.first, row.enabled, !state.enabled else { return }
        var fresh = InviteEventState()
        fresh.enabled = true
        fresh.percent = row.percent
        fresh.months = row.months
        fresh.texts = row.texts
        // Announcing is the signed-in state's business.
        fresh.announceVersion = 0
        state = fresh
    }

    /// The claimable month's price is worked out here (an offer-code offer
    /// is not listed on the product), cut DOWN to the currency's own
    /// decimals: 9.99 at 50% is 4.99 on the App Store, never 5.00. Apple's
    /// redeem page states the real figure before anything is confirmed.
    private func loadPrices() async {
        guard let productId = state.appleProductId,
              let product = try? await Product.products(for: [productId]).first else {
            offerPrice = nil
            fullPrice = nil
            return
        }
        fullPrice = product.displayPrice
        var cut = product.price * Decimal(100 - state.percent) / 100
        var rounded = Decimal()
        let places = product.price == product.price.rounded0 ? 0 : 2
        NSDecimalRound(&rounded, &cut, places, .down)
        offerPrice = rounded.formatted(product.priceFormatStyle)
    }

    // MARK: - Words

    /// One of the event's lines in the app language, falling back to
    /// English, with its numbers filled in. Empty when the server has no
    /// such line, and an empty line is not drawn.
    func text(_ key: String) -> String {
        let language = LanguageCatalog.currentNative
        let base = String(language.split(separator: "-").first ?? "en")
        let raw = state.texts[language]?[key] ?? state.texts[base]?[key] ?? state.texts["en"]?[key] ?? ""
        var out = raw
            .replacingOccurrences(of: "{percent}", with: String(state.percent))
            .replacingOccurrences(of: "{months}", with: String(state.months))
            .replacingOccurrences(of: "{code}", with: state.code ?? "")
            .replacingOccurrences(of: "{waiting}", with: String(monthsWaiting))
            .replacingOccurrences(of: "{price}", with: offerPrice ?? "")
            .replacingOccurrences(of: "{full}", with: fullPrice ?? "")
        if let renews = state.renewsAt {
            // Month and day only: the year is never in doubt a month ahead.
            let style = Date.FormatStyle().month(.abbreviated).day()
                .locale(Locale(identifier: language))
            out = out.replacingOccurrences(of: "{date}", with: renews.formatted(style))
        } else {
            out = out.replacingOccurrences(of: "{date}", with: "")
        }
        return out
    }

    var shareMessage: String { text("share_message") }

    // MARK: - Shown once

    /// The announcement sheet is owed once per `announce_version`.
    var owesAnnouncement: Bool {
        state.enabled && state.announceVersion > UserDefaults.standard.integer(forKey: Self.seenAnnounceKey)
    }

    func markAnnounced() {
        UserDefaults.standard.set(state.announceVersion, forKey: Self.seenAnnounceKey)
    }

    /// The claim sheet raises itself once per reward; after that the banner
    /// is the door.
    var owesClaimOffer: Bool {
        guard phase == .claim, let id = state.claimable else { return false }
        return UserDefaults.standard.string(forKey: Self.offeredClaimKey) != id.uuidString
    }

    func markClaimOffered() {
        UserDefaults.standard.set(state.claimable?.uuidString, forKey: Self.offeredClaimKey)
    }

    // MARK: - Taking the month (App Store)

    private struct CodeAnswer: Decodable { let code: String }
    private static let appStoreId = "6792794655"
    private var awaitingRedeem = false
    private var foregroundWatch: NSObjectProtocol?

    /// The server hands this reward its one-time offer code and Apple's own
    /// redeem page, opened with the code filled in, applies it to the next
    /// renewal. Nothing is reported from here: the reward turns "claimed"
    /// when Apple's renewal info names the offer, so the banner changes a
    /// moment after the learner comes back. True once the page was opened.
    @discardableResult
    func claim() async -> Bool {
        guard !claiming else { return false }
        claiming = true
        claimError = nil
        defer { claiming = false }
        do {
            let answer: CodeAnswer? = try await SupabaseProvider.shared
                .rpc("invite_reward_code")
                .execute()
                .value
            guard let code = answer?.code,
                  let url = URL(string: "https://apps.apple.com/redeem?ctx=offercodes&id=\(Self.appStoreId)&code=\(code)"),
                  await UIApplication.shared.open(url) else {
                claimError = text("claim_failed")
                Analytics.capture("invite_reward_claim_failed", ["error": answer == nil ? "no_code" : "no_open"])
                return false
            }
            Analytics.capture("invite_reward_claim_opened", ["store": "apple"])
            watchForReturn()
            return true
        } catch {
            claimError = text("claim_failed")
            Analytics.capture("invite_reward_claim_failed", ["error": String(describing: error).prefix(120).description])
            return false
        }
    }

    /// Back from Apple's page: Apple tells the server within seconds, not at
    /// once, so the state is read a few times until the claim shows.
    private func watchForReturn() {
        awaitingRedeem = true
        guard foregroundWatch == nil else { return }
        foregroundWatch = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.awaitingRedeem else { return }
                self.awaitingRedeem = false
                for pause in [1, 4, 10, 20] {
                    try? await Task.sleep(for: .seconds(pause))
                    await self.refresh()
                    if self.phase != .claim {
                        Analytics.capture("invite_reward_claimed", ["store": "apple"])
                        return
                    }
                }
            }
        }
    }
}

private extension Decimal {
    /// The value with no fraction, to tell a currency priced in whole units.
    var rounded0: Decimal {
        var value = self, out = Decimal()
        NSDecimalRound(&out, &value, 0, .plain)
        return out
    }
}
