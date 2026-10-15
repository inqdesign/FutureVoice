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
    /// Prompt-only: the LEARNER's side of the situation, for the "try
    /// saying" coach, which otherwise sees only the title and the role.
    var learnerSide: String? = nil

    /// The starter a scenario was minted from, if any — from every chip's
    /// set, since a purpose chip (`DiscoverChip`) mints the same way.
    static func of(_ scenario: Scenario?) -> StarterSituation? {
        guard let id = scenario?.starterId else { return nil }
        return catalog.first { $0.id == id }
    }

    /// Every starter on any chip, each once.
    static var catalog: [StarterSituation] {
        var seen = Set<String>()
        return (all + interview + work + life + travel).filter { seen.insert($0.id).inserted }
    }

    /// The example first line, when the learner opens this one.
    func learnerFirstLine(language: String) -> String? {
        learnerFirst.map { $0[LanguageCatalog.base(language)] ?? $0["en"] ?? "" }
    }

    /// Meeting someone new is the one starter that is NOT open (founder,
    /// 2026-10-05): with only `openNote` the stranger "followed whatever the
    /// learner brought up", nobody brought anything up, and the call drifted
    /// into what TV shows they'd been watching — a chat between friends. What
    /// actually happens when a learner meets a native is getting to know each
    /// other: name, where from, work or study, why this language. And the
    /// stranger has to ASK for it — the persona block above it otherwise
    /// reads as "you already know this, never quiz them".
    private static let meetingNote = """
        You're a native speaker meeting the learner for the first time — at a \
        get-together, a class, through a friend. They're from another country \
        and learning your language, and you're curious about them. Whatever \
        this prompt says about the user, YOU know none of it yet: you find out \
        by asking. Spend the call getting to know each other the way two people \
        really do at a first meeting: their name, where they're from, whether \
        they work or study and what, how long they've been here and what \
        brought them, why they're learning the language. One thing at a time, \
        follow up on what they answer, and give your own answer too (your name, \
        your work, where you're from) so it's an exchange, not an interview. \
        Stay on getting to know each other — no TV, films, news or other small \
        talk unless they bring it up. One short line at a time, no speech. \
        You are two adults who have never met, so address them in the POLITE \
        form the whole call (German Sie, French vous, Spanish usted, Korean \
        존댓말, Japanese です・ます) and never switch to the informal one on \
        your own; only if the learner offers it.
        """

    private static let openNote = "Keep it open and easygoing: one short line the way this person really talks at work (no \"welcome\" speech, no script), then follow whatever the learner brings up. Never push a task, a checklist or specifics they haven't raised."

    static var all: [StarterSituation] {
        [
            StarterSituation(
                id: "introduce-yourself", icon: "hand.wave.fill",
                title: explain("Meeting someone new"),
                role: explain("someone you just met"), showsRole: false,
                notes: meetingNote,
                openers: [
                    "en": ["Hi! I don't think we've met yet.", "Hello! Nice to meet you."],
                    "ko": ["안녕하세요! 처음 뵙는 것 같네요.", "안녕하세요, 반가워요!"],
                    "ja": ["こんにちは！初めてですよね？", "はじめまして！よろしくお願いします。"],
                    "de": ["Hallo! Ich glaube, wir kennen uns noch nicht.", "Hallo, freut mich, Sie kennenzulernen!"],
                    "es": ["¡Hola! Creo que todavía no nos conocemos.", "¡Hola! Mucho gusto."],
                ],
                learnerSide: "The learner is from another country and is learning this language; they have just met a native speaker for the first time. What they're asked is about themselves — their name, where they're from, whether they work or study and what, how long they've been here, why they're learning the language — and a natural answer gives that fact (as a bracketed example). Asking the same thing back is something a speaker does now and then, not on every answer. They have just met, so the learner speaks in the polite form (German Sie, French vous, Spanish usted, Korean 해요체 -요 endings, Japanese です・ます) whatever form the line uses. That is the ending only: honorifics that raise a person (Korean -(으)시-, Japanese 尊敬語) are for the OTHER person and never go on the learner's own actions — Korean 살았어요, not 사셨어요, even when the question asked 사셨어요."),
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
                    "es": ["¡Hola! ¿Qué le sirvo?", "¡Hola! ¿Qué va a tomar?"],
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
                    "es": ["¡Hola! ¿Le traigo algo de tomar para empezar?", "¡Hola! ¿Ya saben qué van a pedir, o necesitan un momento?"],
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
                    "es": "Disculpe, ¿cómo llego a la [estación]?",
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
                    "es": ["¡Hola! ¿Busca algo en especial?", "¡Hola! ¿Le puedo ayudar en algo?"],
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
                    "es": ["Consultorio, buenos días. ¿En qué le puedo ayudar?", "Hola, consultorio médico. Dígame."],
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
                    "es": ["¡Hola! ¿Viene a registrarse?", "¡Buenas tardes! ¿En qué le puedo ayudar?"],
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
                    "es": ["¡Hola! ¿A dónde va?", "Hola, ¿en qué le puedo ayudar?"],
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
                    "es": ["¡Hola! ¿Qué tal todo?", "¡Ey, por fin llegas! ¿Qué hay de nuevo?"],
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
                    "es": ["¡Ay, hola! ¿Cómo está?", "¡Hola! ¡Cuánto tiempo!"],
                ]),
        ]
    }

    // MARK: - Purpose chips (`LearningPurpose`)

    private static let interviewNote = """
        You're interviewing the learner for a job they applied for, in an \
        ordinary first-round interview. Ask the way a real interviewer does — \
        one question at a time, a short follow-up on what they actually said, \
        no lecture and no feedback on their answers. Stay friendly but \
        professional, and use the polite form the whole call (German Sie, \
        French vous, Spanish usted, Korean 존댓말, Japanese です・ます). \
        Never score them or tell them how they did.
        """

    /// The Interview chip: the questions every first interview asks.
    static var interview: [StarterSituation] {
        [
            StarterSituation(
                id: "interview-about-you", icon: "person.crop.square",
                title: explain("Tell me about yourself"),
                role: explain("an interviewer"),
                notes: interviewNote + " Open by asking them to introduce themselves, then follow their answer: their background, what they do now, what they're looking for.",
                openers: [
                    "en": ["Thanks for coming in. So, tell me a little about yourself.", "Nice to meet you. Why don't you start by telling me about yourself?"],
                    "ko": ["와 주셔서 감사합니다. 먼저 간단히 자기소개 부탁드릴게요.", "반갑습니다. 자기소개부터 해 주시겠어요?"],
                ]),
            StarterSituation(
                id: "interview-why-job", icon: "questionmark.bubble",
                title: explain("Why do you want this job?"),
                role: explain("an interviewer"),
                notes: interviewNote + " This part of the interview is about motivation: why this role, why this company, why now, and where they see themselves.",
                openers: [
                    "en": ["So, what made you apply for this position?", "Tell me, why do you want to work here?"],
                    "ko": ["이 자리에 지원하신 이유가 궁금해요.", "왜 저희 회사에서 일하고 싶으세요?"],
                ]),
            StarterSituation(
                id: "interview-strengths", icon: "chart.bar",
                title: explain("Strengths and weaknesses"),
                role: explain("an interviewer"),
                notes: interviewNote + " This part is about their strengths, a weakness and what they do about it, and a concrete example of each.",
                openers: [
                    "en": ["What would you say is your biggest strength?", "Let's talk about you. What are you really good at?"],
                    "ko": ["본인의 가장 큰 강점은 뭐라고 생각하세요?", "스스로 생각하는 장점부터 들어 볼게요."],
                ]),
            StarterSituation(
                id: "interview-experience", icon: "briefcase",
                title: explain("A project you're proud of"),
                role: explain("an interviewer"),
                notes: interviewNote + " This part is about their experience: one project or situation from their work or studies, what they did, what went wrong, what they learned.",
                openers: [
                    "en": ["Can you walk me through a project you're proud of?", "Tell me about a time you solved a difficult problem at work."],
                    "ko": ["자랑스러웠던 프로젝트 하나 소개해 주시겠어요?", "어려운 문제를 해결했던 경험이 있으면 말씀해 주세요."],
                ]),
            StarterSituation(
                id: "interview-salary", icon: "banknote",
                title: explain("Talking about salary"),
                role: explain("a recruiter"),
                notes: interviewNote + " You're the recruiter at the end of the process, talking about salary expectations, start date and benefits. Be realistic and a little firm, the way recruiters are.",
                openers: [
                    "en": ["Before we wrap up, what are your salary expectations?", "Let's talk about the offer. What range did you have in mind?"],
                    "ko": ["마무리하기 전에, 희망 연봉은 어느 정도 생각하세요?", "처우 얘기를 좀 해 볼까요? 생각하신 범위가 있으세요?"],
                ]),
        ]
    }

    /// The Work chip: speaking moments of an ordinary working week.
    static var work: [StarterSituation] {
        [
            StarterSituation(
                id: "work-meeting", icon: "person.3.fill",
                title: explain("Giving your view in a meeting"),
                role: explain("a coworker"), showsRole: false,
                notes: "You're the learner's coworker in a small team meeting, asking what they think about the plan on the table. " + openNote,
                openers: [
                    "en": ["So, what do you think? Does this plan work for your side?", "Before we decide — any thoughts from you?"],
                    "ko": ["어떻게 생각하세요? 이 계획, 그쪽 입장에선 괜찮을까요?", "결정하기 전에, 의견 있으세요?"],
                ]),
            StarterSituation(
                id: "work-update", icon: "chart.line.uptrend.xyaxis",
                title: explain("Your project update"),
                role: explain("your manager"),
                notes: "You're the learner's manager in a weekly one-on-one, asking how their work is going. " + openNote,
                openers: [
                    "en": ["Hey, how's everything going on your side this week?", "So, where are we with your project?"],
                    "ko": ["이번 주 일은 어떻게 돼 가요?", "맡은 프로젝트는 지금 어디까지 왔어요?"],
                ]),
            StarterSituation(
                id: "work-client", icon: "phone.fill",
                title: explain("A call with a client"),
                role: explain("a client"),
                notes: "You're a client calling the learner's company about something you need. Be polite, a bit busy, and expect clear answers. " + openNote,
                openers: [
                    "en": ["Hi, thanks for taking my call. Do you have a minute?", "Hello! I wanted to check in about our order."],
                    "ko": ["안녕하세요, 통화 괜찮으세요?", "안녕하세요! 저희 주문 건 때문에 연락드렸어요."],
                ]),
            StarterSituation(
                id: "work-small-talk", icon: "cup.and.saucer",
                title: explain("Small talk with a coworker"),
                role: explain("a coworker"), showsRole: false,
                notes: "You're the learner's coworker, chatting by the coffee machine. " + openNote,
                openers: [
                    "en": ["Morning! Busy day?", "Hey! How was your weekend?"],
                    "ko": ["좋은 아침이에요! 오늘 바빠요?", "주말 잘 보냈어요?"],
                ]),
        ]
    }

    /// The Life chip: living somewhere, not visiting it.
    static var life: [StarterSituation] {
        [
            StarterSituation(
                id: "life-landlord", icon: "key.fill",
                title: explain("Calling your landlord"),
                role: explain("your landlord"),
                notes: "You're the learner's landlord, answering the phone. Something in the flat probably needs fixing. " + openNote,
                openers: [
                    "en": ["Hello? Oh, hi. What can I do for you?", "Hi there, is everything all right with the flat?"],
                    "ko": ["여보세요? 아, 네. 무슨 일이세요?", "안녕하세요, 집에 무슨 문제 있으세요?"],
                ]),
            StarterSituation(
                id: "life-town-hall", icon: "building.columns.fill",
                title: explain("At the town hall"),
                role: explain("a clerk"),
                notes: "You're a clerk at the town hall's registration desk. You're busy but correct, and you ask for the documents you need. " + openNote,
                openers: [
                    "en": ["Next, please. How can I help you?", "Good morning. What do you need today?"],
                    "ko": ["다음 분이요. 어떤 일로 오셨어요?", "안녕하세요. 무슨 업무 보러 오셨어요?"],
                ]),
            StarterSituation(
                id: "life-teacher", icon: "figure.and.child.holdinghands",
                title: explain("Your child's teacher"),
                role: explain("a teacher"),
                notes: "You're the teacher of the learner's child, at pick-up time or a short parent meeting. " + openNote,
                openers: [
                    "en": ["Oh, hello! Do you have a minute? I wanted to tell you about today.", "Hi! Thanks for coming in."],
                    "ko": ["아, 안녕하세요! 잠깐 시간 괜찮으세요? 오늘 있었던 일 말씀드리려고요.", "안녕하세요! 와 주셔서 감사해요."],
                ]),
        ] + all.filter { ["doctor-appointment", "neighbor-small-talk"].contains($0.id) }
    }

    /// The Travel chip: being a visitor.
    static var travel: [StarterSituation] {
        [
            StarterSituation(
                id: "travel-airport", icon: "airplane",
                title: explain("At the check-in desk"),
                role: explain("an airline agent"),
                notes: "You're an agent at an airline check-in desk. " + openNote,
                openers: [
                    "en": ["Hi! Where are you flying today?", "Good morning. Passport, please."],
                    "ko": ["안녕하세요! 오늘 어디로 가세요?", "안녕하세요. 여권 부탁드릴게요."],
                ]),
            StarterSituation(
                id: "travel-problem", icon: "exclamationmark.bubble",
                title: explain("When something goes wrong"),
                role: explain("a front desk clerk"),
                notes: "You're at a hotel front desk. The learner comes to you because something went wrong — the room, a booking, lost luggage; let them say what. " + openNote,
                openers: [
                    "en": ["Hi, is everything all right?", "Hello! What can I do for you?"],
                    "ko": ["안녕하세요, 무슨 문제 있으세요?", "안녕하세요! 뭘 도와드릴까요?"],
                ]),
        ] + all.filter { ["hotel-checkin", "train-ticket", "ask-directions", "order-restaurant"].contains($0.id) }
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
