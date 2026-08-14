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
///   These are ALWAYS written in the language the learner picked as their own,
///   whatever their level. Resolved per call through `Bundle.explanations`.
///
/// Nothing here names a specific language. Adding German is a `de` column in
/// `Localizable.xcstrings` — no code change, here or anywhere else.
enum UILanguage {

    /// The language chrome is written in — always the language being learned.
    static var chromeLanguage: String {
        UserDefaults.standard.string(forKey: LanguageCatalog.targetLanguageDefaultsKey) ?? "en"
    }

    /// The language explanatory copy is written in: the one the learner chose,
    /// full stop.
    ///
    /// This used to flip to the target language above B1, on the theory that an
    /// advanced learner reads target-language prose for free. Proficiency in
    /// SPEAKING says nothing about wanting to decode a destructive-action
    /// confirmation, and the flip silently overrode a setting the learner had
    /// made by hand — a level they moved for calibration reasons quietly
    /// changed what language the app talked to them in. An explicit choice
    /// outranks an inference about it.
    static var explanationLanguage: String {
        LanguageCatalog.currentNative
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

/// Marks a string as CHROME that can't be written as `Text("literal")` —
/// it has to flow through a `String` first (a computed navigation title, a
/// `switch` that returns a label, an interpolated headline).
///
/// A plain `String(localized:)` looks WRONG here even though it compiles: it
/// resolves against the main bundle and the system locale, so it ignores the
/// root's `.environment(\.locale, targetLanguage)` entirely and hands back the
/// source language forever. `Text("literal")` follows the environment; a
/// `String` never sees it. This routes through the chrome bundle instead, so
/// both spellings of chrome land in the same language.
func chrome(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .chrome)
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

    /// The bundle whose `.lproj` holds chrome for this learner — the target
    /// language. Same `.main` fallback as `explanations`: the source language
    /// has no `.lproj`, so a learner practicing English resolves nothing for
    /// `en` and correctly degrades to the catalog keys themselves.
    static var chrome: Bundle {
        lproj(UILanguage.chromeLanguage) ?? .main
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
