import Foundation

extension AccountStatus {
    /// Writing new speech scripts is a Plus-and-up feature; the bundled
    /// script is everyone's. Read off the TIER on purpose — this is about
    /// which plan was bought, not about a pool — so Max is included and a
    /// Light or free account is not. The admin flag passes like everywhere.
    var canWriteSpeechScripts: Bool {
        unlimited || (isEntitled && ["plus", "max"].contains(tier ?? ""))
    }
}

extension BillingGate {
    /// Same cache rule as `blocks()`: a yes from cache, a no only from a
    /// fresh fetch (a purchase a minute ago must not be refused again).
    func allowsSpeechScripts() async -> Bool {
        if let cached = account, cached.canWriteSpeechScripts { return true }
        return await snapshot(force: account != nil)?.canWriteSpeechScripts ?? false
    }
}

extension SpeechGenre {
    var title: String {
        switch self {
        case .explainer:  return explain(key: "speech.genre.explain", default: "Explainer")
        case .product:  return explain(key: "speech.genre.product", default: "Product")
        case .person:   return explain(key: "speech.genre.person", default: "Person")
        case .briefing: return explain(key: "speech.genre.briefing", default: "Briefing")
        case .news:     return explain(key: "speech.genre.news", default: "News")
        case .own:      return explain(key: "speech.genre.own", default: "My script")
        }
    }

    var blurb: String {
        switch self {
        case .explainer:  return explain("How or why something works")
        case .product:  return explain("Present a real product or invention")
        case .person:   return explain("Introduce someone worth knowing")
        case .briefing: return explain("Useful information, clearly told")
        case .news:     return explain("Read the news like an anchor")
        case .own:      return explain("Your own text")
        }
    }

    var symbol: String {
        switch self {
        case .explainer:  return "lightbulb"
        case .product:  return "shippingbox"
        case .person:   return "person.crop.square"
        case .briefing: return "info.circle"
        case .news:     return "newspaper"
        case .own:      return "pencil.line"
        }
    }

    var topicPlaceholder: String {
        switch self {
        case .explainer:  return explain("e.g. Why the sky is blue")
        case .product:  return explain("e.g. The first iPhone")
        case .person:   return explain("e.g. Marie Curie")
        case .briefing: return explain("e.g. How to sleep better on a long flight")
        case .news:     return explain("e.g. Space news this month")
        case .own:      return ""
        }
    }
}

enum SpeechFormat {
    static func length(_ seconds: Int) -> String {
        seconds < 60 ? explain("\(seconds) sec") : explain("\(seconds / 60) min")
    }

    static func rate(_ value: Int, language: String) -> String {
        switch SpeechLibrary.rateUnit(language) {
        case .words:      return explain("\(value) words/min")
        case .syllables:  return explain("\(value) syllables/min")
        case .characters: return explain("\(value) characters/min")
        }
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
