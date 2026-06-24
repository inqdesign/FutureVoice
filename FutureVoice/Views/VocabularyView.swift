import SwiftUI
import NaturalLanguage

/// The word cloud — the words "in your head", floating in space. Size = how
/// often you've used the word; tap one for its card (part of speech, meaning,
/// example). Words enter the cloud automatically as you use them in talks.
struct VocabularyView: View {
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
    @State private var hideKnown = false
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
                        currentWord = store.studying.first         // open on a study word
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
                let used = store.records[node.word] != nil
                if (!hideKnown || !used),
                   sx > -margin, sx < size.width + margin, sy > -margin, sy < size.height + margin {
                    let dist = hypot(sx - center.x, sy - center.y)
                    let opacity = max(0, min(1, 1.15 - dist / fade))
                    Text(node.word)
                        .font(.system(size: node.size, weight: used ? .regular : .semibold, design: .rounded))
                        .foregroundStyle(used ? Color.secondary : Color.primary)
                        .opacity(used ? opacity * 0.4 : opacity)
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

/// Packs a set of words into a jittered grid on a large canvas. Position is
/// hash-scattered (so sizes mix → depth), size + parallax depth come from word
/// frequency rank.
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
        let order = items.sorted { hash($0.word) < hash($1.word) }
        let cols = max(1, Int(ceil(sqrt(Double(order.count)))))
        return order.enumerated().map { slot, e in
            let col = slot % cols
            let row = slot / cols
            let pos = CGPoint(x: CGFloat(col) * cell + cell / 2 + jitter(e.word, 0x9E3779B1),
                              y: CGFloat(row) * cell + cell / 2 + jitter(e.word, 0x85EBCA77))
            // Per-word depth layer (hash-based) so parallax is visible even when
            // every word on screen is the same size (a single CEFR level).
            let layer = CGFloat(hash(e.word) % 1000) / 1000.0   // 0…1
            let depth = 0.65 + layer * 0.7                       // 0.65 (far) … 1.35 (near)
            return Node(word: e.word, pos: pos, size: e.size, depth: depth)
        }
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
                Label("I know it", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
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
