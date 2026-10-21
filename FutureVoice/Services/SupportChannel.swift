import Foundation

/// Where a learner reaches the person building this, in one tap.
///
/// **A DM first, email beside it.** A mail draft is a form: a subject line, a
/// signature, an empty body that asks to be composed — a DM is a sentence, and
/// the whole point of a one-person app is that the person is reachable. But
/// not everyone has Instagram, and some things (a receipt, a screenshot of a
/// charge) are easier to send as a mail, so email sits under the DM
/// (2026-10-21, founder) at the same address the Privacy page names.
///
/// **Instagram is the primary, and Threads deliberately is not.** Threads has
/// no direct messages at all — a reply there is a public post, which is a
/// different thing with a different audience, and the one time someone most
/// wants to write is when something went wrong in private. Threads accounts
/// are Instagram accounts, so the same person is behind `ig.me`; the DM simply
/// lands in the inbox that exists. `https://ig.me/m/<handle>` opens the app
/// straight into a thread with that account, and falls back to the web when
/// Instagram isn't installed.
///
/// Telegram is offered beside it for learners who don't use Instagram — the
/// app ships in seven UI languages and Instagram is not universal.
///
/// **A channel with no handle draws no row.** A contact row that opens
/// nothing is worse than no contact row at all, so filling these in is what
/// turns the section on.
enum SupportChannel: String, CaseIterable, Identifiable {
    case instagram
    case email
    case telegram

    var id: String { rawValue }

    /// The account to write to. Handle only — no `@`, no URL.
    var handle: String {
        switch self {
        case .instagram: return "nawana.app"
        case .email:     return ConsentStore.contactEmail
        case .telegram:  return ""      // e.g. "nawanaapp"
        }
    }

    /// Channels that are actually set up, in the order they should be shown.
    static var available: [SupportChannel] {
        allCases.filter { !$0.handle.isEmpty }
    }

    var url: URL? {
        guard !handle.isEmpty else { return nil }
        switch self {
        // `ig.me/m/` is Instagram's own "message this account" link: it opens
        // the app on a DM thread, and the web on a desktop.
        case .instagram: return URL(string: "https://ig.me/m/\(handle)")
        case .email:     return URL(string: "mailto:\(handle)")
        case .telegram:  return URL(string: "https://t.me/\(handle)")
        }
    }

    var title: String {
        switch self {
        case .instagram: return explain("Instagram DM")
        case .email:     return explain("Email")
        case .telegram:  return explain("Telegram")
        }
    }

    /// SF Symbols has no brand glyphs (and shipping the real logos means
    /// carrying someone else's trademark rules), so both rows wear the plain
    /// message symbol and the handle underneath says which app it is.
    var icon: String {
        switch self {
        case .instagram: return "bubble.left.and.bubble.right"
        case .email:     return "envelope"
        case .telegram:  return "paperplane"
        }
    }

    var subtitle: String { self == .email ? handle : "@\(handle)" }
}
