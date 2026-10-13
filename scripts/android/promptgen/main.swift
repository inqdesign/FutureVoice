import Foundation

// Golden conversation prompts: the REAL iOS `ConversationEngine` builds the
// system prompt for each fixture below, and Android's
// `ConversationPromptVectorTest` builds the same fixtures and must produce the
// same bytes. The fixtures are mirrored by hand in that test — change both.
//
// Run with TZ=UTC: a remembered line's age ("3 days ago") is measured from
// the real clock on both sides, and only UTC has no DST to shift a day.

let now = Date()
func daysAgo(_ d: Int) -> Date { now.addingTimeInterval(-Double(d) * 86_400) }

/// 2026-10-13 08:14 UTC = 10:14 in Berlin.
let callStart = Date(timeIntervalSince1970: 1_791_879_240)
let berlin = TimeZone(identifier: "Europe/Berlin")!

let notes: [PersonaNote] = [
    PersonaNote(text: "works as a nurse on night shifts", learnedAt: daysAgo(90), share: .all, kind: .fact),
    PersonaNote(text: "two kids, kindergarten age", learnedAt: daysAgo(20), share: .gist, kind: .fact,
                gist: "a parent of young kids"),
    PersonaNote(text: "has a sister in Busan", learnedAt: daysAgo(3), share: .nothing, kind: .fact),
    PersonaNote(text: "flying to Seoul next Thursday", learnedAt: daysAgo(2), share: .all, kind: .now),
    PersonaNote(text: "had a cold", learnedAt: daysAgo(40), share: .all, kind: .now),
]

let fullPersona = UserPersona(
    displayName: "Eunggyu", city: "Munich", country: "Germany", lengthOfStay: "3 years",
    occupation: "Solo founder of a language app", household: "Wife and 4yo daughter at Kita",
    interests: ["hiking", "AI", "coffee"], situations: ["Kita parent small talk", "client calls"],
    freeNotes: "Prefers short calls", updatedAt: now, learnedNotes: notes, metAt: daysAgo(30))

let thinPersona = UserPersona(
    displayName: "Mina", city: "", country: "", lengthOfStay: "", occupation: "", household: "",
    interests: [], situations: [], freeNotes: "", updatedAt: now,
    learnedNotes: [notes[2], notes[3]], metAt: nil)

let patterns = [
    LearnerPattern(mistake: "I go yesterday", correction: "I went yesterday", context: "past tense", frequency: 4, lastSeenAt: now),
    LearnerPattern(mistake: "more better", correction: "better", context: "comparatives", frequency: 3, lastSeenAt: now),
    LearnerPattern(mistake: "discuss about", correction: "discuss", context: "verb + preposition", frequency: 2, lastSeenAt: now),
    LearnerPattern(mistake: "a advice", correction: "some advice", context: "uncountables", frequency: 1, lastSeenAt: now),
]

let brief = ScenarioBrief(
    summary: "Interview for a product role at Siemens",
    counterpartFacts: ["You are the hiring manager", "The team ships medical imaging software"],
    likelyQuestions: ["Why Siemens?", "Tell me about a hard launch"],
    learnerFacts: ["Eight years in product", "Led a team of five"],
    keyExpressions: ["walk you through", "on the same page"])

func clock(_ today: Int, lastToday: Date?, before: Date?, resumed: Date? = nil) -> PromptClock {
    PromptClock(now: callStart, timeZone: berlin, talksEarlierToday: today,
                lastTalkToday: lastToday, lastTalkBeforeToday: before, resumedFrom: resumed)
}

func person(_ name: String, _ relationship: String, _ build: (inout Counterpart) -> Void) -> Counterpart {
    var c = Counterpart(name: name, relationship: relationship, background: "", conversationStyle: "",
                        voicePresetId: "preset")
    build(&c)
    return c
}

let closeFriend = person("Minsu", "best friend from university") {
    $0.relationshipKind = "Friend"
    $0.howWeMet = "College roommates, 8 years"
    $0.location = "Seoul, works at a game studio"
    $0.conversationStyle = "jokes a lot"
    $0.commonTopics = "games, football"
    $0.background = "We backpacked through Japan together"
    $0.freeNotes = "Just had a baby"
    $0.myRegister = .casual
    $0.theirRegister = .casual
    $0.iCallThem = "민수야"
    $0.theyCallMe = "형"
}
let manager = person("Ms. Keller", "my manager") {
    $0.relationshipKind = "Colleague"
    $0.conversationStyle = "careful, formal"
}
let stranger = person("Lena", "Met on nawana") {
    $0.remoteId = "remote-lena"
    $0.location = "Munich, Germany"
    $0.commonTopics = "hiking, piano"
    $0.intro = "I teach piano in Munich and hike every weekend. My son just started school."
    $0.background = $0.intro
    $0.conversationStyle = "warm, curious"
    $0.personaKind = "user"
}
let strangerNoGround = person("Paul", "Met on nawana") {
    $0.remoteId = "remote-paul"
    $0.intro = "Je suis boulanger à Lyon."
    $0.background = $0.intro
    $0.personaKind = "character"
}
let publicFigure = person("RM", "") {
    $0.isPublicFigure = true
    $0.publicIdentity = "BTS RM · rapper"
    $0.relationshipKind = "Public figure"
}

struct Fixture {
    let name: String
    let target: String, native: String, level: CEFRLevel
    var patterns: [LearnerPattern] = []
    var weak: [String] = []
    var topic = ""
    var persona: UserPersona? = nil
    var counterpart: Counterpart? = nil
    var news: [String] = []
    var brief: ScenarioBrief? = nil
    var firstMeeting = false
    var clock: PromptClock? = nil
    var tutor = false
}

let fixtures: [Fixture] = [
    Fixture(name: "free_en_b1_bare", target: "en", native: "ko", level: .b1),
    Fixture(name: "free_ko_a2_full_tutor", target: "ko", native: "en", level: .a2,
            patterns: patterns, weak: ["food", "work"], topic: "Weekend plans", persona: fullPersona,
            news: ["The city opened a new tram line", "Fares stay the same"],
            clock: clock(2, lastToday: callStart.addingTimeInterval(-3 * 3600), before: daysAgo(3)),
            tutor: true),
    Fixture(name: "first_ja_a1_tutor", target: "ja", native: "ko", level: .a1, persona: thinPersona,
            firstMeeting: true, clock: clock(0, lastToday: nil, before: nil), tutor: true),
    Fixture(name: "brief_de_c1", target: "de", native: "en", level: .c1,
            topic: "Job interview at Siemens. Practice the interview.", persona: fullPersona, brief: brief,
            clock: clock(1, lastToday: callStart.addingTimeInterval(-20 * 60), before: nil,
                         resumed: callStart.addingTimeInterval(-2 * 86_400)), tutor: true),
    Fixture(name: "cast_own_close_ko", target: "ko", native: "en", level: .b2, persona: fullPersona,
            counterpart: closeFriend, clock: clock(1, lastToday: callStart.addingTimeInterval(-3600), before: daysAgo(10))),
    Fixture(name: "cast_own_manager_en", target: "en", native: "ko", level: .b1, persona: fullPersona,
            counterpart: manager),
    Fixture(name: "cast_stranger_en_tutor", target: "en", native: "ko", level: .b1, persona: fullPersona,
            counterpart: stranger, clock: clock(0, lastToday: nil, before: daysAgo(1)), tutor: true),
    Fixture(name: "cast_stranger_fr_noground", target: "fr", native: "en", level: .c2, counterpart: strangerNoGround),
    Fixture(name: "cast_public_figure_ko", target: "ko", native: "en", level: .a2, persona: thinPersona,
            counterpart: publicFigure),
    Fixture(name: "first_counterpart_ignored_es", target: "es", native: "en", level: .b2, persona: nil,
            counterpart: manager, firstMeeting: true),
]

var prompts: [String: String] = [:]
for f in fixtures {
    LanguageScope.active = f.target
    prompts["system/" + f.name] = ConversationEngine.conversationSystemPrompt(
        targetLanguage: f.target, nativeLanguage: f.native, level: f.level,
        topPatterns: f.patterns, weakVocabAreas: f.weak, topic: f.topic,
        persona: f.persona, counterpart: f.counterpart, newsFacts: f.news, brief: f.brief,
        firstMeeting: f.firstMeeting, clock: f.clock, tutor: f.tutor)
}

let outputs: [(String, String, String, Counterpart?, Bool)] = [
    ("output/en_plain", "en", "ko", nil, false),
    ("output/ko_close_friend", "ko", "en", closeFriend, false),
    ("output/ko_scene", "ko", "en", nil, true),
    ("output/ko_manager", "ko", "ja", manager, false),
    ("output/ja_stranger", "ja", "ko", stranger, false),
    ("output/de_plain", "de", "en", nil, false),
]
for (name, target, native, cp, scene) in outputs {
    LanguageScope.active = target
    prompts[name] = ConversationEngine.turnOutputInstruction(
        targetLanguage: target, nativeLanguage: native, counterpart: cp, inScene: scene)
}

// The realtime path's correction request (`correctionOnlyPrompt`), on the
// same people: a set register, a scene, a stranger, three guard languages.
let corrections: [(String, String, String, CEFRLevel, Counterpart?, Bool)] = [
    ("correction/en_plain", "en", "ko", .b1, nil, false),
    ("correction/ko_close_friend", "ko", "en", .b2, closeFriend, false),
    ("correction/ko_scene", "ko", "en", .a2, nil, true),
    ("correction/ko_manager", "ko", "ja", .b1, manager, false),
    ("correction/ja_stranger", "ja", "ko", .a1, stranger, false),
    ("correction/de_plain", "de", "en", .c1, nil, false),
]
for (name, target, native, level, cp, scene) in corrections {
    LanguageScope.active = target
    prompts[name] = ConversationEngine.correctionOnlyPrompt(
        targetLanguage: target, nativeLanguage: native, level: level, counterpart: cp, inScene: scene)
}

let ref = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "?"
let doc: [String: Any] = ["ios_ref": ref, "prompts": prompts]
let data = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(prompts.count) prompts → \(CommandLine.arguments[1])")
