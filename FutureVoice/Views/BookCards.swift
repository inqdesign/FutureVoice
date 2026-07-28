import SwiftUI

/// Shared avatar vocabulary for the book shelves (Practice's Talk · Watch)
/// and the people list.
enum Books {
    /// Source color coding — one hue per book source, carried by each card's
    /// origin tag so a source is tellable at a glance even inside a single
    /// activity shelf or the mixed Studying grid: Free talk = blue,
    /// News = orange, Scenario = purple. Mastery stays green everywhere.
    static let talksColor: Color = .blue
    static let topicsColor: Color = .orange
    static let scenariosColor: Color = .purple
    /// Practice's two activity chips.
    static let talkChipColor: Color = .blue
    static let watchChipColor: Color = .indigo
    static func color(for scenario: Scenario) -> Color {
        scenario.isTopic == true ? topicsColor : scenariosColor
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    /// Role text → a representative SF Symbol for a scenario card's avatar.
    static func roleIcon(for role: String) -> String {
        let r = role.lowercased()
        switch true {
        case r.contains("doctor"), r.contains("nurse"):            return "stethoscope"
        case r.contains("manager"), r.contains("boss"):            return "briefcase.fill"
        case r.contains("colleague"):                              return "briefcase.fill"
        case r.contains("teacher"):                                return "graduationcap.fill"
        case r.contains("shop"), r.contains("service"), r.contains("agent"): return "bag.fill"
        case r.contains("friend"):                                 return "person.2.fill"
        case r.contains("family"), r.contains("kid"), r.contains("child"): return "figure.and.child.holdinghands"
        case r.contains("date"), r.contains("romantic"):           return "heart.fill"
        case r.contains("neighbor"):                               return "house.fill"
        case r.contains("stranger"):                               return "person.fill.questionmark"
        default:                                                   return "person.fill"
        }
    }
}

/// A small pill naming where a book came from — Free talk, News, or a
/// Scenario. Practice's shelves split by ACTIVITY (Talk vs Watch), so this
/// tag carries the orthogonal SOURCE on each card. Build it from a `Session`
/// (Talk book) or a `Scenario` (Watch book).
struct OriginTag: View {
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        // Quiet source label — plain tinted text, no glyph or fill, so it
        // names the origin without pulling the eye off the title.
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

extension OriginTag {
    /// Talk book — the session's stored origin. Legacy rows (nil origin) fall
    /// back to News when they carried a topic, else Free talk.
    init(session: Session) {
        switch session.origin ?? (session.topic?.isEmpty == false ? .news : .free) {
        case .free:     self.init(label: "Free talk", icon: "waveform", color: Books.talksColor)
        case .news:     self.init(label: "News", icon: "newspaper.fill", color: Books.topicsColor)
        case .scenario: self.init(label: "Scenario", icon: "theatermasks.fill", color: Books.scenariosColor)
        }
    }
    /// Watch book — a scenario is either a news-born topic or a built situation.
    init(scenario: Scenario) {
        if scenario.isTopic == true {
            self.init(label: "News", icon: "newspaper.fill", color: Books.topicsColor)
        } else {
            self.init(label: "Scenario", icon: "theatermasks.fill", color: Books.scenariosColor)
        }
    }
}

/// One scenario/topic book on a shelf — cover avatar, title, partner, and
/// the mastery strip. Tap/context actions are the caller's.
struct ScenarioBookCard: View {
    let scenario: Scenario
    /// Linked persona's name when the scenario points at a real person.
    let personaName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                avatar
                Spacer()
                HStack(spacing: 6) {
                    if scenario.isMastered {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title3).foregroundStyle(.green)
                    }
                    OriginTag(scenario: scenario)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 2) {
                // The tidy summary (not the raw prompt); topic headlines are
                // full sentences so give them a second line.
                Text(scenario.cardTitle).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(scenario.isTopic == true || partnerLabel == nil ? 2 : 1)
                if let partnerLabel {
                    Text("with \(partnerLabel)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.bottom, 8)
            progressStrip
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(Rectangle())
        .tint(Books.color(for: scenario))
    }

    /// Who the "with" line names — the linked persona, else the role; nil for
    /// free-described situations (the scene casts its own counterpart).
    private var partnerLabel: String? {
        if let personaName { return personaName }
        let r = scenario.role.trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? nil : r
    }

    /// Bare tinted glyph, no background disc — the same icon vocabulary as
    /// Watch's category cards, so books and situations read as one family.
    @ViewBuilder
    private var avatar: some View {
        if let name = personaName {
            Text(Books.initials(name)).font(.title3.weight(.bold)).foregroundStyle(.tint)
        } else if scenario.isTopic == true {
            Image(systemName: "newspaper.fill").font(.title2).foregroundStyle(.tint)
        } else {
            Image(systemName: Books.roleIcon(for: scenario.role)).font(.title2).foregroundStyle(.tint)
        }
    }

    /// Curriculum progress once the book exists, or the "new book" hint.
    @ViewBuilder
    private var progressStrip: some View {
        if let c = scenario.curriculum, c.totalCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: c.progress)
                    .tint(scenario.isMastered ? .green : Books.color(for: scenario))
                Text(scenario.isMastered ? "Mastered" : "\(c.masteredCount)/\(c.totalCount) mastered")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(scenario.isMastered ? .green : .secondary)
            }
        } else {
            Label("Open to start", systemImage: "book")
                .font(.caption2).foregroundStyle(.tint)
        }
    }
}

/// One finished talk on the Talks shelf — same card anatomy as a scenario
/// book, seeded by a real conversation. `snapshot` is the derived
/// `TalkCurriculum` progress; nil while it's still computing.
struct TalkBookCard: View {
    let session: Session
    let snapshot: TalkCurriculum.Snapshot?

    /// The last time this book was worked — a mastery event or the last time
    /// the talk itself was had/continued, whichever is later. Falls back to
    /// the start date for a brand-new, untouched book.
    private var lastStudiedAt: Date {
        [snapshot?.lastStudiedAt, session.endedAt, session.startedAt]
            .compactMap { $0 }.max() ?? session.startedAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.title2).foregroundStyle(.tint)
                Spacer()
                HStack(spacing: 6) {
                    if snapshot?.isMastered == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title3).foregroundStyle(.green)
                    }
                    OriginTag(session: session)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary).lineLimit(2)
                // When you last WORKED this book, not when the chat happened —
                // the most recent of a mastery event or talking/continuing it,
                // so it keeps advancing as you study. Relative ("2 days ago")
                // reads as recency, which is the point.
                Text("Studied \(lastStudiedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.bottom, 8)
            progressStrip
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(Rectangle())
        .tint(Books.talksColor)
    }

    @ViewBuilder
    private var progressStrip: some View {
        if let s = snapshot {
            if s.totalCount > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: s.progress)
                        .tint(s.isMastered ? .green : Books.talksColor)
                    Text(s.isMastered ? "Mastered" : "\(s.masteredCount)/\(s.totalCount) mastered")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(s.isMastered ? .green : .secondary)
                }
            } else {
                // A chat that produced no material — still replayable.
                Label("Replay anytime", systemImage: "play.circle")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            Label("Open to review", systemImage: "book")
                .font(.caption2).foregroundStyle(.tint)
        }
    }
}
