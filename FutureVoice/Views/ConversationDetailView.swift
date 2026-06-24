import SwiftUI

/// Full read-back of a past conversation: the whole transcript (You / Future
/// self), the session's score + note, with per-line "meaning" and audio replay.
/// Review cards are one tap away at the bottom — but the default, expected view
/// is the conversation itself, not the drill deck.
struct ConversationDetailView: View {
    @EnvironmentObject private var appState: AppState
    let session: Session
    @StateObject private var player = AudioPlayer()
    @State private var showingContinue = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let sc = session.summary?.scorecard { scorecardCard(sc) }
                if let note = session.summary?.overallNote, !note.isEmpty { noteCard(note) }
                Text("Transcript").font(.headline).padding(.top, 4)
                ForEach(session.turns) { turn in
                    TranscriptRow(turn: turn,
                                  nativeLanguage: appState.nativeLanguage,
                                  targetLanguage: appState.targetLanguage,
                                  player: player)
                }
            }
            .padding(20)
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    DrillView(source: .session(session.id))
                        .navigationTitle("Review")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Review", systemImage: "rectangle.stack")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .onDisappear { player.stop() }
        .fullScreenCover(isPresented: $showingContinue) {
            ConversationView(resumeSession: session)
                .environmentObject(appState)
        }
    }

    private var header: some View {
        Text((session.endedAt ?? session.startedAt).formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func scorecardCard(_ sc: SessionScorecard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Score").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(overall(sc))").font(.title3.weight(.bold)).monospacedDigit()
                    .foregroundStyle(color(overall(sc)))
            }
            axis("Vocabulary", sc.vocabulary.score)
            axis("Grammar", sc.grammar.score)
            axis("Fluency", sc.fluency.score)
            axis("Expressiveness", sc.expressiveness.score)
            if let p = sc.pronunciation { axis("Pronunciation", p.score) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private func axis(_ name: String, _ score: Int) -> some View {
        HStack(spacing: 10) {
            Text(name).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            GeometryReader { geo in
                Capsule().fill(Color(.tertiarySystemFill))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color(score))
                            .frame(width: max(0, geo.size.width * CGFloat(score) / 100))
                    }
            }
            .frame(height: 6)
            Text("\(score)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 26, alignment: .trailing)
        }
    }

    private func noteCard(_ note: String) -> some View {
        Text(note)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private var bottomBar: some View {
        Button {
            showingContinue = true
        } label: {
            Label("Continue this conversation", systemImage: "phone.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func overall(_ sc: SessionScorecard) -> Int {
        var s = [sc.vocabulary.score, sc.grammar.score, sc.expressiveness.score, sc.fluency.score]
        if let p = sc.pronunciation { s.append(p.score) }
        return s.isEmpty ? 0 : s.reduce(0, +) / s.count
    }

    private func color(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 50..<80: return .accentColor
        default: return .orange
        }
    }
}

/// All past conversations → each opens its full transcript.
struct ConversationsListView: View {
    @State private var sessions: [Session] = []

    var body: some View {
        List(sessions) { s in
            NavigationLink {
                ConversationDetailView(session: s)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.displayTitle).font(.body).lineLimit(1)
                    Text((s.endedAt ?? s.startedAt).formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .onAppear {
            sessions = SessionStore.shared.load()
                .filter { $0.endedAt != nil }
                .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
        }
    }
}

/// One transcript line — role, text, optional audio replay, "meaning" toggle,
/// and (for the user's lines) the more-natural suggestion.
private struct TranscriptRow: View {
    @EnvironmentObject private var appState: AppState
    let turn: Turn
    let nativeLanguage: String
    let targetLanguage: String
    @ObservedObject var player: AudioPlayer

    @State private var translation: String?
    @State private var showing = false
    @State private var loading = false
    @State private var reasonNative: String?
    @State private var reasonShowing = false
    @State private var reasonLoading = false
    @State private var showingShadow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.role == .user ? "You" : "Future self")
                .font(.caption).foregroundStyle(.secondary)

            Text(turn.transcript)
                .font(.body)
                .foregroundStyle(turn.role == .user ? .primary : Color.accentColor)
                .fixedSize(horizontal: false, vertical: true)

            if turn.role == .fluentSelf, hasAudio {
                HStack(spacing: 8) {
                    Button { playTurn() } label: {
                        Label("Listen", systemImage: "play.circle")
                    }
                    Button { showingShadow = true } label: {
                        Label("Shadow", systemImage: "waveform.badge.mic")
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.accentColor)
            }

            Button(action: toggleMeaning) {
                HStack(spacing: 4) {
                    if loading { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "character.bubble") }
                    Text(showing ? "Hide meaning" : "Meaning")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if showing, let t = translation {
                Text(t).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if turn.role == .user, let s = turn.suggestion {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.alternative).font(.subheadline).foregroundStyle(.primary)
                    Text(s.reason).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { toggleReason(s.reason) } label: {
                        HStack(spacing: 4) {
                            if reasonLoading { ProgressView().controlSize(.mini) }
                            else { Image(systemName: "character.bubble") }
                            Text(reasonShowing ? "Hide" : "Explain in my language")
                        }
                        .font(.caption2).foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    if reasonShowing, let r = reasonNative {
                        Text(r).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .sheet(isPresented: $showingShadow) {
            ShadowDrillView(turn: turn, targetLanguage: targetLanguage)
                .environmentObject(appState)
        }
    }

    /// Audio exists if TurnAudioStore still has it (resolved from the CURRENT
    /// Documents path by turnId — survives the app-container path changing on
    /// reinstall/update, which would have invalidated the stored absolute URL).
    private var hasAudio: Bool {
        TurnAudioStore.shared.url(for: turn.id) != nil || turn.audioURL != nil
    }

    private func playTurn() {
        let data = TurnAudioStore.shared.data(for: turn.id)
            ?? turn.audioURL.flatMap { try? Data(contentsOf: $0) }
        guard let data else { return }
        try? player.play(data, forceSessionReset: true)
    }

    private func toggleMeaning() {
        if showing { showing = false; return }
        showing = true
        guard translation == nil else { return }
        if let c = Translator.cached(turn.transcript, to: nativeLanguage) { translation = c; return }
        loading = true
        Task {
            let t = await Translator.translate(turn.transcript, to: nativeLanguage)
            translation = t
            loading = false
            if t == nil { showing = false }
        }
    }

    private func toggleReason(_ reason: String) {
        if reasonShowing { reasonShowing = false; return }
        reasonShowing = true
        guard reasonNative == nil else { return }
        if let c = Translator.cached(reason, to: nativeLanguage) { reasonNative = c; return }
        reasonLoading = true
        Task {
            let t = await Translator.translate(reason, to: nativeLanguage)
            reasonNative = t
            reasonLoading = false
            if t == nil { reasonShowing = false }
        }
    }
}
