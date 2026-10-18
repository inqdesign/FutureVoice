import SwiftUI

/// The Speech tab: read a script aloud like a presenter, under a prompter
/// that follows your voice, camera on or off, and get the take scored.
/// Nothing here synthesizes speech — the only voice is the learner's.
struct SpeechTab: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = SpeechStore.shared
    @ObservedObject private var gate = BillingGate.shared
    @ObservedObject private var challenges = SpeechChallenges.shared
    @State private var publishing: SpeechScript?
    @State private var publishError: String?
    /// The script whose prompter is open. Tapping a script opens it straight
    /// away — picking one IS starting to practise it.
    @State private var practicing: SpeechScript?
    /// A script just written or added, opened once its sheet has gone (a
    /// cover raised while a sheet is still dismissing never appears).
    @State private var openAfterSheet: SpeechScript?
    @State private var editing: SpeechScript?
    @State private var composing = false
    @State private var addingOwn = false
    @State private var showingUpsell = false
    /// The menu's two choices, for the tap that only learned after a fresh
    /// fetch that this account may write.
    @State private var choosingKind = false

    private var canWrite: Bool { gate.account?.canWriteSpeechScripts ?? false }
    static let challengesOnTab = 3
    /// The inset-grouped list's side margin, where its cards start.
    static let listMargin: CGFloat = 16
    static let challengeSpacing: CGFloat = 10
    /// How much of the third card shows at the right edge.
    static let challengePeek: CGFloat = 20

    private var ownScripts: [SpeechScript] {
        store.scripts.filter { challenges.script(id: $0.id) == nil }
    }

    private enum NewKind { case write, own }

    /// The empty state's two buttons, on the toolbar's rule: a yes from
    /// cache, a no only after a fresh fetch, and the Plus sheet otherwise.
    private func startNew(_ kind: NewKind) {
        let open = { if kind == .write { composing = true } else { addingOwn = true } }
        if canWrite { open(); return }
        Task {
            if await BillingGate.shared.allowsSpeechScripts() { open() } else { showingUpsell = true }
        }
    }

    /// How far the list's header sits in from the screen's leading edge,
    /// measured, so the challenge row can bleed back out to the edge.
    @State private var challengeBleed: CGFloat = 32

    /// One row that scrolls sideways (2026-10-17, founder: three stacked
    /// cards took most of the screen). Two cards across and the third cut at
    /// the screen's edge, so it reads as a row that scrolls; the row runs to
    /// both screen edges rather than stopping at the list's margins.
    private var challengeRow: some View {
        let bleed = challengeBleed
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Self.challengeSpacing) {
                ForEach(challenges.live.prefix(Self.challengesOnTab)) { script in
                    NavigationLink {
                        SpeechChallengeView(script: script)
                            .environmentObject(appState)
                    } label: {
                        SpeechChallengeRow(script: script, standing: challenges.standings[script.id])
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal) { width, _ in
                        // `width` is already inside BOTH content margins, but
                        // the trailing one is where the third card peeks, so
                        // it is given back: screen = leading margin + two
                        // cards + two gaps + the peek. Leaving it out showed
                        // ~60 pt of the third card instead of the peek.
                        (width + Self.listMargin - 2 * Self.challengeSpacing - Self.challengePeek) / 2
                    }
                }
            }
            .scrollTargetLayout()
        }
        // The first card lines up with the list's own cards below.
        .contentMargins(.horizontal, Self.listMargin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .padding(.horizontal, -bleed)
        .background {
            // The header's own slot: its leading edge is how far it sits in
            // from the screen.
            Color.clear.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
                challengeBleed = max(0, $0)
            }
        }
        .padding(.top, 4)
        // A header greys its content; the cards are not header text.
        .foregroundStyle(Color.primary)
    }

    var body: some View {
        NavigationStack {
            List {
                if !challenges.scripts.isEmpty {
                    Section {
                    } header: {
                        // The newest three on the tab; everything else, past
                        // ones included, one tap away from the title. The
                        // cards live in the HEADER (2026-10-17): a List row
                        // is masked to the section's margins, so a row that
                        // should run to both screen edges was cut short.
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Challenges")
                                Spacer()
                                if challenges.live.count > Self.challengesOnTab || !challenges.past.isEmpty {
                                    NavigationLink {
                                        SpeechChallengeListView()
                                            .environmentObject(appState)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("All challenges")
                                            Text(verbatim: "\(challenges.scripts.count)").monospacedDigit()
                                        }
                                        .font(.subheadline)
                                    }
                                    .textCase(nil)
                                }
                            }
                            challengeRow
                        }
                        .textCase(nil)
                    } footer: {
                        Text("Everyone reads the same script. Your best take goes on the board.")
                    }
                }

                Section {
                    // A script that is also a challenge (the bundled sample
                    // is the first one) is listed once, up there — so for
                    // most learners this section is THEIR scripts, and it
                    // starts empty. Empty, it says what goes here and offers
                    // both ways to make one, rather than a bare header.
                    if ownScripts.isEmpty {
                        SpeechScriptsEmptyState(onWrite: { startNew(.write) },
                                                onOwn: { startNew(.own) })
                    }
                    ForEach(ownScripts) { script in
                        Button {
                            practicing = script
                        } label: {
                            SpeechScriptRow(script: script, best: store.best(for: script.id))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if !script.isBuiltIn {
                                Button(role: .destructive) {
                                    store.deleteScript(id: script.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            if script.genre == .own {
                                Button { editing = script } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.accentColor)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            // Admin accounts put one of their own scripts on
                            // every learner's tab as a challenge.
                            if gate.account?.unlimited == true, !script.isBuiltIn {
                                Button { publishing = script } label: {
                                    Label("Publish as challenge", systemImage: "trophy")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                } header: {
                    Text("My scripts")
                } footer: {
                    if !canWrite {
                        Text("Write scripts on any topic, or add your own, with Plus.")
                    }
                }
            }
            .navigationTitle("Speech")
            // Same header as Watch and Progress: the title inline-large on
            // the toolbar row, the tab's one action at its trailing edge.
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if canWrite {
                        Menu {
                            Button { composing = true } label: {
                                Label("Write with AI", systemImage: "sparkles")
                            }
                            Button { addingOwn = true } label: {
                                Label("Add my own script", systemImage: "pencil.line")
                            }
                        } label: {
                            Label("New script", systemImage: "plus")
                        }
                    } else {
                        // Not known to be Plus: ask fresh. A purchase a minute
                        // ago must not be met with the upsell again.
                        Button {
                            Task {
                                if await BillingGate.shared.allowsSpeechScripts() { choosingKind = true }
                                else { showingUpsell = true }
                            }
                        } label: {
                            Label("New script", systemImage: "plus")
                        }
                    }
                }
            }
        }
        .onAppear {
            store.reloadIfLanguageChanged()
            if store.scripts.isEmpty { store.reload() }
            BillingGate.shared.warm()
        }
        .task(id: appState.targetLanguage) {
            await challenges.refresh(language: appState.targetLanguage)
        }
        .onChange(of: appState.targetLanguage) { _, _ in
            store.reload()
        }
        .confirmationDialog("Publish as a challenge? Every learner of this language will see it, with a leaderboard.",
                            isPresented: Binding(get: { publishing != nil },
                                                 set: { if !$0 { publishing = nil } }),
                            titleVisibility: .visible, presenting: publishing) { script in
            Button("Publish") {
                Task {
                    do { try await challenges.publish(script) }
                    catch { publishError = String(describing: error) }
                }
            }
        }
        .alert("Couldn't publish", isPresented: Binding(get: { publishError != nil },
                                                        set: { if !$0 { publishError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(publishError ?? "")
        }
        .sheet(isPresented: $composing, onDismiss: openPending) {
            SpeechComposerSheet { script in
                store.add(script)
                openAfterSheet = script
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $addingOwn, onDismiss: openPending) {
            SpeechOwnScriptSheet(existing: nil) { script in
                store.add(script)
                openAfterSheet = script
            }
            .environmentObject(appState)
        }
        .sheet(item: $editing) { script in
            SpeechOwnScriptSheet(existing: script) { updated in
                store.add(updated)
            }
            .environmentObject(appState)
        }
        .fullScreenCover(item: $practicing) { script in
            SpeechPrompterView(script: script, native: appState.nativeLanguage,
                               level: appState.proficiency)
                .environmentObject(appState)
        }
        // Any script beyond the bundled one is Plus and up. The tap is
        // answered with what the feature is FIRST, never a bare paywall; the
        // sheet owns its paywall (a sheet raised from under a sheet never
        // appears).
        .sheet(isPresented: $showingUpsell) {
            SpeechPlusSheet(isLight: gate.account?.isLightPlan ?? false)
        }
        .confirmationDialog("New script", isPresented: $choosingKind) {
            Button("Write with AI") { composing = true }
            Button("Add my own script") { addingOwn = true }
        }
    }

    private func openPending() {
        guard let script = openAfterSheet else { return }
        openAfterSheet = nil
        practicing = script
    }
}

/// "My scripts" before there are any: what the section is for, and the two
/// ways to fill it.
struct SpeechScriptsEmptyState: View {
    var onWrite: () -> Void
    var onOwn: () -> Void

    var body: some View {
        // The buttons sit in the TEXT column, the icon's column left empty
        // below it; stacked, so neither label is cut and both are one size.
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Write your first script")
                        .font(.body.weight(.semibold))
                    Text("Choose a topic and AI writes it for your level, or paste a text of your own.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 8) {
                    Button(action: onWrite) {
                        Label("Write with AI", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(action: onOwn) {
                        Label("Add my own script", systemImage: "pencil.line")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }
}

struct SpeechScriptRow: View {
    let script: SpeechScript
    let best: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: script.genre.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(script.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(SpeechFormat.length(SpeechLibrary.estimatedSeconds(script.body, language: script.language)))
                    Text("·")
                    Text(script.genre.title)
                    if script.isBuiltIn {
                        Text("·")
                        Text("Sample")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let best {
                Text("\(best)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(SpeechScoreColor.color(best))
            }
        }
        .padding(.vertical, 2)
    }
}

enum SpeechScoreColor {
    static func color(_ score: Int) -> Color {
        score >= 85 ? .green : score >= 65 ? .orange : .red
    }
}

// MARK: - The whole script

/// The full text with its notes, opened from the prompter's script button —
/// to read it through before a take, or to look something up.
struct SpeechScriptSheet: View {
    /// Called with the script after an edit, so the prompter reads the new
    /// text at once.
    var onEdited: (SpeechScript) -> Void = { _ in }
    @State private var script: SpeechScript
    @State private var editing = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    /// Study mode (2026-10-14): the script's expressions, grammar and words
    /// marked in the text, a note under each paragraph. Remembered across
    /// scripts — someone who studies keeps studying.
    @AppStorage("speech.script.study") private var studying = false
    @State private var study: ScriptStudy?
    @State private var studyFailed = false
    @State private var studyLoading = false
    @State private var card: ScriptStudy.Highlight?

    init(script: SpeechScript, onEdited: @escaping (SpeechScript) -> Void = { _ in },
         study: ScriptStudy? = nil) {
        _script = State(initialValue: script)
        _study = State(initialValue: study)
        self.onEdited = onEdited
    }

    private var paragraphs: [String] { ScriptStudy.paragraphs(script.body) }

    var body: some View {
        NavigationStack {
            List {
                // Its own row, not the toolbar (founder, 2026-10-14): a switch
                // beside the title and Done crowded the header, and in longer
                // languages the label had nowhere to go.
                Section {
                    Toggle(isOn: $studying) {
                        Label {
                            // Its own key: the catalog's "Study" is a noun
                            // (공부, Lernzeit); this is the act (공부하기).
                            Text(explain(key: "speech.study.toggle", default: "Study"))
                        } icon: {
                            Image(systemName: "highlighter")
                        }
                    }
                } footer: {
                    // Right under the switch, where the eye is: below a long
                    // script the "Preparing…" row was off screen, and the
                    // switch read as doing nothing.
                    if studying {
                        if study != nil {
                            Text("Tap for an explanation")
                        } else {
                            studyStatus
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(script.title)
                            .font(.title2.weight(.semibold))
                        if !script.summary.isEmpty {
                            Text(script.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Group {
                            if studying, let study {
                                ScriptStudyText(paragraphs: paragraphs, study: study) { card = $0 }
                            } else {
                                Text(script.body)
                                    .font(.body)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                } header: {
                    if studying, let study {
                        ScriptStudyLegend(study: study)
                    }
                } footer: {
                    HStack(spacing: 6) {
                        Label(script.genre.title, systemImage: script.genre.symbol)
                        Text("·")
                        Text(SpeechFormat.length(SpeechLibrary.estimatedSeconds(script.body, language: script.language)))
                    }
                }

                ScriptVoiceoverSection(script: script)

                if !script.keyTerms.isEmpty {
                    Section("Key terms") {
                        ForEach(script.keyTerms, id: \.self) { term in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(term.term).font(.body.weight(.medium))
                                if !term.meaning.isEmpty {
                                    Text(term.meaning).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !script.sources.isEmpty {
                    Section("Sources") {
                        Text(script.sources.joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The bundled sample is everyone's and stays as shipped;
                // changing it would make it a script of your own, which is
                // the Plus side of the tab.
                if !script.isBuiltIn && !script.isChallenge {
                    // Edit on the left, Done alone on the right (founder,
                    // 2026-10-14).
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Edit") { editing = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $editing) {
                SpeechOwnScriptSheet(existing: script) { updated in
                    SpeechStore.shared.add(updated)
                    script = updated
                    study = nil
                    onEdited(updated)
                }
                .environmentObject(appState)
            }
            .sheet(item: $card) { h in
                if let study {
                    ScriptStudyCardSheet(highlight: h, study: study)
                        .environmentObject(appState)
                }
            }
            .task(id: studyTaskId) { await loadStudy() }
        }
    }

    private var studyTaskId: String { "\(studying)|\(script.body.hashValue)" }

    @ViewBuilder private var studyStatus: some View {
        if studyFailed {
            VStack(alignment: .leading, spacing: 8) {
                Text(ScriptStudyEngine.StudyError.empty.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try again") { Task { await loadStudy(force: true) } }
                    .buttonStyle(.bordered)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView()
                Text("Preparing study notes…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadStudy(force: Bool = false) async {
        guard studying, study == nil, !studyLoading || force else { return }
        studyLoading = true
        studyFailed = false
        defer { studyLoading = false }
        do {
            study = try await ScriptStudyEngine.study(for: script, native: appState.nativeLanguage,
                                                      level: appState.proficiency)
        } catch {
            if !(error is CancellationError) { studyFailed = true }
        }
    }
}

// MARK: - Takes

/// Every take of one script, newest first, each opening its result.
struct SpeechTakesSheet: View {
    let scriptId: UUID
    @ObservedObject private var store = SpeechStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let takes = store.takes(for: scriptId)
        NavigationStack {
            Group {
                if takes.isEmpty {
                    ContentUnavailableView("No takes yet", systemImage: "record.circle",
                                           description: Text("Your recordings of this script will be here."))
                } else {
                    List {
                        ForEach(takes) { take in
                            NavigationLink {
                                SpeechResultView(takeId: take.id)
                            } label: {
                                SpeechTakeRow(take: take)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { store.deleteTake(id: takes[i].id) }
                        }
                    }
                }
            }
            .navigationTitle("Takes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct SpeechTakeRow: View {
    let take: SpeechTake

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(take.createdAt, format: .dateTime.month().day().hour().minute())
                HStack(spacing: 6) {
                    Text(SpeechFormat.duration(take.durationSeconds))
                    if take.videoFilename != nil {
                        Image(systemName: "video.fill")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(take.metrics.overall)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(SpeechScoreColor.color(take.metrics.overall))
        }
    }
}

// MARK: - Composer

/// Writing a new script: what kind, about what (optional), how long. One
/// button. Plus and up — the caller checks before presenting.
struct SpeechComposerSheet: View {
    var onWritten: (SpeechScript) -> Void
    /// Opens with "Also make it in my voice" on (screenshot captures).
    var voiceoverOn = false
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speech.composer.genre") private var genreRaw = SpeechGenre.explainer.rawValue
    @AppStorage("speech.composer.seconds") private var seconds = 60
    @State private var topic = ""
    @State private var writing = false
    @State private var error: String?
    /// "Also make it in my voice" — optional, priced before anything is
    /// written, made right after (`ScriptVoiceoverCenter`).
    @State private var voiceover = false
    @State private var wall: TalkWall?
    @ObservedObject private var gate = BillingGate.shared

    private var genre: SpeechGenre { SpeechGenre(rawValue: genreRaw) ?? .explainer }
    private var quote: Int {
        ScriptVoiceover.quoteMinutes(targetSeconds: seconds, language: appState.targetLanguage)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $genreRaw) {
                        ForEach(SpeechGenre.writable) { g in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.title)
                                    Text(g.blurb).font(.footnote).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: g.symbol)
                            }
                            .tag(g.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    TextField(genre.topicPlaceholder, text: $topic, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Topic")
                } footer: {
                    Text("Leave it empty and we'll pick something worth knowing.")
                }

                Section("Length") {
                    Picker("Length", selection: $seconds) {
                        ForEach(SpeechLibrary.lengths, id: \.self) { s in
                            Text(SpeechFormat.length(s)).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if appState.voiceCloneId != nil {
                    Section {
                        Toggle("Also make it in my voice", isOn: $voiceover)
                    } footer: {
                        Text(ScriptVoiceover.priceLine(minutes: quote, account: gate.account))
                    }
                }
            }
            .disabled(writing)
            .talkWall($wall, source: "speech_composer_voiceover")
            .onAppear {
                gate.warm()
                if voiceoverOn { voiceover = true }
                if topic.isEmpty { topic = SheetDrafts.text("speech.topic") ?? "" }
            }
            .onChange(of: topic) { _, t in SheetDrafts.set("speech.topic", t) }
            .navigationTitle("New script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Write") { write() }
                        .disabled(writing)
                }
            }
            .overlay {
                if writing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Writing your script…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("Couldn't write the script", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        .interactiveDismissDisabled(writing)
    }

    private func write() {
        writing = true
        let avoid = SpeechStore.shared.scripts.map(\.title)
        let quoted = quote
        let voiceId = voiceover ? appState.voiceCloneId : nil
        Task {
            // The minutes are asked about BEFORE the script is written, so
            // nobody waits for a script whose voiceover they can't have.
            if voiceId != nil {
                if await BillingGate.shared.blocks() {
                    writing = false
                    wall = .paywall(tier: nil)
                    return
                }
                if let refused = await ScriptVoiceoverCenter.shared.wall(forMinutes: quoted) {
                    writing = false
                    if let w = await TalkWall.resolve(refused) { wall = w } else { error = refused.localizedDescription }
                    return
                }
            }
            do {
                let script = try await SpeechScriptEngine.write(
                    genre: genre, topic: topic, seconds: seconds,
                    language: appState.targetLanguage, native: appState.nativeLanguage,
                    level: appState.proficiency, avoidTitles: avoid)
                Analytics.capture("speech_script_written", [
                    "genre": genre.rawValue, "seconds": seconds, "topic": !topic.isEmpty,
                ])
                writing = false
                if let voiceId {
                    // Made in the background; the Script sheet shows its
                    // progress, and a failure there is a button to try again.
                    // The written script's own price, never more than the
                    // estimate the toggle showed.
                    let price = min(quoted, ScriptVoiceover.quoteMinutes(text: script.body,
                                                                         language: script.language))
                    Task { try? await ScriptVoiceoverCenter.shared.make(script: script, voiceId: voiceId,
                                                                         quotedMinutes: price) }
                }
                SheetDrafts.clear("speech.topic")
                dismiss()
                onWritten(script)
            } catch {
                writing = false
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Your own script

/// Type or paste a text to practise — a talk you have to give, a pitch, a
/// speech for a wedding. Nothing is generated; the text is saved as given.
struct SpeechOwnScriptSheet: View {
    let existing: SpeechScript?
    var onSave: (SpeechScript) -> Void
    /// A draft to open with, and the voiceover choice on (screenshot captures).
    var draft: String? = nil
    var voiceoverOn = false
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @FocusState private var bodyFocused: Bool
    /// "Also make it in my voice", priced live from what is typed.
    @State private var voiceover = false
    @State private var wall: TalkWall?
    @State private var checking = false
    @ObservedObject private var gate = BillingGate.shared

    private var language: String { existing?.language ?? LanguageCatalog.base(appState.targetLanguage) }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (optional)", text: $title)
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 260)
                        .focused($bodyFocused)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Type or paste the text you want to practise.")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    HStack {
                        Text("Script")
                        Spacer()
                        PasteButton(payloadType: String.self) { strings in
                            guard let pasted = strings.first else { return }
                            text = text.isEmpty ? pasted : text + "\n\n" + pasted
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    }
                } footer: {
                    if !trimmed.isEmpty {
                        Text("About \(SpeechFormat.length(max(1, SpeechLibrary.estimatedSeconds(trimmed, language: language)))) to read · leave a blank line between paragraphs.")
                    } else {
                        Text("Write it in \(LanguageCatalog.name(language, in: appState.nativeLanguage)).")
                    }
                }

                // Only once there IS a script: the price is measured from it,
                // and before a word is typed there is nothing to price
                // (founder, 2026-10-14 — the length first, then the cost).
                if appState.voiceCloneId != nil && !trimmed.isEmpty {
                    Section {
                        Toggle("Also make it in my voice", isOn: $voiceover)
                            .disabled(quote > ScriptVoiceover.maxMinutes)
                    } footer: {
                        if quote > ScriptVoiceover.maxMinutes {
                            Text(ScriptVoiceoverCenter.VoiceoverError.tooLong.localizedDescription)
                        } else {
                            Text(ScriptVoiceover.priceLine(minutes: quote, account: gate.account))
                        }
                    }
                }
            }
            .talkWall($wall, source: "speech_own_voiceover")
            .onAppear { gate.warm() }
            .navigationTitle(existing == nil ? Text("My script") : Text("Edit script"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTapped() }
                        .disabled(trimmed.isEmpty || checking)
                }
            }
            .onAppear {
                if let existing {
                    title = existing.title
                    text = existing.body
                } else if let draft {
                    text = draft
                } else if let kept = SheetDrafts.text("speech.body") {
                    // What they typed before closing the sheet unsaved.
                    title = SheetDrafts.text("speech.title") ?? ""
                    text = kept
                } else {
                    bodyFocused = true
                }
                if voiceoverOn { voiceover = true }
            }
            .onChange(of: text) { _, t in
                guard existing == nil, draft == nil else { return }
                SheetDrafts.set("speech.body", t)
                SheetDrafts.set("speech.title", title)
            }
            .onChange(of: title) { _, t in
                guard existing == nil, draft == nil, !trimmed.isEmpty else { return }
                SheetDrafts.set("speech.title", t)
            }
        }
    }

    /// The voiceover's price for what is typed so far — the same function
    /// the Script sheet's button reads.
    private var quote: Int {
        ScriptVoiceover.quoteMinutes(text: trimmed.isEmpty ? " " : trimmed, language: language)
    }

    private func saveTapped() {
        guard voiceover, let voiceId = appState.voiceCloneId, quote <= ScriptVoiceover.maxMinutes else {
            save(); return
        }
        let quoted = quote
        checking = true
        Task {
            defer { checking = false }
            if await BillingGate.shared.blocks() { wall = .paywall(tier: nil); return }
            if let refused = await ScriptVoiceoverCenter.shared.wall(forMinutes: quoted) {
                if let w = await TalkWall.resolve(refused) { wall = w }
                return
            }
            let script = save()
            Task { try? await ScriptVoiceoverCenter.shared.make(script: script, voiceId: voiceId,
                                                                 quotedMinutes: quoted) }
        }
    }

    @discardableResult
    private func save() -> SpeechScript {
        let givenTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Editing keeps what the script already was — an AI script stays an
        // AI script with its summary and sources; only key terms the new text
        // no longer contains drop out.
        let script = SpeechScript(
            id: existing?.id ?? UUID(),
            title: givenTitle.isEmpty ? Self.defaultTitle(trimmed) : givenTitle,
            genre: existing?.genre ?? .own,
            topic: existing?.topic ?? "",
            body: trimmed,
            summary: existing?.summary ?? "",
            keyTerms: (existing?.keyTerms ?? []).filter { trimmed.localizedCaseInsensitiveContains($0.term) },
            sources: existing?.sources ?? [],
            language: language,
            targetSeconds: SpeechLibrary.estimatedSeconds(trimmed, language: language),
            createdAt: existing?.createdAt ?? Date(),
            isBuiltIn: false
        )
        if existing == nil {
            Analytics.capture("speech_script_added", ["seconds": script.targetSeconds])
            SheetDrafts.clear("speech.title", "speech.body")
        }
        dismiss()
        onSave(script)
        return script
    }

    /// The first sentence, cut to a title's length.
    static func defaultTitle(_ text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        let enders: Set<Character> = [".", "!", "?", "。", "！", "？"]
        let sentence = firstLine.split(whereSeparator: { enders.contains($0) }).first.map(String.init) ?? firstLine
        let clean = sentence.trimmingCharacters(in: .whitespaces)
        return clean.count > 48 ? String(clean.prefix(46)) + "…" : clean
    }
}

// MARK: - Plus only

/// What a free or Light account sees on "+": the feature, said first, and
/// the way to it. The paywall opens only from here, on purpose.
struct SpeechPlusSheet: View {
    let isLight: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Plus and Max", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text("New scripts are a Plus feature")
                        .font(.title2.weight(.bold))
                    Text("The sample script stays free to practise. With Plus or Max, practise any text you like.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Write with AI").font(.body.weight(.medium))
                            Text("Explainers, products, people, briefings and news — true, and at your level.")
                                .font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "sparkles").foregroundStyle(.tint)
                    }
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add your own script").font(.body.weight(.medium))
                            Text("A presentation, a pitch, a speech you have to give.")
                                .font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "pencil.line").foregroundStyle(.tint)
                    }
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button {
                        showingPaywall = true
                    } label: {
                        Text(isLight ? "Upgrade to Plus" : "See plans")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Not now") { dismiss() }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                }
            }
        }
        .presentationDetents([.height(560), .large])
        .sheet(isPresented: $showingPaywall, onDismiss: {
            // Bought Plus in the paywall: this sheet has nothing left to say.
            Task {
                if await BillingGate.shared.allowsSpeechScripts() { dismiss() }
            }
        }) {
            PaywallView(source: "speech_script", preselectTier: "plus")
        }
        .onAppear { Analytics.capture("speech_plus_sheet", ["light": isLight]) }
    }
}
