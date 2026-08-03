import Foundation
import os

/// Which language each kind of on-screen text is written in.
///
/// Two axes, deliberately different:
///
/// - **Chrome** — tabs, labels, buttons, section headers — speaks the TARGET
///   language. It's one-word A1 vocabulary the learner meets dozens of times a
///   day with an icon beside it: free exposure, no comprehension cost. Wired
///   once at the root as `.environment(\.locale, targetLanguage)`, so every
///   SwiftUI `Text("literal")` follows with no per-call code.
/// - **Explanations** — anything the learner has to actually parse to act on:
///   why a score moved, what a credit is, what happens if they delete this.
///   These are written in the learner's OWN language while their level is low,
///   and switch to the target language once they can read them without effort.
///   Resolved per call through `Bundle.explanations`.
///
/// Nothing here names a specific language. Adding German is a `de` column in
/// `Localizable.xcstrings` — no code change, here or anywhere else.
enum UILanguage {

    /// The highest level that still gets explanations in their own language.
    /// At B2 the learner reads target-language prose without it costing them
    /// anything, and the exposure is worth more than the shortcut. A learner
    /// who disagrees can move their level in Me.
    static let nativeExplanationsThrough: CEFRLevel = .b1

    /// Mirrors AppState's key so non-UI code can resolve the explanation
    /// language without reaching into AppState.
    static let proficiencyDefaultsKey = "futurevoice.proficiency"

    /// The language chrome is written in — always the language being learned.
    static var chromeLanguage: String {
        UserDefaults.standard.string(forKey: LanguageCatalog.targetLanguageDefaultsKey) ?? "en"
    }

    /// The language explanatory copy is written in: the learner's own language
    /// until they outgrow needing it, the target language after.
    static var explanationLanguage: String {
        let level = UserDefaults.standard.string(forKey: proficiencyDefaultsKey)
            .flatMap(CEFRLevel.init(rawValue:)) ?? .b1
        return needsNativeExplanations(at: level) ? LanguageCatalog.currentNative : chromeLanguage
    }

    /// Ordering comes from `CEFRLevel: CaseIterable`, declared a1…c2.
    static func needsNativeExplanations(at level: CEFRLevel) -> Bool {
        let order = CEFRLevel.allCases
        guard let here = order.firstIndex(of: level),
              let cutoff = order.firstIndex(of: nativeExplanationsThrough) else { return true }
        return here <= cutoff
    }
}

/// Marks a string as EXPLANATORY — copy the learner has to parse to act on,
/// not a label they recognize by shape. Resolves through `Bundle.explanations`
/// (their own language while their level is low), unlike a plain
/// `Text("literal")`, which follows the chrome locale.
///
/// Use it for: why a number moved, what a control will do, what a term means,
/// what happens if they confirm, empty states that instruct, error recovery.
/// Do NOT use it for labels, buttons, titles, or chips — those are chrome.
func explain(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .explanations)
}

extension Bundle {

    /// The bundle whose `.lproj` holds explanatory copy for this learner.
    ///
    /// Falls back to `.main` — the source language — and NEVER to the chrome
    /// language. The source language has no `.lproj` of its own (its strings
    /// are the catalog keys), so an English speaker learning Korean resolves
    /// nothing for `en`; routing that miss to the chrome bundle handed them
    /// KOREAN explanations, the exact failure this whole split exists to
    /// prevent. A miss must degrade to the language the app is written in,
    /// like every other unlocalized string does.
    static var explanations: Bundle {
        lproj(UILanguage.explanationLanguage) ?? .main
    }

    /// Cached `.lproj` lookup. `Bundle(path:)` hits the filesystem and
    /// explanation strings resolve inside `body` — one probe per language per
    /// launch is the budget.
    private static func lproj(_ code: String) -> Bundle? {
        if let cached = lprojCache.withLock({ $0[code] }) { return cached }
        let resolved = Bundle.main.path(forResource: code, ofType: "lproj")
            .flatMap(Bundle.init(path:))
        lprojCache.withLock { $0[code] = resolved }
        return resolved
    }

    /// `[code: bundle?]` — the outer optional says "probed", the inner says
    /// "found", so a missing language is cached as a miss instead of re-probed.
    private static let lprojCache = OSAllocatedUnfairLock(initialState: [String: Bundle?]())
}
