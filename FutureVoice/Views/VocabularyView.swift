import SwiftUI
import UIKit
import NaturalLanguage
import Supabase   // FunctionInvokeOptions for the free word-entry lookup

/// The word cloud — the words "in your head", floating in space. Size = how
/// often you've used the word; tap one for its card (part of speech, meaning,
/// example). Words enter the cloud automatically as you use them in talks.
struct VocabularyView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = VocabStore.shared
    @State private var currentWord: String?
    @State private var showSheet = true
    /// Two stops, not three. The old ladder was 130 → medium → large, so
    /// reading a word's meaning cost TWO drags, and the 130pt rung showed
    /// nothing the cloud hadn't already shown (the word you just tapped).
    /// The peek is now tall enough to carry the meaning itself, and one drag —
    /// or one tap — goes all the way.
    static let peekHeight: CGFloat = 220
    @State private var detent: PresentationDetent = .height(VocabularyView.peekHeight)
    @State private var pan: CGSize = .zero
    @State private var panAnchor: CGSize = .zero
    @State private var nodes: [CloudLayout.Node] = []
    @State private var canvas: CGSize = .zero
    @State private var viewport: CGSize = .zero
    @AppStorage("futurevoice.vocab.hideKnown") private var hideKnown = true
    @State private var level: LevelFilter = .all
    @State private var inited = false

    enum LevelFilter: String, CaseIterable, Identifiable {
        case all, a1, a2, b1, b2, c1, c2
        var id: String { rawValue }
        var label: String { self == .all ? "All levels" : rawValue.uppercased() }
        var cefr: CEFRLevel? { self == .all ? nil : CEFRLevel(rawValue: rawValue) }
        init(_ cefr: CEFRLevel) { self = LevelFilter(rawValue: cefr.rawValue) ?? .all }
    }

    var body: some View {
        GeometryReader { geo in
            cloud(in: geo.size)
                .onAppear {
                    viewport = geo.size
                    if !inited {
                        inited = true
                        store.backfillFromSessions()
                        level = LevelFilter(appState.proficiency)   // start at the user's level
                        // A widget-tapped word opens straight to its card; the
                        // sheet shows it regardless of the cloud's level filter.
                        currentWord = appState.focusWord ?? store.studying.first
                        appState.focusWord = nil
                        #if DEBUG
                        if DebugCapture.previewWordCard { detent = .large }
                        #endif
                    }
                    if nodes.isEmpty { rebuild(center: true) }      // don't recompute on every re-appear
                }
        }
        // A later widget tap (page already open) focuses the new word's card.
        .onChange(of: appState.focusWord) { _, w in
            guard let w else { return }
            currentWord = w
            showSheet = true
            appState.focusWord = nil
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSheet = false   // close the notebook first, so it doesn't linger on Progress
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Hide words I know", isOn: $hideKnown)
                    Picker("Level", selection: $level) {
                        ForEach(LevelFilter.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .onChange(of: level) { _, _ in rebuild(center: true) }
        .sheet(isPresented: $showSheet) {
            NotebookSheet(currentWord: $currentWord,
                          isExpanded: detent != .height(Self.peekHeight),
                          onExpand: { withAnimation(.easeOut(duration: 0.25)) { detent = .large } })
                .environmentObject(appState)
                .presentationDetents([.height(Self.peekHeight), .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .large))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(true)
        }
    }

    /// Header reflects the active level filter: a specific level shows its
    /// label + how many of THAT level's words you've used or know; "All levels"
    /// shows the overall pool. Per-level totals are precomputed; records is
    /// small — so this stays cheap and won't stutter the pan.
    private var titleText: String {
        if let lv = level.cefr {
            let total = CoreVocabulary.total(at: lv)
            let known = store.records.keys.reduce(0) {
                $0 + (CoreVocabulary.level(of: $1) == lv ? 1 : 0)
            }
            return "\(lv.rawValue.uppercased()) · \(known) / \(total)"
        }
        return "\(store.knownCount) / \(store.total) words"
    }

    // MARK: - Explorable cloud (parallax pan + edge vignette + cull)

    private func cloud(in size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let margin: CGFloat = 70

        return ZStack {
            Color(.systemBackground)
            ForEach(nodes) { node in
                // Parallax: each word's offset from the viewport centre is scaled
                // by its depth, so near words sweep faster than far ones as you
                // drag — but the drift stays bounded by the screen, so the
                // collision-free packing survives panning.
                let sx = center.x + (node.pos.x + pan.width - center.x) * node.depth
                let sy = center.y + (node.pos.y + pan.height - center.y) * node.depth
                let used = store.records[node.word] != nil
                if (!hideKnown || !used),
                   sx > -margin, sx < size.width + margin, sy > -margin, sy < size.height + margin {
                    // Elliptical vignette: full strength in the middle, gently
                    // fading toward the screen edges — not a min-dimension circle
                    // that leaves the top/bottom of tall screens empty.
                    let nd = hypot((sx - center.x) / center.x, (sy - center.y) / center.y)
                    let opacity = max(0, min(1, 1.25 - nd))
                    let studying = store.isStudying(node.word)
                    Text(node.word)
                        .font(.system(size: node.size, weight: used ? .regular : .semibold, design: .rounded))
                        .foregroundStyle(used ? Color.secondary : Color.primary)
                        .overlay(alignment: .topLeading) {
                            // Status badge, floating just off the word's leading
                            // top corner — same grammar as the word card's
                            // toolbar: bookmark = studying, check = known.
                            if studying || used {
                                Image(systemName: studying ? "bookmark.fill" : "checkmark")
                                    .font(.system(size: max(8, node.size * 0.42), weight: .semibold))
                                    .foregroundStyle(studying ? Color.accentColor : Color.green)
                                    .offset(x: -4, y: -max(8, node.size * 0.42))
                            }
                        }
                        .opacity(opacity)
                        .fixedSize()
                        .position(x: sx, y: sy)
                        .onTapGesture {
                            currentWord = node.word
                            // Stay on the peek — it now shows the meaning, so
                            // tapping through the cloud is a quick-check loop
                            // with no drag at all. Tap the peek for the rest.
                            detent = .height(Self.peekHeight)
                        }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    let raw = CGSize(width: panAnchor.width + value.translation.width,
                                     height: panAnchor.height + value.translation.height)
                    pan = rubberBanded(raw, in: size)
                }
                .onEnded { value in
                    // Carry a fraction of the flick's momentum so the cloud keeps
                    // drifting briefly after the finger lifts, then eases to rest
                    // inside the canvas bounds.
                    let extraX = value.predictedEndTranslation.width - value.translation.width
                    let extraY = value.predictedEndTranslation.height - value.translation.height
                    let target = clamped(CGSize(width: pan.width + extraX * 0.4,
                                                height: pan.height + extraY * 0.4), in: size)
                    withAnimation(.easeOut(duration: 0.6)) { pan = target }
                    panAnchor = target
                }
        )
    }

    // MARK: - Pan bounds (the canvas is finite — never show blank space past its edge)

    private func panBounds(in size: CGSize) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        guard canvas.width > 0, canvas.height > 0 else { return (0...0, 0...0) }
        // Overscroll head-room: the canvas edge can travel ~a third of the way
        // into the screen, so words in the outermost rows/columns are readable —
        // not stuck clipped at the viewport edge, faded by the vignette, or
        // hidden under the notebook sheet — without ever exposing more than a
        // sliver of empty space past the cloud.
        let padX = size.width * 0.35
        let padY = size.height * 0.35
        let spanX = size.width - canvas.width
        let spanY = size.height - canvas.height
        // Canvas smaller than the viewport (a tiny level filter) → pin it centered.
        let x: ClosedRange<CGFloat> = spanX < 0 ? (spanX - padX)...padX : (spanX / 2)...(spanX / 2)
        let y: ClosedRange<CGFloat> = spanY < 0 ? (spanY - padY)...padY : (spanY / 2)...(spanY / 2)
        return (x, y)
    }

    private func clamped(_ p: CGSize, in size: CGSize) -> CGSize {
        let b = panBounds(in: size)
        return CGSize(width: min(max(p.width, b.x.lowerBound), b.x.upperBound),
                      height: min(max(p.height, b.y.lowerBound), b.y.upperBound))
    }

    /// During a drag, movement past the edge is allowed but resisted; the release
    /// clamp then settles it back inside — the familiar iOS rubber-band feel.
    private func rubberBanded(_ p: CGSize, in size: CGSize) -> CGSize {
        let b = panBounds(in: size)
        func soft(_ v: CGFloat, _ r: ClosedRange<CGFloat>) -> CGFloat {
            if v < r.lowerBound { return r.lowerBound + (v - r.lowerBound) * 0.25 }
            if v > r.upperBound { return r.upperBound + (v - r.upperBound) * 0.25 }
            return v
        }
        return CGSize(width: soft(p.width, b.x), height: soft(p.height, b.y))
    }

    /// Pure + thread-safe (CoreVocabulary is a static let) so the heavy layout
    /// can run off the main thread without blocking the open animation.
    private static func items(for lvl: CEFRLevel?) -> [(word: String, size: CGFloat)] {
        guard let lvl else {
            return CoreVocabulary.entries.map { (word: $0.word, size: size(for: $0.level)) }
        }
        // Within a single level every word is the same difficulty, so grading
        // the font by level would just make the whole cloud uniformly huge (A1)
        // or tiny (C2) — use one comfortable reading size instead.
        return CoreVocabulary.entries.filter { $0.level == lvl }
            .map { (word: $0.word, size: 21) }
    }

    /// Easier (A1) words bigger, harder (C2) smaller — size encodes difficulty,
    /// giving depth when "All levels" is shown.
    static func size(for level: CEFRLevel) -> CGFloat {
        switch level {
        case .a1: return 28
        case .a2: return 24
        case .b1: return 20.5
        case .b2: return 18
        case .c1: return 16
        case .c2: return 14.5
        }
    }

    private func rebuild(center: Bool) {
        let lvl = level.cefr
        Task { @MainActor in
            // Compute the packing off the main thread so opening the page (and
            // changing filters) doesn't stutter.
            let cloud = await Task.detached(priority: .userInitiated) {
                CloudLayout.layout(VocabularyView.items(for: lvl))
            }.value
            nodes = cloud.nodes
            canvas = cloud.canvas
            if center, !cloud.nodes.isEmpty, viewport != .zero {
                pan = clamped(CGSize(width: viewport.width / 2 - cloud.canvas.width / 2,
                                     height: viewport.height / 2 - cloud.canvas.height / 2),
                              in: viewport)
                panAnchor = pan
            }
        }
    }
}

/// Packs a set of words into wobbling rows on a large, roughly square canvas,
/// spacing neighbours by each word's real rendered width — so words never
/// collide. Order is hash-scattered (so sizes mix → depth), parallax depth
/// comes from a per-word hash layer.
enum CloudLayout {
    struct Node: Identifiable {
        let word: String
        let pos: CGPoint
        let size: CGFloat
        let depth: CGFloat
        var id: String { word }
    }

    struct Cloud {
        var nodes: [Node] = []
        var canvas: CGSize = .zero
    }

    /// Gaps sized so the wobble below can never close them: horizontal wobble
    /// (±8) stays under hGap, and row pitch leaves head-room for the tallest
    /// (A1, 28pt) words plus vertical wobble (±12).
    private static let hGap: CGFloat = 34
    private static let rowPitch: CGFloat = 72

    static func layout(_ items: [(word: String, size: CGFloat)]) -> Cloud {
        guard !items.isEmpty else { return Cloud() }
        let order = items.sorted { hash($0.word) < hash($1.word) }

        var fonts: [CGFloat: UIFont] = [:]
        func width(_ word: String, _ size: CGFloat) -> CGFloat {
            let font: UIFont
            if let f = fonts[size] {
                font = f
            } else {
                let base = UIFont.systemFont(ofSize: size, weight: .semibold)
                font = base.fontDescriptor.withDesign(.rounded)
                    .map { UIFont(descriptor: $0, size: size) } ?? base
                fonts[size] = font
            }
            return (word as NSString).size(withAttributes: [.font: font]).width
        }

        let widths = order.map { width($0.word, $0.size) }
        // Row width that makes the canvas roughly square, so panning feels the
        // same in every direction.
        let totalRun = widths.reduce(0, +) + CGFloat(widths.count) * hGap
        let rowWidth = max(800, sqrt(totalRun * rowPitch))

        var nodes: [Node] = []
        nodes.reserveCapacity(order.count)
        var x: CGFloat = 0
        var row = 0
        for (i, e) in order.enumerated() {
            let w = widths[i]
            if x > 0, x + w > rowWidth { row += 1; x = 0 }
            // Small per-word wobble hides the row structure without being able
            // to close the gaps above.
            let pos = CGPoint(x: x + w / 2 + jitter(e.word, 0x9E3779B1, span: 16),
                              y: CGFloat(row) * rowPitch + rowPitch / 2 + jitter(e.word, 0x85EBCA77, span: 24))
            x += w + hGap
            // Per-word depth layer (hash-based) so parallax is visible even when
            // every word on screen is the same size (a single CEFR level).
            // Narrow band: enough for visible parallax, small enough that the
            // depth drift near the screen edges can't cross a row gap.
            let layer = CGFloat(hash(e.word) % 1000) / 1000.0   // 0…1
            let depth = 0.9 + layer * 0.2                        // 0.9 (far) … 1.1 (near)
            nodes.append(Node(word: e.word, pos: pos, size: e.size, depth: depth))
        }
        return Cloud(nodes: nodes,
                     canvas: CGSize(width: rowWidth, height: CGFloat(row + 1) * rowPitch))
    }

    private static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    private static func jitter(_ s: String, _ salt: UInt64, span: CGFloat) -> CGFloat {
        let h = hash(s) ^ salt
        return (CGFloat(h % 1000) / 1000.0 - 0.5) * span
    }
}

/// The persistent notebook — a collapsible sheet over the discovery cloud.
/// Collapsed: a peek + how many words you're studying. Pulled up: the current
/// word's card, navigable through your collection.
struct NotebookSheet: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = VocabStore.shared
    @Binding var currentWord: String?
    let isExpanded: Bool
    /// Pull the sheet to full height. Given to the peek so the whole card is
    /// one TAP away — dragging a sheet is the slowest way to ask for more.
    var onExpand: () -> Void = {}

    var body: some View {
        NavigationStack {
            if let word = currentWord {
                // No .id(word) — keep the SAME card view and just swap its
                // content, so navigating doesn't rebuild/jolt the layout.
                WordCard(word: word, currentWord: $currentWord, isExpanded: isExpanded,
                         onExpand: onExpand)
            } else {
                emptyState
                    .navigationTitle("My words · \(store.studying.count)")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical").font(.largeTitle).foregroundStyle(.secondary)
            Text(explain("Tap a word in the cloud to start your notebook"))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One word's card: meaning, example, your real sentences (listen + shadow),
/// and the two actions — keep studying, or mark known.
struct WordCard: View {
    let word: String
    @Binding var currentWord: String?
    var isExpanded: Bool = true
    /// Optional override for the header chevrons: walk THIS list instead of
    /// the notebook (`store.studying`). ConversationDetailView passes the
    /// tapped chip's sibling words so the user can browse a session's new
    /// words without closing and reopening the sheet per word.
    var navigationWords: [String]? = nil
    /// Pull the containing sheet to full height. nil where the card is already
    /// full-screen (ConversationDetailView), which also means no peek there.
    var onExpand: (() -> Void)? = nil
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = VocabStore.shared
    @StateObject private var player = AudioPlayer()

    @State private var entry: WordEntry?
    @State private var nlPos: String?
    @State private var loading = false
    @State private var speaking = false
    @State private var sentences: [VocabStore.SourceSentence] = []
    @State private var shadowing: Turn?

    private var studyIndex: Int? { store.studying.firstIndex(of: word) }
    /// The list the chevrons navigate — a caller-supplied list, or the notebook.
    private var navList: [String] { navigationWords ?? store.studying }
    private var navIndex: Int? { navList.firstIndex(of: word) }
    /// Words the user has USED count as known too — using a word in a real
    /// conversation is stronger evidence than a self-check, and every other
    /// surface (chips, cloud, counts) already treats them that way.
    private var isKnown: Bool { store.records[word] != nil }

    var body: some View {
        Group {
            if isExpanded {
                fullCard
            } else {
                peekCard
            }
        }
        // Walking a dealt list (daily words, a session's chip siblings) titles
        // by position — "3 of 10" — because that list isn't the notebook and
        // its count would be a lie there. Notebook browsing keeps the count.
        .navigationTitle(navigationWords != nil && navIndex != nil
                         ? Text("\((navIndex ?? 0) + 1) of \(navList.count)")
                         : Text("My words · \(store.studying.count)"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { cardToolbar }
        .safeAreaInset(edge: .bottom) { if isExpanded { actionBar } }
        .task(id: word) { await load() }
        .onDisappear { player.stop() }
        .fullScreenCover(item: $shadowing) { turn in
            NavigationStack {
                ShadowDrillView(turn: turn, targetLanguage: appState.targetLanguage)
                    .environmentObject(appState)
            }
        }
    }

    /// What the sheet shows at its resting height: the word, its part of
    /// speech, and — the whole point — its FIRST meaning, right there. The peek
    /// used to be the top of `fullCard` clipped to 130pt, which is to say the
    /// word the user had just tapped in the cloud and nothing else: a rung that
    /// charged a drag and paid nothing. Tapping anywhere here opens the rest.
    private var peekCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(word).font(.system(size: 30, weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(entry?.pos ?? nlPos ?? " ")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if appState.voiceCloneId != nil { pronounceButton }
            }
            peekMeaning
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { onExpand?() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the full card")
    }

    @ViewBuilder
    private var peekMeaning: some View {
        if let sense = entry?.senses.first {
            VStack(alignment: .leading, spacing: 3) {
                Text(sense.meaning)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                // More than one sense: say so, rather than letting the peek
                // read as the whole truth.
                if let extra = entry.map({ $0.senses.count - 1 }), extra > 0 {
                    Text(extra == 1 ? "+1 more meaning" : "+\(extra) more meanings")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } else if loading {
            // Same spinner + wording as everywhere else a lookup runs. It was
            // redacted (greeked) text alone, which reads as a rendering glitch
            // rather than as work in progress — and this peek is the FIRST
            // thing a tapped word shows, so it's where the app most looked
            // stuck.
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text("Looking it up…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(explain("No dictionary entry yet — tap to open the card."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var fullCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(word).font(.system(size: 34, weight: .bold, design: .rounded))
                        Text(entry?.pos ?? nlPos ?? " ")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if appState.voiceCloneId != nil { pronounceButton }
                }

                section("Meaning") {
                    if let senses = entry?.senses, !senses.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(senses.enumerated()), id: \.element.id) { i, s in
                                senseRow(i + 1, s)
                            }
                        }
                    } else {
                        lookupPlaceholder
                    }
                }

                section(entry?.examples.count == 1 ? "Example" : "Examples") {
                    if let examples = entry?.examples, !examples.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(examples) { exampleRow($0) }
                        }
                    } else {
                        lookupPlaceholder
                    }
                }

                if let phrases = entry?.phrases, !phrases.isEmpty {
                    section("Common phrases") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(phrases) { phraseRow($0) }
                        }
                    }
                }

                if let note = entry?.properNoun, !note.isEmpty {
                    section("As a name") {
                        Text(note).font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !sentences.isEmpty {
                    section("From your talks") {
                        VStack(spacing: 8) { ForEach(sentences) { sentenceRow($0) } }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)   // fixed full width — no jump as content loads
        }
    }

    /// Shared by peek and full card.
    @ToolbarContentBuilder
    private var cardToolbar: some ToolbarContent {
        Group {
            // Collapsed: quick bookmark / mark-known top-left (no need to expand).
            if !isExpanded {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        store.isStudying(word) ? store.removeStudying(word) : store.addStudying(word)
                    } label: {
                        Image(systemName: store.isStudying(word) ? "bookmark.fill" : "bookmark")
                    }
                    .tint(store.isStudying(word) ? .accentColor : .secondary)

                    Button {
                        isKnown ? store.unmark(word) : store.markKnown(word)
                    } label: {
                        Image(systemName: isKnown ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .tint(isKnown ? .green : .secondary)
                }
            }
            // Collapsed only — expanded, the same two chevrons live at the
            // bottom next to Keep / I know, and two sets would be a puzzle.
            if !isExpanded, let i = navIndex {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { currentWord = navList[i - 1] } label: { Image(systemName: "chevron.up") }
                        .disabled(i == 0)
                    Button { currentWord = navList[i + 1] } label: { Image(systemName: "chevron.down") }
                        .disabled(i + 1 >= navList.count)
                }
            }
        }
    }

    private var pronounceButton: some View {
        Button {
            Task { await speakWord() }
        } label: {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 46, height: 46)
                if speaking {
                    ProgressView()
                } else {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3).foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(speaking)
    }


    /// While a dictionary entry is being generated, say so — with the same
    /// spinner every other generation in the app uses. A bare "…" was
    /// pixel-identical to the "—" no-entry state, so a slow first lookup
    /// (a cold word runs a full LLM generation server-side) read as a frozen
    /// screen rather than as work in progress.
    @ViewBuilder
    private var lookupPlaceholder: some View {
        if loading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text("Looking it up…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("—").font(.body).foregroundStyle(.secondary)
        }
    }

    private func speakWord() async {
        guard let voiceId = appState.voiceCloneId else { return }
        // Reuse cached audio so we never re-bill TTS for the same word.
        if let data = PhraseAudioStore.shared.data(text: word, voiceId: voiceId) {
            try? player.play(data, forceSessionReset: true)
            return
        }
        speaking = true
        defer { speaking = false }
        do {
            let data = try await ElevenLabsClient.shared.synthesize(voiceId: voiceId, text: word, purpose: "library")
            PhraseAudioStore.shared.save(data, text: word, voiceId: voiceId)
            try? player.play(data, forceSessionReset: true)
        } catch {
            // network/credits failure — leave the button idle, nothing to play
        }
    }

    private func senseRow(_ index: Int, _ s: WordEntry.Sense) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(.tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 4) {
                Text(s.pos)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(s.meaning)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let note = s.note, !note.isEmpty {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func exampleRow(_ e: WordEntry.Example) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let m = e.meaning, !m.isEmpty {
                    Text(m).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .contextMenu { saveActions(for: e.text) }
    }

    private func phraseRow(_ p: WordEntry.Phrase) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(p.phrase)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(p.meaning).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .contentShape(Rectangle())
        .contextMenu { saveActions(for: p.phrase) }
    }

    /// Long-press actions shared by examples and common phrases — save the
    /// text to study later, or shadow-practice it right now.
    @ViewBuilder
    private func saveActions(for text: String) -> some View {
        if store.hasExpression(text) {
            Label("Saved to expressions", systemImage: "checkmark")
        } else {
            Button {
                store.addExpression(text)
                HapticEngine.drillCorrect()
            } label: {
                Label("Save to expressions", systemImage: "bookmark")
            }
        }
        Button {
            shadowing = Turn(id: UUID(), role: .fluentSelf, audioURL: nil,
                             transcript: text, durationMs: 0, timestamp: Date(),
                             suggestion: nil)
        } label: {
            Label("Shadow this", systemImage: "waveform.badge.mic")
        }
    }

    private func sentenceRow(_ s: VocabStore.SourceSentence) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(s.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Text(s.source).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let url = s.audioURL {
                    Button { play(url) } label: { Label("Listen", systemImage: "play.circle") }
                }
                Button { shadowing = makeTurn(s) } label: { Label("Shadow", systemImage: "waveform.badge.mic") }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill)))
    }

    /// Everything you do to the word you're reading, on one row at the bottom
    /// of the expanded card: the two verdicts, then walk to the next word.
    ///
    /// Labels stay ONE word. They used to say "Keep studying" / "I know it",
    /// and swap to "Studying" / "Known" once set — four strings that pushed the
    /// two capsules to the screen edges and left nowhere for the chevrons. The
    /// state is carried by the icon (outline → filled) and its tint instead,
    /// which is what the eye reads first anyway.
    private var actionBar: some View {
        HStack(spacing: 8) {
            let studying = store.isStudying(word)
            blurButton("Keep",
                       icon: studying ? "bookmark.fill" : "bookmark",
                       tint: studying ? .accentColor : .primary) {
                studying ? store.removeStudying(word) : store.addStudying(word)
            }
            .accessibilityLabel(studying ? "Studying this word" : "Keep studying this word")

            blurButton("I know",
                       icon: isKnown ? "checkmark.circle.fill" : "checkmark.circle",
                       tint: isKnown ? .green : .primary) {
                // Toggle: tap to mark known, tap again to clear it. Stay on the
                // word so it visibly flips — confirmation the tap worked.
                // Deliberately NO jump to the next study word.
                isKnown ? store.unmark(word) : store.markKnown(word)
            }
            .accessibilityLabel(isKnown ? "Marked as known" : "Mark as known")

            // Walking the list belongs next to the verdicts — you decide, then
            // move on, and both halves of that are now under the same thumb.
            // (Collapsed, where there's no action bar, the chevrons stay in
            // the toolbar.)
            if let i = navIndex {
                stepButton("chevron.up", label: "Previous word") { currentWord = navList[i - 1] }
                    .disabled(i == 0)
                stepButton("chevron.down", label: "Next word") { currentWord = navList[i + 1] }
                    .disabled(i + 1 >= navList.count)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Icon-only sibling of `blurButton` — same glass capsule, sized to its
    /// glyph so the two labelled buttons keep the width.
    private func stepButton(_ icon: String, label: String,
                            action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                // Just the glyph — every point saved here is a point the two
                // labelled buttons get to keep.
                .frame(width: 14)
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .tint(.primary)
        .accessibilityLabel(label)
        if #available(iOS 26.0, *) {
            return AnyView(button.buttonStyle(.glass))
        } else {
            return AnyView(button.buttonStyle(.bordered)
                .background(.regularMaterial, in: Capsule()))
        }
    }

    /// Action button matching the header's chevron buttons: native Liquid Glass
    /// on iOS 26, a bordered capsule fallback below. One system style — fill and
    /// edge can't misalign.
    private func blurButton(_ title: String, icon: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                // One line, always. Four controls share this row now, so a
                // label that wraps ("I" / "know") both looks broken and grows
                // the bar's height.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .tint(tint)
        if #available(iOS 26.0, *) {
            return AnyView(button.buttonStyle(.glass))
        } else {
            // .bordered alone is a translucent tint with NO blur, so over the
            // scrolling sheet content the label fought whatever sat beneath it
            // (visible on pre-26 iPads). A material capsule underneath gives
            // the same read-through-blur the glass style provides.
            return AnyView(button.buttonStyle(.bordered)
                .background(.regularMaterial, in: Capsule()))
        }
    }

    // MARK: - Logic

    private func makeTurn(_ s: VocabStore.SourceSentence) -> Turn {
        Turn(id: UUID(), role: .fluentSelf, audioURL: s.audioURL,
             transcript: s.text, durationMs: 0, timestamp: Date(), suggestion: nil)
    }

    private func play(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        try? player.play(data, forceSessionReset: true)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private func load() async {
        // `loading` FIRST, same as the expression card: clearing the entry
        // before flipping it shows the no-entry state for a frame every time
        // the card walks to the next word.
        loading = true
        entry = nil
        nlPos = WordLore.partOfSpeech(word)
        sentences = store.sentences(using: word)
        let fetched = await WordLore.entry(for: word, native: appState.nativeLanguage,
                                     target: appState.targetLanguage, kind: .word)
        // A newer word already owns this card — its own load is in flight, so
        // neither the stale entry nor the stale `loading = false` may land.
        guard !Task.isCancelled else { return }
        entry = fetched
        loading = false
    }
}

/// A full dictionary entry for one word, in the reader's native language:
/// senses grouped by part of speech, an example with its translation, and
/// common phrases/idioms. Proper-noun uses (e.g. "Slack" the app) get a note.
struct WordEntry: Codable, Equatable {
    struct Sense: Codable, Equatable, Identifiable {
        var id: String { pos + meaning }
        let pos: String       // part of speech, in the native language ("형용사")
        let meaning: String   // native-language gloss
        let note: String?     // usage nuance, native language (optional)
    }
    struct Phrase: Codable, Equatable, Identifiable {
        var id: String { phrase }
        let phrase: String    // the English collocation / idiom
        let meaning: String   // native-language meaning
    }
    struct Example: Codable, Equatable, Identifiable {
        var id: String { text }
        let text: String      // natural spoken English
        let meaning: String?  // its native-language translation
    }
    let pos: String?            // short headline part-of-speech summary
    let senses: [Sense]
    let examples: [Example]     // count decided by the model, per word
    let phrases: [Phrase]
    let properNoun: String?     // note if it's also a name/brand (optional)
}

/// Builds + caches the rich `WordEntry`. Generated by Gemini in ONE call and
/// stored in Supabase (`word_entry`, keyed by word + native + target language
/// + kind) so every user who taps the same word reuses it — no repeat API
/// calls.
@MainActor
enum WordLore {
    /// Which prompt writes the entry. A single word gets a headword treatment
    /// (senses by part of speech); a multi-word chunk gets explained WHOLE.
    /// Asking for a phrase as a `.word` is what produced "hundred active
    /// users" → the dictionary entry for "hundred".
    enum Kind: String {
        case word, expression
    }

    private static var cache: [String: WordEntry] = [:]

    /// On-device fallback part of speech (used only if generation fails).
    static func partOfSpeech(_ word: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = word
        tagger.setLanguage(.english, range: word.startIndex..<word.endIndex)
        return tagger.tag(at: word.startIndex, unit: .word, scheme: .lexicalClass).0?.rawValue
    }

    private struct EntryRow: Decodable { let data: WordEntry }
    private struct LookupBody: Encodable {
        let word: String
        let native_lang: String
        let target_lang: String
        let kind: String
    }
    private struct LookupResponse: Decodable { let data: WordEntry }

    /// - Parameters:
    ///   - target: the language the entry TEACHES. Part of the key: without
    ///     it a Spanish learner's word collides with an English learner's.
    ///   - kind: `.expression` for anything multi-word.
    static func entry(for word: String, native: String,
                      target: String, kind: Kind = .word) async -> WordEntry? {
        #if DEBUG
        // Capture seam: the loading state is invisible offline (the lookup
        // fails instantly), so a screenshot run can hold it open.
        if DebugCapture.slowLookupSeconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(DebugCapture.slowLookupSeconds) * 1_000_000_000)
        }
        #endif
        let key = [native, target, kind.rawValue, word].joined(separator: "|")
        if let c = cache[key] { return c }
        // 1. Shared cache — a direct read is free and skips a function cold
        //    start for the common (already-generated) case.
        if let rows = try? await SupabaseProvider.shared.from("word_entry")
            .select("data").eq("word", value: word).eq("native_lang", value: native)
            .eq("target_lang", value: target).eq("kind", value: kind.rawValue)
            .limit(1).execute().value as [EntryRow], let row = rows.first {
            cache[key] = row.data
            return row.data
        }
        // 2. Cache miss → the `word-entry` function generates + publishes it
        //    server-side, FREE. Dictionary entries are a global shared cache,
        //    so they're never credit-gated (see the function for why the
        //    generation prompt lives server-side rather than a free `gemini`
        //    purpose). Returns the same word from the cache if another user
        //    generated it in the meantime.
        do {
            let res: LookupResponse = try await SupabaseProvider.shared.functions.invoke(
                "word-entry",
                options: FunctionInvokeOptions(body: LookupBody(
                    word: word, native_lang: native,
                    target_lang: target, kind: kind.rawValue))
            )
            cache[key] = res.data
            return res.data
        } catch {
            return nil
        }
    }
}
