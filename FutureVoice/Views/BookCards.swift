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

/// A quiet source label for a book — "Free talk", "News", "Scenario", with an
/// optional activity prefix ("Talk ·" / "Watch ·") for the mixed Studying grid
/// where the shelf no longer says which activity a card came from. Plain gray
/// text, no glyph or fill, so it names the source without pulling the eye off
/// the title. `nil` when a legacy talk's source can't be known.
struct OriginTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// Talk book. Legacy rows (no stored origin) only claim "Free talk" when
    /// they carried no topic; otherwise the source is genuinely unknown and we
    /// show no source rather than mislabel a free talk as News. `showActivity`
    /// prefixes "Talk ·" for the Studying grid.
    init?(session: Session, showActivity: Bool = false) {
        let source: String?
        switch session.origin {
        case .free:     source = explain("Free talk")
        case .news:     source = explain("News")
        case .scenario: source = explain("Scenario")
        case .none:     source = (session.topic?.isEmpty ?? true) ? explain("Free talk") : nil
        }
        guard showActivity || source != nil else { return nil }
        text = Self.join(activity: showActivity ? explain("Talk") : nil, source: source)
    }

    /// Watch book — a scenario is a news-born topic or a built situation.
    init(scenario: Scenario, showActivity: Bool = false) {
        let source = scenario.isTopic == true ? explain("News") : explain("Scenario")
        text = Self.join(activity: showActivity ? explain("Watch") : nil, source: source)
    }

    private static func join(activity: String?, source: String?) -> String {
        [activity, source].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A book card's icon: a soft tinted circle with the glyph (or initials)
/// in it, or — for a person with a photo on file — the photo, clipped to
/// the same circle.
struct BookIconDisc<Content: View>: View {
    var photoId: UUID? = nil
    @ViewBuilder var content: () -> Content
    @ObservedObject private var photos = CounterpartPhotoStore.shared
    static var size: CGFloat { 44 }

    var body: some View {
        Group {
            if let id = photoId, let img = photos.image(for: id) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(.tint.opacity(0.14))
                    .overlay { content() }
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(Circle())
    }
}

/// One scenario/topic book on a shelf — cover avatar, title, partner, and
/// the mastery strip. Tap/context actions are the caller's.
struct ScenarioBookCard: View {
    let scenario: Scenario
    /// Linked persona's name when the scenario points at a real person.
    let personaName: String?
    /// Prefix the source line with the activity ("Watch ·") for the mixed
    /// Studying grid, where the shelf no longer names the activity.
    var showActivity: Bool = false
    /// The whole-book progress strip. Off on the Studying page, where each
    /// chapter button under the card carries its own bar.
    var showsProgress: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                avatar
                Spacer()
                if scenario.isMastered {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3).foregroundStyle(.green)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 2) {
                OriginTag(scenario: scenario, showActivity: showActivity)
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
            .padding(.bottom, showsProgress ? 8 : 0)
            if showsProgress { progressStrip }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: showsProgress ? 150 : 0, alignment: .leading)
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

    /// In a soft round disc (2026-10-03, user decision). A scene with a
    /// person shows THAT person — their photo, else their initials on the
    /// same disc; otherwise the scene's own glyph.
    @ViewBuilder
    private var avatar: some View {
        if let name = personaName {
            BookIconDisc(photoId: scenario.counterpartId) {
                Text(Books.initials(name)).font(.headline.weight(.bold)).foregroundStyle(.tint)
            }
        } else if scenario.isTopic == true {
            BookIconDisc { Image(systemName: "newspaper.fill").font(.title3).foregroundStyle(.tint) }
        } else {
            BookIconDisc {
                Image(systemName: Books.roleIcon(for: scenario.role)).font(.title3).foregroundStyle(.tint)
            }
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
    /// Prefix the source line with "Talk ·" for the mixed Studying grid.
    var showActivity: Bool = false
    /// The whole-book progress strip. Off on the Studying page, where each
    /// chapter button under the card carries its own bar.
    var showsProgress: Bool = true

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
                BookIconDisc {
                    Image(systemName: "bubble.left.and.bubble.right.fill").font(.title3).foregroundStyle(.tint)
                }
                Spacer()
                if snapshot?.isMastered == true {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3).foregroundStyle(.green)
                }
                // How the talk itself went — the single headline number, only
                // once the summary has scored it.
                if let sc = session.summary?.scorecard {
                    scoreChip(sc.overall)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 2) {
                OriginTag(session: session, showActivity: showActivity)
                Text(session.displayTitle).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary).lineLimit(2)
                // When you last WORKED this book, not when the chat happened —
                // the most recent of a mastery event or talking/continuing it,
                // so it keeps advancing as you study. Relative ("2 days ago")
                // reads as recency, which is the point.
                Text("Studied \(lastStudiedAt.formatted(Date.RelativeFormatStyle(presentation: .named, locale: Locale(identifier: UILanguage.chromeLanguage))))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.bottom, showsProgress ? 8 : 0)
            if showsProgress { progressStrip }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: showsProgress ? 150 : 0, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(Rectangle())
        .tint(Books.talksColor)
    }

    /// The talk's overall score as a small ring — number inside, band color on
    /// the stroke. Quiet, but present, so a Talk book shows how it went.
    private func scoreChip(_ score: Int) -> some View {
        Text("\(score)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(scoreBand(score))
            .frame(width: 30, height: 30)
            .background(Circle().stroke(scoreBand(score).opacity(0.35), lineWidth: 2))
    }

    private func scoreBand(_ s: Int) -> Color {
        switch s {
        case ..<50:  return .red
        case ..<70:  return .orange
        case ..<85:  return .blue
        default:     return .green
        }
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
