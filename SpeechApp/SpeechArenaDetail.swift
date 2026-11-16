import SwiftUI

// A challenge's page in the speech app (2026-11-12, founder: "the card scales
// up and becomes the hero, the rest slides and fades in"). The card a learner
// tapped grows into the top of this page through the zoom transition; what
// it holds (what to keep in mind, my best, the boards) comes in under it.

extension View {
    /// The card a tap grows out of (iOS 18; a plain push before).
    /// A card dims and zooms as ONE sheet. Without the group, a press dims
    /// the picture and the card behind it separately, and the picture's cream
    /// over the half-dimmed card cream shows up as a lighter square.
    @ViewBuilder func zoomSource(_ id: String, in ns: Namespace.ID?, radius: CGFloat) -> some View {
        if #available(iOS 18.0, *), let ns {
            compositingGroup().matchedTransitionSource(id: id, in: ns) {
                $0.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
        } else {
            compositingGroup()
        }
    }

    /// The page a card grows into.
    @ViewBuilder func zoomDestination(_ id: String, in ns: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let ns {
            navigationTransition(.zoom(sourceID: id, in: ns))
        } else {
            self
        }
    }

    /// Comes in after the hero: a short slide up and a fade, one step later
    /// per section.
    /// No darkening under the bars. iOS 26 softens content that scrolls
    /// under a bar with a dark layer in the dark look; over the cream cards
    /// and the picture that layer reads as a stain on the image, and it comes
    /// and goes as the page zooms open and is dragged shut.
    @ViewBuilder func noBarShade(_ edges: Edge.Set = .all) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: edges)
        } else {
            self
        }
    }

    /// Under the tab bar the shade has to stay: the bar's labels are white
    /// (the app is dark), and over a cream card with nothing dark behind the
    /// glass they vanish. A hard edge keeps it a short band behind the bar
    /// instead of a long dim creeping up the card.
    @ViewBuilder func tabBarBand() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            self
        }
    }

    /// A round button that belongs to the page: solid, no glass, so it reads
    /// on the cream picture and on the black below it alike.
    func pageButtonFace() -> some View {
        foregroundStyle(Color(red: 0.13, green: 0.12, blue: 0.11))
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.white.opacity(0.92)))
            .contentShape(Circle())
    }

    func arrives(_ shown: Bool, step: Int) -> some View {
        // The spring reaches the fade and the short slide only. Applied to
        // the whole view, it also carried the view's PLACE: in nawana the page
        // is a full-screen cover, first laid out at another size, and the
        // buttons at its foot flew down from the top (2026-11-13, founder).
        animation(.spring(response: 0.55, dampingFraction: 0.9).delay(0.12 + Double(step) * 0.07)) {
            $0.opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 26)
        }
    }
}

/// The face every challenge card shares: its figure, its kind and its title,
/// on the card ground. The grid, the ticket and the page's hero all draw it,
/// so the card the learner tapped is the card that grows.
struct ChallengeCardFace: View {
    let script: SpeechScript
    let category: String?
    var figureHeight: CGFloat? = nil
    var titleSize: CGFloat = 17
    var titleLines: Int = 2
    /// One of the learner's own scripts (2026-11-13, founder: My scripts
    /// wears the challenge cards): its kind drawn where a challenge has its
    /// picture, and its length where a challenge says who is on it.
    var mine: Bool = false
    /// Who is on the public board. Off on a group's card: in a group the
    /// standings are the group's.
    var showsCrowd: Bool = true

    @ObservedObject private var challenges = SpeechChallenges.shared

    private var large: Bool { titleSize > 24 }
    private var standing: SpeechChallenges.Standing? { challenges.standings[script.id] }

    var body: some View {
        VStack(spacing: large ? 12 : 8) {
            if let art = ChallengeArt.image(for: script.id) {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: figureHeight ?? .infinity)
                    .frame(height: figureHeight)
            } else if mine {
                Image(systemName: script.genre.symbol)
                    .font(.system(size: large ? 84 : 52, weight: .light))
                    .foregroundStyle(ChallengeArt.inkText.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: figureHeight ?? .infinity)
                    .frame(height: figureHeight)
            } else {
                Spacer(minLength: 0)
            }
            VStack(spacing: large ? 6 : 3) {
                // The category as an eyebrow over the title (2026-11-13,
                // founder). Every card keeps its line, so titles stay level.
                eyebrow
                    .font((large ? Font.caption : .caption2).weight(.semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(ChallengeArt.inkText.opacity(0.45))
                    .lineLimit(1)
                Text(script.title)
                    .font(Arena.display(titleSize))
                    .foregroundStyle(ChallengeArt.inkText)
                    .multilineTextAlignment(.center)
                    // Every card keeps room for the longest title, so a short
                    // one never hands its line to the picture.
                    .lineLimit(titleLines, reservesSpace: true)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            if mine {
                Text(SpeechFormat.length(SpeechLibrary.estimatedSeconds(script.body, language: script.language)))
                    .font((large ? Font.footnote : .caption2).monospacedDigit())
                    .foregroundStyle(ChallengeArt.inkText.opacity(0.5))
                    .lineLimit(1)
                    .frame(height: large ? 22 : 16)
            } else if showsCrowd {
                crowd
            }
        }
    }

    private var eyebrow: Text {
        if mine {
            return script.isBuiltIn ? Text("Sample") : Text(verbatim: script.genre.title)
        }
        return Text(verbatim: SpeechChallengeCategory.label(category) ?? " ")
    }

    /// Who is on it, quietly (2026-11-13, founder: "minimal, but say how many
    /// took it and who leads"): the top three's faces and the count.
    private var crowd: some View {
        let people = standing?.entrants ?? 0
        let faces = Array((standing?.topThree ?? []).prefix(3))
        let size: CGFloat = large ? 22 : 16
        return HStack(spacing: 6) {
            if !faces.isEmpty {
                HStack(spacing: -size * 0.3) {
                    ForEach(Array(faces.enumerated()), id: \.offset) { i, face in
                        CardLeaderFace(face: face, size: size)
                            .zIndex(Double(3 - i))
                    }
                }
            }
            Group {
                if people > 0 {
                    Text("\(people) taking part")
                } else {
                    Text("Be the first")
                }
            }
            .font((large ? Font.footnote : .caption2).monospacedDigit())
            .foregroundStyle(ChallengeArt.inkText.opacity(0.5))
            .lineLimit(1)
        }
        .frame(height: size)
    }
}

/// A leader's face on a cream card: their photo, or their initial.
private struct CardLeaderFace: View {
    let face: SpeechChallenges.Face
    let size: CGFloat

    var body: some View {
        Group {
            if let image = face.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(face.display_name.first.map { String($0).uppercased() } ?? "")
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(ChallengeArt.inkText.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ChallengeArt.faceFill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(ChallengeArt.paper, lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}

struct SpeechArenaDetail: View {
    let script: SpeechScript
    var zoomID: String? = nil
    var zoom: Namespace.ID? = nil
    /// Shown over the whole tab (nawana's grid presents it full screen): the
    /// tab bar is already covered, and hiding it underneath would move the
    /// page behind while the card zooms.
    var covering: Bool = false

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var challenges = SpeechChallenges.shared
    @ObservedObject private var store = SpeechStore.shared
    #if SPEECH_APP
    @ObservedObject private var groups = SpeechGroups.shared
    #endif
    @ObservedObject private var gate = BillingGate.shared
    @Environment(\.dismiss) private var dismiss

    @State private var board: [SpeechChallenges.BoardRow]?
    @State private var shown = false
    @State private var practicing = false
    @State private var naming = false
    @State private var startAfterNaming = false
    @State private var showingScript = false
    @State private var showingTakes = false
    @State private var showingMedals = false
    @State private var confirmWithdraw = false
    @State private var confirmRetire = false
    /// The fluent reading's opening, fading in as the page opens (2026-11-13,
    /// founder: an intro to how it should sound).
    @StateObject private var intro = SpeechListenModel()

    private var standing: SpeechChallenges.Standing? { challenges.standings[script.id] }
    private var isPast: Bool { standing?.retiredAt != nil }
    private var best: Int? { [standing?.myBest, store.best(for: script.id)].compactMap { $0 }.max() }
    private var takes: Int { store.takes(for: script.id).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 28) {
                    about.arrives(shown, step: 0)
                    VStack(alignment: .leading, spacing: 8) {
                        mine
                        seasonRecordLine
                    }
                    .arrives(shown, step: 1)
                    #if SPEECH_APP
                    // The group's standings, while this is its running round.
                    if let group = groups.selected, let round = groups.runningRound(for: script.id) {
                        groupSection(group, round: round).arrives(shown, step: 2)
                    }
                    #endif
                    everyone.arrives(shown, step: 3)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
        }
        // The picture runs under the status bar to the screen's edges.
        .ignoresSafeArea(edges: .top)
        .noBarShade(.top)
        .background(Look.page.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // Clock and battery against the picture's ground: light over the
        // speech app's graphite, dark over nawana's cream.
        .toolbarColorScheme(SpeechAppFlags.isSpeechApp ? .dark : .light, for: .navigationBar)
        // The page draws its own back and ⋯ (`pageButtons`): the system's
        // glass buttons are drawn apart from the page, and while it zooms
        // open or is dragged shut they showed as grey blocks on the picture.
        .navigationBarBackButtonHidden(true)
        .overlay(alignment: .top) { pageButtons }
        // A challenge is a page of its own: the tabs step aside and the
        // buttons below are the way on (2026-11-13, founder).
        // Through the shared hider: nawana's tab roots hold the bar's
        // visibility themselves, and a page's own `.toolbar` alone left the
        // tabs showing there.
        .hidesTabBar(!covering)
        .safeAreaInset(edge: .bottom) { actions.arrives(shown, step: 4) }
        .zoomDestination(zoomID ?? "", in: zoomID == nil ? nil : zoom)
        // The boards load once the card has grown, not during it.
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            await reload()
        }
        .refreshable { await reload() }
        // After the card has grown: a sound under a zoom that is still
        // opening reads as the tap making a noise.
        .task {
            guard SpeechListenService.available(for: script) else { return }
            try? await Task.sleep(for: .milliseconds(600))
            await intro.load(script)
            // Only the first time this challenge is opened (2026-11-13,
            // founder); after that the reading is the Script button's.
            if !practicing, !showingScript, !showingTakes, intro.phase == .ready,
               IntroMemory.firstOpening(of: script.id) {
                intro.playIntro()
            }
        }
        .onAppear { shown = true }
        .onDisappear { intro.fadeOut() }
        .onChange(of: practicing) { _, on in if on { intro.fadeToPause() } }
        .onChange(of: showingTakes) { _, on in if on { intro.fadeToPause() } }
        .sheet(isPresented: $naming, onDismiss: {
            if startAfterNaming, SpeechChallenges.displayName != nil {
                startAfterNaming = false
                practicing = true
            }
        }) {
            SpeechChallengeNameSheet(suggested: appState.persona?.displayName ?? "")
        }
        .sheet(isPresented: $showingScript) { SpeechScriptSheet(script: script, reading: intro) }
        .sheet(isPresented: $showingMedals) { MedalGuideSheet() }
        .fullScreenCover(isPresented: $showingTakes) { SpeechTakesPager(scriptId: script.id) }
        .fullScreenCover(isPresented: $practicing, onDismiss: { Task { await reload() } }) {
            SpeechPrompterView(script: script, native: appState.nativeLanguage, level: appState.proficiency)
                .environmentObject(appState)
        }
        .confirmationDialog("Remove your score from this board?", isPresented: $confirmWithdraw, titleVisibility: .visible) {
            Button("Remove me from this board", role: .destructive) {
                Task {
                    try? await challenges.withdraw(script.id)
                    await reload()
                }
            }
        }
        .confirmationDialog("Retire this challenge? It leaves everyone's Speech tab.", isPresented: $confirmRetire, titleVisibility: .visible) {
            Button("Retire", role: .destructive) {
                Task {
                    try? await challenges.retire(script.id)
                    dismiss()
                }
            }
        }
        // The speech app is a dark stage whatever the phone's mode; nawana's
        // page follows the phone (2026-11-13, founder).
        .arenaScheme(SpeechAppFlags.isSpeechApp)
    }

    // MARK: The hero: the card itself, grown

    /// The picture across the whole top of the screen, edge to edge and
    /// under the status bar, on the card's ground (2026-11-12, founder). A
    /// pull down stretches it. The title sits at its foot.
    private var hero: some View {
        VStack(spacing: 10) {
            heroPicture
            if let label = SpeechChallengeCategory.label(standing?.category) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Look.dim)
            }
            Text(script.title)
                .font(Arena.display(32))
                .foregroundStyle(Look.text)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 20)
            if let best, let tier = MedalTier(score: best) {
                // Tap: how medals work, like the medal on the "my best" card.
                Button { showingMedals = true } label: {
                    MedalBadge(tier: tier, label: "\(best)", size: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("How medals work"))
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The picture across the top, edge to edge and under the status bar. Its
    /// paper doesn't stop at a line: it bleeds into the page's black below
    /// (2026-11-12, founder). A pull down stretches it.
    private var heroPicture: some View {
        // The picture is drawn on the card's own cream, so paper and picture
        // are one sheet with no edge between them; black thickens over its
        // foot (eased, so it never meets the page as a band). Nothing here
        // reads the scroll position in the body: the stretch on a pull is a
        // `visualEffect`, worked out at draw time, so a zoom or a scroll never
        // rebuilds this block (it did every frame, and the open stuttered).
        ZStack(alignment: .top) {
            ChallengeArt.paper
            if let art = ChallengeArt.image(for: script.id) {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFit()
                    .padding(.top, 36)
            }
        }
        .frame(height: 480, alignment: .top)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay {
            LinearGradient(stops: [
                .init(color: Look.page.opacity(0), location: 0.56),
                .init(color: Look.page.opacity(0.1), location: 0.64),
                .init(color: Look.page.opacity(0.3), location: 0.73),
                .init(color: Look.page.opacity(0.55), location: 0.82),
                .init(color: Look.page.opacity(0.8), location: 0.9),
                .init(color: Look.page.opacity(0.95), location: 0.96),
                .init(color: Look.page, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .visualEffect { content, proxy in
            let pull = max(0, proxy.frame(in: .scrollView).minY)
            return content.scaleEffect(1 + pull / 480, anchor: .bottom)
        }
    }

    // MARK: What it is

    private var about: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let intro = SpeechChallenges.intro(standing, native: LanguageCatalog.currentNative) {
                Text(intro)
                    .font(.body)
                    .foregroundStyle(Look.body)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !script.summary.isEmpty {
                Text(script.summary).font(.body).foregroundStyle(Look.body)
            }
            HStack(spacing: 8) {
                Text(SpeechFormat.length(SpeechLibrary.estimatedSeconds(script.body, language: script.language)))
                Text(verbatim: "·")
                Text(script.genre.title)
                if let tries = standing?.attempts, tries > 0 {
                    Text(verbatim: "·")
                    Text("\(tries) tries")
                }
            }
            .font(.footnote)
            .foregroundStyle(Look.dim)
            if let link = standing?.link {
                Link(destination: link) {
                    Label("Watch the original", systemImage: "play.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Look.text)
                }
            }
        }
    }

    // MARK: Me: my best, the next medal, my place

    private var mine: some View {
        HStack(spacing: 16) {
            // Tap: how medals work (a medal is a score, not a place).
            Button { showingMedals = true } label: {
                MedalBadge(tier: best.flatMap(MedalTier.init(score:)), label: best.map(String.init) ?? "", size: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("How medals work"))
            VStack(alignment: .leading, spacing: 3) {
                if let best {
                    Text("Best \(best)").font(Arena.display(22))
                } else {
                    Text("Not tried yet").font(Arena.display(22))
                }
                nextMedal.font(.subheadline).foregroundStyle(Look.dim)
            }
            Spacer()
            if let rank = standing?.myRank {
                VStack(spacing: 2) {
                    Text(verbatim: "#\(rank)").font(Arena.display(22)).monospacedDigit()
                    Text("of \(standing?.entrants ?? rank)").font(.caption).foregroundStyle(Look.dim)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Look.card))
    }

    /// A challenge back from an earlier season keeps my score there, frozen.
    @ViewBuilder
    private var seasonRecordLine: some View {
        if let record = challenges.seasonRecords[script.id] {
            Text("Season \(record.season): \(record.score) · #\(record.rank) of \(record.entrants)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Look.dim)
                .padding(.horizontal, 18)
        }
    }

    private var nextMedal: Text {
        guard let best else { return Text("Gold at 90") }
        if best >= 90 { return Text("Gold won") }
        if let next = MedalTier.allCases.first(where: { $0.bar > best }) {
            switch next {
            case .bronze: return Text("\(next.bar - best) to bronze")
            case .silver: return Text("\(next.bar - best) to silver")
            case .gold: return Text("\(next.bar - best) to gold")
            }
        }
        return Text("Gold at 90")
    }

    // MARK: Boards

    #if SPEECH_APP
    private func groupSection(_ group: SpeechGroups.Group, round: SpeechGroups.Round) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.name).font(Arena.display(24))
                Spacer()
                Label(SpeechGroupTime.left(until: round.ends_at), systemImage: "clock")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Look.dim)
            }
            if let rows = groups.roundBoard {
                VStack(spacing: 0) {
                    ForEach(rows) { row in groupLine(row) }
                }
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Look.card))
            } else {
                HStack { Spacer(); ProgressView().tint(Look.dim); Spacer() }
            }
            Text("Takes made before the deadline count, camera on or off. The best score then takes the card.")
                .font(.footnote)
                .foregroundStyle(Look.faint)
        }
    }

    private func groupLine(_ row: SpeechGroups.RoundRow) -> some View {
        HStack(spacing: 12) {
            Group {
                if let rank = row.rank, let tier = MedalTier(rank: rank) {
                    MedalBadge(tier: tier, label: "\(rank)", size: 34)
                } else {
                    Text(verbatim: row.rank.map { "\($0)" } ?? "–")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Look.dim)
                }
            }
            .frame(width: 34)
            SpeechChallengeFace(face: row.face, size: 34)
                .opacity(row.score == nil ? 0.5 : 1)
            Text(row.shownName)
                .font(.body.weight(row.is_me ? .semibold : .regular))
                .foregroundStyle(row.score == nil ? Look.dim : .primary)
                .lineLimit(1)
            if row.is_me {
                Text("You").font(.caption.weight(.semibold)).foregroundStyle(Arena.gold)
            }
            Spacer()
            if let score = row.score {
                Text(verbatim: "\(score)")
                    .font(Arena.display(20))
                    .monospacedDigit()
            } else {
                Text("Not started").font(.footnote).foregroundStyle(Look.dim)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    #endif

    private var everyone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leaderboard").font(Arena.display(24))
            if let board {
                if board.isEmpty {
                    Text("Nobody's on this board yet. Be the first.").font(.subheadline).foregroundStyle(Look.dim)
                } else {
                    VStack(spacing: 0) {
                        ForEach(board) { row in boardLine(row) }
                    }
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Look.card))
                }
            } else {
                HStack { Spacer(); ProgressView().tint(Look.dim); Spacer() }
            }
            Group {
                if isPast {
                    Text("This challenge has ended. These are the final standings.")
                } else {
                    Text("Camera-on takes go on the board, and your best one stands. The board shows your name and score — your video and voice stay on your phone.")
                }
            }
                .font(.footnote)
                .foregroundStyle(Look.faint)
        }
    }

    private func boardLine(_ row: SpeechChallenges.BoardRow) -> some View {
        HStack(spacing: 12) {
            if let tier = MedalTier(rank: row.rank) {
                MedalBadge(tier: tier, label: "\(row.rank)", size: 34)
            } else {
                Text(verbatim: "\(row.rank)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Look.dim)
                    .frame(width: 34)
            }
            SpeechChallengeFace(face: row.face, size: 34)
            Text(row.display_name)
                .font(.body.weight(row.is_me ? .semibold : .regular))
                .lineLimit(1)
            // nawana's Core seat rides beside the name, as on its old board.
            if !SpeechAppFlags.isSpeechApp, let theme = row.core_theme { CoreCubeBadge(theme: theme) }
            if row.is_me {
                Text("You").font(.caption.weight(.semibold)).foregroundStyle(Arena.gold)
            }
            Spacer()
            Text(verbatim: "\(row.score)")
                .font(Arena.display(20))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: The way in

    private var actions: some View {
        HStack(spacing: 10) {
            Button { showingTakes = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.headline)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Look.raised))
                    .overlay(alignment: .topTrailing) {
                        if takes > 0 {
                            Text("\(takes)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(Look.ctaText)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Look.cta))
                        }
                    }
            }
            .accessibilityLabel(Text("Takes"))
            // A mini player (2026-11-13, founder): the fluent reading's
            // progress fills a ring inside the button, and a tap opens the
            // script with the reading going on from where the intro paused.
            MiniReadingButton(model: intro) {
                intro.playOn()
                showingScript = true
            }
            Button(action: start) {
                Text(isPast ? LocalizedStringKey("speech.challenge.practice")
                            : best == nil ? LocalizedStringKey("speech.challenge.take")
                                          : LocalizedStringKey("speech.challenge.again"))
                    .font(.headline)
                    .foregroundStyle(Look.ctaText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(Look.cta))
            }
        }
        .foregroundStyle(Look.text)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(LinearGradient(colors: [Look.page.opacity(0), Look.page], startPoint: .top, endPoint: .center).ignoresSafeArea())
    }

    private var pageButtons: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .pageButtonFace()
            }
            .accessibilityLabel(Text("Back"))
            Spacer()
            AppMenu {
                Button {
                    startAfterNaming = false
                    naming = true
                } label: {
                    Label("Name on the board", systemImage: "person.text.rectangle")
                }
                if standing?.myBest != nil {
                    Button(role: .destructive) { confirmWithdraw = true } label: {
                        Label("Remove me from this board", systemImage: "minus.circle")
                    }
                }
                if gate.account?.unlimited == true, !isPast {
                    Button(role: .destructive) { confirmRetire = true } label: {
                        Label("Retire challenge", systemImage: "archivebox")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .pageButtonFace()
            }
            .accessibilityLabel(Text("More"))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    /// Nothing goes on a public board until the learner has seen the name.
    private func start() {
        if !isPast, SpeechChallenges.displayName == nil {
            startAfterNaming = true
            naming = true
        } else {
            practicing = true
        }
    }

    private func reload() async {
        async let rows = challenges.board(script.id)
        #if SPEECH_APP
        if groups.runningRound(for: script.id) != nil {
            await groups.refreshSelected()
        }
        #endif
        if let rows = await rows { board = rows }
    }
}

/// Which challenges have played their intro on this phone: it plays on the
/// first opening only.
private enum IntroMemory {
    private static let key = "speech.introHeard"

    /// True once per challenge: the first call records it.
    static func firstOpening(of id: UUID) -> Bool {
        let d = UserDefaults.standard
        var heard = Set(d.stringArray(forKey: key) ?? [])
        guard heard.insert(id.uuidString).inserted else { return false }
        d.set(Array(heard), forKey: key)
        return true
    }
}

/// The page's fluent reading as a mini player (2026-11-13, founder: not a
/// ring pulsing outside the button, a progress ring inside it). A tap opens
/// the script, the reading playing on in it. Its own view, so the player's
/// 30-a-second clock redraws this and nothing else.
private struct MiniReadingButton: View {
    @ObservedObject var model: SpeechListenModel
    @ObservedObject var player: AudioPlayer
    let open: () -> Void

    init(model: SpeechListenModel, open: @escaping () -> Void) {
        self.model = model
        self.player = model.player
        self.open = open
    }

    var body: some View {
        let ready = model.phase == .ready
        ZStack {
            Circle().fill(Look.raised)
            if ready {
                Circle()
                    .stroke(Look.ringTrack, lineWidth: 2.5)
                    .padding(4)
                Circle()
                    .trim(from: 0, to: model.progress)
                    .stroke(Arena.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(4)
                    .animation(.linear(duration: 0.1), value: model.progress)
            }
            Image(systemName: "doc.text").font(.headline)
        }
        .frame(width: 52, height: 52)
        .contentShape(Circle())
        .onTapGesture(perform: open)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Script"))
    }
}

/// The page's colours (2026-11-13, founder): the speech app's dark stage as
/// it was, and in nawana the system's own, so the page follows the phone's
/// light or dark mode like every other page there.
private enum Look {
    static let adaptive = !SpeechAppFlags.isSpeechApp
    static var page: Color { adaptive ? Color(.systemGroupedBackground) : .black }
    static var card: Color { adaptive ? Color(.secondarySystemGroupedBackground) : Arena.card }
    static var raised: Color { adaptive ? Color(.secondarySystemGroupedBackground) : Arena.raised }
    static var text: Color { adaptive ? .primary : .white }
    static var body: Color { adaptive ? .primary : .white.opacity(0.85) }
    static var dim: Color { adaptive ? .secondary : Arena.dim }
    static var faint: Color { adaptive ? Color(.tertiaryLabel) : .white.opacity(0.4) }
    /// The main button: the opposite of the page.
    static var cta: Color { adaptive ? Color(.label) : Color(white: 0.92) }
    static var ctaText: Color { adaptive ? Color(.systemBackground) : .black }
    static var ringTrack: Color { adaptive ? Color(.systemFill) : .white.opacity(0.12) }
}
