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
        // the schedule doesn't keep (DEBUG shortens it — see `soonDelay`).
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
    /// What landed where this session — the chips' counts and their folder
    /// sheets, same as the drill deck's folders.
    @State private var folderItems: [DrillBin: [StudyDeckItem]] = [:]
    @State private var openFolder: DrillBin?
    @StateObject private var player = AudioPlayer()
    @State private var loadingAudio = false

    // Drag state — mirrors DrillView.
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var activeBin: DrillBin?
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

    var body: some View {
        Group {
            if queue.isEmpty && dealt {
                doneState
            } else if !queue.isEmpty {
                deckBody
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard !dealt else { return }
            queue = items
            dealt = true
        }
    }

    // MARK: - Deck

    private var deckBody: some View {
        VStack(spacing: 12) {
            Text("\(min(resolvedCount + 1, items.count)) of \(items.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            deck
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

    private var deck: some View {
        ZStack {
            // Peek of the next card so the user feels there's a deck.
            if queue.count > 1 {
                cardSurface(queue[1].text, revealed: false, showHint: false)
                    .scaleEffect(0.95)
                    .opacity(0.45)
                    .offset(y: 14)
            }
            cardSurface(queue[0].text, revealed: revealed, showHint: true)
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
                .accessibilityActions { binAccessibilityActions }
                .task(id: queue.first) {
                    revealed = false
                    entry = nil
                    guard let top = queue.first else { return }
                    loadingEntry = true
                    // A mixed deck holds both kinds; each card must be looked
                    // up as what it is or an expression comes back glossed as
                    // one of its words.
                    let fetched = await WordLore.entry(
                        for: top.text, native: appState.nativeLanguage,
                        target: appState.targetLanguage,
                        kind: top.kind == .expression ? .expression : .word)
                    // The deck advances mid-lookup all the time; a cancelled
                    // fetch must not clear the next card's loading flag.
                    guard !Task.isCancelled else { return }
                    entry = fetched
                    loadingEntry = false
                }
        }
        .padding(.horizontal, 16)
    }

    /// Supporting text on the slab — the card's own "secondary".
    private static let onCardSecondary: Color = Color.white.opacity(0.72)

    /// Same slab as a drill card — same anatomy too: a caption-labeled
    /// section for the item, the flipped content below it, pill buttons on
    /// the revealed card, "tap to reveal" on the concealed one.
    private func cardSurface(_ text: String, revealed: Bool, showHint: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            labeled(revealed ? "When should it come back?" : "Say it out loud — do you know it?") {
                Text(text)
                    .font(DrillView.targetFont(for: text))
                    .foregroundStyle(Self.onCard)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if revealed {
                labeled("Meaning") {
                    meaningBlock
                }
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
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
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

    /// The flipped side: senses + one example from the shared dictionary cache.
    @ViewBuilder
    private var meaningBlock: some View {
        if let senses = entry?.senses, !senses.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(senses.prefix(2))) { s in
                    senseRow(s)
                }
            }
            if let ex = entry?.examples.first {
                exampleRow(ex)
            }
        } else {
            if loadingEntry {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Self.onCard)
                    Text("Looking it up…")
                        .font(.subheadline)
                        .foregroundStyle(Self.onCardSecondary)
                }
            } else {
                Text("—")
                    .font(.body)
                    .foregroundStyle(Self.onCardSecondary)
            }
        }
    }

    private func senseRow(_ s: WordEntry.Sense) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.meaning)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Self.onCard)
                .fixedSize(horizontal: false, vertical: true)
            if !s.pos.isEmpty {
                Text(s.pos)
                    .font(.caption)
                    .foregroundStyle(Self.onCardSecondary)
            }
        }
    }

    private func exampleRow(_ ex: WordEntry.Example) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\u{201C}\(ex.text)\u{201D}")
                .font(.subheadline)
                .foregroundStyle(Self.onCard)
                .fixedSize(horizontal: false, vertical: true)
            if let meaning = ex.meaning, !meaning.isEmpty {
                Text(meaning)
                    .font(.caption)
                    .foregroundStyle(Self.onCardSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
            HStack(spacing: 8) {
                ForEach(DrillBin.allCases) { bin in
                    binSlot(bin)
                }
            }
            Group {
                if let activeBin {
                    Text(activeBin.deckDropHint)
                } else {
                    Text("Drop it on a folder")
                }
            }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: activeBin)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 24,
                                   style: .continuous)
                .fill(.regularMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .allowsHitTesting(false)
    }

    private func binSlot(_ bin: DrillBin) -> some View {
        let active = activeBin == bin && isDragging
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
                .fill(active ? AnyShapeStyle(bin.tint) : AnyShapeStyle(Color(.tertiarySystemFill)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(active ? 0 : 0.25),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
        updateActiveBin(fingerX: value.location.x, translation: value.translation)
    }

    /// Which bin the FINGER is over, by nearest centre in the deck's own
    /// coordinate space. (The drill deck derives this from deck-centre +
    /// translation; here the deck-frame preference silently never delivered —
    /// midX stayed 0 and the highlight pinned to the left folders — so the
    /// gesture reports its location in the named space directly instead.)
    private func updateActiveBin(fingerX: CGFloat, translation: CGSize) {
        let travelled = hypot(translation.width, translation.height)
        guard travelled > Self.binDeadZone, !binFrames.isEmpty else {
            if activeBin != nil { activeBin = nil }
            return
        }
        let candidate = binFrames
            .min { abs($0.value.midX - fingerX) < abs($1.value.midX - fingerX) }
            .map(\.key)
        guard let candidate, candidate != activeBin else { return }
        if let current = activeBin, let currentFrame = binFrames[current],
           let candidateFrame = binFrames[candidate] {
            let gain = abs(currentFrame.midX - fingerX) - abs(candidateFrame.midX - fingerX)
            guard gain > Self.binHysteresis else { return }
        }
        activeBin = candidate
        HapticEngine.drillBinChanged()
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let travelled = hypot(value.translation.width, value.translation.height)
        guard travelled > Self.commitThreshold, let bin = activeBin else {
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
        activeBin = nil
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
            activeBin = nil
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
