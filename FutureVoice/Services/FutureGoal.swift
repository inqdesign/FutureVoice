import Foundation

/// What the learner's fluent self already DOES — picked once in setup
/// ("Imagine your future", 2026-10-28, founder: "those are the real goal, the
/// model should really keep them"). Each purpose offers two or three; the
/// learner ticks as many as they like (a cap of three lived an hour; founder:
/// "I don't see any good reason why we are limiting it").
///
/// Stored as ids on `UserPersona.goals`, never as text: the label follows the
/// app language, the prompt reads `promptText`, and an id from a newer build
/// that this one doesn't know is simply skipped. Never shown to strangers —
/// nothing that writes the public intro or a cast counterpart's block reads
/// it.
enum FutureGoal: String, CaseIterable, Codable, Identifiable {
    case startOrder = "start.order"
    case startChat = "start.chat"
    case hobbyLikes = "hobby.likes"
    case hobbyNoSubs = "hobby.noSubs"
    case hobbyFriends = "hobby.friends"
    case examScore = "exam.score"
    case examCalm = "exam.calm"
    case studySeminar = "study.seminar"
    case studyPresent = "study.present"
    case jobInterview = "job.interview"
    case jobOffer = "job.offer"
    case workMeetings = "work.meetings"
    case workClients = "work.clients"
    case workBanter = "work.banter"
    case abroadErrands = "abroad.errands"
    case abroadNeighbors = "abroad.neighbors"
    case abroadHome = "abroad.home"
    case travelAlone = "travel.alone"
    case travelLocals = "travel.locals"

    var id: String { rawValue }

    var purpose: LearningPurpose {
        switch self {
        case .startOrder, .startChat: return .start
        case .hobbyLikes, .hobbyNoSubs, .hobbyFriends: return .hobby
        case .examScore, .examCalm: return .exam
        case .studySeminar, .studyPresent: return .study
        case .jobInterview, .jobOffer: return .job
        case .workMeetings, .workClients, .workBanter: return .work
        case .abroadErrands, .abroadNeighbors, .abroadHome: return .abroad
        case .travelAlone, .travelLocals: return .travel
        }
    }

    static func options(for purpose: LearningPurpose) -> [FutureGoal] {
        allCases.filter { $0.purpose == purpose }
    }

    /// First person, present tense: the future already lived.
    var title: String {
        switch self {
        case .startOrder:      return explain("I order and ask for things without freezing")
        case .startChat:       return explain("I keep a simple conversation going")
        case .hobbyLikes:      return explain("I talk about what I love for as long as I want")
        case .hobbyNoSubs:     return explain("I watch shows without subtitles")
        case .hobbyFriends:    return explain("I have friends I chat with in the language")
        case .examScore:       return explain("I got the score I needed")
        case .examCalm:        return explain("I answer the speaking test calmly")
        case .studySeminar:    return explain("I speak up in seminars")
        case .studyPresent:    return explain("I present my work with confidence")
        case .jobInterview:    return explain("I tell my story in interviews without freezing")
        case .jobOffer:        return explain("I got the job I wanted")
        case .workMeetings:    return explain("I lead meetings")
        case .workClients:     return explain("Client calls don't make me nervous")
        case .workBanter:      return explain("I joke around with my colleagues")
        case .abroadErrands:   return explain("I handle the doctor, the landlord and the town hall myself")
        case .abroadNeighbors: return explain("I chat easily with neighbors and other parents")
        case .abroadHome:      return explain("This place feels like home")
        case .travelAlone:     return explain("I travel on my own without worrying")
        case .travelLocals:    return explain("I talk with locals, not just order")
        }
    }

    /// What the fluent self is told. English: prompts are English, and the
    /// language name is filled in by the caller.
    func promptText(languageName: String) -> String {
        switch self {
        case .startOrder:      return "orders and asks for things in \(languageName) without freezing"
        case .startChat:       return "keeps a simple conversation going in \(languageName)"
        case .hobbyLikes:      return "talks about what they love in \(languageName) for as long as they want"
        case .hobbyNoSubs:     return "watches shows in \(languageName) without subtitles"
        case .hobbyFriends:    return "has friends they chat with in \(languageName)"
        case .examScore:       return "got the score they needed on their \(languageName) exam"
        case .examCalm:        return "answers the \(languageName) speaking test calmly"
        case .studySeminar:    return "speaks up in seminars in \(languageName)"
        case .studyPresent:    return "presents their own work in \(languageName) with confidence"
        case .jobInterview:    return "tells their story in job interviews in \(languageName) without freezing"
        case .jobOffer:        return "got the job they wanted, one that runs in \(languageName)"
        case .workMeetings:    return "leads meetings at work in \(languageName)"
        case .workClients:     return "takes client calls in \(languageName) without getting nervous"
        case .workBanter:      return "jokes around with colleagues in \(languageName)"
        case .abroadErrands:   return "handles the doctor, the landlord and the town hall in \(languageName) on their own"
        case .abroadNeighbors: return "chats easily in \(languageName) with neighbors and other parents"
        case .abroadHome:      return "feels at home where they live, in \(languageName)"
        case .travelAlone:     return "travels on their own in \(languageName) without worrying"
        case .travelLocals:    return "has real conversations with locals in \(languageName), not just orders"
        }
    }

    /// Ids on disk → goals this build knows, in the order ticked.
    static func decode(_ ids: [String]) -> [FutureGoal] {
        ids.compactMap(FutureGoal.init(rawValue:))
    }
}

/// The goals picked in setup, held until the persona exists (it is written
/// one step later, by the persona cards) — `AppState.savePersona` moves them
/// onto it.
enum FutureGoalStore {
    private static let key = "futurevoice.pendingFutureGoals"

    static var pending: [FutureGoal] {
        get { FutureGoal.decode(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set {
            if newValue.isEmpty { UserDefaults.standard.removeObject(forKey: key) }
            else { UserDefaults.standard.set(newValue.map(\.rawValue), forKey: key) }
        }
    }
}
