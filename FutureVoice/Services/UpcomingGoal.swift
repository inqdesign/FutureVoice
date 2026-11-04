import Foundation
import SwiftUI

/// Something real the learner is preparing for: an exam on a date, an
/// interview at a company, a presentation, a move (2026-10-30, founder: "the
/// exam, when it is; the interview, where it is; all of it in one place, and
/// the tutor builds its content from it"). `LearningPurpose` says WHY they
/// learn and `FutureGoal` what the fluent self already does; this is the
/// dated, named thing in between, and the tutor bot reads it.
///
/// Kept in its own file and its own sync kind, never on `UserPersona`: an
/// older build that saves the profile re-encodes it without the fields it
/// doesn't know, and the newer `updatedAt` would win, erasing the goals.
struct UpcomingGoal: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case interview, exam, presentation, move, trip, other
        var id: String { rawValue }

        var label: String {
            switch self {
            case .interview:    return explain("Interview")
            case .exam:         return explain("Exam")
            case .presentation: return explain("Presentation")
            case .move:         return explain("Moving")
            case .trip:         return explain("Trip")
            case .other:        return explain("Something else")
            }
        }

        var symbol: String {
            switch self {
            case .interview:    return "person.text.rectangle.fill"
            case .exam:         return "checklist"
            case .presentation: return "person.wave.2.fill"
            case .move:         return "house.fill"
            case .trip:         return "airplane"
            case .other:        return "star.fill"
            }
        }

        var tint: Color {
            switch self {
            case .interview:    return .purple
            case .exam:         return .orange
            case .presentation: return .teal
            case .move:         return .green
            case .trip:         return .cyan
            case .other:        return .blue
            }
        }

        /// The purpose this goal is a case of — saving the goal turns it on.
        var purpose: LearningPurpose? {
            switch self {
            case .interview:    return .job
            case .exam:         return .exam
            case .presentation: return .work
            case .move:         return .abroad
            case .trip:         return .travel
            case .other:        return nil
            }
        }

        /// The profile's row for a purpose with no goal of this kind yet.
        var addPrompt: String {
            switch self {
            case .interview:    return explain("Add your interview")
            case .exam:         return explain("Add your exam")
            case .presentation: return explain("Add your presentation")
            case .move:         return explain("Add your move")
            case .trip:         return explain("Add your trip")
            case .other:        return explain("Add a goal")
            }
        }

        /// The editor's example title — what kind of line belongs there.
        var titlePrompt: String {
            switch self {
            case .interview:    return explain("e.g. Lufthansa cabin crew")
            case .exam:         return explain("e.g. IELTS, band 7")
            case .presentation: return explain("e.g. Quarterly review with the Berlin team")
            case .move:         return explain("e.g. Moving to Munich")
            case .trip:         return explain("e.g. Two weeks in Japan")
            case .other:        return explain("What are you preparing for?")
            }
        }

        /// The notes field's example, per kind: what is worth telling the
        /// tutor about THIS kind of day (one example for all of them asked
        /// a presentation for "the score you need").
        var notesPrompt: String {
            switch self {
            case .interview:    return explain("The role, questions you expect, what worries you…")
            case .exam:         return explain("The score you need, your weakest part, the format…")
            case .presentation: return explain("The topic, how long you speak, questions after…")
            case .move:         return explain("What to sort out there: a flat, the bank, a visa…")
            case .trip:         return explain("What you'll do there, who you'll meet…")
            case .other:        return explain("What it is, who's involved, what worries you…")
            }
        }

        var placePrompt: String {
            switch self {
            case .interview:    return explain("Company or place")
            case .exam:         return explain("Test centre")
            case .presentation: return explain("Where, and for whom")
            case .move, .trip:  return explain("Where")
            case .other:        return explain("Where")
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var title: String
    /// The day it happens. Optional: "someday this year" is still a goal.
    var date: Date?
    var place: String = ""
    /// Anything else: the role, the score they need, who will be there.
    var notes: String = ""
    /// The target language it was made under — an interview is in one
    /// language, and the tutor of another language shouldn't drill it.
    var language: String
    var createdAt = Date()
    var updatedAt = Date()
    /// A job posting, a CV, an exam's page — read once by the same reader a
    /// Watch scenario's material uses (`ScenarioBriefEngine`). The files are
    /// never copied: a bookmark stays here, the bytes stay where they are.
    var brief: ScenarioBrief? = nil

    /// Days from today to the goal's day: 0 = today, negative = past.
    /// Counted here, not with `PromptClock.calendarDays`, which never goes
    /// below 0 — a past goal would never read as past.
    func daysLeft(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let date else { return nil }
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// Over once its day has passed.
    func isPast(now: Date = Date()) -> Bool { (daysLeft(now: now) ?? 0) < 0 }

    /// "D-12", "D-day". Nil without a date or once it is over.
    func countdown(now: Date = Date()) -> String? {
        guard let d = daysLeft(now: now), d >= 0 else { return nil }
        return d == 0 ? explain("D-day") : "D-\(d)"
    }

    /// What the reading of the attached material found, as prompt lines.
    /// Empty when nothing is attached or it hasn't been read yet.
    var materialLines: String {
        guard let b = brief, b.readAt != nil, b.hasContent || !b.summary.isEmpty else { return "" }
        var out = ["FROM THEIR OWN MATERIAL (job posting, CV, the exam's page — read from the source):"]
        if !b.summary.isEmpty { out.append("About: \(b.summary)") }
        if !b.counterpartFacts.isEmpty { out.append("The other side: " + b.counterpartFacts.joined(separator: "; ")) }
        if !b.likelyQuestions.isEmpty { out.append("Likely asked: " + b.likelyQuestions.joined(separator: " | ")) }
        if !b.learnerFacts.isEmpty { out.append("The learner's side: " + b.learnerFacts.joined(separator: "; ")) }
        if !b.keyExpressions.isEmpty { out.append("Key expressions: " + b.keyExpressions.joined(separator: "; ")) }
        return out.joined(separator: "\n")
    }

    /// The tutor drill's context: the goal, and what its material is about.
    var drillBlurb: String {
        var line = "Preparing for: " + promptLine()
        if let s = brief?.summary, !s.isEmpty { line += ". Their material: \(s)" }
        return line
    }

    /// One plain line for a prompt.
    func promptLine(now: Date = Date()) -> String {
        var parts = ["\(kind.rawValue): \(title)"]
        if !place.isEmpty { parts.append("at \(place)") }
        if let date {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "EEE d MMM yyyy"
            let left = daysLeft(now: now) ?? 0
            parts.append("on \(f.string(from: date)) (\(left <= 0 ? "today" : "in \(left) days"))")
        } else {
            parts.append("no date set")
        }
        if !notes.isEmpty { parts.append("notes: \(notes)") }
        return parts.joined(separator: ", ")
    }
}

/// `Documents/upcoming_goals.json`, one list for the install (a goal is the
/// learner's, not a language's; each carries its own `language`).
@MainActor
final class UpcomingGoalStore: ObservableObject {
    static let shared = UpcomingGoalStore()
    static let filename = "upcoming_goals.json"

    @Published private(set) var goals: [UpcomingGoal] = []

    private var url: URL { SyncFiles.url(Self.filename, lang: nil) }

    private init() { reload() }

    func reload() {
        goals = Self.sorted(SyncFiles.read([UpcomingGoal].self, at: url,
                                           decoder: SyncFiles.storeDecoder, empty: []) ?? [])
    }

    /// The goals still ahead for a target language, soonest first; undated
    /// ones after the dated ones.
    func active(language: String, now: Date = Date()) -> [UpcomingGoal] {
        goals.filter { LanguageCatalog.sameLanguage($0.language, language) && !$0.isPast(now: now) }
    }

    func save(_ goal: UpcomingGoal) {
        var g = goal
        g.updatedAt = Date()
        var list = goals.filter { $0.id != g.id }
        list.append(g)
        write(list)
        // The goal is a case of a purpose: turn that purpose on, so Talk's
        // chips and the tutor know about it too.
        LearningPurposeStore.cover(g.kind)
        Analytics.capture("upcoming_goal_saved", ["kind": g.kind.rawValue, "dated": g.date != nil])
    }

    /// Read the goal's attached material, then save what it found. The
    /// learner just saved the goal or opened its page, so they are here.
    func readMaterial(_ id: UUID, appState: AppState) async {
        guard !readingMaterial.contains(id),
              let goal = goals.first(where: { $0.id == id }), goal.brief?.hasSources == true else { return }
        readingMaterial.insert(id)
        materialFailed.remove(id)
        defer { readingMaterial.remove(id) }
        let stand = Scenario(environment: goal.promptLine(), role: "", notes: goal.notes, brief: goal.brief)
        do {
            let brief = try await ScenarioBriefEngine.read(scenario: stand, persona: appState.persona,
                                                           targetLanguage: goal.language,
                                                           nativeLanguage: appState.nativeLanguage)
            guard var current = goals.first(where: { $0.id == id }),
                  current.brief?.sources.map(\.id) == brief.sources.map(\.id) else { return }
            current.brief = brief
            save(current)
            Analytics.capture("upcoming_goal_material_read", ["sources": brief.sources.count])
        } catch {
            materialFailed.insert(id)
        }
    }

    @Published private(set) var readingMaterial: Set<UUID> = []
    @Published private(set) var materialFailed: Set<UUID> = []

    func delete(_ id: UUID) {
        write(goals.filter { $0.id != id })
    }

    private func write(_ list: [UpcomingGoal]) {
        goals = Self.sorted(list)
        try? SyncFiles.write(goals, to: url, encoder: SyncFiles.storeEncoder)
        SyncEngine.noteChanged(.upcomingGoal)
    }

    static func sorted(_ list: [UpcomingGoal]) -> [UpcomingGoal] {
        list.sorted { a, b in
            switch (a.date, b.date) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.createdAt < b.createdAt
            }
        }
    }
}
