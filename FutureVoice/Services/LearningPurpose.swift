import Foundation
import SwiftUI

/// Why the learner is learning — asked once in setup, MANY answers allowed,
/// in the order they were picked (founder, 2026-10-11). The answer shapes
/// two things and nothing else:
///
/// - **Talk's chip row** (`DiscoverSection`): which chips there are and in
///   what order. Each purpose leads with its own chip (exam topics, interview
///   questions, work situations…), the first purpose picked is the chip the
///   row opens on, and news + the learner's own situations follow. A learner
///   who never answered keeps the row they always had.
/// - **The first routine** (`RoutineRecipe`): a week built for those purposes,
///   shown at the end of setup with every time editable, instead of the plain
///   "talk X minutes a day".
///
/// No exam date, no target score (founder: "don't make it complicated") —
/// which exam is a filter on the Exam chip, not a setup question.
enum LearningPurpose: String, CaseIterable, Codable, Identifiable {
    case start, hobby, exam, study, job, work, abroad, travel
    var id: String { rawValue }

    var title: String {
        switch self {
        case .start:  return explain("I want to start speaking")
        case .hobby:  return explain("For fun")
        case .exam:   return explain("For an exam")
        case .study:  return explain("For my studies")
        case .job:    return explain("For a job hunt")
        case .work:   return explain("I need it at work")
        case .abroad: return explain("I live abroad")
        case .travel: return explain("For travel")
        }
    }

    var subtitle: String {
        switch self {
        case .start:  return explain("Words don't come out yet")
        case .hobby:  return explain("Talk about what I like")
        case .exam:   return explain("IELTS, OPIc, TOEIC Speaking…")
        case .study:  return explain("Seminars, presentations, my subject")
        case .job:    return explain("Interviews, the field I'm applying to")
        case .work:   return explain("Meetings, presentations, client calls")
        case .abroad: return explain("Landlord, town hall, doctor, my kid's school")
        case .travel: return explain("Airport, hotel, restaurants")
        }
    }

    /// Read before the words: a glyph on its own colour, Settings-style.
    var symbol: String {
        switch self {
        case .start:  return "bubble.left.and.bubble.right.fill"
        case .hobby:  return "heart.fill"
        case .exam:   return "checklist"
        case .study:  return "graduationcap.fill"
        case .job:    return "person.text.rectangle.fill"
        case .work:   return "briefcase.fill"
        case .abroad: return "house.fill"
        case .travel: return "airplane"
        }
    }

    /// System colours only, and never indigo (the Core's).
    var tint: Color {
        switch self {
        case .start:  return .blue
        case .hobby:  return .pink
        case .exam:   return .orange
        case .study:  return .teal
        case .job:    return .purple
        case .work:   return .brown
        case .abroad: return .green
        case .travel: return .cyan
        }
    }

    /// The chip this purpose puts first.
    var leadChip: DiscoverChip {
        switch self {
        case .start:  return .everyday
        case .hobby:  return .news
        case .exam:   return .exam
        case .study:  return .study
        case .job:    return .interview
        case .work:   return .work
        case .abroad: return .life
        case .travel: return .travel
        }
    }
}

/// One chip on Talk's discover row.
enum DiscoverChip: String, CaseIterable, Identifiable {
    case exam, study, interview, work, life, travel, everyday, news, scenarios
    var id: String { rawValue }

    var label: String {
        switch self {
        case .exam:      return chrome("Exam")
        case .study:     return chrome("Studies")
        case .interview: return chrome("Interview")
        case .work:      return chrome("Work")
        case .life:      return chrome("Life")
        case .travel:    return chrome("Travel")
        case .everyday:  return chrome("Everyday")
        case .news:      return chrome("News")
        case .scenarios: return chrome("Scenarios")
        }
    }

    /// The ready-made situations behind a situation chip.
    var starters: [StarterSituation]? {
        switch self {
        case .everyday:  return StarterSituation.all
        case .interview: return StarterSituation.interview
        case .work:      return StarterSituation.work
        case .life:      return StarterSituation.life
        case .travel:    return StarterSituation.travel
        case .exam, .study, .news, .scenarios: return nil
        }
    }
}

enum LearningPurposeStore {
    private static let key = "futurevoice.learningPurposes"
    private static let examKey = "futurevoice.examKind"
    /// Setup saved the suggested week — the call's own setup then keeps its
    /// times instead of collapsing them to one.
    static let routineAppliedKey = "futurevoice.routineFromPurpose"

    /// What the learner wrote under a purpose — the school and subject, the
    /// job and their role in it, the role they're applying for. Each is
    /// optional; a filled one turns its chip's topics into topics of THAT
    /// field (`PurposeTopicEngine`).
    static var details: PurposeDetails {
        get {
            UserDefaults.standard.data(forKey: detailsKey)
                .flatMap { try? JSONDecoder().decode(PurposeDetails.self, from: $0) } ?? PurposeDetails()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: detailsKey) }
    }
    private static let detailsKey = "futurevoice.purposeDetails"

    /// In the order picked. Empty = never asked (every install before this).
    static var purposes: [LearningPurpose] {
        get {
            Array((UserDefaults.standard.stringArray(forKey: key) ?? [])
                .compactMap(LearningPurpose.init(rawValue:)).prefix(3))
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue), forKey: key) }
    }

    /// The exam picked in the Exam chip's filter, for this target language.
    static func exam(for language: String) -> ExamKind {
        let options = ExamKind.options(for: language)
        let saved = UserDefaults.standard.string(forKey: examKey + "." + LanguageCatalog.base(language))
        return options.first { $0.rawValue == saved } ?? options[0]
    }

    static func setExam(_ exam: ExamKind, for language: String) {
        UserDefaults.standard.set(exam.rawValue, forKey: examKey + "." + LanguageCatalog.base(language))
    }

    /// Talk's chips: each purpose's own chip in the order picked, then news
    /// and the learner's own situations. A beginner who picked "for fun"
    /// gets the everyday starters too — news alone asks too much of A1/A2.
    static func chips(level: CEFRLevel) -> [DiscoverChip] {
        let picked = purposes
        guard !picked.isEmpty else { return [.news, .everyday, .scenarios] }
        var out: [DiscoverChip] = []
        func add(_ c: DiscoverChip) { if !out.contains(c) { out.append(c) } }
        picked.forEach { add($0.leadChip) }
        add(.news)
        if picked.contains(.hobby), [.a1, .a2].contains(level) { add(.everyday) }
        add(.scenarios)
        return out
    }
}

// MARK: - Exams

/// Speaking exams per target language. A language with none of its own falls
/// back to OPIc, which is offered in most.
enum ExamKind: String, CaseIterable, Identifiable {
    case ielts, toefl, opic, toeicSpeaking, goethe, telc, topik, bjt, dele, siele
    var id: String { rawValue }

    var name: String {
        switch self {
        case .ielts: return "IELTS"
        case .toefl: return "TOEFL"
        case .opic: return "OPIc"
        case .toeicSpeaking: return "TOEIC Speaking"
        case .goethe: return "Goethe-Zertifikat"
        case .telc: return "telc"
        case .topik: return "TOPIK"
        case .bjt: return "BJT"
        case .dele: return "DELE"
        case .siele: return "SIELE"
        }
    }

    static func options(for language: String) -> [ExamKind] {
        switch LanguageCatalog.base(language) {
        case "en": return [.ielts, .toefl, .opic, .toeicSpeaking]
        case "de": return [.goethe, .telc, .opic]
        case "ko": return [.topik, .opic]
        case "ja": return [.opic, .bjt]
        case "es": return [.dele, .siele, .opic]
        default:   return [.opic]
        }
    }
}

/// One common exam question, talked through with the fluent self.
struct ExamTopic: Identifiable, Hashable {
    var id: String { title }
    let title: String
    /// "Part 2", "Task 1" — shown beside the exam's name.
    let part: String
    /// A cue card's bullet points, when the exam gives them.
    var points: [String] = []

    /// What the call is told: the exam, the part, the question. The fluent
    /// self asks it the way the exam would, then talks it through.
    func callBlurb(exam: ExamKind) -> String {
        var s = "Speaking practice for the \(exam.name) exam. This is a common \(part) question: \"\(title)\"."
        if !points.isEmpty { s += " The cue card asks them to cover: " + points.joined(separator: "; ") + "." }
        s += " Ask it the way the examiner would, let the learner do most of the talking, and follow up on what they say — one question at a time. Never score them."
        return s
    }
}

enum ExamTopics {
    static func topics(for exam: ExamKind, language: String) -> [ExamTopic] {
        switch exam {
        case .ielts:
            return [
                ExamTopic(title: "Describe a skill you learned as an adult", part: "Part 2",
                          points: ["what the skill is", "how you learned it", "how long it took you", "why you decided to learn it"]),
                ExamTopic(title: "Your hometown", part: "Part 1"),
                ExamTopic(title: "Should children have smartphones?", part: "Part 3"),
                ExamTopic(title: "Describe a time you helped a stranger", part: "Part 2",
                          points: ["who the person was", "what happened", "how you helped", "how you felt afterwards"]),
                ExamTopic(title: "Work or study", part: "Part 1"),
                ExamTopic(title: "Is public transport worth what it costs?", part: "Part 3"),
                ExamTopic(title: "Describe a place you would like to visit", part: "Part 2",
                          points: ["where it is", "how you know about it", "what you would do there", "why you want to go"]),
                ExamTopic(title: "How you spend your weekends", part: "Part 1"),
                ExamTopic(title: "Will robots replace teachers?", part: "Part 3"),
                ExamTopic(title: "Describe a book or film that changed your mind", part: "Part 2",
                          points: ["what it was", "when you read or saw it", "what it was about", "how it changed your view"]),
                ExamTopic(title: "Music in your life", part: "Part 1"),
                ExamTopic(title: "Do cities need more green space?", part: "Part 3"),
            ]
        case .toefl:
            return [
                ExamTopic(title: "Is it better to study alone or in a group?", part: "Task 1"),
                ExamTopic(title: "Should university attendance be required?", part: "Task 1"),
                ExamTopic(title: "Working from home or at the office — which do you prefer?", part: "Task 1"),
                ExamTopic(title: "Is it better to live in a dorm or off campus?", part: "Task 1"),
                ExamTopic(title: "Should students take a gap year?", part: "Task 1"),
                ExamTopic(title: "A big decision you made recently", part: "Task 1"),
            ]
        case .opic:
            switch LanguageCatalog.base(language) {
            case "ja":
                return [
                    ExamTopic(title: "あなたの住んでいる家について話してください", part: "Survey"),
                    ExamTopic(title: "最近行った旅行について", part: "Survey"),
                    ExamTopic(title: "週末によくすること", part: "Survey"),
                    ExamTopic(title: "よく行くカフェについて", part: "Survey"),
                    ExamTopic(title: "予約が取れなかったときの対応", part: "Role-play"),
                ]
            case "es":
                return [
                    ExamTopic(title: "Describa su casa", part: "Survey"),
                    ExamTopic(title: "Su último viaje", part: "Survey"),
                    ExamTopic(title: "¿Qué hace normalmente los fines de semana?", part: "Survey"),
                    ExamTopic(title: "Una cafetería a la que va a menudo", part: "Survey"),
                    ExamTopic(title: "Llame a una tienda por un producto que llegó roto", part: "Role-play"),
                ]
            case "de":
                return [
                    ExamTopic(title: "Beschreiben Sie Ihre Wohnung", part: "Survey"),
                    ExamTopic(title: "Ihre letzte Reise", part: "Survey"),
                    ExamTopic(title: "Was machen Sie am Wochenende?", part: "Survey"),
                    ExamTopic(title: "Ein Problem im Restaurant lösen", part: "Role-play"),
                ]
            default:
                return [
                    ExamTopic(title: "Describe your home", part: "Survey"),
                    ExamTopic(title: "Your most recent trip", part: "Survey"),
                    ExamTopic(title: "What you usually do on weekends", part: "Survey"),
                    ExamTopic(title: "A café you often go to", part: "Survey"),
                    ExamTopic(title: "Your favourite park and what you do there", part: "Survey"),
                    ExamTopic(title: "Call a store about a broken item", part: "Role-play"),
                    ExamTopic(title: "A time something went wrong on a trip", part: "Unexpected"),
                ]
            }
        case .toeicSpeaking:
            return [
                ExamTopic(title: "Your ideal workplace", part: "Express an opinion"),
                ExamTopic(title: "Should companies let employees work from home?", part: "Express an opinion"),
                ExamTopic(title: "A survey about your commute", part: "Respond to questions"),
                ExamTopic(title: "A survey about shopping habits", part: "Respond to questions"),
                ExamTopic(title: "Is it better to have one long vacation or several short ones?", part: "Express an opinion"),
            ]
        case .goethe:
            return [
                ExamTopic(title: "Stellen Sie sich vor", part: "Teil 1"),
                ExamTopic(title: "Sollen Kinder ein eigenes Handy haben?", part: "Teil 2"),
                ExamTopic(title: "Eine Feier gemeinsam planen", part: "Teil 1"),
                ExamTopic(title: "Wohnen in der Stadt oder auf dem Land?", part: "Teil 2"),
                ExamTopic(title: "Homeoffice — Vor- und Nachteile", part: "Teil 2"),
                ExamTopic(title: "Ein Ausflug mit dem Sprachkurs", part: "Teil 1"),
            ]
        case .telc:
            return [
                ExamTopic(title: "Über sich selbst sprechen", part: "Teil 1"),
                ExamTopic(title: "Ein Foto beschreiben: Freizeit", part: "Teil 2"),
                ExamTopic(title: "Gemeinsam etwas planen: ein Geschenk", part: "Teil 3"),
            ]
        case .topik:
            return [
                ExamTopic(title: "자기소개를 해 보세요", part: "1번"),
                ExamTopic(title: "주말에 보통 무엇을 해요?", part: "2번"),
                ExamTopic(title: "식당에서 주문이 잘못 나왔을 때", part: "3번"),
                ExamTopic(title: "온라인 수업과 교실 수업, 어느 쪽이 좋아요?", part: "5번"),
                ExamTopic(title: "도시에 사는 것의 장점과 단점", part: "6번"),
            ]
        case .bjt:
            return [
                ExamTopic(title: "取引先に納期の遅れを伝える", part: "Business"),
                ExamTopic(title: "上司に休みを相談する", part: "Business"),
                ExamTopic(title: "新しい企画を短く説明する", part: "Business"),
            ]
        case .dele:
            return [
                ExamTopic(title: "Hable de una persona que ha sido importante en su vida", part: "Tarea 1",
                          points: ["quién es", "cómo la conoció", "qué ha aprendido de ella"]),
                ExamTopic(title: "Describa una fotografía: una familia en un parque", part: "Tarea 2"),
                ExamTopic(title: "Organice con un amigo una cena para celebrar algo", part: "Tarea 3"),
                ExamTopic(title: "¿Es mejor vivir en el centro o en las afueras?", part: "Tarea 1",
                          points: ["ventajas", "inconvenientes", "su preferencia y por qué"]),
                ExamTopic(title: "Describa una fotografía: personas trabajando en una oficina", part: "Tarea 2"),
                ExamTopic(title: "Quéjese en un hotel porque la habitación no es la que reservó", part: "Tarea 3"),
            ]
        case .siele:
            return [
                ExamTopic(title: "Preséntese: dónde vive, a qué se dedica y por qué estudia español", part: "Tarea 1"),
                ExamTopic(title: "Describa una foto: una calle llena de gente", part: "Tarea 2"),
                ExamTopic(title: "Llame a un compañero para cambiar el día de una reunión", part: "Tarea 3"),
                ExamTopic(title: "Cuente una experiencia que le hizo cambiar de opinión", part: "Tarea 4"),
                ExamTopic(title: "¿Deberían los estudiantes llevar uniforme? Dé su opinión", part: "Tarea 5"),
            ]
        }
    }
}

// MARK: - The first routine

/// The week a learner's purposes suggest, built from ordinary plan blocks so
/// everything after setup (the timetable, the daily call, the reminders, the
/// promise) treats it like any routine. Each block carries a one-line WHY,
/// shown only in setup — that line is what makes it read as picked for them.
enum RoutineRecipe {
    struct Line: Identifiable {
        var block: StudyPlan.Block
        var why: String
        var id: UUID { block.id }
    }

    static func lines(for purposes: [LearningPurpose], goalMinutes: Int) -> [Line] {
        let minutes = max(5, goalMinutes)
        let everyDay = Set(1...7)
        let mwf: Set<Int> = [2, 4, 6]
        var out: [Line] = []
        let picked = purposes.isEmpty ? [LearningPurpose.start] : purposes
        // De-duplicate by chip: two purposes sharing a chip share a talk.
        var leads: [LearningPurpose] = []
        for p in picked where !leads.contains(where: { $0.leadChip == p.leadChip }) { leads.append(p) }

        // Talks: the first purpose every day (a hobby, four evenings), the
        // second Tue/Thu evening, a third Saturday late morning.
        let slots: [(Set<Int>, Int, Int)] = [(everyDay, 8, 0), ([3, 5], 20, 0), ([7], 11, 0)]
        for (i, p) in leads.prefix(3).enumerated() {
            var (days, h, m) = slots[i]
            if i == 0, p == .hobby { days = [2, 4, 6, 7]; h = 19 }
            out.append(Line(block: StudyPlan.Block(kind: .talk, weekdays: days, hour: h, minute: m, minutes: minutes),
                            why: talkWhy(p)))
        }

        // Say it again right after the first talk: every day for someone
        // starting out (repetition is the whole method), else Mon/Wed/Fri.
        if let first = out.first?.block {
            let end = first.startMinute + minutes
            let days = picked.first == .start ? first.weekdays : first.weekdays.intersection(mwf)
            if end + StudyPlan.sayItAgainMinutes <= 24 * 60, !days.isEmpty {
                out.append(Line(block: StudyPlan.Block(kind: .sayItAgain, weekdays: days, hour: end / 60,
                                                       minute: end % 60, minutes: 1),
                                why: explain("That day's talk, said the way it should have gone")))
            }
        }

        // Review: every evening, or three for a hobby.
        let reviewDays = picked == [.hobby] ? mwf : everyDay
        out.append(Line(block: StudyPlan.Block(kind: .review, weekdays: reviewDays, hour: 21, minute: 30,
                                               minutes: StudyPlan.Kind.review.defaultAmount),
                        why: explain("The sentences your talks corrected")))

        // A speech for purposes that end in speaking alone to someone.
        if picked.contains(.job) {
            out.append(Line(block: StudyPlan.Block(kind: .speech, weekdays: [1], hour: 19, minute: 0, minutes: 1),
                            why: explain("Polish your one-minute self-introduction")))
        } else if picked.contains(.work) {
            out.append(Line(block: StudyPlan.Block(kind: .speech, weekdays: [6], hour: 18, minute: 0, minutes: 1),
                            why: explain("A short update, the way you'd give it in a meeting")))
        } else if picked.contains(.exam) {
            out.append(Line(block: StudyPlan.Block(kind: .speech, weekdays: [1], hour: 19, minute: 0, minutes: 1),
                            why: explain("Two minutes on one topic, without stopping")))
        }
        return out
    }

    private static func talkWhy(_ p: LearningPurpose) -> String {
        switch p {
        case .start:  return explain("Everyday chip · a café, asking the way, a neighbor")
        case .hobby:  return explain("News chip · stories on what you're into")
        case .exam:   return explain("Exam chip · topics the exam keeps asking")
        case .study:  return explain("Studies chip · topics from your subject")
        case .job:    return explain("Interview chip · about yourself, why this job")
        case .work:   return explain("Work chip · meetings, presentations, client calls")
        case .abroad: return explain("Life chip · landlord, town hall, doctor")
        case .travel: return explain("Travel chip · airport, hotel, restaurants")
        }
    }

    static func headline(for purposes: [LearningPurpose]) -> String {
        switch purposes.first ?? .start {
        case .start:  return explain("A week to get you talking")
        case .hobby:  return explain("A week of talking about what you love")
        case .exam:   return explain("A week of exam practice")
        case .study:  return explain("A week of talking about what you study")
        case .job:    return explain("A week to get interview-ready")
        case .work:   return explain("A week of the talk you need at work")
        case .abroad: return explain("A week of handling life where you live")
        case .travel: return explain("A week to get ready for your trip")
        }
    }

    /// The plan to save: these blocks, a promise from today like the plain
    /// seeded routine.
    static func plan(from lines: [Line], now: Date = Date()) -> StudyPlan {
        var plan = StudyPlan()
        plan.blocks = lines.map(\.block)
        plan.streakSince = Calendar.current.startOfDay(for: now)
        plan.unitsVersion = 2
        return plan
    }
}

struct PurposeDetails: Codable, Equatable {
    var school = ""
    var subject = ""
    var job = ""
    var role = ""
    var target = ""
}
