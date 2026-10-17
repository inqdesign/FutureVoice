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

/// A quiet source label for a book — "Free talk", "News", "Scenario". Plain
/// gray text, no glyph or fill, so it names the source without pulling the
/// eye off the title. `nil` when a legacy talk's source can't be known. The
/// "Talk ·" / "Watch ·" activity prefix the Studying grid used to put in
/// front was dropped (2026-10-16, founder): beside the source it read as the
/// same label twice ("대화 · 자유 대화").
struct OriginTag: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// The source with the card's one fact after it — "Free talk · 11 hours
    /// ago", "Scenario · Sarah" — on ONE line under the title (2026-10-16,
    /// founder). A nil source leaves the fact alone.
    func with(_ detail: String?) -> OriginTag {
        var copy = self
        copy.text = [text.isEmpty ? nil : text, detail].compactMap { $0 }.joined(separator: " · ")
        return copy
    }

    private init(text: String) { self.text = text }

    /// Just the fact, for a legacy talk whose source can't be known.
    static func detail(_ detail: String) -> OriginTag { OriginTag(text: detail) }

    /// Talk book. Legacy rows (no stored origin) only claim "Free talk" when
    /// they carried no topic; otherwise the source is genuinely unknown and we
    /// show no source rather than mislabel a free talk as News.
    init?(session: Session) {
        var source: String?
        switch session.origin {
        case .free:     source = explain("Free talk")
        case .news:     source = explain("News")
        case .scenario: source = explain("Scenario")
        case .none:     source = (session.topic?.isEmpty ?? true) ? explain("Free talk") : nil
        }
        // A coach-mode call says so in place of "Free talk" (after "News" /
        // "Scenario"). A practice call (`Session.coached` — tutor mode, or
        // coach mode before 2026-10-14) carries no score, so it is named that.
        let coached = session.turns.contains { $0.coachLine != nil }
        if session.isPractice || coached {
            let coach = session.isPractice ? explain("Practice call") : explain("Coach mode")
            switch session.origin {
            case .news, .scenario: source = [source, coach].compactMap { $0 }.joined(separator: " · ")
            default:               source = coach
            }
        }
        guard let source else { return nil }
        text = source
    }

    /// Watch book — a scenario is a news-born topic or a built situation.
    init(scenario: Scenario) {
        text = scenario.isTopic == true ? explain("News") : explain("Scenario")
    }
}

/// A book card's icon: a soft TINTED circle with the glyph (or initials)
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
                        .font(.title3).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 3) {
                // The tidy summary (not the raw prompt). Title first and
                // large, then ONE quiet line — the source and who it's with
                // (2026-10-16, founder: the activity prefix "Watch ·" said
                // the same thing as the source beside it).
                Text(scenario.cardTitle).font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                OriginTag(scenario: scenario).with(partnerLabel)
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

    /// In a soft round disc in the book's colour — the card's one coloured
    /// mark besides its bars (2026-10-03, user decision). A scene with a
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
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("Open to start", systemImage: "book")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// One finished talk on the Talks shelf — same card anatomy as a scenario
/// book, seeded by a real conversation. `snapshot` is the derived
/// `TalkCurriculum` progress; nil while it's still computing.
struct TalkBookCard: View {
    let session: Session
    let snapshot: TalkCurriculum.Snapshot?
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

    private var metaLine: OriginTag {
        let when = lastStudiedAt.formatted(Date.RelativeFormatStyle(
            presentation: .named, locale: Locale(identifier: UILanguage.chromeLanguage)))
        return OriginTag(session: session)?.with(when) ?? .detail(when)
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
                        .font(.title3).foregroundStyle(.secondary)
                }
                // How the talk itself went — the single headline number, only
                // once the summary has scored it.
                // A practice (coach mode) call has no score to headline.
                if let sc = session.summary?.scorecard, !session.isPractice {
                    scoreChip(sc.overall)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle).font(.headline)
                    .foregroundStyle(.primary).lineLimit(2)
                // The source, then when you last WORKED this book — the most
                // recent of a mastery event or talking/continuing it, so it
                // keeps advancing as you study — on one line: "Free talk ·
                // 11 hours ago" (2026-10-16, founder).
                metaLine
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
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(Circle().stroke(Color(.separator), lineWidth: 2))
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
                        .foregroundStyle(.secondary)
                }
            } else {
                // A chat that produced no material — still replayable.
                Label("Replay anytime", systemImage: "play.circle")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            Label("Open to review", systemImage: "book")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
