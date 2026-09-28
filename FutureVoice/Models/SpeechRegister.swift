import Foundation

/// How one side of a relationship speaks to the other — an abstract rung
/// that each target language renders its own way (반말 / du / tu, 해요체 /
/// Sie / vous). Abstract because a person is shared by every language the
/// learner practises: "we talk casually" is true of the friendship, and
/// Korean and German only differ in what that sounds like.
///
/// English has no grammatical form of address, so there the rung is TONE —
/// still worth setting, because "the way close friends talk" is exactly what
/// a call with a friend was missing.
enum SpeechRegister: String, Codable, CaseIterable, Identifiable {
    case casual, polite, formal

    var id: String { rawValue }

    /// The rung's name on screen, in the app language.
    var title: String {
        switch self {
        case .casual: return explain("Casual")
        case .polite: return explain("Polite")
        case .formal: return explain("Formal")
        }
    }

    /// What the rung is CALLED in the target language, where the language
    /// has a name for it (반말, du, tu). nil where the language has no
    /// grammatical form of address — the rung is tone only there.
    func term(in language: String) -> String? {
        switch LanguageCatalog.base(language) {
        case "ko": return ["반말", "해요체", "합니다체"][index]
        case "ja": return ["タメ口", "です・ます", "敬語"][index]
        case "de": return ["du", "Sie", "Sie"][index]
        case "fr": return ["tu", "vous", "vous"][index]
        case "es": return ["tú", "usted", "usted"][index]
        case "it": return ["tu", "Lei", "Lei"][index]
        default: return nil
        }
    }

    /// True where the target language marks the form of address in grammar,
    /// so a line can be said in the WRONG one — the only case a correction
    /// may touch it.
    static func hasForms(_ language: String) -> Bool {
        SpeechRegister.casual.term(in: language) != nil
    }

    /// The rung as a prompt line names it: the form, the endings that mark it,
    /// and the tone that goes with it.
    func promptDescription(in language: String) -> String {
        switch LanguageCatalog.base(language) {
        case "ko":
            return [
                "반말 (the informal speech level: -어/-아, -야 endings, never -요) and the loose, easy tone that goes with it",
                "해요체 (the polite speech level: -요 endings)",
                "합니다체 (the formal speech level: -습니다 / -ㅂ니까 endings)",
            ][index]
        case "ja":
            return [
                "plain form, タメ口 (never です/ます) and the loose, easy tone that goes with it",
                "です・ます form",
                "keigo — 尊敬語 for the other person, 謙譲語 for yourself",
            ][index]
        case "de", "fr", "es", "it":
            let form = term(in: language) ?? ""
            return [
                "\(form) (informal address) and the loose, easy tone that goes with it",
                "\(form) (formal address), friendly",
                "\(form) (formal address) in a formal, professional register",
            ][index]
        default:
            return [
                "casual — the way close friends talk: contractions, slang, teasing welcome",
                "friendly but polite — the way you'd talk to a colleague or an acquaintance",
                "formal and professional",
            ][index]
        }
    }

    private var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

extension Counterpart {

    /// Which of the app's three kinds of person this is — each gets its own
    /// character block in a call, because they stand in three different
    /// relations to the learner.
    enum Cast {
        /// Someone from the learner's own life, made by them. They KNOW each
        /// other; the learner's note is the shared history.
        case ownPerson
        /// A persona from the Find-people pool. A new acquaintance.
        case stranger
        /// A singer, an actor, an athlete. The learner knows them; they
        /// don't know the learner.
        case publicFigure
    }

    var cast: Cast {
        if isPublicFigure == true { return .publicFigure }
        return remoteId == nil ? .ownPerson : .stranger
    }

    /// The intake's relationship chips whose default is "we talk casually
    /// and know each other's lives". Raw values of the intake's
    /// `RelationshipKind`.
    static let closeKinds: Set<String> = ["Friend", "Partner", "Family"]

    /// What the "How do you two talk?" card starts on for a relationship.
    /// A starting point to confirm, never a rule: a family can be formal and
    /// a manager can be on first-name terms, which is why the card exists.
    static func defaultRegisters(forKind kind: String?) -> (mine: SpeechRegister, theirs: SpeechRegister) {
        guard let kind, closeKinds.contains(kind) else { return (.polite, .polite) }
        return (.casual, .casual)
    }

    /// How the learner speaks to them, as the prompts use it. A stranger or a
    /// public figure left unset is polite — that is what meeting someone is.
    /// An own person left unset returns nil: the relationship decides, which
    /// is what every person made before this field did.
    var effectiveMyRegister: SpeechRegister? {
        myRegister ?? (cast == .ownPerson ? nil : .polite)
    }

    /// How they speak to the learner — same fallbacks as `effectiveMyRegister`.
    var effectiveTheirRegister: SpeechRegister? {
        theirRegister ?? (cast == .ownPerson ? nil : .polite)
    }

    /// The default for `knowsMyLife`: close relationships know the learner's
    /// life; everyone else hears what a stranger may.
    static func knowsMyLifeByDefault(kind: String?) -> Bool {
        kind.map(closeKinds.contains) ?? false
    }

    /// Whether a call with this person is handed the learner's whole
    /// notebook. Only ever for someone from their own life: a stranger or a
    /// public figure never gets past what the learner lets strangers hear.
    var knowsLearnersLife: Bool {
        guard cast == .ownPerson else { return false }
        return knowsMyLife ?? Self.knowsMyLifeByDefault(kind: relationshipKind)
    }

    /// Close in the way that changes how a call SOUNDS: a close relationship,
    /// or two people who talk casually to each other whatever the label.
    var isClose: Bool {
        if let k = relationshipKind, Self.closeKinds.contains(k) { return true }
        return myRegister == .casual && theirRegister == .casual
    }
}
