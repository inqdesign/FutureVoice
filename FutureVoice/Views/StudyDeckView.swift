import SwiftUI

/// The daily deck drops into the SAME four bins as the sentence deck —
/// `DrillBin` itself, so the two decks can never drift apart. The three
/// delays schedule the item's return (via `StudyScheduleStore`, the parent's
/// job); "Got it" files it as known. Display strings live here as literal
/// LocalizedStringKeys so they extract into the catalog (DrillBin's own
/// `title` is a plain String).
private extension DrillBin {
    var deckTitle: LocalizedStringKey {
        switch self {
        // Follows DrillBin's own label so the deck can't advertise a delay
        // the schedule doesn't keep (see `DrillBin.soonDelay`).
        case .tenMinutes: return LocalizedStringKey(DrillBin.soonTitle)
        case .tomorrow:   return "Tomorrow"
        case .threeDays:  return "3 days"
        case .gotIt:      return "Got it"
        }
    }
    /// Same schedule hints as the drill tray; only "Got it" reads differently
    /// — here it means known, not a ladder promotion.
    var deckDropHint: LocalizedStringKey {
        switch self {
        case .tenMinutes: return LocalizedStringKey(DrillBin.soonHint)
        case .tomorrow:   return "Back tomorrow"
        case .threeDays:  return "Back in 3 days"
        case .gotIt:      return "Marked as known"
        }
    }
}

/// The daily challenge deck — the Words and Expressions sessions share this
/// one surface, and it deliberately speaks the drill deck's language: a card
/// stack graded by dragging into the SAME four folders (10 min · Tomorrow ·
/// 3 days · Got it — `DrillBin` itself), with the same thresholds, fly-to-bin
/// swallow and haptics. Front of the card is the item alone — recall first;
/// tap flips the meaning (`WordLore`, which handles phrases like single
/// words). The delays schedule the item's return through the parent's
/// `onResolve`; Got it files it as known.
/// One card in a daily deck: the text plus what kind of thing it is, so a
/// mixed review session (words AND expressions, whatever came due) can
/// resolve each card into the right store.
struct StudyDeckItem: Identifiable, Hashable {
    let kind: StudyScheduleStore.Kind
    let text: String
    var id: String { kind.rawValue + "|" + text.lowercased() }

    static func word(_ t: String) -> StudyDeckItem { .init(kind: .word, text: t) }
    static func expression(_ t: String) -> StudyDeckItem { .init(kind: .expression, text: t) }
}

struct StudyDeckView: View {
    /// What the page is called. The deck draws it ITSELF, stacked over the
    /// progress counter in the navigation bar's centre — see `deckHeader`.
    let title: LocalizedStringKey
    /// The dealt hand, in order. Fixed for the session.
    let items: [StudyDeckItem]
    /// A card was dropped into a folder — the parent writes the store state
    /// (schedule or known) and the rep. Called for every drop.
    let onResolve: (StudyDeckItem, DrillBin) -> Void

    @EnvironmentObject private var appState: AppState

    @State private var queue: [StudyDeckItem] = []
    @State private var dealt = false
    @State private var resolvedCount = 0
    /// Top card flipped to its meaning. Reset per card.
    @State private var revealed = false
    @State private var entry: WordEntry?
    @State private var loadingEntry = false
    /// The lookup failed — the deck offers the same retry the cards do, so a
    /// flaky moment doesn't cost the learner the card.
    @State private var lookupFailed = false
    /// What landed where this session — the chips' counts and their folder
    /// sheets, same as the drill deck's folders.
    @State private var folderItems: [DrillBin: [StudyDeckItem]] = [:]
    @State private var openFolder: DrillBin?
    @StateObject private var player = AudioPlayer()
    @State private var loadingAudio = false

    // Drag state — mirrors DrillView.
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var activeTarget: DropTarget?
    @State private var binFrames: [DrillBin: CGRect] = [:]
    @State private var flyScale: CGFloat = 1
    @State private var flyOpacity: Double = 1

    /// Content color on the accent slab — same values as the drill card's
    /// (fileprivate there, so restated rather than exposed).
    private static let onCard: Color = .white

    private static let commitThreshold: CGFloat = 64
    private static let binDeadZone: CGFloat = 28
    private static let binHysteresis: CGFloat = 14
    private static let deckSpace = "studydeck"
    /// Upward travel that means "not into any of these". Above the folders'
    /// dead zone so a sideways drag that drifts a little high still files.
    private static let cancelThreshold: CGFloat = 44

    var body: some View {
        // The deck reads the height it was OFFERED, never the height it ended
        // up at. Those differ exactly when it matters: a card whose meaning
        // has overrun its slab reports the overrun as available room, so
        // sizing off its own frame would let it keep growing. The proposal
        // from above can't be pushed by content, so it's the honest number —
        // and every card below is cut to fit it (see `cardHeight`).
        GeometryReader { geo in
            Group {
                if queue.isEmpty && dealt {
                    doneState
                } else if !queue.isEmpty {
                    deckBody(offered: geo.size.height)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar { deckHeader }
        .onAppear {
            guard !dealt else { return }
            queue = items
            dealt = true
            #if DEBUG
            if DebugCapture.previewStudyTray {
                revealed = true
                isDragging = true
                activeTarget = .cancel
            }
            #endif
        }
    }

    // MARK: - Deck

    /// The page title with the deck's progress under it, in the navigation
    /// bar's centre. The counter used to be a line of its own above the deck,
    /// which cost the card a full row to say "1 of 10" — the smallest thing
    /// on the screen paying the same rent as the biggest. It's a subtitle;
    /// the bar is where a subtitle goes, and the row it vacated goes to the
    /// card, which is the one thing here that can always use more of it.
    private var deckHeader: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.headline)
                Text("\(min(resolvedCount + 1, items.count)) of \(items.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    // Matched by identifier in the drag tests: the label is
                    // chrome, so it's in whatever language the profile under
                    // test happens to be learning.
                    .accessibilityIdentifier("studyDeck.counter")
            }
            .animation(.snappy, value: resolvedCount)
        }
    }

    /// Everything in the deck that ISN'T the card: the drag hint, the folder
    /// chips, and the spacing/padding between them. Subtracted from the
    /// offered height to get the card's real budget.
    /// drag hint 40 + chips 34 + two 12pt gaps + 20pt padding.
    private static let deckFurnitureHeight: CGFloat = 118

    /// The card's height, fixed rather than grown-to-fit. Fixing it is what
    /// makes the card safe on a small screen: the meaning side then gets a
    /// BOUNDED proposal, which is the only thing `ViewThatFits` can measure
    /// against. Floor of 240 so a freak-small container degrades to a
    /// scrunched card rather than an invisible one.
    private func cardHeight(offered: CGFloat) -> CGFloat {
        max(240, offered - Self.deckFurnitureHeight)
    }

    private func deckBody(offered: CGFloat) -> some View {
        VStack(spacing: 12) {
            deck(height: cardHeight(offered: offered))
            // Mid-drag the panel says where the card is headed; this row keeps
            // its height so the deck doesn't jump when the drag begins.
            Label("Drag the card into a folder", systemImage: "hand.draw")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .opacity(isDragging ? 0 : 1)
            // The folders live where the tray will rise — at rest they're
            // quiet counters, mid-drag the panel takes their place. Same
            // arrangement as the drill deck.
            folderChipsRow
                .opacity(isDragging ? 0 : 1)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        // The overlay is applied AFTER the padding, so the panel's bottom is
        // the deck's outer bottom edge; the 8pt is the resting chips' breathing
        // room, which the panel replaces rather than sits above.
        .overlay(alignment: .bottom) {
            if isDragging {
                binPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .coordinateSpace(name: Self.deckSpace)
        .onPreferenceChange(BinFramesKey.self) { binFrames = $0 }
        .sheet(item: $openFolder) { bin in
            folderSheet(bin)
        }
    }

    // MARK: - Folder chips (mirrors DrillView's)

    private var folderChipsRow: some View {
        HStack(spacing: 8) {
            ForEach(DrillBin.allCases) { bin in
                folderChip(bin)
            }
        }
    }

    private func folderChip(_ bin: DrillBin) -> some View {
        let count = folderItems[bin]?.count ?? 0
        return Button {
            openFolder = bin
        } label: {
            HStack(spacing: 5) {
                Image(systemName: bin.icon)
                    .font(.caption)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(count == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(bin.tint))
            .background(Capsule().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .animation(.snappy, value: count)
        .accessibilityLabel(Text(bin.deckTitle))
        // Stable hooks for the drag UI test — which folder actually swallowed
        // the card is invisible in the counter alone.
        .accessibilityIdentifier("studyDeck.folder.\(bin.rawValue)")
        .accessibilityValue("\(count)")
    }

    private func folderSheet(_ bin: DrillBin) -> some View {
        NavigationStack {
            List {
                ForEach(folderItems[bin] ?? []) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text)
                            .font(.subheadline)
                            .lineLimit(2)
                        Text(bin.deckDropHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if (folderItems[bin] ?? []).isEmpty {
                    ContentUnavailableView { Label(bin.deckTitle, systemImage: bin.icon) }
                }
            }
            .navigationTitle(Text(bin.deckTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { openFolder = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func deck(height: CGFloat) -> some View {
        ZStack {
            // Peek of the next card so the user feels there's a deck.
            if queue.count > 1 {
                cardSurface(queue[1].text, revealed: false, showHint: false, height: height)
                    .scaleEffect(0.95)
                    .opacity(0.45)
                    .offset(y: 14)
            }
            cardSurface(queue[0].text, revealed: revealed, showHint: true, height: height)
                .scaleEffect(flyScale)
                .opacity(flyOpacity)
                .offset(dragOffset)
                .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                .gesture(
                    DragGesture(coordinateSpace: .named(Self.deckSpace))
                        .onChanged { handleDragChanged($0) }
                        .onEnded { handleDragEnded($0) }
                )
                .onTapGesture {
                    guard !revealed else { return }
                    HapticEngine.drillCorrect()
                    withAnimation(.easeOut(duration: 0.2)) { revealed = true }
                }
                .accessibilityElement(children: .contain)
                // The card's own frame, so a UI test can check that nothing
                // inside it has spilled past the slab onto the folder chips.
                .accessibilityIdentifier("studyDeck.card")
                .accessibilityActions { binAccessibilityActions }
                .task(id: queue.first) {
                    revealed = false
                    await reloadEntry()
                }
        }
        .padding(.horizontal, 16)
    }

    /// Look up the top card's meaning. Shared by the card-changed task and by
    /// the retry button, so a retry can't drift from the first attempt.
    private func reloadEntry() async {
        entry = nil
        guard let top = queue.first else { return }
        loadingEntry = true
        lookupFailed = false
        // A mixed deck holds both kinds; each card must be looked up as what
        // it is or an expression comes back glossed as one of its words.
        let fetched = await WordLore.entry(
            for: top.text, native: appState.nativeLanguage,
            target: appState.targetLanguage,
            kind: top.kind == .expression ? .expression : .word)
        // The deck advances mid-lookup all the time; a cancelled fetch must
        // not clear the next card's loading flag.
        guard !Task.isCancelled else { return }
        entry = fetched
        lookupFailed = fetched == nil
        loadingEntry = false
    }

    /// Supporting text on the slab — the card's own "secondary".
    private static let onCardSecondary: Color = Color.white.opacity(0.72)

    /// Same slab as a drill card — same anatomy too: a caption-labeled
    /// section for the item, the flipped content below it, pill buttons on
    /// the revealed card, "tap to reveal" on the concealed one.
    private func cardSurface(_ text: String, revealed: Bool, showHint: Bool,
                             height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            labeled(revealed ? "When should it come back?" : "Say it out loud — do you know it?") {
                Text(text)
                    .font(DrillView.targetFont(for: text))
                    .foregroundStyle(Self.onCard)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if revealed {
                meaningBlock
            }

            Spacer(minLength: 12)

            if showHint {
                if revealed {
                    if appState.voiceCloneId != nil {
                        HStack(spacing: 8) {
                            pillButton(systemImage: loadingAudio ? nil : "speaker.wave.2.fill",
                                       text: loadingAudio ? "Loading…" : "Hear it",
                                       showSpinner: loadingAudio) {
                                Task { await speak(text) }
                            }
                            .disabled(loadingAudio)
                        }
                    }
                } else {
                    Label("Tap to check the meaning", systemImage: "eye")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height,
               alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .tint(Self.onCard)
        .shadow(color: Color.accentColor.opacity(0.28), radius: 8, y: 4)
    }

    /// Caption-over-content, exactly the drill card's `labeled`.
    private func labeled<Content: View>(_ label: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Self.onCardSecondary)
            content()
        }
    }

    /// The drill card's pill, restated (fileprivate there).
    private func pillButton(systemImage: String?, text: LocalizedStringKey,
                            showSpinner: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if showSpinner {
                    ProgressView().controlSize(.mini)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white.opacity(0.18)))
            .foregroundStyle(Self.onCard)
        }
        .buttonStyle(.plain)
    }

    /// The learner's own cloned voice saying the item — cache-first so the
    /// same word never bills TTS twice (same rule as the word/expression
    /// cards' pronounce buttons).
    private func speak(_ text: String) async {
        guard let voiceId = appState.voiceCloneId else { return }
        if let data = PhraseAudioStore.shared.data(text: text, voiceId: voiceId) {
            try? player.play(data, forceSessionReset: true)
            return
        }
        loadingAudio = true
        defer { loadingAudio = false }
        do {
            let data = try await ElevenLabsClient.shared.synthesize(voiceId: voiceId, text: text, purpose: "library")
            PhraseAudioStore.shared.save(data, text: text, voiceId: voiceId)
            try? player.play(data, forceSessionReset: true)
        } catch {
            // network/credits failure — leave the button idle, nothing to play
        }
    }

    /// The flipped side, laid out like the word notebook it comes from — the
    /// same numbered senses, the same part-of-speech label above the meaning,
    /// the same ruled examples. Same dictionary entry too (`WordLore.entry`);
    /// the card differs only in how much of it there is room for.
    ///
    /// How much is decided by `ViewThatFits`, not by a fixed cap. A cap in
    /// items ("two senses, one example") is a guess about heights it can't
    /// see: the same two senses are four lines on a 6.3" screen and seven on
    /// an SE, more again at large Dynamic Type or in a language that doesn't
    /// abbreviate. So the richest layout is offered first and the first one
    /// that actually fits the card wins. The last candidate is the floor —
    /// one sense, line-limited, no example — so there is always something
    /// that fits and the card can never spill onto the folder chips.
    @ViewBuilder
    private var meaningBlock: some View {
        if let senses = entry?.senses, !senses.isEmpty {
            let examples = entry?.examples ?? []
            ViewThatFits(in: .vertical) {
                meaningLayout(senses, examples, senseCount: 3, exampleCount: 2)
                meaningLayout(senses, examples, senseCount: 3, exampleCount: 1)
                // Senses outrank examples all the way down — the meaning is
                // what the card is asking about — but once a sense has been
                // dropped, spend what that freed on a second example rather
                // than leaving the slab half empty.
                meaningLayout(senses, examples, senseCount: 2, exampleCount: 2)
                meaningLayout(senses, examples, senseCount: 2, exampleCount: 1)
                meaningLayout(senses, examples, senseCount: 2, exampleCount: 0)
                meaningLayout(senses, examples, senseCount: 1, exampleCount: 1)
                meaningLayout(senses, examples, senseCount: 1, exampleCount: 0, meaningLines: 3)
            }
        } else {
            labeled("Meaning") {
                if loadingEntry {
                    LookupProgress(onCard: true)
                } else if lookupFailed {
                    LookupFailure(onCard: true) { Task { await reloadEntry() } }
                } else {
                    Text("—")
                        .font(.body)
                        .foregroundStyle(Self.onCardSecondary)
                }
            }
        }
    }

    /// One candidate layout for `ViewThatFits`. Every candidate is the same
    /// shape — only the counts change — so whichever one wins, the card reads
    /// identically.
    private func meaningLayout(_ senses: [WordEntry.Sense],
                               _ examples: [WordEntry.Example],
                               senseCount: Int,
                               exampleCount: Int,
                               meaningLines: Int? = nil) -> some View {
        let shownExamples = Array(examples.prefix(exampleCount))
        return VStack(alignment: .leading, spacing: 16) {
            labeled("Meaning") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(senses.prefix(senseCount).enumerated()), id: \.element.id) { i, s in
                        senseRow(i + 1, s, meaningLines: meaningLines)
                    }
                }
            }
            if !shownExamples.isEmpty {
                labeled(shownExamples.count == 1 ? "Example" : "Examples") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(shownExamples) { exampleRow($0) }
                    }
                }
            }
        }
    }

    /// The notebook's sense row, restated in the card's on-accent colours:
    /// numbered index, part of speech above the meaning, meaning in title3.
    private func senseRow(_ index: Int, _ s: WordEntry.Sense,
                          meaningLines: Int?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(Self.onCard)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.20)))
            VStack(alignment: .leading, spacing: 3) {
                if !s.pos.isEmpty {
                    Text(s.pos)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Self.onCardSecondary)
                }
                Text(s.meaning)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Self.onCard)
                    .lineLimit(meaningLines)
                    .fixedSize(horizontal: false, vertical: meaningLines == nil)
            }
            Spacer(minLength: 0)
        }
    }

    /// The notebook's ruled example, minus its context menu — the card is a
    /// question, not a place to file things away from.
    private func exampleRow(_ ex: WordEntry.Example) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.35))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(ex.text)
                    .font(.callout)
                    .foregroundStyle(Self.onCard)
                    .fixedSize(horizontal: false, vertical: true)
                if let meaning = ex.meaning, !meaning.isEmpty {
                    Text(meaning)
                        .font(.footnote)
                        .foregroundStyle(Self.onCardSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var doneState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Done for today")
                .font(.headline)
            Text(explain("Every card in today's hand is sorted. Come back tomorrow — or keep going from the library below."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bin panel (mirrors DrillView's)

    private var binPanel: some View {
        VStack(spacing: 10) {
            // Above the row, and centred: the folders are a decision, and
            // this is the way past it — so it sits on the path back to the
            // card rather than at the end of the row, where it would read as
            // a fifth folder.
            cancelSlot
            HStack(spacing: 8) {
                ForEach(DrillBin.allCases) { bin in
                    binSlot(bin)
                }
            }
            Group {
                switch activeTarget {
                case .bin(let bin): Text(bin.deckDropHint)
                case .cancel:       Text("Leave it undecided")
                case nil:           Text("Drop it on a folder")
                }
            }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: activeTarget)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        // As low as it can go. The tray used to run past the screen edge
        // (`ignoresSafeArea`), so its inner padding read as part of a surface
        // that reached the bottom; without the slab that same padding just
        // left the folders floating short of it.
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity)
        // No slab behind the row. The folders and the cancel circle carry
        // their own fills, and a tray drawn around them read as a second
        // surface sliding up over the card.
        .allowsHitTesting(false)
    }

    /// The way out: drag UP and the card goes back where it was. Not red —
    /// nothing is being destroyed, and a card you aren't ready to answer for
    /// is a normal thing to want, not a mistake being undone.
    private var cancelSlot: some View {
        let active = activeTarget == .cancel && isDragging
        return Image(systemName: "xmark")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(active ? Color(.systemBackground) : Color.secondary)
            .frame(width: 46, height: 46)
            .background {
                // Blur, not a translucent fill: with no tray behind the row
                // each target has to make its own backdrop, and a fill lets
                // the card's text read straight through it. Aimed-at, it goes
                // OPAQUE (systemGray, not `.secondary` — a label colour is
                // ~60% alpha, so the card showed through the one target the
                // finger is on).
                Circle().fill(active ? AnyShapeStyle(Color(.systemGray))
                                     : AnyShapeStyle(.regularMaterial))
            }
            .scaleEffect(active ? 1.12 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: active)
            .accessibilityIdentifier("studyDeck.cancel")
            .accessibilityLabel(Text("Leave it undecided"))
    }

    private func binSlot(_ bin: DrillBin) -> some View {
        let active = activeTarget == .bin(bin) && isDragging
        return VStack(spacing: 5) {
            Image(systemName: bin.icon)
                .font(.title3)
            Text(bin.deckTitle)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .foregroundStyle(active ? Color.white : Color.secondary)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(active ? AnyShapeStyle(bin.tint) : AnyShapeStyle(.regularMaterial))
        }
        .scaleEffect(active ? 1.08 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: active)
        .background {
            GeometryReader { g in
                Color.clear.preference(key: BinFramesKey.self,
                                       value: [bin: g.frame(in: .named(Self.deckSpace))])
            }
        }
    }

    /// VoiceOver can't drag. Same three outcomes, as rotor actions.
    @ViewBuilder
    private var binAccessibilityActions: some View {
        ForEach(DrillBin.allCases) { bin in
            Button {
                apply(bin)
            } label: {
                Text(bin.deckTitle)
            }
        }
    }

    // MARK: - Drag → bin (mirrors DrillView)

    private func handleDragChanged(_ value: DragGesture.Value) {
        if !isDragging {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isDragging = true }
        }
        dragOffset = value.translation
        updateActiveTarget(fingerX: value.location.x, translation: value.translation)
    }

    /// Which bin the FINGER is over, by nearest centre in the deck's own
    /// coordinate space. (The drill deck derives this from deck-centre +
    /// translation; here the deck-frame preference silently never delivered —
    /// midX stayed 0 and the highlight pinned to the left folders — so the
    /// gesture reports its location in the named space directly instead.)
    private func updateActiveTarget(fingerX: CGFloat, translation: CGSize) {
        let travelled = hypot(translation.width, translation.height)
        guard travelled > Self.binDeadZone, !binFrames.isEmpty else {
            if activeTarget != nil { activeTarget = nil }
            return
        }
        // Direction decides between the two KINDS of target before position
        // decides between folders. The folders sit at the bottom of the
        // screen, so pulling the card up is already the gesture for "away
        // from all of them" — cancel only has to be given a face.
        if translation.height < -Self.cancelThreshold {
            guard activeTarget != .cancel else { return }
            activeTarget = .cancel
            HapticEngine.drillBinChanged()
            return
        }
        let candidate = binFrames
            .min { abs($0.value.midX - fingerX) < abs($1.value.midX - fingerX) }
            .map(\.key)
        guard let candidate, activeTarget != .bin(candidate) else { return }
        // Hysteresis applies between two FOLDERS only. Coming back down from
        // cancel there is no previous folder to be sticky about, and making
        // it sticky would leave the card highlighting nothing on the way.
        if case .bin(let current) = activeTarget,
           let currentFrame = binFrames[current],
           let candidateFrame = binFrames[candidate] {
            let gain = abs(currentFrame.midX - fingerX) - abs(candidateFrame.midX - fingerX)
            guard gain > Self.binHysteresis else { return }
        }
        activeTarget = .bin(candidate)
        HapticEngine.drillBinChanged()
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let travelled = hypot(value.translation.width, value.translation.height)
        // Cancel and "didn't drag far enough" end the same way, on purpose:
        // the card goes back, undecided, and nothing is written. The circle
        // exists to make that outcome VISIBLE, not to add a new one.
        guard travelled > Self.commitThreshold,
              case .bin(let bin) = activeTarget else {
            springBack()
            return
        }
        drop(into: bin, from: value.location)
    }

    private func springBack() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            dragOffset = .zero
            isDragging = false
        }
        activeTarget = nil
    }

    private func drop(into bin: DrillBin, from endLocation: CGPoint) {
        HapticEngine.drillBinned(mastered: bin == .gotIt)
        let target = binFrames[bin].map {
            CGSize(width: dragOffset.width + ($0.midX - endLocation.x),
                   height: dragOffset.height + ($0.midY - endLocation.y))
        } ?? .zero
        withAnimation(.easeIn(duration: 0.28)) {
            dragOffset = target
            flyScale = 0.12
            flyOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            apply(bin)
            dragOffset = .zero
            flyScale = 1
            flyOpacity = 1
            withAnimation(.easeOut(duration: 0.2)) { isDragging = false }
            activeTarget = nil
        }
    }

    /// Every drop resolves the card, exactly like the drill deck: the three
    /// delays schedule its return (a review happened — it counts), "Got it"
    /// files it as known. The parent writes the store state and the rep.
    private func apply(_ bin: DrillBin) {
        guard let top = queue.first else { return }
        player.stop()
        queue.removeFirst()
        resolvedCount += 1
        folderItems[bin, default: []].append(top)
        onResolve(top, bin)
        revealed = false
    }

    // MARK: - Geometry plumbing

    private struct BinFramesKey: PreferenceKey {
        static var defaultValue: [DrillBin: CGRect] { [:] }
        static func reduce(value: inout [DrillBin: CGRect], nextValue: () -> [DrillBin: CGRect]) {
            value.merge(nextValue()) { _, new in new }
        }
    }
}
