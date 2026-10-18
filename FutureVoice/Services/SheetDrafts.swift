import Foundation

/// What a learner typed into a sheet they closed without finishing — so a
/// swipe-down (or a tap outside, on Android) doesn't throw the words away.
/// Reported by an Android tester and true of both apps: every input sheet
/// held its text in view state, and dismissing it was deleting it.
///
/// In memory only, on purpose: it keeps a draft across closing and reopening
/// the sheet, which is the complaint, without leaving half-written text on
/// disk for weeks. A draft is cleared the moment its sheet finishes (sent,
/// saved, started).
@MainActor
enum SheetDrafts {
    private static var texts: [String: String] = [:]

    static func text(_ key: String) -> String? { texts[key] }

    /// Blank text clears the draft — an emptied field is not a draft.
    static func set(_ key: String, _ value: String) {
        texts[key] = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    static func clear(_ keys: String...) {
        keys.forEach { texts[$0] = nil }
    }
}
