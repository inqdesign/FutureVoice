import Foundation

/// The pronunciation call (2026-11-04, founder: "a call whose goal is
/// pronunciation, like tutor mode — mainly for beginners").
///
/// The third page of the Talk ring. It IS a call: same screen, same gateway,
/// same voice, metered as talk time. What changes is who decides: the
/// learner's screen shows one sentence in big letters, they read it aloud,
/// the turn is HELD at the gateway (`holdReplies`) while the app judges the
/// take with Azure's pronunciation assessment (`PronunciationAssessor`), and
/// the fluent self says ONE line built from the app's verdict — the word that
/// wasn't clear yet, said right in the learner's own voice, then "again".
/// The same "the app decides, the voice says it" contract as tutor mode
/// (`TutorMode`), with Azure in place of the correction call and the judge.
///
/// Topics come from a small COURSE per target language
/// (`PronunciationCourse`): one sound per topic (th, r·l, ü, っ, ㄲㄸㅃ…).
/// A round is five sentences written for that sound at the learner's level
/// (`PronunciationPlanner`). Every take lands in `PronunciationLedger`, so
/// Progress and the week's coach see it like any shadow take.
///
/// No summary and no book: a round of read sentences is not a conversation,
/// and its words would otherwise fill the notebook. What it leaves is the
/// ledger and the course's progress.
enum PronunciationCall {
    /// Written by the ring: true while its pronunciation page is the one
    /// showing, so the call opened from it knows what it is.
    static let key = "futurevoice.call.pronunciationMode"
    /// The last topic practiced, per target language — the ring's headline
    /// and the next call's default.
    static func lastTopicKey(_ language: String) -> String {
        "futurevoice.pron.lastTopic.\(LanguageCatalog.base(language))"
    }

    /// The last topic's round was finished (not left halfway).
    static func lastFinishedKey(_ language: String) -> String {
        "futurevoice.pron.lastFinished.\(LanguageCatalog.base(language))"
    }

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    static let sentencesPerRound = 5
    // No try limit anywhere (founder, 2026-11-04): a sentence or a word is
    // left only by the learner's own "Next sentence" / "Back to the sentence".

    /// The topic the next call opens on (founder, 2026-11-04: a session
    /// finished and ended starts a NEW one next time, not the old one): the
    /// course's next sound once the last topic's round was finished; the
    /// same sound when it was left halfway; the course's first otherwise.
    static func startingTopic(language: String, level: CEFRLevel) -> PronunciationCourse.Topic? {
        let course = PronunciationCourse.topics(for: language)
        let d = UserDefaults.standard
        if let id = d.string(forKey: lastTopicKey(language)),
           let t = course.first(where: { $0.id == id }) {
            guard d.bool(forKey: lastFinishedKey(language)) else { return t }
            return PronunciationCourse.next(language: language, level: level, excluding: id) ?? t
        }
        return PronunciationCourse.next(language: language, level: level)
    }
}

// MARK: - Course

/// The pronunciation course ("교재", founder): chapters of sounds per target
/// language, the same for everyone, written by us. A topic is one sound (or
/// one pair that is easy to confuse), with example words in the target
/// language. The planner writes each round's sentences from it, at the
/// learner's level.
///
/// `symbol` and `examples` are target-language material and are never
/// translated; the chapter names are chrome.
enum PronunciationCourse {
    struct Chapter: Identifiable {
        let id: String
        let icon: String
        let title: String
        let topics: [Topic]
    }

    struct Topic: Identifiable, Hashable {
        let id: String
        /// How the sound is written, as a learner would recognise it ("th",
        /// "r · l", "ü", "っ", "ㄲ ㄸ ㅃ").
        let symbol: String
        /// Three or four words that carry it, in the target language.
        let examples: String
        /// Azure's IPA names for the sound (en-US only; other locales send
        /// phonemes without names). Used to point at the sound in a word;
        /// the verdict never depends on them.
        let phonemes: [String]
        /// For the planner and the voice: what the sound is and how it goes
        /// wrong, in English.
        let english: String
    }

    static func chapters(for language: String) -> [Chapter] {
        let consonants = explain("Consonants")
        let vowels = explain("Vowels")
        let flow = explain("Endings and flow")
        switch LanguageCatalog.base(language) {
        case "en":
            return [
                Chapter(id: "en.cons", icon: "mouth.fill", title: consonants, topics: [
                    Topic(id: "en.th", symbol: "th", examples: "think · three · thank",
                          phonemes: ["θ"],
                          english: "the voiceless 'th' /θ/ (think, three, thank): tongue tip lightly between the teeth, air out — not 's', 't' or 'f'"),
                    Topic(id: "en.dh", symbol: "th", examples: "this · that · mother",
                          phonemes: ["ð"],
                          english: "the voiced 'th' /ð/ (this, that, mother): tongue between the teeth with voice — not 'd' or 'z'"),
                    Topic(id: "en.r", symbol: "r", examples: "right · red · very",
                          phonemes: ["ɹ", "r", "ɻ"],
                          english: "the English 'r' /ɹ/ (right, red, very): tongue pulled back, never touching the roof of the mouth, lips a little round"),
                    Topic(id: "en.rl", symbol: "r · l", examples: "right · light · read · lead",
                          phonemes: ["ɹ", "r", "l"],
                          english: "telling 'r' and 'l' apart (right/light, read/lead): for 'l' the tongue tip touches behind the top teeth, for 'r' it touches nothing"),
                    Topic(id: "en.f", symbol: "f · p", examples: "coffee · five · phone",
                          phonemes: ["f", "p"],
                          english: "'f' (coffee, five, phone) as the top teeth on the lower lip with air — not 'p'"),
                    Topic(id: "en.v", symbol: "v · b", examples: "very · love · video",
                          phonemes: ["v", "b"],
                          english: "'v' (very, love, video) as top teeth on the lower lip with voice — not 'b'"),
                    Topic(id: "en.z", symbol: "z", examples: "zoo · is · music",
                          phonemes: ["z"],
                          english: "'z' (zoo, is, music) as a buzzing 's' — not 'j' or 's'"),
                    Topic(id: "en.sh", symbol: "s · sh", examples: "see · she · sip · ship",
                          phonemes: ["s", "ʃ"],
                          english: "telling 's' and 'sh' apart (see/she, sip/ship): 'sh' with rounded lips and the tongue further back"),
                ]),
                Chapter(id: "en.vow", icon: "waveform", title: vowels, topics: [
                    Topic(id: "en.i", symbol: "ee · i", examples: "sheep · ship · leave · live",
                          phonemes: ["i", "iː", "ɪ"],
                          english: "long 'ee' /i/ vs short 'i' /ɪ/ (sheep/ship, leave/live): 'ee' is long with a wide smile, 'i' is short and relaxed"),
                    Topic(id: "en.ae", symbol: "a", examples: "cat · bad · apple",
                          phonemes: ["æ"],
                          english: "the 'a' in cat /æ/: mouth wide open and spread — not 'e' as in bed"),
                    Topic(id: "en.uh", symbol: "u", examples: "cup · but · love",
                          phonemes: ["ʌ"],
                          english: "the short 'u' in cup /ʌ/: short, relaxed, mouth half open — not 'o'"),
                    Topic(id: "en.oo", symbol: "oo · u", examples: "food · good · pool · pull",
                          phonemes: ["u", "uː", "ʊ"],
                          english: "long 'oo' /u/ vs short /ʊ/ (food/good, pool/pull)"),
                    Topic(id: "en.er", symbol: "or · er", examples: "walk · work · born · burn",
                          phonemes: ["ɔ", "ɝ", "ɚ", "ɜ"],
                          english: "'or' /ɔ/ vs 'er' /ɝ/ (walk/work, born/burn): 'er' with the tongue pulled back like an 'r'"),
                ]),
                Chapter(id: "en.flow", icon: "text.word.spacing", title: flow, topics: [
                    Topic(id: "en.final", symbol: "-t · -d · -k", examples: "cat · bed · book",
                          phonemes: [],
                          english: "ending a word on a consonant (cat, bed, book) without adding a vowel after it ('book-u')"),
                    Topic(id: "en.sed", symbol: "-s · -ed", examples: "walks · walked · needs",
                          phonemes: ["s", "z", "t", "d"],
                          english: "saying the -s and -ed endings (walks, walked, needs) instead of dropping them"),
                    Topic(id: "en.cluster", symbol: "str · spr", examples: "street · spring · strong",
                          phonemes: [],
                          english: "consonant groups (street, spring, strong) said together, no vowel slipped in between"),
                ]),
            ]
        case "de":
            return [
                Chapter(id: "de.vow", icon: "waveform", title: vowels, topics: [
                    Topic(id: "de.ue", symbol: "ü", examples: "über · grün · müde",
                          phonemes: [], english: "German 'ü' (über, grün, müde): say 'i' with the lips rounded like 'u'"),
                    Topic(id: "de.oe", symbol: "ö", examples: "schön · hören · Möbel",
                          phonemes: [], english: "German 'ö' (schön, hören): say 'e' with the lips rounded like 'o'"),
                    Topic(id: "de.eiie", symbol: "ei · ie", examples: "mein · mir · Wein · Wien",
                          phonemes: [], english: "'ei' is 'ai', 'ie' is a long 'ee' (mein/mir, Wein/Wien)"),
                    Topic(id: "de.long", symbol: "aa · ah", examples: "Staat · Stadt · Bahn · Bann",
                          phonemes: [], english: "long vs short vowels (Staat/Stadt, Bahn/Bann)"),
                ]),
                Chapter(id: "de.cons", icon: "mouth.fill", title: consonants, topics: [
                    Topic(id: "de.ich", symbol: "ch", examples: "ich · nicht · Milch",
                          phonemes: [], english: "the soft 'ch' after e/i (ich, nicht, Milch): a hissing sound, not 'sch' and not 'k'"),
                    Topic(id: "de.ach", symbol: "ch", examples: "Bach · noch · Buch",
                          phonemes: [], english: "the rough 'ch' after a/o/u (Bach, noch, Buch): from the back of the throat"),
                    Topic(id: "de.r", symbol: "r", examples: "rot · Reise · Brot",
                          phonemes: [], english: "German 'r' (rot, Reise): from the back of the throat, and soft like 'a' at the end of a word (Lehrer)"),
                    Topic(id: "de.z", symbol: "z", examples: "Zeit · zehn · Pizza",
                          phonemes: [], english: "German 'z' (Zeit, zehn) is 'ts', never a buzzing 'z'"),
                    Topic(id: "de.w", symbol: "w", examples: "Wasser · wann · Wein",
                          phonemes: [], english: "German 'w' (Wasser, wann) is an English 'v', never 'w'"),
                ]),
            ]
        case "ja":
            return [
                Chapter(id: "ja.len", icon: "waveform", title: vowels, topics: [
                    Topic(id: "ja.long", symbol: "ー", examples: "おばさん · おばあさん · ビル · ビール",
                          phonemes: [], english: "long vowels (おばさん/おばあさん, ビル/ビール): a long vowel takes twice the time"),
                    Topic(id: "ja.tsu", symbol: "っ", examples: "きって · きて · まって",
                          phonemes: [], english: "the small っ (きって/きて): a short pause, one beat long, before the next sound"),
                    Topic(id: "ja.n", symbol: "ん", examples: "ほん · きんえん · せんせい",
                          phonemes: [], english: "ん is a full beat of its own (ほん, きんえん)"),
                ]),
                Chapter(id: "ja.cons", icon: "mouth.fill", title: consonants, topics: [
                    Topic(id: "ja.r", symbol: "ら", examples: "らいねん · くるま · ありがとう",
                          phonemes: [], english: "the Japanese r (ら行): a light tap of the tongue, between r, l and d"),
                    Topic(id: "ja.tsusu", symbol: "つ · す", examples: "つくえ · すし · なつ",
                          phonemes: [], english: "'tsu' vs 'su' (つくえ, すし): つ starts with a 't'"),
                    Topic(id: "ja.zuji", symbol: "ざ · じゃ", examples: "ざっし · じゃあ · ぜんぶ",
                          phonemes: [], english: "the z-row (ざ, ぜ, ぞ) vs じゃ"),
                ]),
            ]
        case "ko":
            return [
                Chapter(id: "ko.cons", icon: "mouth.fill", title: consonants, topics: [
                    Topic(id: "ko.tense", symbol: "ㄲ ㄸ ㅃ ㅆ ㅉ", examples: "까치 · 딸기 · 빵 · 싸다",
                          phonemes: [], english: "tense consonants (까, 따, 빠, 싸, 짜): tight throat, no puff of air"),
                    Topic(id: "ko.asp", symbol: "ㅋ ㅌ ㅍ ㅊ", examples: "커피 · 토요일 · 포도 · 차",
                          phonemes: [], english: "aspirated consonants (커, 터, 퍼, 처): a strong puff of air"),
                    Topic(id: "ko.three", symbol: "ㄱ ㄲ ㅋ", examples: "가다 · 까다 · 카드",
                          phonemes: [], english: "the three-way contrast (가/까/카, 달/딸/탈)"),
                    Topic(id: "ko.batchim", symbol: "받침", examples: "밥 · 국 · 옷 · 꽃",
                          phonemes: [], english: "final consonants (밥, 국, 옷): closed and not released, no vowel after"),
                ]),
                Chapter(id: "ko.vow", icon: "waveform", title: vowels, topics: [
                    Topic(id: "ko.eoo", symbol: "ㅓ · ㅗ", examples: "어머니 · 오늘 · 거기 · 고기",
                          phonemes: [], english: "ㅓ (open, lips not rounded) vs ㅗ (rounded) — 거기/고기"),
                    Topic(id: "ko.eu", symbol: "ㅡ", examples: "그림 · 크다 · 음악",
                          phonemes: [], english: "ㅡ: lips spread flat, tongue back — not 'u'"),
                    Topic(id: "ko.link", symbol: "연음", examples: "한국어 · 음악 · 옷이",
                          phonemes: [], english: "linking a final consonant into the next vowel (한국어 → 한구거, 옷이 → 오시)"),
                ]),
            ]
        case "es":
            return [
                Chapter(id: "es.cons", icon: "mouth.fill", title: consonants, topics: [
                    Topic(id: "es.rr", symbol: "rr", examples: "perro · carro · rojo",
                          phonemes: [], english: "the trilled 'rr' (perro, carro, rojo at the start of a word): the tongue tip flutters"),
                    Topic(id: "es.r", symbol: "r", examples: "pero · caro · para",
                          phonemes: [], english: "the single tapped 'r' (pero, caro): one quick tap — pero vs perro"),
                    Topic(id: "es.j", symbol: "j · g", examples: "jamón · gente · ojo",
                          phonemes: [], english: "'j' and 'g' before e/i (jamón, gente): a rough 'h' from the throat"),
                    Topic(id: "es.bv", symbol: "b · v", examples: "vino · bueno · Cuba",
                          phonemes: [], english: "'b' and 'v' are the same sound, soft between vowels (Cuba, uva)"),
                    Topic(id: "es.ny", symbol: "ñ", examples: "año · España · niño",
                          phonemes: [], english: "'ñ' (año, España): like 'ny' in canyon"),
                ]),
                Chapter(id: "es.vow", icon: "waveform", title: vowels, topics: [
                    Topic(id: "es.vowels", symbol: "a e i o u", examples: "casa · mesa · libro · todo",
                          phonemes: [], english: "the five pure vowels (casa, mesa, todo): short and clean, never glided like English 'o-u' or 'e-i'"),
                ]),
            ]
        default:
            return []
        }
    }

    static func topics(for language: String) -> [Topic] {
        chapters(for: language).flatMap(\.topics)
    }

    static func topic(_ id: String, language: String) -> Topic? {
        topics(for: language).first { $0.id == id }
    }

    /// The first topic never practiced; once every topic has been, the one
    /// with the lowest recent score.
    static func next(language: String, level: CEFRLevel,
                     excluding: String? = nil) -> Topic? {
        let progress = PronunciationProgressStore.all(language: language)
        let all = topics(for: language).filter { $0.id != excluding }
        if let fresh = all.first(where: { progress[$0.id] == nil }) { return fresh }
        return all.min { (progress[$0.id]?.lastScore ?? 0) < (progress[$1.id]?.lastScore ?? 0) }
    }
}

// MARK: - Progress

struct PronunciationTopicProgress: Codable, Equatable {
    /// Rounds finished on this topic.
    var rounds: Int = 0
    /// Sentences passed, all rounds.
    var passed: Int = 0
    /// The mean sound score of the last finished round.
    var lastScore: Int?
    var bestScore: Int?
    var lastAt: Date?
    /// Words that still didn't come out after the round brought them back
    /// once: the next round on this topic is written around them, and a
    /// word leaves the list when it is said right (newest 8 kept).
    var missedWords: [String]?
}

/// `Documents/lang/<code>/pronunciation_course.json`. Device-local for now
/// (the takes themselves sync through `PronunciationLedger`).
enum PronunciationProgressStore {
    private static func url(_ language: String) -> URL {
        LanguageScope.directory(for: LanguageCatalog.base(language))
            .appendingPathComponent("pronunciation_course.json")
    }

    static func all(language: String) -> [String: PronunciationTopicProgress] {
        guard let data = try? Data(contentsOf: url(language)) else { return [:] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([String: PronunciationTopicProgress].self, from: data)) ?? [:]
    }

    static func update(language: String, topicId: String,
                       _ change: (inout PronunciationTopicProgress) -> Void) {
        var all = all(language: language)
        var p = all[topicId] ?? PronunciationTopicProgress()
        change(&p)
        p.lastAt = Date()
        all[topicId] = p
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(all) else { return }
        try? data.write(to: url(language), options: .atomic)
    }
}

// MARK: - Round

/// One round: five sentences for one sound, read one at a time.
struct PronunciationRound: Equatable {
    struct Line: Equatable, Identifiable {
        let id: UUID
        let text: String
        /// The words in `text` that carry the sound, as written there.
        let focus: [String]
        var tries = 0
        var passed = false
        /// Left by the learner's "Next sentence" without a pass.
        var skipped = false
        /// The last judged take, drawn on the card.
        var lastResult: PronunciationResult?
        var bestScore: Int?
        /// The last take's word that came out as ANOTHER word: the word on
        /// screen and what the transcriber heard instead ("read" → "lead").
        var heardWord: String?
        var heardAs: String?
        /// The last take had every sound but stopped and started.
        var notSmooth = false
        /// A word that didn't come out, practiced ON ITS OWN before the
        /// sentence is read again (founder, 2026-11-04: "repeat that word,
        /// not 'say the whole sentence again'"). nil = the sentence.
        var drillWord: String?
        var drillTries = 0
        /// The last take's verdict as the learner sees it: what was judged
        /// (a word and its sound, or the flow), its score, and whether it
        /// cleared the bar (founder, 2026-11-04: "show 'not yet' or a score
        /// for that sound").
        var feedback: Feedback?
        /// The second time this sentence comes up in the round: it was
        /// moved to the end when the learner skipped it. Skipped again, it is
        /// left, and its word goes to the topic's `missedWords`.
        var isRetry = false
    }

    struct Feedback: Equatable {
        /// The word ("flight"); nil when the flow was judged.
        let word: String?
        /// The sound in it ("l"), English only.
        let sound: String?
        let score: Int
        let ok: Bool
        /// How that sound came out (founder, 2026-11-04: "show how it
        /// sounded"), when Azure heard something else.
        var heardAs: PronunciationJudge.HeardAs? = nil
    }

    let id: UUID
    let topic: PronunciationCourse.Topic
    /// How to make the sound, in the learner's NATIVE language (coaching).
    let tip: String
    var lines: [Line]
    let language: String
    /// The sentence the learner just skipped: what it was about and when
    /// it comes back, shown on the next sentence's card until its first take.
    var carried: Carried?

    struct Carried: Equatable {
        let word: String?
        let sound: String?
        /// At the end of this round; else in the next round.
        let laterInRound: Bool
    }

    var current: Int? { lines.firstIndex { !$0.passed && !$0.skipped } }
    var isFinished: Bool { current == nil }
    var doneCount: Int { lines.filter { $0.passed || $0.skipped }.count }
    var passedCount: Int { lines.filter(\.passed).count }
    /// Sentences in the round, a sentence brought back at the end counted once.
    var sentenceCount: Int { Set(lines.map(\.text)).count }

    /// Mean of each line's best sound score, over the lines that have one.
    var meanScore: Int? {
        let s = lines.compactMap(\.bestScore)
        return s.isEmpty ? nil : s.reduce(0, +) / s.count
    }
}

// MARK: - Planner

enum PronunciationPlanner {
    private struct Plan: Decodable {
        let tip: String?
        let sentences: [Item]?
        struct Item: Decodable {
            let text: String
            let focus: [String]?
        }
    }

    /// Five sentences for `topic` at the learner's level, and a one-line tip
    /// in their native language. Nil when the call failed.
    static func plan(topic: PronunciationCourse.Topic, targetLanguage: String,
                     nativeLanguage: String, level: CEFRLevel,
                     persona: UserPersona?, avoid: [String] = [],
                     review: [String] = []) async -> PronunciationRound? {
        let target = LanguageCatalog.englishName(targetLanguage)
        let native = LanguageCatalog.englishName(nativeLanguage)
        let length: String
        switch level {
        case .a1: length = "4 to 7 words, the most everyday words there are"
        case .a2: length = "5 to 9 words, everyday words"
        case .b1: length = "7 to 12 words"
        default: length = "8 to 14 words, natural and a little challenging"
        }
        let about = [persona?.occupation, persona?.city]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " · ")
        let system = """
        You write PRONUNCIATION practice for a \(target) learner at CEFR \
        \(level.rawValue.uppercased()) whose own language is \(native). They \
        will read each sentence aloud from their screen, and a machine will \
        score how they pronounced it.

        Today's sound: \(topic.english).
        Example words: \(topic.examples).

        Write \(PronunciationCall.sentencesPerRound) sentences in \(target):
        - Each sentence is \(length), something a person would really say, \
          in first person or about everyday life. Spoken, so contracted the \
          way people talk.
        - Each sentence carries today's sound at least TWICE, in different \
          words where possible. Start easy (the sound once or twice, short \
          words) and get a little harder toward the last.
        - "focus": the words in that sentence that carry the sound, copied \
          EXACTLY as they are written in it (same spelling, same case).
        - No names, numbers written as digits, abbreviations, brackets or \
          quotes — only words a reader can say.
        - No two sentences alike, and none of these: \(avoid.isEmpty ? "(none)" : avoid.joined(separator: " | ")).\(review.isEmpty ? "" : """

        - These words did NOT come out right last time: \(review.joined(separator: ", ")). Put them in the FIRST sentences, one or two per sentence, and list them in "focus" too.
        """)

        "tip": ONE or two short sentences in \(native) telling a beginner how \
        to make the sound with their mouth (tongue, lips, teeth, breath), \
        concrete, friendly, no phonetic symbols.
        \(about.isEmpty ? "" : "\nWhat is known about them: \(about). Context only.")
        Return STRICT JSON only:
        {"tip": "...", "sentences": [{"text": "...", "focus": ["..."]}]}
        """
        var plan: Plan?
        for _ in 0..<2 where plan == nil {
            plan = try? await GeminiClient.shared.sendJSON(
                system: system,
                messages: [GeminiClient.Message(role: .user, content: "Sound: \(topic.symbol) (\(topic.examples))")],
                maxTokens: 1500, purpose: "tutor",
                idempotencyKey: "pron-plan:\(UUID().uuidString)", requestTimeout: 20)
            if plan?.sentences?.isEmpty ?? true { plan = nil }
        }
        guard let plan, let items = plan.sentences else { return nil }
        let lines = items.prefix(PronunciationCall.sentencesPerRound).compactMap { item -> PronunciationRound.Line? in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            // A focus word the sentence doesn't contain would mark nothing.
            let focus = (item.focus ?? []).filter {
                !$0.isEmpty && text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            return .init(id: UUID(), text: text, focus: focus)
        }
        guard lines.count >= 3 else { return nil }
        return PronunciationRound(id: UUID(), topic: topic,
                                  tip: plan.tip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                                  lines: lines, language: targetLanguage)
    }
}

// MARK: - Judge

/// What a take of the sentence on screen gets. Code, never a model: the
/// numbers are Azure's, the bar is ours.
enum PronunciationJudge {
    enum Verdict: Equatable {
        /// Every sound clear and the sentence said in one go.
        case pass(score: Int)
        /// One word to work on: the word whose LESSON sound scored lowest,
        /// else a word Azure scored low. `sound` is the phoneme that let it
        /// down (English only). `heard` is set only by the text-only
        /// fallback, when there was no audio judge at all.
        case notYet(word: String, sound: String?, score: Int, heard: String?)
        /// Every sound was clear but the reading stopped and started.
        case notSmooth(score: Int)
        /// They said something else (a question, "this is hard").
        case offScript
        /// Nothing usable came back (silence, a failed request).
        case unheard
    }

    /// The AUDIO decides, never the transcript (founder, 2026-11-04: "why
    /// do you analyze the transcription? Azure should judge the audio").
    /// A transcriber writes the word it can tell was meant, so it hides
    /// exactly what this call exists to catch.
    ///
    /// The bars, set on the founder's own takes that day (the dev app's
    /// `pronunciation.json`): Azure's sentence and word scores are lenient —
    /// "flight" said as "프-라이트" scored 95 for the sentence and 73 for
    /// the word, with its l at 60; "read" said as "lead" kept 60 as a word
    /// with its r at 17. The accent is in the PHONEMES, and in a sound
    /// lesson the lesson's own phonemes are what is judged.
    /// A lesson phoneme under this is "not yet".
    static let lessonSoundBar = 70
    /// Any word under this is "not yet".
    static let wordBar = 70
    /// Any sound under this is "not yet", lesson sound or not.
    static let soundBar = 65
    /// A word-final p/t/k/b/d/g: often unreleased in native speech.
    static let finalStopBar = 55
    /// Prosody (en-US only) and fluency under these: said, but not smoothly.
    static let prosodyBar = 80
    static let fluencyBar = 70
    /// Less of the sentence than this was heard: they said something else.
    static let completenessBar = 50
    /// Kept for the course's colour of a topic's last score.
    static let passBar = 70

    static func verdict(result: PronunciationResult?, line: PronunciationRound.Line,
                        said: String, phonemes: [String], language: String) -> Verdict {
        guard let result else { return .unheard }
        if (result.completeness ?? 100) < completenessBar { return .offScript }
        let judged = result.referenceWords.filter(\.isJudged)

        // 1. The lesson's sound, wherever it is in the sentence.
        if !phonemes.isEmpty {
            let hits = judged.compactMap { w -> (PronunciationResult.Word, PronunciationResult.Phoneme)? in
                let lesson = w.phonemes.filter { isLesson($0.phoneme, phonemes) && $0.accuracy != nil }
                guard let worst = lesson.min(by: { $0.accuracy! < $1.accuracy! }),
                      worst.accuracy! < lessonSoundBar else { return nil }
                return (w, worst)
            }
            if let (w, p) = hits.min(by: { $0.1.accuracy! < $1.1.accuracy! }) {
                return .notYet(word: w.word, sound: p.phoneme, score: result.soundScore, heard: nil)
            }
        } else {
            // No phoneme names (every language but English): the words that
            // carry the sound, held to a higher bar than the rest.
            let focusKeys = Set(line.focus.map(key))
            if let w = judged.filter({ focusKeys.contains(key($0.word)) && ($0.accuracy ?? 100) < 85 })
                .min(by: { ($0.accuracy ?? 100) < ($1.accuracy ?? 100) }) {
                return .notYet(word: w.word, sound: nil, score: result.soundScore, heard: nil)
            }
        }
        // 2. Any SOUND that came out badly, wherever it is. Measured on
        //    2026-11-04 (macOS voices, en-US): word scores can't tell
        //    "드링크" from a native "drink" (97 both), but the phonemes do —
        //    the Korean-style readings put consonants at 23–60 (프라이트's f
        //    at 38, heard as p), the native ones at 81–100. A word-final
        //    stop gets a lower bar: left unreleased, as English often does,
        //    it scores low without being wrong.
        let soundHits = judged.compactMap { w -> (PronunciationResult.Word, PronunciationResult.Phoneme)? in
            let named = w.phonemes.filter { $0.accuracy != nil }
            let off = named.enumerated().filter { i, p in
                let finalStop = i == named.count - 1 && ["p", "t", "k", "b", "d", "g"].contains(p.phoneme)
                return p.accuracy! < (finalStop ? finalStopBar : soundBar)
            }.map(\.element)
            guard let worst = off.min(by: { $0.accuracy! < $1.accuracy! }) else { return nil }
            return (w, worst)
        }
        if let (w, p) = soundHits.min(by: { $0.1.accuracy! < $1.1.accuracy! }) {
            return .notYet(word: w.word, sound: p.phoneme.isEmpty ? nil : p.phoneme,
                           score: result.soundScore, heard: nil)
        }
        // 3. Any word that came out badly, or a word left out.
        if let w = result.referenceWords.filter({ $0.isOmission || ($0.isJudged && ($0.accuracy ?? 100) < wordBar) })
            .min(by: { ($0.accuracy ?? 0) < ($1.accuracy ?? 0) }) {
            return .notYet(word: w.word, sound: w.isJudged ? sound(in: w, preferring: phonemes) : nil,
                           score: result.soundScore, heard: nil)
        }
        // 4. Smooth: in one go, without stopping and starting.
        if (result.prosody ?? 100) < prosodyBar || result.fluency < fluencyBar {
            return .notSmooth(score: result.soundScore)
        }
        return .pass(score: result.soundScore)
    }

    /// What the card shows for a verdict: the word and sound that were
    /// judged and the score that decided it.
    static func feedback(for verdict: Verdict, result: PronunciationResult?,
                         line: PronunciationRound.Line, phonemes: [String]) -> PronunciationRound.Feedback? {
        guard let result else { return nil }
        let words = result.referenceWords.filter(\.isJudged)
        func scoreOf(_ word: String, _ sound: String?) -> Int? {
            guard let w = words.first(where: { key($0.word) == key(word) }) else { return nil }
            if let sound, let p = w.phonemes.filter({ $0.phoneme == sound }).compactMap(\.accuracy).min() {
                return p
            }
            return w.accuracy
        }
        switch verdict {
        case .notYet(let word, let sound, _, _):
            return .init(word: word, sound: sound, score: scoreOf(word, sound) ?? result.soundScore, ok: false,
                         heardAs: heardAs(result: result, word: word, sound: sound))
        case .notSmooth:
            return .init(word: nil, sound: nil, score: result.prosody ?? result.fluency, ok: false)
        case .pass:
            // The lesson's weakest sound in what was said, or the take's
            // sound score when the language names no phonemes.
            let lesson = words.flatMap { w in
                w.phonemes.filter { isLesson($0.phoneme, phonemes) }.compactMap { p in
                    p.accuracy.map { (w.word, p.phoneme, $0) }
                }
            }
            if let worst = lesson.min(by: { $0.2 < $1.2 }) {
                return .init(word: worst.0, sound: worst.1, score: worst.2, ok: true)
            }
            if words.count == 1, let w = words.first {
                return .init(word: w.word, sound: nil, score: w.accuracy ?? result.soundScore, ok: true)
            }
            return .init(word: nil, sound: nil, score: result.soundScore, ok: true)
        case .offScript, .unheard:
            return nil
        }
    }

    /// What is practiced on its own when `word` didn't come out. A word
    /// whose sound DEPENDS on the sentence is never cut out alone (founder,
    /// 2026-11-04: "the" is "더" in the sentence, and said alone the voice
    /// made it "디"): English weak forms and any one- or two-letter word go
    /// with their neighbour — "the road", "to read" — so the drill sounds the
    /// way the sentence does. Every other word is practiced alone.
    static func drillText(for word: String, in sentence: String, language: String) -> String {
        let clean = word.trimmingCharacters(in: .punctuationCharacters)
        let k = key(clean)
        let weak: Set<String> = ["the", "a", "an", "to", "of", "for", "and", "but", "or", "at",
                                 "from", "as", "than", "that", "can", "was", "were", "have",
                                 "has", "had", "do", "does", "you", "your", "them", "her",
                                 "his", "him", "some", "are", "is", "am", "be", "been", "would",
                                 "could", "should", "just", "there", "us", "our"]
        let dependsOnSentence = k.count <= 2
            || (LanguageCatalog.base(language) == "en" && weak.contains(k))
        guard dependsOnSentence else { return clean }
        let words = sentence.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let i = words.firstIndex(where: { key($0) == k }) else { return clean }
        let pair: [String]
        if i + 1 < words.count {
            pair = [words[i], words[i + 1]]
        } else if i > 0 {
            pair = [words[i - 1], words[i]]
        } else {
            return clean
        }
        return pair.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
    }

    /// How a sound came out, read off Azure's list of what it heard
    /// (`Phoneme.heard`). Only for a sound that scored low: a clean sound's
    /// list is noise (a native "drink"'s ɪ had æ on top at 100).
    enum HeardAs: Equatable {
        /// It came out as another sound ("f" → "p").
        case sound(String)
        /// A vowel slipped in with this consonant ("드링크" for "drink").
        case vowelAdded
    }

    static let vowelChars = Set("aeiouɪʊəɛæʌɔɑɒɐɜɝɚy")

    static func heardAs(_ p: PronunciationResult.Phoneme) -> HeardAs? {
        guard let list = p.heard, !list.isEmpty, (p.accuracy ?? 100) < 70 else { return nil }
        let isConsonant = !p.phoneme.contains(where: { vowelChars.contains($0) })
        if let top = list.first, top.phoneme != p.phoneme, top.score >= 70 {
            // A consonant whose top guess is a vowel lost itself to a vowel —
            // say that, not "it sounded like ə".
            let topIsVowel = top.phoneme.contains(where: { vowelChars.contains($0) })
            return isConsonant && topIsVowel ? .vowelAdded : .sound(top.phoneme)
        }
        if isConsonant, list.contains(where: { c in
            c.phoneme.contains(where: { vowelChars.contains($0) }) && c.score >= 60
        }) {
            return .vowelAdded
        }
        return nil
    }

    /// `heardAs` for the sound a verdict named, found in the take.
    static func heardAs(result: PronunciationResult?, word: String, sound: String?) -> HeardAs? {
        guard let sound,
              let w = result?.referenceWords.first(where: { key($0.word) == key(word) }),
              let p = w.phonemes.filter({ $0.phoneme == sound })
                  .min(by: { ($0.accuracy ?? 100) < ($1.accuracy ?? 100) }) else { return nil }
        return heardAs(p)
    }

    /// Whether Azure's phoneme `p` is (or carries) one of the lesson's
    /// sounds — r-coloured vowels ("ɔɹ", "ɝ") carry the r.
    static func isLesson(_ p: String, _ lesson: [String]) -> Bool {
        if lesson.contains(p) { return true }
        if lesson.contains(where: { $0.count == 1 && p.count > 1 && p.contains($0) }) { return true }
        if lesson.contains("ɹ") && (p.contains("ɝ") || p.contains("ɚ")) { return true }
        return false
    }

    /// Words of the sentence the transcript has as a DIFFERENT single word,
    /// in sentence order: the sentence and what was said aligned on their
    /// common words, and a one-for-one gap read as a swap. Unspaced scripts
    /// and uneven gaps ("I'm" for "I am") give nothing.
    static func substitutions(said: String, line: String,
                              language: String) -> [(expected: String, heard: String)] {
        let ref = tokens(line, language: language)
        let hyp = tokens(said, language: language)
        guard ref.count >= 2, hyp.count >= 2 else { return [] }
        let a = ref.map(key), b = hyp.map(key)
        // Longest common subsequence, then walk it.
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var out: [(String, String)] = []
        var i = 0, j = 0
        var gapA: [Int] = [], gapB: [Int] = []
        func add(_ x: Int, _ y: Int) {
            guard !b[y].allSatisfy(\.isNumber) else { return }
            out.append((ref[x].trimmingCharacters(in: .punctuationCharacters),
                        hyp[y].trimmingCharacters(in: .punctuationCharacters)))
        }
        func flush() {
            if gapA.count == gapB.count {
                for (x, y) in zip(gapA, gapB) { add(x, y) }
            } else {
                // Uneven ("need lead" for "need to read"): pair a heard word
                // only with the sentence word it is spelled most like.
                var used = Set<Int>()
                for y in gapB {
                    let best = gapA.filter { !used.contains($0) }
                        .map { ($0, similarity(a[$0], b[y])) }
                        .max { $0.1 < $1.1 }
                    if let best, best.1 >= 0.5 { used.insert(best.0); add(best.0, y) }
                }
            }
            gapA = []; gapB = []
        }
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                flush(); i += 1; j += 1
            } else if j >= b.count || (i < a.count && dp[i + 1][j] >= dp[i][j + 1]) {
                gapA.append(i); i += 1
            } else {
                gapB.append(j); j += 1
            }
        }
        flush()
        return out
    }

    /// Text-only verdict for when no assessment can be had (the reader is
    /// unconfigured or capped): a reading that says the sentence passes.
    /// Words for comparing a reading with its sentence: contractions spelled
    /// out and digits written as words (`ShadowEngine.expandForDiff`), so
    /// "it's" and "it is" are the same reading.
    static func tokens(_ text: String, language: String) -> [String] {
        ShadowEngine.expandForDiff(text, language: language)
            .split(whereSeparator: \.isWhitespace).map(String.init)
            .filter { !key($0).isEmpty }
    }

    /// 1 − edit distance / longer length.
    static func similarity(_ x: String, _ y: String) -> Double {
        let p = Array(x), q = Array(y)
        guard !p.isEmpty || !q.isEmpty else { return 1 }
        var row = Array(0...q.count)
        for i in 1...max(p.count, 1) where !p.isEmpty {
            var prev = row[0]; row[0] = i
            for j in stride(from: 1, through: q.count, by: 1) {
                let cur = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (p[i - 1] == q[j - 1] ? 0 : 1))
                prev = cur
            }
        }
        return 1 - Double(row[q.count]) / Double(max(p.count, q.count))
    }

    static func fallback(line: PronunciationRound.Line, said: String, language: String) -> Verdict {
        guard overlap(said: said, line: line.text) >= 0.85 else { return .offScript }
        let focusKeys = Set(line.focus.map(key))
        if let s = substitutions(said: said, line: line.text, language: language)
            .first(where: { focusKeys.contains(key($0.expected)) }) {
            return .notYet(word: s.expected, sound: nil, score: 0, heard: s.heard)
        }
        return .pass(score: 0)
    }

    /// The weakest named sound in a word, the lesson's own first.
    static func sound(in word: PronunciationResult.Word, preferring: [String]) -> String? {
        let weak = word.weakPhonemes
        return weak.first { preferring.contains($0.phoneme) }?.phoneme ?? weak.first?.phoneme
    }

    private static func rank(_ w: PronunciationResult.Word) -> Int {
        min(w.accuracy ?? 100, w.worstPhoneme ?? 100)
    }

    static func key(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Share of the sentence's letters found in what was said — a reading
    /// of the sentence scores near 1 in any script, another line much lower.
    static func overlap(said: String, line: String) -> Double {
        let a = Array(key(line)), b = key(said)
        guard !a.isEmpty else { return 0 }
        var pool: [Character: Int] = [:]
        for c in b { pool[c, default: 0] += 1 }
        var hit = 0
        for c in a where (pool[c] ?? 0) > 0 {
            pool[c]! -= 1
            hit += 1
        }
        // Letters alone would let an anagram pass; the length check keeps a
        // long ramble that happens to contain the letters from counting.
        let lengthRatio = Double(min(a.count, b.count)) / Double(max(a.count, b.count, 1))
        return Double(hit) / Double(a.count) * min(1, lengthRatio + 0.3)
    }
}

// MARK: - Notes

/// What the app tells the voice after each take (`RealtimeTalkClient.nudge`).
/// English instructions; the model speaks the target language.
enum PronunciationNotes {
    static func systemPrompt(target: String, level: CEFRLevel,
                             round: PronunciationRound?, planning: Bool) -> String {
        let lang = LanguageCatalog.englishName(target)
        var now = ""
        if let round {
            now = "\nToday's sound: \(round.topic.symbol) — \(round.topic.english)."
            if let i = round.current, let word = round.lines[i].drillWord {
                now += "\nTheir screen now shows ONLY the word \"\(word)\": they are practicing it on its own, out of the sentence \"\(round.lines[i].text)\"."
            } else if let i = round.current {
                now += "\nThe sentence on their screen now: \"\(round.lines[i].text)\"."
            } else {
                now += "\nThe round is finished."
            }
        } else if planning {
            now = "\nThe sentences are being prepared; there is nothing on their screen yet."
        }
        return """
        You are the learner's fluent self: them, a few years on, speaking \
        \(lang) fluently, in their own voice. This call is PRONUNCIATION \
        PRACTICE, not a conversation. Their screen shows one \(lang) sentence \
        at a time in big letters; they read it aloud, and the APP listens and \
        decides how it went. You never judge a line yourself, never correct \
        grammar or word choice, and never ask about their life.

        HOW YOU SPEAK
        - \(lang) only, the simplest words (they are around CEFR \
          \(level.rawValue.uppercased())), short sentences, warm and calm, \
          like a friend. Informal.
        - Each of your lines answers ONE note from the app. Do exactly what \
          the note says and nothing more. Keep it SHORT: a few words is a \
          whole line here. Never explain how to make a sound — the tip is \
          on their screen.
        - When you say a word or a sentence for them to copy, say it clearly \
          at a natural pace. Never spell it, never cut it into letters or \
          syllables, no symbols, nothing in brackets.
        - "Perfect", "great", "well done" only when the note says PASSED.
        - If they say something that isn't the sentence ("this is hard", a \
          question), answer it in a few words and bring them back to the \
          sentence on their screen.
        \(now)
        """
    }

    static func ready(_ round: PronunciationRound, first: Bool) -> String {
        let intro = first
            ? "No greeting. In one short sentence say today's sound is \"\(round.topic.symbol)\", as in \(round.topic.examples)."
            : "Say in a few words that the new sentences for \"\(round.topic.symbol)\" are ready."
        return "\(intro) Then ask them to read the first sentence on their screen out loud. Don't read it for them."
    }

    static func preparing(_ topic: PronunciationCourse.Topic, picked: Bool) -> String {
        picked
            ? "They picked a new sound on their screen: \"\(topic.symbol)\" (\(topic.examples)). Say in a few words that you're getting the sentences ready — nothing else."
            : "Say hi in a few words and that you're getting today's sentences ready — nothing else."
    }

    // Every line below is SHORT and set by the app (founder, 2026-11-04:
    // "the retry lines are too long — that's all cost, and it says the same
    // thing every time"). Each note is a fresh generation and a fresh
    // synthesis, and the fluent self's seconds are the learner's talk time,
    // so a retry is a few words: the word, said right, and "again". How to
    // make the sound is on the card, in their own language — the voice does
    // not explain it again.
    private static func only(_ example: String, max words: Int) -> String {
        "Say ONLY this, in the call's language, at most \(words) words, nothing before or after it: \"\(example)\""
    }

    // A pass is said many times a call, and one fixed line ("Yes! Next
    // one.") was heard on every one (founder, 2026-11-04). The reaction
    // rotates, never the same twice in a row, and fits HOW it passed: right
    // away, after misses, or cleanly. Still a few words: it is talk time.
    nonisolated(unsafe) private static var lastReaction: String?

    private static func reaction(_ pool: [String]) -> String {
        let pick = pool.filter { $0 != lastReaction }.randomElement() ?? pool[0]
        lastReaction = pick
        return pick
    }

    static func passed(score: Int, next: PronunciationRound.Line?, round: PronunciationRound,
                       afterMisses: Bool = false) -> String {
        if next != nil {
            let pool: [String]
            if afterMisses {
                pool = ["There it is! Next one.", "You got it! Next.", "That's the one! Next.",
                        "Yes, much better! Next one.", "Nailed it this time. Next."]
            } else if score >= 90 {
                pool = ["Perfect! Next one.", "Spot on. Next.", "Beautiful! Next one.",
                        "First try, perfect! Next.", "Wow, clean! Next one."]
            } else {
                pool = ["Yes! Next one.", "Good! Next.", "Nice, that works. Next.",
                        "Well done! Next one.", "Great. On to the next."]
            }
            return "Result: PASSED. " + only(reaction(pool), max: 6)
        }
        return "Result: PASSED — the last sentence of the round (\(round.passedCount) of \(round.sentenceCount) passed). In one or two short sentences: the round is done; another round of this sound, or a different one with the button on their screen?"
    }

    /// The sentence missed on `word`: the screen now shows that word alone.
    static func notYet(word: String, sound: String?, heard: String?,
                       topic: PronunciationCourse.Topic, sentence: String,
                       heardAs: PronunciationJudge.HeardAs? = nil) -> String {
        if let sound, let heardAs {
            let how: String
            switch heardAs {
            case .sound(let other):
                how = "Your \"\(sound)\" in \"\(word)\" came out like \"\(other)\""
            case .vowelAdded:
                how = "A little vowel slipped in at \"\(sound)\" in \"\(word)\" — it should be one tight sound"
            }
            return "Result: NOT YET. Say ONLY this, in the call's language, in at most 16 words: \(how); then \"\(word.capitalized). \(word.capitalized). Just this.\"" + asInSentence
        }
        if let heard {
            return "Result: NOT YET. " + only("Sounded like \(heard). \(word.capitalized). \(word.capitalized). Just this.", max: 12)
                + Self.asInSentence
        }
        return "Result: NOT YET. " + only("Not yet. \(word.capitalized). \(word.capitalized). Just this.", max: 12)
            + Self.asInSentence
    }

    static func wordAgain(word: String, sound: String?, topic: PronunciationCourse.Topic,
                          withTip: Bool) -> String {
        guard withTip else { return "Result: NOT YET. " + only("Again. \(word.capitalized).", max: 6) + Self.asInSentence }
        let which = sound.map { " (its \"\($0)\" sound)" } ?? ""
        return "Result: NOT YET, several tries now. \"\(word)\"\(which): give ONE different short tip on how to make it (today's sound: \(topic.english)), at most 10 words, then say \"\(word)\" once, clearly, and \"again\". At most 20 words in all."
    }

    /// Said alone, a word can lose the sound it has in the sentence ("the"
    /// becomes "thee"); the voice says it the sentence's way.
    static let asInSentence = " Say it exactly the way it sounds inside the sentence on their screen (a reduced \"the\" stays \"thuh\" before a consonant), never a careful dictionary form."

    static func wordPassed(word: String) -> String {
        "Result: PASSED. " + only(reaction(["Yes! Now the whole sentence.",
                                            "That's it! Now the sentence.",
                                            "Good! Back to the whole sentence.",
                                            "There it is. Now all of it.",
                                            "Nice! Now read the sentence."]), max: 7)
    }

    /// Back to the sentence after the word's tries ran out: say what is
    /// still off and how to fix it, never just move on.
    static func wordBack(word: String, sound: String?, topic: PronunciationCourse.Topic) -> String {
        let which = sound.map { " (its \"\($0)\" sound)" } ?? ""
        return "They chose to go back to the sentence. \"\(word)\"\(which) isn't there yet — that's fine. Give ONE short tip on how to make it (today's sound: \(topic.english)), at most 10 words, say \"\(word)\" once, clearly, then: now the whole sentence. At most 25 words in all."
    }

    static func wordOffScript(word: String) -> String {
        only("Just the word: \(word).", max: 5)
    }

    static func notSmooth(sentence: String) -> String {
        "Result: NOT YET (it stopped and started). " + only("Good sounds. Once more, without stopping.", max: 7)
    }

    /// The learner skipping a sentence (founder, 2026-11-04: "'tricky
    /// one' and moving on with no explanation is the worst"). Always: what
    /// wasn't there, one tip, the word said right, and WHEN it comes back.
    /// `laterInRound`: it went to the end of this round; else its word is
    /// kept for the next round on this sound.
    static func moveOn(word: String?, sound: String?, topic: PronunciationCourse.Topic,
                       next: PronunciationRound.Line?, round: PronunciationRound,
                       laterInRound: Bool) -> String {
        let what: String
        if let word {
            let which = sound.map { " — its \"\($0)\" sound" } ?? ""
            what = "Say which word isn't there yet: \"\(word)\"\(which). Give ONE short tip on how to make it (today's sound: \(topic.english)), at most 10 words, and say \"\(word)\" once, clearly."
        } else {
            what = "Say every sound was right, but the reading kept stopping: slowly is fine, just no stops."
        }
        let when = laterInRound ? "it comes back at the end of this round" : "it'll be in the next round"
        let after = next == nil
            ? "Then: the round is done — another round of this sound, or a different one with the button on their screen?"
            : "Then: the next sentence is on their screen."
        return "They chose to move on to the next sentence. Explain, then move on — never just \"tricky one\". \(what) Say \(when). \(after) At most 40 words in all."
    }

    static func offScript(said: String) -> String {
        "They didn't read it (they said: \"\(said)\"). Answer in at most one short sentence, then ask them to read what's on their screen."
    }

    static let unheard = only("Sorry, once more?", max: 4)

    static let planFailed = "Getting the sentences didn't work. Say sorry in a few words and ask them to pick a sound with the button on their screen."

    static let unclearNext = "Ask them, in one short question: another round of this sound, or a different sound? (The button on their screen has the sounds.)"

    static let goodbye = "They're done for today. Say a warm, short goodbye and that they can hang up whenever they like."
}
