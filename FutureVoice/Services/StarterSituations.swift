import Foundation

/// The ready-made situations on Talk's Everyday chip — a place and a person
/// (a café, a clothing store, a neighbor), startable with one tap and no
/// writing. Until these existed the Scenarios list held only situations the
/// learner had built, so a beginner who couldn't think of one had nothing
/// to start.
///
/// **Open on purpose** (founder, 2026-10-04). The first cut carried a task
/// per row ("buy a shirt: size, color, price") and the model opened the
/// clothing store on "What size are you looking for?" — nobody is greeted
/// like that. A row is now only where you are and who you are talking to;
/// the counterpart greets the way that person really would and the learner
/// takes it wherever they like.
///
/// **The greetings are written here, not generated.** A generated pool kept
/// coming back mid-task, and a starter is the same few lines for everyone,
/// so they are hand-written per target language and stored on the minted
/// scenario (`Scenario.openers`) — the call starts instantly and asks Gemini
/// for nothing. They are reused on every talk, so nothing in them is tied
/// to a time of day.
///
/// A starter is not a second kind of scenario. The first tap mints an
/// ordinary `Scenario` stamped with `starterId`; every later tap refreshes
/// that row from this catalog (so an edit here reaches phones that already
/// have it) and keeps its talks, curriculum and Practice book.
struct StarterSituation: Identifiable, Hashable {
    let id: String
    let icon: String
    /// Row title, which is also the scene — "At a clothing store".
    let title: String
    /// Who the counterpart is — `Scenario.role`.
    let role: String
    /// False where the title already names the person ("With a friend").
    var showsRole = true
    /// Prompt-only: what the counterpart is like. Never a task.
    let notes: String
    /// Greeting lines per target-language code (en · ko · ja · de).
    var openers: [String: [String]] = [:]
    /// The LEARNER opens (asking a stranger the way): the counterpart says
    /// nothing until spoken to, and the call shows this line as a way in.
    var learnerFirst: [String: String]? = nil
    /// That line in the APP language, for the coach's meaning row.
    var learnerFirstMeaning: String? = nil

    /// The starter a scenario was minted from, if any.
    static func of(_ scenario: Scenario?) -> StarterSituation? {
        guard let id = scenario?.starterId else { return nil }
        return all.first { $0.id == id }
    }

    /// The example first line, when the learner opens this one.
    func learnerFirstLine(language: String) -> String? {
        learnerFirst.map { $0[LanguageCatalog.base(language)] ?? $0["en"] ?? "" }
    }

    private static let openNote = "Keep it open and easygoing: one short line the way this person really talks at work (no \"welcome\" speech, no script), then follow whatever the learner brings up. Never push a task, a checklist or specifics they haven't raised."

    static var all: [StarterSituation] {
        [
            StarterSituation(
                id: "introduce-yourself", icon: "hand.wave.fill",
                title: explain("Meeting someone new"),
                role: explain("someone you just met"), showsRole: false,
                notes: "You've just met the learner for the first time. " + openNote,
                openers: [
                    "en": ["Hi! I don't think we've met yet.", "Hello! Nice to meet you."],
                    "ko": ["안녕하세요! 처음 뵙는 것 같네요.", "안녕하세요, 반가워요!"],
                    "ja": ["こんにちは！初めてですよね？", "はじめまして！よろしくお願いします。"],
                    "de": ["Hallo! Wir kennen uns noch nicht, oder?", "Hi, freut mich! Wie geht's?"],
                ]),
            StarterSituation(
                id: "order-cafe", icon: "cup.and.saucer.fill",
                title: explain("At a café"),
                role: explain("a barista"),
                notes: "You work behind the counter at a café. " + openNote,
                openers: [
                    "en": ["Hi! What can I get you?", "Hey! What are you having?"],
                    "ko": ["안녕하세요, 뭐 드릴까요?", "안녕하세요! 주문하시겠어요?"],
                    "ja": ["こんにちは、ご注文はお決まりですか？", "こんにちは！何にしますか？"],
                    "de": ["Hallo! Was darf's sein?", "Hallo, was hätten Sie gern?"],
                ]),
            StarterSituation(
                id: "order-restaurant", icon: "fork.knife",
                title: explain("At a restaurant"),
                role: explain("a server"),
                notes: "You're a server at a restaurant. " + openNote,
                openers: [
                    "en": ["Hi! Can I get you something to drink to start?", "Hi! Have you decided, or do you need a minute?"],
                    "ko": ["안녕하세요, 주문하시겠어요?", "안녕하세요! 메뉴 보시고 편하게 불러 주세요."],
                    "ja": ["こんにちは、お飲み物はどうされますか？", "こんにちは！ご注文はお決まりですか？"],
                    "de": ["Hallo! Darf ich Ihnen schon etwas zu trinken bringen?", "Hallo! Haben Sie schon gewählt?"],
                ]),
            StarterSituation(
                id: "ask-directions", icon: "map.fill",
                title: explain("On the street"),
                role: explain("a passerby"),
                notes: "You're a friendly local walking down the street. The learner stops you to ask something — you speak only once they have, and help the way a kind stranger would. " + openNote,
                learnerFirst: [
                    "en": "Excuse me, how do I get to the [station]?",
                    "ko": "저기요, [역]에 어떻게 가요?",
                    "ja": "すみません、[駅]はどう行けばいいですか？",
                    "de": "Entschuldigung, wie komme ich zum [Bahnhof]?",
                ],
                learnerFirstMeaning: explain("Excuse me, how do I get to the [station]?")),
            StarterSituation(
                id: "shopping", icon: "bag.fill",
                title: explain("At a clothing store"),
                role: explain("a shop assistant"),
                notes: "You work at a clothing store. " + openNote,
                openers: [
                    "en": ["Hi! Looking for anything in particular?", "Hi! Is there anything I can help you find?"],
                    "ko": ["안녕하세요, 찾으시는 거 있으세요?", "안녕하세요! 편하게 보시고 필요하면 불러 주세요."],
                    "ja": ["こんにちは、何かお探しですか？", "こんにちは！気になるものがあったら声をかけてくださいね。"],
                    "de": ["Hallo! Suchen Sie etwas Bestimmtes?", "Hallo! Kann ich Ihnen helfen?"],
                ]),
            StarterSituation(
                id: "doctor-appointment", icon: "cross.case.fill",
                title: explain("Calling a clinic"),
                role: explain("a clinic receptionist"),
                notes: "You answer the phone at a doctor's clinic; the learner is calling. " + openNote,
                openers: [
                    "en": ["Hello, this is the clinic. How can I help?", "Hi, clinic speaking. What can I do for you?"],
                    "ko": ["네, 병원입니다. 무엇을 도와드릴까요?", "여보세요, 병원입니다. 말씀하세요."],
                    "ja": ["はい、クリニックです。どうされましたか？", "お電話ありがとうございます。クリニックです。"],
                    "de": ["Arztpraxis, guten Tag! Was kann ich für Sie tun?", "Praxis, hallo! Wie kann ich helfen?"],
                ]),
            StarterSituation(
                id: "hotel-checkin", icon: "bed.double.fill",
                title: explain("At a hotel"),
                role: explain("a front desk clerk"),
                notes: "You work at a hotel front desk. " + openNote,
                openers: [
                    "en": ["Hi! Checking in?", "Hello! How can I help you?"],
                    "ko": ["안녕하세요, 체크인하시나요?", "안녕하세요! 무엇을 도와드릴까요?"],
                    "ja": ["こんにちは、チェックインですか？", "こんにちは！どうされましたか？"],
                    "de": ["Hallo! Möchten Sie einchecken?", "Guten Tag! Wie kann ich Ihnen helfen?"],
                ]),
            StarterSituation(
                id: "train-ticket", icon: "tram.fill",
                title: explain("At the train station"),
                role: explain("a ticket agent"),
                notes: "You work at the ticket counter of a train station. " + openNote,
                openers: [
                    "en": ["Hi! Where are you headed?", "Hi, what can I do for you?"],
                    "ko": ["안녕하세요, 어디 가세요?", "안녕하세요! 어떻게 도와드릴까요?"],
                    "ja": ["こんにちは、どちらまでですか？", "こんにちは！どうされましたか？"],
                    "de": ["Hallo! Wohin soll's gehen?", "Hallo, was kann ich für Sie tun?"],
                ]),
            StarterSituation(
                id: "make-plans", icon: "person.2.fill",
                title: explain("With a friend"),
                role: explain("a friend"), showsRole: false,
                notes: "You're the learner's friend, catching up casually. Speak like a friend. " + openNote,
                openers: [
                    "en": ["Hey! How's it going?", "Hey, there you are! What's new?"],
                    "ko": ["오, 안녕! 요즘 어때?", "야, 왔어? 잘 지냈어?"],
                    "ja": ["おー、元気？", "あ、来た来た！最近どう？"],
                    "de": ["Hey! Na, wie geht's?", "Hey, da bist du ja! Was gibt's Neues?"],
                ]),
            StarterSituation(
                id: "neighbor-small-talk", icon: "house.fill",
                title: explain("With a neighbor"),
                role: explain("a neighbor"), showsRole: false,
                notes: "You're the learner's friendly neighbor, bumping into them near home. " + openNote,
                openers: [
                    "en": ["Oh, hi! How are you doing?", "Hey, hello! Haven't seen you in a while."],
                    "ko": ["어, 안녕하세요! 잘 지내셨어요?", "안녕하세요! 오랜만이에요."],
                    "ja": ["あ、こんにちは！お元気ですか？", "どうも、こんにちは！お久しぶりです。"],
                    "de": ["Oh, hallo! Wie geht's Ihnen?", "Hallo! Lange nicht gesehen."],
                ]),
        ]
    }

    /// The scenario to launch: the one this starter already minted, brought
    /// up to date with this catalog, else a fresh unsaved one. The launcher
    /// saves it once the tap passes the billing gate, so a paywalled tap
    /// leaves nothing behind.
    func scenario(in scenarios: [Scenario], language: String) -> Scenario {
        var s = scenarios.first { $0.starterId == id }
            ?? Scenario(environment: title, role: role, notes: notes)
        s.environment = title
        s.role = role
        s.notes = notes
        s.summary = title
        s.category = title
        s.categoryIcon = icon
        s.starterId = id
        // A language without written lines falls back to the generated pool
        // (nil openers → `generateOpener`).
        let pool = learnerFirst == nil ? openers[LanguageCatalog.base(language)] : nil
        if s.openers != pool {
            s.openers = pool
            s.openerCursor = 0
        }
        return s
    }
}
