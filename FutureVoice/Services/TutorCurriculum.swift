import Foundation

/// The tutor's curriculum (2026-10-28, founder: "the tutor has its own
/// curriculum — chapters, and topics inside them; finish one and it's
/// checked off"). See docs/tutor-curriculum-plan.md.
///
/// Two tiers: a CHAPTER is an area of life, a TOPIC is one thing to be able
/// to say, small enough for one lesson. A topic is DONE when its lesson's
/// final check is passed (`TutorLesson.FinalCheck`), never by finishing the
/// challenges alone. Written once by us, the same map for everyone; the
/// planner fits each topic to the learner's level, so `level` only decides
/// which topics are lit and which read "a step up" (soft unlocking: a step
/// up is still a tap away).
enum TutorCurriculum {
    struct Chapter: Identifiable {
        let id: String
        let icon: String
        /// For the planner and telemetry.
        let english: String
        /// In the app language.
        let title: String
        let topics: [Topic]
    }

    struct Topic: Identifiable {
        let id: String
        /// The lowest band it suits.
        let level: CEFRLevel
        let english: String
        let title: String
    }

    /// Built on every read: the titles follow the app language, which can
    /// change while the app runs.
    static var chapters: [Chapter] {
        [
        Chapter(id: "meet", icon: "person.2.fill", english: "Meeting people", title: explain("Meeting people"), topics: [
            Topic(id: "meet.intro", level: .a1, english: "Introducing yourself", title: explain("Introducing yourself")),
            Topic(id: "meet.from", level: .a2, english: "Where you're from and why you're here", title: explain("Where you're from and why you're here")),
            Topic(id: "meet.work", level: .a1, english: "What you do", title: explain("What you do")),
            Topic(id: "meet.family", level: .a1, english: "Your family", title: explain("Your family")),
            Topic(id: "meet.hobbies", level: .a1, english: "Hobbies", title: explain("Hobbies")),
            Topic(id: "meet.ask", level: .a2, english: "Asking someone about themselves", title: explain("Asking someone about themselves")),
            Topic(id: "meet.keepgoing", level: .b1, english: "Keeping a first conversation going", title: explain("Keeping a first conversation going")),
            Topic(id: "meet.plans", level: .a2, english: "Making plans to meet again", title: explain("Making plans to meet again")),
            Topic(id: "meet.names", level: .a2, english: "Remembering and using names", title: explain("Remembering and using names")),
            Topic(id: "meet.goodbye", level: .a2, english: "Saying goodbye naturally", title: explain("Saying goodbye naturally")),
        ]),
        Chapter(id: "cafe", icon: "cup.and.saucer.fill", english: "Café & food", title: explain("Café & food"), topics: [
            Topic(id: "cafe.order", level: .a1, english: "Ordering at a café", title: explain("Ordering at a café")),
            Topic(id: "cafe.restaurant", level: .a1, english: "Ordering at a restaurant", title: explain("Ordering at a restaurant")),
            Topic(id: "cafe.whatsgood", level: .a2, english: "Asking what's good", title: explain("Asking what's good")),
            Topic(id: "cafe.allergy", level: .a2, english: "Allergies and special requests", title: explain("Allergies and special requests")),
            Topic(id: "cafe.wrong", level: .b1, english: "Your order came out wrong", title: explain("Your order came out wrong")),
            Topic(id: "cafe.soldout", level: .a2, english: "Something is sold out", title: explain("Something is sold out")),
            Topic(id: "cafe.bill", level: .a2, english: "Paying and splitting the bill", title: explain("Paying and splitting the bill")),
            Topic(id: "cafe.booking", level: .a2, english: "Booking a table", title: explain("Booking a table")),
            Topic(id: "cafe.likes", level: .a1, english: "Talking about food you like", title: explain("Talking about food you like")),
            Topic(id: "cafe.compliment", level: .a2, english: "Complimenting the food", title: explain("Complimenting the food")),
        ]),
        Chapter(id: "shop", icon: "bag.fill", english: "Shopping", title: explain("Shopping"), topics: [
            Topic(id: "shop.size", level: .a1, english: "Asking for a size or color", title: explain("Asking for a size or color")),
            Topic(id: "shop.tryon", level: .a1, english: "Trying things on", title: explain("Trying things on")),
            Topic(id: "shop.price", level: .a1, english: "Asking the price and paying", title: explain("Asking the price and paying")),
            Topic(id: "shop.return", level: .b1, english: "Returning something", title: explain("Returning something")),
            Topic(id: "shop.discount", level: .b1, english: "Asking for a discount", title: explain("Asking for a discount")),
            Topic(id: "shop.supermarket", level: .a1, english: "At the supermarket", title: explain("At the supermarket")),
            Topic(id: "shop.gift", level: .a2, english: "Buying a gift", title: explain("Buying a gift")),
            Topic(id: "shop.phoneplan", level: .b1, english: "Buying a phone plan", title: explain("Buying a phone plan")),
            Topic(id: "shop.online", level: .b1, english: "An online order went wrong", title: explain("An online order went wrong")),
            Topic(id: "shop.compare", level: .b1, english: "Comparing two options", title: explain("Comparing two options")),
        ]),
        Chapter(id: "travel", icon: "tram.fill", english: "Getting around", title: explain("Getting around"), topics: [
            Topic(id: "travel.way", level: .a1, english: "Asking the way", title: explain("Asking the way")),
            Topic(id: "travel.ticket", level: .a1, english: "Buying a ticket", title: explain("Buying a ticket")),
            Topic(id: "travel.taxi", level: .a1, english: "Taking a taxi", title: explain("Taking a taxi")),
            Topic(id: "travel.delay", level: .b1, english: "A delayed or cancelled train", title: explain("A delayed or cancelled train")),
            Topic(id: "travel.checkin", level: .a2, english: "At the airport check-in", title: explain("At the airport check-in")),
            Topic(id: "travel.luggage", level: .b1, english: "Lost luggage", title: explain("Lost luggage")),
            Topic(id: "travel.car", level: .b1, english: "Renting a car", title: explain("Renting a car")),
            Topic(id: "travel.hotel", level: .a2, english: "Checking in at a hotel", title: explain("Checking in at a hotel")),
            Topic(id: "travel.room", level: .b1, english: "A problem with the room", title: explain("A problem with the room")),
            Topic(id: "travel.directions", level: .a2, english: "Giving directions to someone", title: explain("Giving directions to someone")),
        ]),
        Chapter(id: "home", icon: "house.fill", english: "Home & neighbors", title: explain("Home & neighbors"), topics: [
            Topic(id: "home.landlord", level: .a2, english: "Calling the landlord", title: explain("Calling the landlord")),
            Topic(id: "home.broken", level: .a2, english: "Something is broken", title: explain("Something is broken")),
            Topic(id: "home.neighbor", level: .a2, english: "Talking to a neighbor", title: explain("Talking to a neighbor")),
            Topic(id: "home.noise", level: .b1, english: "A noise complaint", title: explain("A noise complaint")),
            Topic(id: "home.movein", level: .a2, english: "Moving in", title: explain("Moving in")),
            Topic(id: "home.internet", level: .b1, english: "Setting up internet", title: explain("Setting up internet")),
            Topic(id: "home.delivery", level: .b1, english: "A delivery that didn't arrive", title: explain("A delivery that didn't arrive")),
            Topic(id: "home.townhall", level: .b1, english: "At the town hall", title: explain("At the town hall")),
            Topic(id: "home.bank", level: .b1, english: "Opening a bank account", title: explain("Opening a bank account")),
            Topic(id: "home.rules", level: .a2, english: "Recycling and house rules", title: explain("Recycling and house rules")),
        ]),
        Chapter(id: "health", icon: "cross.case.fill", english: "Health", title: explain("Health"), topics: [
            Topic(id: "health.appointment", level: .a2, english: "Booking a doctor's appointment", title: explain("Booking a doctor's appointment")),
            Topic(id: "health.symptoms", level: .a2, english: "Describing symptoms", title: explain("Describing symptoms")),
            Topic(id: "health.pharmacist", level: .a2, english: "Asking the pharmacist", title: explain("Asking the pharmacist")),
            Topic(id: "health.allergy", level: .a2, english: "Explaining an allergy", title: explain("Explaining an allergy")),
            Topic(id: "health.emergency", level: .b1, english: "An emergency call", title: explain("An emergency call")),
            Topic(id: "health.dentist", level: .a2, english: "At the dentist", title: explain("At the dentist")),
            Topic(id: "health.feel", level: .a1, english: "Talking about how you feel", title: explain("Talking about how you feel")),
            Topic(id: "health.sick", level: .a2, english: "Calling in sick", title: explain("Calling in sick")),
            Topic(id: "health.checkup", level: .b1, english: "A check-up", title: explain("A check-up")),
            Topic(id: "health.help", level: .b1, english: "Helping someone who is unwell", title: explain("Helping someone who is unwell")),
        ]),
        Chapter(id: "work", icon: "briefcase.fill", english: "Work", title: explain("Work"), topics: [
            Topic(id: "work.smalltalk", level: .a2, english: "Small talk with a coworker", title: explain("Small talk with a coworker")),
            Topic(id: "work.update", level: .b1, english: "Your project update", title: explain("Your project update")),
            Topic(id: "work.meeting", level: .b1, english: "Giving your view in a meeting", title: explain("Giving your view in a meeting")),
            Topic(id: "work.help", level: .a2, english: "Asking for help", title: explain("Asking for help")),
            Topic(id: "work.disagree", level: .b2, english: "Disagreeing politely", title: explain("Disagreeing politely")),
            Topic(id: "work.client", level: .b1, english: "A call with a client", title: explain("A call with a client")),
            Topic(id: "work.delay", level: .b1, english: "Explaining a delay", title: explain("Explaining a delay")),
            Topic(id: "work.no", level: .b2, english: "Saying no to extra work", title: explain("Saying no to extra work")),
            Topic(id: "work.review", level: .b2, english: "A performance review", title: explain("A performance review")),
            Topic(id: "work.voicemail", level: .a2, english: "Leaving a voicemail", title: explain("Leaving a voicemail")),
        ]),
        Chapter(id: "interview", icon: "person.crop.rectangle.fill", english: "Job interview", title: explain("Job interview"), topics: [
            Topic(id: "interview.about", level: .b1, english: "Tell me about yourself", title: explain("Tell me about yourself")),
            Topic(id: "interview.why", level: .b1, english: "Why this job", title: explain("Why this job")),
            Topic(id: "interview.strengths", level: .b1, english: "Strengths and weaknesses", title: explain("Strengths and weaknesses")),
            Topic(id: "interview.project", level: .b1, english: "A project you're proud of", title: explain("A project you're proud of")),
            Topic(id: "interview.conflict", level: .b2, english: "A conflict you handled", title: explain("A conflict you handled")),
            Topic(id: "interview.future", level: .b1, english: "Where you see yourself", title: explain("Where you see yourself")),
            Topic(id: "interview.salary", level: .b2, english: "Talking about salary", title: explain("Talking about salary")),
            Topic(id: "interview.questions", level: .b1, english: "Questions for them", title: explain("Questions for them")),
            Topic(id: "interview.gap", level: .b2, english: "Explaining a gap", title: explain("Explaining a gap")),
            Topic(id: "interview.followup", level: .b1, english: "Following up after", title: explain("Following up after")),
        ]),
        Chapter(id: "stories", icon: "text.bubble.fill", english: "Opinions & stories", title: explain("Opinions & stories"), topics: [
            Topic(id: "stories.weekend", level: .a2, english: "What happened this weekend", title: explain("What happened this weekend")),
            Topic(id: "stories.funny", level: .b1, english: "A funny story", title: explain("A funny story")),
            Topic(id: "stories.film", level: .b1, english: "Describing a film or book", title: explain("Describing a film or book")),
            Topic(id: "stories.opinion", level: .b1, english: "Giving your opinion", title: explain("Giving your opinion")),
            Topic(id: "stories.agree", level: .b1, english: "Agreeing and disagreeing", title: explain("Agreeing and disagreeing")),
            Topic(id: "stories.countries", level: .b2, english: "Comparing life in two countries", title: explain("Comparing life in two countries")),
            Topic(id: "stories.decision", level: .b1, english: "A decision you made", title: explain("A decision you made")),
            Topic(id: "stories.dreams", level: .a2, english: "Plans and dreams", title: explain("Plans and dreams")),
            Topic(id: "stories.news", level: .b2, english: "Reacting to news", title: explain("Reacting to news")),
            Topic(id: "stories.explain", level: .b2, english: "Explaining something you know well", title: explain("Explaining something you know well")),
        ]),
        Chapter(id: "family", icon: "figure.2.and.child.holdinghands", english: "Family & school", title: explain("Family & school"), topics: [
            Topic(id: "family.teacher", level: .a2, english: "Talking to your child's teacher", title: explain("Talking to your child's teacher")),
            Topic(id: "family.event", level: .a2, english: "A school event", title: explain("A school event")),
            Topic(id: "family.playdate", level: .a2, english: "Arranging a playdate", title: explain("Arranging a playdate")),
            Topic(id: "family.kids", level: .a1, english: "Talking about your kids", title: explain("Talking about your kids")),
            Topic(id: "family.meeting", level: .b1, english: "A parent-teacher meeting", title: explain("A parent-teacher meeting")),
            Topic(id: "family.absence", level: .a2, english: "Calling the school about an absence", title: explain("Calling the school about an absence")),
            Topic(id: "family.pickup", level: .a2, english: "At the kindergarten pick-up", title: explain("At the kindergarten pick-up")),
            Topic(id: "family.help", level: .b1, english: "Asking another parent for help", title: explain("Asking another parent for help")),
            Topic(id: "family.birthday", level: .a2, english: "Birthdays and invitations", title: explain("Birthdays and invitations")),
            Topic(id: "family.visit", level: .a2, english: "A family visit", title: explain("A family visit")),
        ]),
        ]
    }

    static func topic(_ id: String) -> (chapter: Chapter, topic: Topic)? {
        for c in chapters { if let t = c.topics.first(where: { $0.id == id }) { return (c, t) } }
        return nil
    }

    /// What the planner is handed for a topic from the map.
    static func request(for id: String) -> String? {
        topic(id).map { "\($0.chapter.english): \($0.topic.english)" }
    }

    static func isStepUp(_ topic: Topic, level: CEFRLevel) -> Bool {
        rank(topic.level) > rank(level)
    }

    static func rank(_ level: CEFRLevel) -> Int {
        CEFRLevel.allCases.firstIndex(of: level) ?? 0
    }

    /// The one topic to do next: a lesson whose final check is still open
    /// comes first; then the first lit topic not passed, in the chapter
    /// touched last, then in chapter order. Step-ups only when nothing lit
    /// is left.
    static func next(progress: [String: TutorTopicProgress], level: CEFRLevel,
                     excluding: String? = nil) -> (chapter: Chapter, topic: Topic)? {
        let all = chapters
        let pairs = all.flatMap { c in c.topics.map { (chapter: c, topic: $0) } }
            .filter { $0.topic.id != excluding }
        if let open = pairs
            .filter({ progress[$0.topic.id]?.checkLeft == true })
            .max(by: { (progress[$0.topic.id]?.touchedAt ?? .distantPast)
                       < (progress[$1.topic.id]?.touchedAt ?? .distantPast) }) {
            return open
        }
        let lastChapter = pairs
            .compactMap { p in progress[p.topic.id]?.touchedAt.map { (p.chapter.id, $0) } }
            .max(by: { $0.1 < $1.1 })?.0
        let ordered = pairs.filter { $0.chapter.id == lastChapter }
            + pairs.filter { $0.chapter.id != lastChapter }
        let notPassed = ordered.filter { progress[$0.topic.id]?.passedAt == nil }
        return notPassed.first { !isStepUp($0.topic, level: level) } ?? notPassed.first
    }
}

/// How far a learner got with one topic of the map.
struct TutorTopicProgress: Codable, Equatable {
    var startedAt: Date?
    /// Every challenge done; the final check is what's left.
    var lessonDoneAt: Date?
    var passedAt: Date?
    /// Final checks passed on this topic — the first is the tick, the rest
    /// are the depth shown beside it.
    var rounds: Int = 0
    var touchedAt: Date?

    var checkLeft: Bool { passedAt == nil && lessonDoneAt != nil }
    var inProgress: Bool { passedAt == nil && lessonDoneAt == nil && startedAt != nil }
}

/// `Documents/lang/<code>/tutor_progress.json`, per target language.
/// Synced (`SyncKind.tutorProgress`): a topic done anywhere is done.
enum TutorProgressStore {
    private static func url(_ language: String) -> URL {
        LanguageScope.directory(for: LanguageCatalog.base(language))
            .appendingPathComponent("tutor_progress.json")
    }

    static func all(language: String) -> [String: TutorTopicProgress] {
        guard let data = try? Data(contentsOf: url(language)) else { return [:] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([String: TutorTopicProgress].self, from: data)) ?? [:]
    }

    static func update(language: String, topicId: String,
                       _ change: (inout TutorTopicProgress) -> Void) {
        var all = all(language: language)
        var p = all[topicId] ?? TutorTopicProgress()
        change(&p)
        p.touchedAt = Date()
        all[topicId] = p
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(all) else { return }
        try? data.write(to: url(language), options: .atomic)
        SyncEngine.noteChanged(.tutorProgress)
    }
}
