import SwiftUI
import NaturalLanguage

/// The word cloud — the words "in your head", floating in space. Size = how
/// often you've used the word; tap one for its card (part of speech, meaning,
/// example). Words enter the cloud automatically as you use them in talks.
struct VocabularyView: View {
    var initialWord: String? = nil
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = VocabStore.shared
    @State private var currentWord: String?
    @State private var showSheet = true
    @State private var detent: PresentationDetent = .height(130)
    @State private var pan: CGSize = .zero
    @State private var panAnchor: CGSize = .zero
    @State private var nodes: [CloudLayout.Node] = []
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
                        currentWord = initialWord ?? store.studying.first
                        if initialWord != nil { detent = .medium }  // opened for a specific word → show its card
                    }
                    if nodes.isEmpty { rebuild(center: true) }      // don't recompute on every re-appear
                }
        }
        .navigationTitle("\(store.knownCount) / \(store.total) words")
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
            NotebookSheet(currentWord: $currentWord, isExpanded: detent != .height(130))
                .environmentObject(appState)
                .presentationDetents([.height(130), .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .large))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(true)
        }
    }

    // MARK: - Explorable cloud (parallax pan + radial fade + cull)

    private func cloud(in size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let fade = min(size.width, size.height) * 0.62
        let margin: CGFloat = 70

        return ZStack {
            Color(.systemBackground)
            ForEach(nodes) { node in
                // Parallax: bigger (common) words ride the pan faster, so the
                // cloud has real depth as you drag.
                let sx = node.pos.x + pan.width * node.depth
                let sy = node.pos.y + pan.height * node.depth
                let inPool = store.records[node.word] != nil   // used in a talk OR self-marked known
                if (!hideKnown || !inPool),
                   sx > -margin, sx < size.width + margin, sy > -margin, sy < size.height + margin {
                    let dist = hypot(sx - center.x, sy - center.y)
                    let opacity = max(0, min(1, 1.15 - dist / fade))
                    Text(node.word)
                        // Words you already know — spoken in a talk OR
                        // self-marked — recede (grey, dimmed). The focus is the
                        // words you haven't reached for yet: those stay bold and
                        // full-strength so the cloud highlights what's left to learn.
                        .font(.system(size: node.size,
                                      weight: inPool ? .regular : .semibold,
                                      design: .rounded))
                        .foregroundStyle(inPool ? Color.secondary : Color.primary)
                        .opacity(inPool ? opacity * 0.4 : opacity)
                        .fixedSize()
                        .position(x: sx, y: sy)
                        .onTapGesture {
                            currentWord = node.word
                            detent = .height(130)     // stay compact — quick-check & move on; scroll/drag to open
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
                    pan = CGSize(width: panAnchor.width + value.translation.width,
                                 height: panAnchor.height + value.translation.height)
                }
                .onEnded { value in
                    // Carry a fraction of the flick's momentum so the cloud keeps
                    // drifting briefly after the finger lifts, then eases to rest.
                    let extraX = value.predictedEndTranslation.width - value.translation.width
                    let extraY = value.predictedEndTranslation.height - value.translation.height
                    let target = CGSize(width: pan.width + extraX * 0.4,
                                        height: pan.height + extraY * 0.4)
                    withAnimation(.easeOut(duration: 0.6)) { pan = target }
                    panAnchor = target
                }
        )
    }

    /// Pure + thread-safe (CoreVocabulary is a static let) so the heavy layout
    /// can run off the main thread without blocking the open animation.
    private static func items(for lvl: CEFRLevel?) -> [(word: String, size: CGFloat)] {
        let entries = lvl == nil ? CoreVocabulary.entries
                                 : CoreVocabulary.entries.filter { $0.level == lvl }
        return entries.map { (word: $0.word, size: size(for: $0.level)) }
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
        let vp = viewport
        Task { @MainActor in
            // Compute the packing off the main thread so opening the page (and
            // changing filters) doesn't stutter.
            let newNodes = await Task.detached(priority: .userInitiated) {
                CloudLayout.layout(VocabularyView.items(for: lvl))
            }.value
            nodes = newNodes
            if center, !newNodes.isEmpty, vp != .zero {
                let mid = newNodes[newNodes.count / 2].pos
                pan = CGSize(width: vp.width / 2 - mid.x, height: vp.height / 2 - mid.y)
                panAnchor = pan
            }
        }
    }
}

/// Lays words on a large pannable canvas. Position is SEMANTIC — Apple's
/// on-device word embeddings projected to 2D (PCA) so related words cluster —
/// snapped to a grid so labels don't overlap. Size encodes CEFR difficulty;
/// per-word parallax depth gives the cloud 3D feel. Falls back to a hash grid.
enum CloudLayout {
    struct Node: Identifiable {
        let word: String
        let pos: CGPoint
        let size: CGFloat
        let depth: CGFloat
        var id: String { word }
    }

    private static let cell: CGFloat = 116

    static func layout(_ items: [(word: String, size: CGFloat)]) -> [Node] {
        semanticLayout(items) ?? gridLayout(items)
    }

    private static func node(_ word: String, col: Int, row: Int, size: CGFloat) -> Node {
        let pos = CGPoint(x: CGFloat(col) * cell + cell / 2 + jitter(word, 0x9E3779B1),
                          y: CGFloat(row) * cell + cell / 2 + jitter(word, 0x85EBCA77))
        let layer = CGFloat(hash(word) % 1000) / 1000.0   // 0…1 parallax depth
        return Node(word: word, pos: pos, size: size, depth: 0.65 + layer * 0.7)
    }

    /// Fallback when embeddings are unavailable: hash-scattered jittered grid
    /// (no semantic meaning — just spreads words out).
    private static func gridLayout(_ items: [(word: String, size: CGFloat)]) -> [Node] {
        let order = items.sorted { hash($0.word) < hash($1.word) }
        let cols = max(1, Int(ceil(sqrt(Double(order.count)))))
        return order.enumerated().map { slot, e in
            node(e.word, col: slot % cols, row: slot / cols, size: e.size)
        }
    }

    /// Semantic map: project Apple's on-device word embeddings to 2D (top-2
    /// PCA via power iteration) so related words land near each other, then
    /// snap each to the nearest free grid cell so labels never overlap.
    /// Returns nil → caller falls back to `gridLayout`.
    private static func semanticLayout(_ items: [(word: String, size: CGFloat)]) -> [Node]? {
        guard let emb = NLEmbedding.wordEmbedding(for: .english) else { return nil }
        let dim = emb.dimension
        guard dim > 0 else { return nil }

        var withVec: [(word: String, size: CGFloat, v: [Double])] = []
        var noVec: [(word: String, size: CGFloat)] = []
        for it in items {
            if let v = emb.vector(for: it.word), v.count == dim {
                withVec.append((it.word, it.size, v))
            } else {
                noVec.append((it.word, it.size))
            }
        }
        let n = withVec.count
        guard n >= 8 else { return nil }

        // Mean-center into a flat row-major buffer.
        var mean = [Double](repeating: 0, count: dim)
        for w in withVec { for j in 0..<dim { mean[j] += w.v[j] } }
        for j in 0..<dim { mean[j] /= Double(n) }
        var X = [Double](repeating: 0, count: n * dim)
        for i in 0..<n {
            let base = i * dim, v = withVec[i].v
            for j in 0..<dim { X[base + j] = v[j] - mean[j] }
        }

        // Matrix-free covariance multiply: Xᵀ(Xv) — never forms dim×dim.
        func covMul(_ v: [Double]) -> [Double] {
            var u = [Double](repeating: 0, count: n)
            for i in 0..<n {
                let base = i * dim
                var sdot = 0.0
                for j in 0..<dim { sdot += X[base + j] * v[j] }
                u[i] = sdot
            }
            var r = [Double](repeating: 0, count: dim)
            for i in 0..<n {
                let base = i * dim, ui = u[i]
                for j in 0..<dim { r[j] += X[base + j] * ui }
            }
            return r
        }
        func norm(_ v: inout [Double]) {
            var m = 0.0; for x in v { m += x * x }; m = m.squareRoot()
            if m > 1e-12 { for k in 0..<v.count { v[k] /= m } }
        }
        func principal(deflating prev: [[Double]]) -> [Double] {
            var v = (0..<dim).map { Double(($0 &* 2654435761) % 997) / 997.0 - 0.5 }
            norm(&v)
            for _ in 0..<30 {
                var w = covMul(v)
                for pcomp in prev {
                    var dot = 0.0; for k in 0..<dim { dot += w[k] * pcomp[k] }
                    for k in 0..<dim { w[k] -= dot * pcomp[k] }
                }
                norm(&w)
                v = w
            }
            return v
        }
        let pc1 = principal(deflating: [])
        let pc2 = principal(deflating: [pc1])

        func project(_ i: Int, _ pc: [Double]) -> Double {
            let base = i * dim
            var sdot = 0.0
            for j in 0..<dim { sdot += X[base + j] * pc[j] }
            return sdot
        }
        var xs = (0..<n).map { project($0, pc1) }
        var ys = (0..<n).map { project($0, pc2) }
        func normalize01(_ a: inout [Double]) {
            guard let lo = a.min(), let hi = a.max(), hi > lo else { return }
            for k in 0..<a.count { a[k] = (a[k] - lo) / (hi - lo) }
        }
        normalize01(&xs); normalize01(&ys)

        // Snap to a sparse grid; nearby-in-meaning → nearby cell, no overlap.
        let total = n + noVec.count
        let cols = max(1, Int(ceil(sqrt(Double(total) * 1.6))))
        let rows = max(1, Int(ceil(Double(total) / Double(cols))))
        var occupied = Set<Int>()
        func claim(_ col0: Int, _ row0: Int) -> (Int, Int) {
            let c0 = min(max(col0, 0), cols - 1), r0 = min(max(row0, 0), rows - 1)
            if occupied.insert(r0 * cols + c0).inserted { return (c0, r0) }
            for radius in 1..<(cols + rows) {
                for dc in -radius...radius {
                    for dr in -radius...radius where abs(dc) == radius || abs(dr) == radius {
                        let c = c0 + dc, r = r0 + dr
                        guard c >= 0, c < cols, r >= 0, r < rows else { continue }
                        if occupied.insert(r * cols + c).inserted { return (c, r) }
                    }
                }
            }
            return (c0, r0)
        }

        var nodes: [Node] = []
        nodes.reserveCapacity(total)
        for i in 0..<n {
            let (c, r) = claim(Int((xs[i] * Double(cols - 1)).rounded()),
                               Int((ys[i] * Double(rows - 1)).rounded()))
            nodes.append(node(withVec[i].word, col: c, row: r, size: withVec[i].size))
        }
        var scan = 0
        for w in noVec {
            while scan < cols * rows && occupied.contains(scan) { scan += 1 }
            let cell = scan < cols * rows ? scan : 0
            occupied.insert(cell)
            nodes.append(node(w.word, col: cell % cols, row: cell / cols, size: w.size))
        }
        return nodes
    }

    private static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    private static func jitter(_ s: String, _ salt: UInt64) -> CGFloat {
        let h = hash(s) ^ salt
        return CGFloat(Double(h % 680) / 10.0 - 34.0)
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

    var body: some View {
        NavigationStack {
            if let word = currentWord {
                // No .id(word) — keep the SAME card view and just swap its
                // content, so navigating doesn't rebuild/jolt the layout.
                WordCard(word: word, currentWord: $currentWord, isExpanded: isExpanded)
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
            Text("Tap a word in the cloud to start your notebook")
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
    private var isKnown: Bool { store.records[word]?.state == .known }

    var body: some View {
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
                        Text(loading ? "…" : "—").font(.body).foregroundStyle(.secondary)
                    }
                }

                section(entry?.examples.count == 1 ? "Example" : "Examples") {
                    if let examples = entry?.examples, !examples.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(examples) { exampleRow($0) }
                        }
                    } else {
                        Text(loading ? "…" : "—").font(.body).foregroundStyle(.secondary)
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
        .navigationTitle("My words · \(store.studying.count)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
                        store.markKnown(word)
                        advanceAfterRemoval()
                    } label: {
                        Image(systemName: isKnown ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .tint(isKnown ? .green : .secondary)
                }
            }
            // Navigate the notebook from a fixed spot in the header.
            if let i = studyIndex {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { currentWord = store.studying[i - 1] } label: { Image(systemName: "chevron.up") }
                        .disabled(i == 0)
                    Button { currentWord = store.studying[i + 1] } label: { Image(systemName: "chevron.down") }
                        .disabled(i + 1 >= store.studying.count)
                }
            }
        }
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
            let data = try await ElevenLabsClient.shared.synthesize(voiceId: voiceId, text: word)
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

    private var actionBar: some View {
        HStack(spacing: 10) {
            if store.isStudying(word) {
                Button { store.removeStudying(word) } label: {
                    Label("Studying", systemImage: "bookmark.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large).tint(.accentColor)
            } else {
                Button { store.addStudying(word) } label: {
                    Label("Keep studying", systemImage: "bookmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Button {
                store.markKnown(word)
                advanceAfterRemoval()
            } label: {
                Label("I know it", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
                    // Opaque fill UNDER the label so scrolling content doesn't
                    // bleed through the translucent .bordered material.
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Logic

    private func advanceAfterRemoval() {
        // markKnown removed it from the notebook; move to a neighbour.
        currentWord = store.studying.first
    }

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
        entry = nil
        nlPos = WordLore.partOfSpeech(word)
        sentences = store.sentences(using: word)
        loading = true
        entry = await WordLore.entry(for: word, native: appState.nativeLanguage)
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
/// stored in Supabase (`word_entry`, keyed by word + native language) so every
/// user who taps the same word reuses it — no repeat API calls.
@MainActor
enum WordLore {
    private static var cache: [String: WordEntry] = [:]

    /// On-device fallback part of speech (used only if generation fails).
    static func partOfSpeech(_ word: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = word
        tagger.setLanguage(.english, range: word.startIndex..<word.endIndex)
        return tagger.tag(at: word.startIndex, unit: .word, scheme: .lexicalClass).0?.rawValue
    }

    private struct EntryRow: Decodable { let data: WordEntry }
    private struct EntryInsert: Encodable { let word: String; let native_lang: String; let data: WordEntry }

    static func entry(for word: String, native: String) async -> WordEntry? {
        let key = native + "|" + word
        if let c = cache[key] { return c }
        // 1. Shared store
        if let rows = try? await SupabaseProvider.shared.from("word_entry")
            .select("data").eq("word", value: word).eq("native_lang", value: native)
            .limit(1).execute().value as [EntryRow], let row = rows.first {
            cache[key] = row.data
            return row.data
        }
        // 2. Generate once, then publish for everyone.
        guard let entry = await generate(word, native: native) else { return nil }
        cache[key] = entry
        let insert = EntryInsert(word: word, native_lang: native, data: entry)
        Task { try? await SupabaseProvider.shared.from("word_entry")
            .upsert(insert, onConflict: "word,native_lang").execute() }
        return entry
    }

    private static func generate(_ word: String, native: String) async -> WordEntry? {
        let lang = Locale(identifier: "en").localizedString(forLanguageCode: native) ?? native
        let system = """
        You are a bilingual learner's dictionary. For the English word the user sends, \
        return a JSON object explaining it for a native \(lang) speaker. Write every \
        meaning, note and phrase-meaning in \(lang) — never transliterate the English \
        word (e.g. "slack" must be explained, NOT written "슬랙").

        JSON shape (no markdown, JSON only):
        {
          "pos": "<short part-of-speech summary in \(lang), e.g. 형용사·명사·동사>",
          "senses": [
            { "pos": "<part of speech in \(lang)>", "meaning": "<gloss in \(lang)>", "note": "<short usage nuance in \(lang), or null>" }
          ],
          "examples": [
            { "text": "<short, natural SPOKEN English sentence using the word>", "meaning": "<that sentence translated into \(lang)>" }
          ],
          "phrases": [
            { "phrase": "<common English idiom/collocation with the word>", "meaning": "<its meaning in \(lang)>" }
          ],
          "properNoun": "<one line in \(lang) if the capitalized word is also a well-known name/brand, else null>"
        }

        Cover the distinct common senses. Give as many examples as the word genuinely \
        warrants — a simple one-sense word may need a single example, a word with \
        several senses may want one example per sense. Don't pad; don't force a count. \
        Include only genuinely common phrases (none is fine). Keep everything concise.
        """
        do {
            return try await GeminiClient.shared.sendJSON(
                system: system,
                messages: [GeminiClient.Message(role: .user, content: word)],
                maxTokens: 700, temperature: 0.3
            )
        } catch { return nil }
    }
}
