import SwiftUI

/// Watch as a map of people (2026-10-11, founder's design, DEBUG experiment
/// behind `PeopleSky.isEnabled`). The learner sits in the middle; everyone
/// they could practise with HANGS around them — still, never drifting — at a
/// distance that IS the relationship: family, partner and friends close,
/// work and neighbourhood further out, strangers and roles at the edge. The
/// map is bigger than the screen and pans like a word cloud.
///
/// The lens on top is ONE choice (All · My people · People I know ·
/// Strangers). Every lens uses the same rings: a ring with nobody on it in
/// that lens folds away and the next ring moves in, so on Strangers the
/// strangers' rows come straight in around the learner, in the same order. Nobody changes angle —
/// a person who doesn't belong to the lens fades out where they stand, so the
/// map stays the map the learner has learned.
///
/// Why people and not situations: a saved situation is almost never played
/// again (45 days to 2026-10-11, learners other than the founder: 81 made,
/// 46 scenes played in total), but the people in a learner's life come back.
enum PeopleSky {
    static let defaultsKey = "futurevoice.dev.peopleSky"

    /// DEBUG builds default to the map; the Me → Developer toggle is the way
    /// back. A release build never shows it.
    static var isEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
        #else
        return false
        #endif
    }

    /// The situation dock over the map: chips + box, a chip picks the person
    /// and they speak a line. DEBUG only until the founder has seen it.
    static var dockEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.object(forKey: "futurevoice.dev.situationDock") as? Bool ?? true
        #else
        return false
        #endif
    }

    enum Lens: String, CaseIterable, Identifiable {
        case all, mine, known, strangers
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return explain("All")
            case .mine: return explain(key: "watch.sky.lens.mine", default: "My people")
            case .known: return explain(key: "watch.sky.lens.known", default: "People I know")
            case .strangers: return explain("Strangers")
            }
        }
    }

    /// One thing on the map.
    struct Node: Identifiable {
        enum Kind {
            /// A person on file — made by the learner, or a stranger met or
            /// bookmarked through Find people.
            case person(Counterpart)
            /// Someone from the Find-people pool not met yet.
            case pooled(Counterpart)
            /// A role with no particular person behind it (the browse door's
            /// categories): tapping it opens the common situations there.
            case role(ScenarioComposerSheet.Category)
        }
        let id: String
        let name: String
        let kind: Kind
        /// 0 close, 1 known, 2 stranger.
        let ring: Int
        /// The learner made this person.
        let isMine: Bool
        /// Talks + scenes with them. Drives size and the "People I know" lens.
        let practiced: Int
        /// Has a situation the learner kept with them.
        let hasKept: Bool
        /// What the face says when there is no photo: the relationship for
        /// someone the learner made, the job for a stranger.
        var symbol: String = "person.fill"
        /// The small line over the name: what they are to the learner
        /// ("Best friend", "Landlord") or, for a stranger, what they do.
        var eyebrow: String? = nil

        var photoId: UUID? {
            switch kind {
            case .person(let c), .pooled(let c): return c.id
            case .role: return nil
            }
        }

        /// Unused since "All" shows every stranger again (drawn quietly);
        /// kept so a capped "All" is one line away if the pool outgrows it.
        var featured: Bool = false

        var isUnmet: Bool {
            switch kind {
            case .pooled, .role: return true
            case .person: return false
            }
        }

        func shows(in lens: Lens) -> Bool {
            switch lens {
            case .all:
                switch kind {
                case .person: return true
                case .pooled: return true
                case .role: return false
                }
            case .mine: return isMine
            case .known: return practiced > 0
            case .strangers:
                if case .role = kind { return true }
                return !isMine && practiced == 0
            }
        }

        var size: CGFloat {
            if isUnmet { return 64 }
            switch ring {
            case 0: return 82 + CGFloat(min(practiced, 9)) * 3
            case 1: return 74 + CGFloat(min(practiced, 8)) * 3
            default: return 68 + CGFloat(min(practiced, 4)) * 3
            }
        }
    }

    // MARK: - Geometry

    struct Geometry {
        var radii: [CGFloat]
        /// Vertical stretch of the rings (1 = circles).
        var sy: CGFloat
        var me: CGFloat
        /// Whether anyone in the lens sits on each ring. An empty ring is
        /// folded away — no line, no name, no space held for nobody.
        var occupied: [Bool] = [true, true, true]
        /// The outermost row's radius — how far the map has to reach.
        var edge: CGFloat = 330
        /// Where each person in the lens sits: which row, which place in it.
        var seats: [String: Seat] = [:]
    }

    /// The rings for a lens. Rings are SLOTS, filled from the inside: an
    /// empty ring collapses onto the one inside it and the next ring with
    /// people takes its place, so a learner with no close people yet doesn't
    /// look at an empty circle around themselves. A ring also grows with
    /// its own head count, so a crowded one never stacks people up.
    static func geometry(_ lens: Lens, nodes: [Node]) -> Geometry {
        let counts = (0..<3).map { r in nodes.filter { $0.ring == r && $0.shows(in: lens) }.count }
        let occupied = counts.map { $0 > 0 }
        let slots: [CGFloat], me: CGFloat
        switch lens {
        case .mine: (slots, me) = ([150, 280, 410], 100)
        case .known: (slots, me) = ([146, 276, 400], 96)
        default: (slots, me) = ([156, 286, 416], 104)
        }
        var radii: [CGFloat] = []
        var seats: [String: Seat] = [:]
        var inner = me / 2, slot = 0
        for r in 0..<3 {
            guard counts[r] > 0 else { radii.append(inner); continue }
            var radius = slots[slot]
            if slot > 0 { radius = max(radius, inner + bandStep) }
            radii.append(radius)
            // A row holds only as many people as its circumference has room
            // for; the rest sit in a row behind it, one row-step further out.
            let list = nodes.filter { $0.ring == r && $0.shows(in: lens) }
            var start = 0, row = 0
            while start < list.count {
                let around = 2 * .pi * (radius + CGFloat(row) * bandStep)
                let cap = max(3, Int(around / seatWidth))
                let rowList = Array(list[start..<min(start + cap, list.count)])
                for (i, n) in rowList.enumerated() { seats[n.id] = Seat(row: row, index: i, size: rowList.count) }
                start += cap
                row += 1
            }
            inner = radius + CGFloat(max(row - 1, 0)) * bandStep
            slot += 1
        }
        return Geometry(radii: radii, sy: 1, me: me, occupied: occupied, edge: inner, seats: seats)
    }

    struct Seat { let row: Int; let index: Int; let size: Int }

    /// Distance between the rows of one crowded ring.
    static let bandStep: CGFloat = 130
    /// The arc one person needs along a row: their face plus the eyebrow and
    /// name under it, with air on both sides.
    static let seatWidth: CGFloat = 150

    static func side(nodes: [Node]) -> CGFloat {
        2 * (max(geometry(.all, nodes: nodes).edge, 416) + 160)
    }

    /// A stable 0..<1 per id and salt — `hashValue` is reseeded every launch,
    /// and the map must not rearrange itself between visits.
    private static func unit(_ s: String, _ salt: UInt64) -> CGFloat {
        var h: UInt64 = 1469598103934665603 &+ salt
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return CGFloat(h % 10_000) / 10_000
    }

    /// Where everyone sits under a lens: on their ring at their own angle,
    /// then pushed apart until no two overlap. People outside the lens don't
    /// push; they sit at their ring's new radius so they fade out in place.
    static func solve(_ nodes: [Node], lens: Lens, side: CGFloat) -> [String: CGPoint] {
        let g = geometry(lens, nodes: nodes)
        let c = CGPoint(x: side / 2, y: side / 2)

        // seats are dealt among the people this lens shows; anyone hidden
        // keeps their seat from the full map, so they fade out in place
        let allSeats = geometry(.all, nodes: nodes).seats
        func home(_ n: Node) -> CGPoint {
            let b = g.seats[n.id] ?? allSeats[n.id] ?? Seat(row: 0, index: 0, size: 1)
            // each row turned a little so rows interleave instead of lining up
            let start = -CGFloat.pi / 2 + CGFloat(n.ring) * 0.55 + CGFloat(b.row) * 0.37
            let a = start + CGFloat(b.index) * 2 * .pi / CGFloat(max(b.size, 1))
                + (unit(n.id, 1) - 0.5) * 0.3
            let k = 1 + (unit(n.id, 2) - 0.5) * 0.12
            let r = (g.radii[n.ring] + CGFloat(b.row) * bandStep) * k
            return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * g.sy)
        }

        let visible = nodes.filter { $0.shows(in: lens) }
        var pts = visible.map(home)
        let targets = pts
        let sizes = visible.map(\.size)
        for _ in 0..<200 {
            for i in 0..<pts.count {
                // the learner, fixed at the centre
                var dx = pts[i].x - c.x, dy = (pts[i].y - c.y) * 0.85
                var d = max(hypot(dx, dy), 0.01)
                var minD = (g.me + sizes[i]) / 2 + 22
                if d < minD { pts[i].x += dx / d * (minD - d); pts[i].y += dy / d * (minD - d) }
                for j in (i + 1)..<max(pts.count, i + 1) where j < pts.count {
                    dx = pts[j].x - pts[i].x; dy = (pts[j].y - pts[i].y) * 0.85
                    d = max(hypot(dx, dy), 0.01)
                    // the eyebrow and name under a face are wider than the
                    // face, so two people need room for their labels too
                    minD = (max(sizes[i], 120) + max(sizes[j], 120)) / 2 + 24
                    if d < minD {
                        let push = (minD - d) / 2, ux = dx / d, uy = dy / d
                        pts[i].x -= ux * push; pts[i].y -= uy * push
                        pts[j].x += ux * push; pts[j].y += uy * push
                    }
                }
            }
            for i in 0..<pts.count {
                pts[i].x += (targets[i].x - pts[i].x) * 0.05
                pts[i].y += (targets[i].y - pts[i].y) * 0.05
            }
        }
        var out: [String: CGPoint] = [:]
        for (i, n) in visible.enumerated() { out[n.id] = pts[i] }
        for n in nodes where out[n.id] == nil { out[n.id] = home(n) }
        return out
    }

    // MARK: - Faces

    /// The SF Symbol drawn in place of initials. A face that says WHO this is
    /// to the learner — partner, family, the manager, a nurse in Hamburg —
    /// reads across a map at a glance; a letter only reads up close.
    static func symbol(for c: Counterpart, occupation: String? = nil) -> String {
        if c.cast == .publicFigure {
            let id = (c.publicIdentity ?? c.relationship).lowercased()
            return ["singer", "rapper", "music", "가수", "歌手", "sänger"].contains { id.contains($0) }
                ? "music.mic" : "star.fill"
        }
        if c.cast == .stranger {
            return jobSymbol(occupation ?? c.intro) ?? "person.fill"
        }
        switch c.relationshipKind {
        case "Partner": return "heart.fill"
        case "Family": return "house.fill"
        case "Friend": return "person.2.fill"
        case "Coworker", "Manager": return "briefcase.fill"
        case "Fellow parent": return "figure.and.child.holdhands"
        case "Neighbor": return "door.left.hand.open"
        case "Teacher": return "graduationcap.fill"
        default: break
        }
        // People made before the relationship chip: read the learner's own words.
        let r = c.relationship.lowercased()
        // Family words are checked LAST: "친구 엄마" / "a friend's mom" names
        // someone met through a friend, and drew a house when "엄마" won.
        let byWords: [([String], String)] = [
            (["wife", "husband", "partner", "girlfriend", "boyfriend", "아내", "남편", "애인", "여자친구", "남자친구"], "heart.fill"),
            (["friend", "친구"], "person.2.fill"),
            (["manager", "boss", "colleague", "coworker", "team", "상사", "팀장", "동료", "부장", "과장"], "briefcase.fill"),
            (["landlord", "집주인"], "key.fill"),
            (["neighbor", "neighbour", "이웃"], "door.left.hand.open"),
            (["teacher", "coach", "선생님", "강사"], "graduationcap.fill"),
            (["kita", "parent", "학부모"], "figure.and.child.holdhands"),
            (["mom", "dad", "mother", "father", "sister", "brother", "엄마", "아빠", "어머니", "아버지", "누나", "언니", "형", "오빠", "동생", "family", "가족"], "house.fill"),
        ]
        return byWords.first { $0.0.contains(where: r.contains) }?.1
            ?? jobSymbol(c.relationship) ?? "person.fill"
    }

    private static func jobSymbol(_ text: String) -> String? {
        let t = text.lowercased()
        let jobs: [([String], String)] = [
            (["nurse", "간호", "看護", "pfleger", "krankenschwester"], "cross.case.fill"),
            (["doctor", "physician", "의사", "医師", "arzt", "ärztin"], "stethoscope"),
            (["design", "디자인", "デザイン"], "paintbrush.pointed.fill"),
            (["chef", "cook", "요리", "料理", "koch"], "fork.knife"),
            (["developer", "engineer", "programmer", "개발", "엔지니어", "エンジニア", "entwickler"], "laptopcomputer"),
            (["teacher", "professor", "교사", "선생", "教師", "先生", "lehrer"], "graduationcap.fill"),
            (["student", "학생", "学生", "studi"], "book.fill"),
            (["music", "singer", "musician", "음악", "가수", "音楽", "musik"], "music.note"),
            (["photograph", "사진", "写真", "fotograf"], "camera.fill"),
            (["writer", "author", "journalist", "작가", "기자", "作家", "autor"], "pencil"),
            (["market", "sales", "마케팅", "영업", "営業"], "megaphone.fill"),
            (["parent", "mom", "dad", "엄마", "아빠", "육아", "子育て"], "figure.and.child.holdhands"),
        ]
        return jobs.first { $0.0.contains(where: t.contains) }?.1
    }

    /// A stable colour per person, so two friends with the same icon are
    /// still two different faces. Indigo is the Core's and is never used.
    static func faceColor(_ id: String) -> Color {
        let palette: [UIColor] = [.systemRed, .systemOrange, .systemGreen, .systemMint,
                                  .systemTeal, .systemCyan, .systemBlue, .systemPurple,
                                  .systemPink, .systemBrown]
        return Color(palette[Int(unit(id, 4) * CGFloat(palette.count)) % palette.count])
    }

    /// Which ring someone belongs on.
    static func ring(for c: Counterpart) -> Int {
        switch c.cast {
        case .publicFigure, .stranger: return 2
        case .ownPerson: return c.isClose ? 0 : 1
        }
    }
}

// MARK: - The map

struct PeopleSkyMap: View {
    let nodes: [PeopleSky.Node]
    let meName: String
    @Binding var lens: PeopleSky.Lens
    var onTap: (PeopleSky.Node) -> Void
    var onTapMe: () -> Void
    /// Who the situation is with: ringed, a touch larger, their line to me
    /// drawn in the accent. Only a pick changes it — never a scroll.
    var focusedId: String? = nil
    /// Who is in the middle of the screen and says something.
    var bubbleId: String? = nil
    /// What they say while they are in the middle — one of their situation
    /// ideas, rising over their face and gone once they leave the middle.
    var bubble: String? = nil
    /// The bubble is a suggestion: tapping it writes it into the box.
    var onTapBubble: () -> Void = {}
    /// Pan to this person (a chip or the box's own person picker chose them).
    /// Scrolling by hand never sets it, so the map never fights a finger.
    var scrollTarget: String? = nil
    /// Who is nearest the middle of the screen now (nil: nobody close).
    /// Reported as the learner scrolls; iOS 18 and later.
    var onCenterChange: ((String?) -> Void)? = nil
    /// How high "Back to me" sits — above the box while one is open.
    var backToMeBottom: CGFloat = 16

    @State private var centred: String?

    @State private var awayFromMe = false
    /// The learner's own photo (the one on Home and in the profile).
    @ObservedObject private var avatar = AvatarStore.shared

    private var side: CGFloat { PeopleSky.side(nodes: nodes) }
    private var geometry: PeopleSky.Geometry { PeopleSky.geometry(lens, nodes: nodes) }
    private var positions: [String: CGPoint] { PeopleSky.solve(nodes, lens: lens, side: side) }

    private var ringNames: [String] { [
        explain(key: "watch.sky.ring.close", default: "Close to me"),
        explain(key: "watch.sky.ring.known", default: "People around me"),
        explain("Strangers")
    ] }

    var body: some View {
        let pos = positions, g = geometry, c = side / 2
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Background: the rings and their names sit UNDER the people.
                    ForEach(0..<3, id: \.self) { i in
                        Ellipse()
                            .stroke(Color.secondary.opacity(0.22),
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                            .frame(width: g.radii[i] * 2, height: g.radii[i] * 2 * g.sy)
                            .position(x: c, y: c)
                                            .opacity(g.occupied[i] ? 1 : 0)
                        Text(ringNames[i])
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .background(Color(.systemGroupedBackground))
                            .position(x: c, y: c + g.radii[i] * g.sy)
                            .opacity(g.occupied[i] ? 1 : 0)
                    }
                    Color.clear.frame(width: 1, height: 1).position(x: c, y: c).id("centre")


                    ForEach(nodes) { n in
                        let on = n.shows(in: lens)
                        let focused = n.id == focusedId
                        node(n)
                            .modifier(DepthOfField())
                            .overlay(alignment: .top) {
                                if n.id == (bubbleId ?? focusedId), let bubble {
                                    Button(action: onTapBubble) { SkyBubble(text: bubble) }
                                        .buttonStyle(.plain)
                                        .fixedSize()
                                        .offset(y: -64)
                                        .alignmentGuide(.top) { $0[.bottom] }
                                        .transition(.asymmetric(
                                            insertion: .offset(y: 14).combined(with: .opacity),
                                            removal: .opacity))
                                        .id(bubble)
                                }
                            }
                            .scaleEffect(on ? (focused ? 1.12 : 1) : 0.6)
                            .zIndex(focused || n.id == bubbleId ? 1 : 0)
                            .opacity(on ? 1 : 0)
                            .allowsHitTesting(on)
                            .accessibilityHidden(!on)
                            .position(pos[n.id] ?? CGPoint(x: c, y: c))
                        // Placed by alignment guides, not `.position` (a positioned
                        // view fills the whole map) or `.offset` (draws elsewhere,
                        // laid out at the corner): scrolling to it needs its
                        // real frame at the person.
                        let p = pos[n.id] ?? CGPoint(x: c, y: c)
                        Color.clear.frame(width: 1, height: 1)
                            .alignmentGuide(.leading) { _ in -p.x }
                            .alignmentGuide(.top) { _ in -p.y }
                            .id("node-" + n.id)
                    }
                    me(size: g.me).position(x: c, y: c + 8)
                }
                .frame(width: side, height: side)
            }
            .defaultScrollAnchor(.center)
            // The map's bottom runs under the tab bar and the floating
            // "Your own situation" button, and its top under the lens picker's
            // shadow. Margins let the edges be dragged clear of all of it, so
            // nobody on the map is ever out of reach of a tap.
            // Equal top and bottom, or the centre anchor puts "me" off-centre.
            // With the situation dock, a picked person must be able to come
            // to the middle wherever they sit — edge or bottom — with room for
            // their bubble, so the map can be dragged much further.
            .contentMargins(.vertical, PeopleSky.dockEnabled ? 280 : 120, for: .scrollContent)
            .contentMargins(.horizontal, PeopleSky.dockEnabled ? 170 : 24, for: .scrollContent)
            .modifier(TrackDistanceFromCentre(side: side, away: $awayFromMe))
            .onChange(of: lens) { _, _ in
                withAnimation(.smooth(duration: 0.5)) { proxy.scrollTo("centre", anchor: .center) }
            }
            .onChange(of: scrollTarget) { _, id in
                guard let id else { return }
                // A little above centre: the box covers the bottom of the map.
                withAnimation(.smooth(duration: 0.5)) {
                    proxy.scrollTo("node-" + id, anchor: UnitPoint(x: 0.5, y: Self.focusLine))
                }
            }
            // The pool can land after a pick and grow the map; stay on them.
            .onChange(of: side) { _, _ in
                guard let id = scrollTarget else { return }
                proxy.scrollTo("node-" + id, anchor: UnitPoint(x: 0.5, y: Self.focusLine))
            }
            .modifier(CentreFocus(focusLine: Self.focusLine, positions: pos,
                                  candidates: nodes.filter { $0.shows(in: lens) }.map(\.id),
                                  onChange: { id in
                                      guard id != centred else { return }
                                      centred = id
                                      onCenterChange?(id)
                                  }))
            .overlay(alignment: .bottomLeading) {
                if awayFromMe {
                    Button {
                        withAnimation(.smooth) { proxy.scrollTo("centre", anchor: .center) }
                    } label: {
                        Label(explain(key: "watch.sky.backToMe", default: "Back to me"),
                              systemImage: "scope")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
                    .padding(.horizontal, 16)
                    .padding(.bottom, backToMeBottom)
                    .transition(.opacity)
                }
            }
        }
        .animation(.smooth(duration: 0.5), value: lens)
        .animation(.smooth(duration: 0.35), value: focusedId)
        .animation(.smooth(duration: 0.35), value: bubble)
    }

    /// Where "the middle" is, as a share of the map's height: above the true
    /// centre, because the box covers the bottom.
    static let focusLine: CGFloat = 0.42

    private func me(size: CGFloat) -> some View {
        Button(action: onTapMe) {
            VStack(spacing: 6) {
                ZStack {
                    if let img = avatar.image {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        Circle().fill(Color(.secondarySystemGroupedBackground))
                        Text(Books.initials(meName))
                            .font(.system(size: size * 0.26, weight: .bold))
                            .foregroundStyle(.tint)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 3))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                Text("Me")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Me"))
    }

    private func node(_ n: PeopleSky.Node) -> some View {
        Button { onTap(n) } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    switch n.kind {
                    case .role(let cat):
                        Circle()
                            .fill(Color(.secondarySystemGroupedBackground))
                            .overlay(Circle().strokeBorder(Color.secondary.opacity(0.45),
                                                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                            .overlay(Image(systemName: cat.icon)
                                .font(.system(size: n.size * 0.36))
                                .foregroundStyle(.secondary))
                            .frame(width: n.size, height: n.size)
                    case .person, .pooled:
                        // An opaque disc under the tinted bubble, so the rings
                        // and their names behind never show through a face.
                        SkyFace(node: n)
                            .overlay {
                                if n.id == focusedId {
                                    Circle().strokeBorder(Color.accentColor, lineWidth: 3)
                                        .padding(-4)
                                }
                            }
                    }
                    if n.hasKept {
                        Circle().fill(Color.accentColor)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color(.systemGroupedBackground), lineWidth: 2))
                    }
                }
                VStack(spacing: 0) {
                    if let eyebrow = n.eyebrow, !eyebrow.isEmpty {
                        Text(eyebrow)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 116)
                    }
                    Text(n.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(width: 116)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text([n.name, n.eyebrow].compactMap { $0 }.joined(separator: ", ")))
    }
}

/// Reports who sits nearest the focus line as the map scrolls. The scroll
/// geometry hook is iOS 18; on 17 nobody is ever "in the middle".
private struct CentreFocus: ViewModifier {
    let focusLine: CGFloat
    let positions: [String: CGPoint]
    let candidates: [String]
    let onChange: (String?) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in
                let focus = CGPoint(x: rect.midX, y: rect.minY + rect.height * focusLine)
                var best: (String, CGFloat)?
                for id in candidates {
                    guard let p = positions[id] else { continue }
                    let d = hypot(p.x - focus.x, p.y - focus.y)
                    if d < 90, d < (best?.1 ?? .infinity) { best = (id, d) }
                }
                onChange(best?.0)
            }
        } else {
            content
        }
    }
}

/// A picked person's line, over their face: a rounded bubble with a small tail.
struct SkyBubble: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 200)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            Triangle()
                .fill(Color(.systemBackground))
                .frame(width: 16, height: 8)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
    }

    private struct Triangle: Shape {
        func path(in r: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: r.minX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
                p.closeSubpath()
            }
        }
    }
}

/// Shows "Back to me" once the learner has panned well away from the centre.
/// The scroll-geometry hook is iOS 18; on 17 the button simply never shows.
private struct TrackDistanceFromCentre: ViewModifier {
    let side: CGFloat
    @Binding var away: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geo in
                let centre = CGPoint(x: side / 2, y: side / 2)
                let viewCentre = CGPoint(x: geo.visibleRect.midX, y: geo.visibleRect.midY)
                return hypot(viewCentre.x - centre.x, viewCentre.y - centre.y) > 160
            } action: { _, isAway in
                withAnimation(.easeInOut(duration: 0.2)) { away = isAway }
            }
        } else {
            content
        }
    }
}

/// A person's face on the map: their photo when there is one, otherwise the
/// icon of who they are on their own colour.
private struct SkyFace: View {
    let node: PeopleSky.Node
    @ObservedObject private var photos = CounterpartPhotoStore.shared

    var body: some View {
        Group {
            if let id = node.photoId, let img = photos.image(for: id) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if node.isUnmet {
                // someone not met yet is drawn quietly, so the learner's own
                // people are the colour on the map
                Color(.tertiarySystemFill)
                    .overlay(Image(systemName: node.symbol)
                        .font(.system(size: node.size * 0.36, weight: .semibold))
                        .foregroundStyle(.secondary))
            } else {
                PeopleSky.faceColor(node.id)
                    .overlay(Image(systemName: node.symbol)
                        .font(.system(size: node.size * 0.38, weight: .semibold))
                        .foregroundStyle(.white))
            }
        }
        .frame(width: node.size, height: node.size)
        .clipShape(Circle())
        .id(photos.version)
    }
}

/// Like a word cloud: whoever sits in the middle of the screen is sharp, and
/// people fade and shrink a little toward the edges, so panning brings each
/// face forward as it reaches the centre. Read from the node's place in the
/// scroll view's visible area, so it follows every drag with no state.
private struct DepthOfField: ViewModifier {
    func body(content: Content) -> some View {
        content.visualEffect { effect, proxy in
            let frame = proxy.frame(in: .scrollView)
            let size = proxy.bounds(of: .scrollView)?.size ?? .zero
            let dx = frame.midX - size.width / 2
            let dy = frame.midY - size.height / 2
            // 0 at the centre, 1 around the screen's edge
            let reach = max(min(size.width, size.height) * 0.62, 1)
            let t = min(hypot(dx, dy * 0.8) / reach, 1.6)
            // Sharp across the middle of the screen, fading past it. Fade
            // only: a shrink by distance made everyone around the middle
            // squirm while the map was dragged (2026-10-12).
            return effect
                .opacity(max(0.3, min(1, 1.45 - 0.75 * t)))
        }
    }
}
