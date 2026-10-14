import SwiftUI

// MARK: - Study mode

/// The script's paragraphs with the study highlights drawn IN the text and a
/// native-language note under each paragraph (Script sheet, Study on).
/// Tapping a highlight opens the app's own cards — the word card for a word,
/// the expression card for an expression or a grammar pattern (with the
/// study note as its "In this script" section). Never on the prompter.
struct ScriptStudyText: View {
    let paragraphs: [String]
    let study: ScriptStudy
    var onTap: (ScriptStudy.Highlight) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { p, para in
                if p > 0 { Divider() }
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.attributed(para, study.highlights(in: p)))
                        .font(.body)
                        .lineSpacing(5)
                        .tint(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if p < study.paragraphNotes.count, !study.paragraphNotes[p].isEmpty {
                        Text(study.paragraphNotes[p])
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "fvstudy", let id = Int(url.lastPathComponent),
                  let h = study.highlights.first(where: { $0.id == id }) else { return .discarded }
            onTap(h)
            return .handled
        })
    }

    static func attributed(_ para: String, _ highlights: [ScriptStudy.Highlight]) -> AttributedString {
        var a = AttributedString(para)
        for h in highlights {
            let chars = a.characters
            guard let lo = chars.index(chars.startIndex, offsetBy: h.offset, limitedBy: chars.endIndex),
                  let hi = chars.index(lo, offsetBy: h.length, limitedBy: chars.endIndex) else { continue }
            let r = lo ..< hi
            a[r].link = URL(string: "fvstudy://h/\(h.id)")
            a[r].backgroundColor = ScriptStudyStyle.fill(h.kind)
            a[r].underlineStyle = ScriptStudyStyle.line(h.kind)
        }
        return a
    }
}

enum ScriptStudyStyle {
    static func fill(_ kind: ScriptStudy.Kind) -> Color? {
        switch kind {
        case .expression: return Color.yellow.opacity(0.32)
        case .grammar: return Color.blue.opacity(0.14)
        case .word: return nil
        }
    }

    static func line(_ kind: ScriptStudy.Kind) -> Text.LineStyle {
        switch kind {
        case .expression: return Text.LineStyle(pattern: .solid, color: .orange)
        case .grammar: return Text.LineStyle(pattern: .solid, color: .blue)
        case .word: return Text.LineStyle(pattern: .dot, color: .secondary)
        }
    }

    static func name(_ kind: ScriptStudy.Kind, count: Int) -> String {
        switch kind {
        case .expression: return explain("Expressions \(count)")
        case .grammar: return explain("Grammar \(count)")
        case .word: return explain("Words \(count)")
        }
    }
}

/// Kind · count for each kind present, and how to use them.
struct ScriptStudyLegend: View {
    let study: ScriptStudy

    var body: some View {
        HStack(spacing: 12) {
            ForEach(ScriptStudy.Kind.allCases, id: \.self) { kind in
                let n = study.count(kind)
                if n > 0 {
                    HStack(spacing: 5) {
                        Text(verbatim: "ab")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.clear)
                            .background(ScriptStudyStyle.fill(kind) ?? .clear)
                            .underline(true, pattern: kind == .word ? .dot : .solid,
                                       color: kind == .expression ? .orange : kind == .grammar ? .blue : .secondary)
                            .accessibilityHidden(true)
                        Text(ScriptStudyStyle.name(kind, count: n))
                    }
                }
            }
            Spacer(minLength: 4)
            Text("Tap for an explanation")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .textCase(nil)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}

/// What a tapped highlight opens: the existing word or expression card.
struct ScriptStudyCardSheet: View {
    let highlight: ScriptStudy.Highlight
    let study: ScriptStudy

    var body: some View {
        switch highlight.kind {
        case .word:
            let words = study.highlights.filter { $0.kind == .word }.map(Self.wordKey)
            WordSheet(initialWord: Self.wordKey(highlight), words: words)
        case .expression, .grammar:
            let phrases = study.highlights.filter { $0.kind != .word }
            ExpressionSheet(initialPhrase: highlight.text,
                            phrases: phrases.map(\.text),
                            context: Dictionary(phrases.map {
                                ($0.text, ExpressionCard.Context(note: $0.note, example: $0.example,
                                                                 heading: explain("In this script")))
                            }, uniquingKeysWith: { a, _ in a }))
        }
    }

    static func wordKey(_ h: ScriptStudy.Highlight) -> String {
        VocabStore.lookupKey(for: h.lemma ?? h.text)
    }
}

// MARK: - Walls

/// The answer when a voiceover can't be paid for — the same two surfaces
/// every metered launch uses: the paywall for an account with nothing to
/// spend, the spent-pool sheet for a subscriber whose month is used.
enum TalkWall: Identifiable {
    case paywall(tier: String?)
    case spent(AccountStatus, InviteOffer?)

    var id: String {
        switch self {
        case .paywall(let t): return "paywall:\(t ?? "")"
        case .spent: return "spent"
        }
    }

    /// Nil for a wall that is an alert, not a sheet (`fairUseLimit`).
    @MainActor static func resolve(_ error: ElevenLabsError) async -> TalkWall? {
        switch error {
        case .insufficientCredits:
            BillingGate.shared.invalidate()
            return .paywall(tier: nil)
        case .dailyCapReached:
            let account = await AccountStatus.fetch()
            return .spent(account, await InviteOffer.load(for: account))
        default:
            return nil
        }
    }
}

struct TalkWallModifier: ViewModifier {
    @Binding var wall: TalkWall?
    var source: String
    @State private var next: TalkWall?

    func body(content: Content) -> some View {
        content.sheet(item: $wall, onDismiss: {
            guard let n = next else { return }
            next = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { wall = n }
        }) { w in
            switch w {
            case .paywall(let tier):
                PaywallView(source: source, preselectTier: tier)
            case .spent(let account, let invite):
                DailyAllowanceSheet(
                    kind: .talk,
                    canUpgrade: account.upgradeTier != nil,
                    upgradeName: AccountStatus.tierName(account.upgradeTier),
                    allowance: account.monthlyCapSeconds.map { $0 / 60 },
                    renewsOn: account.renewalLabel,
                    endsInstead: account.cancelAtPeriodEnd,
                    isTrial: account.isTrialing,
                    planMinutesAfterTrial: account.planMonthlySeconds.map { $0 / 60 },
                    canTopUp: account.isEntitled && !account.isUncappedTalk && !account.isTrialing,
                    invite: invite,
                    onReview: {},
                    onUpgrade: { next = .paywall(tier: account.upgradeTier ?? "plus") })
            }
        }
    }
}

extension View {
    func talkWall(_ wall: Binding<TalkWall?>, source: String) -> some View {
        modifier(TalkWallModifier(wall: wall, source: source))
    }
}

// MARK: - Hear it in my voice

/// The Script sheet's voiceover section: the priced button before it exists,
/// a progress line while it is made, then Play and Shadow — free forever.
struct ScriptVoiceoverSection: View {
    let script: SpeechScript
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var center = ScriptVoiceoverCenter.shared
    @ObservedObject private var gate = BillingGate.shared
    @StateObject private var player = AudioPlayer()
    @State private var wall: TalkWall?
    @State private var error: String?
    @State private var shadowing: ScriptVoiceoverStore.Stored?

    private var voiceId: String? { appState.voiceCloneId }
    private var quote: Int { ScriptVoiceover.quoteMinutes(text: script.body, language: script.language) }

    var body: some View {
        if let voiceId {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    content(voiceId)
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 4)
                .talkWall($wall, source: "speech_voiceover")
                .alert("Couldn't make it in your voice", isPresented: Binding(
                    get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: { Text(error ?? "") }
                .fullScreenCover(item: Binding(get: { shadowing.map { ShadowItem(stored: $0, body: script.body) } },
                                               set: { if $0 == nil { shadowing = nil } })) { item in
                    ShadowDrillView(turn: item.turn, targetLanguage: appState.targetLanguage,
                                    presetTimings: item.stored.meta.timings)
                        .environmentObject(appState)
                }
                .onDisappear { player.stop() }
                .onAppear { gate.warm() }
            } footer: {
                footer(voiceId)
            }
        }
    }

    private struct ShadowItem: Identifiable {
        let stored: ScriptVoiceoverStore.Stored
        let body: String
        var id: String { stored.url.lastPathComponent }
        /// A stable turn per voiceover file, so its shadow takes are listed
        /// together every time it is opened.
        var turn: Turn {
            let hex = ScriptVoiceover.sha(stored.url.lastPathComponent)
            let id = UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(13).prefix(3))-8\(hex.dropFirst(17).prefix(3))-\(hex.dropFirst(20).prefix(12))") ?? UUID()
            return Turn(id: id, role: .fluentSelf, audioURL: stored.url,
                        transcript: body,
                        durationMs: Int(stored.meta.seconds * 1000), timestamp: stored.meta.createdAt,
                        suggestion: nil)
        }
    }

    @ViewBuilder private func content(_ voiceId: String) -> some View {
        if let stored = center.existing(for: script, voiceId: voiceId) {
            Button {
                togglePlay(stored)
            } label: {
                Label(player.isPlaying ? "Pause" : "Play in my voice",
                      systemImage: player.isPlaying ? "pause.fill" : "play.fill")
            }
            Button {
                player.stop()
                shadowing = stored
            } label: {
                Label("Shadow it", systemImage: "waveform")
            }
        } else if case .making(let done, let total)? = center.job(for: script, voiceId: voiceId) {
            HStack(spacing: 12) {
                ProgressView()
                Text("Making it in your voice…")
                Spacer()
                Text("\(done)/\(total)").monospacedDigit().foregroundStyle(.secondary)
            }
        } else {
            Button {
                start(voiceId)
            } label: {
                Label(ScriptVoiceover.buttonLabel(minutes: quote), systemImage: "person.wave.2")
            }
            .disabled(quote > ScriptVoiceover.maxMinutes)
        }
    }

    @ViewBuilder private func footer(_ voiceId: String) -> some View {
        if center.existing(for: script, voiceId: voiceId) != nil {
            Text("Yours to replay and shadow, free.")
        } else if quote > ScriptVoiceover.maxMinutes {
            Text(ScriptVoiceoverCenter.VoiceoverError.tooLong.localizedDescription)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(ScriptVoiceover.priceLine(minutes: quote, account: gate.account))
                if case .failed(let message)? = center.job(for: script, voiceId: voiceId) {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
    }

    private func togglePlay(_ stored: ScriptVoiceoverStore.Stored) {
        if player.isPlaying { player.pause(); return }
        guard let data = try? Data(contentsOf: stored.url) else { return }
        try? player.play(data, source: "speech_voiceover")
    }

    private func start(_ voiceId: String) {
        Task {
            if await BillingGate.shared.blocks() { wall = .paywall(tier: nil); return }
            center.clearFailure(for: script, voiceId: voiceId)
            do {
                try await center.make(script: script, voiceId: voiceId, quotedMinutes: quote)
            } catch let e as ElevenLabsError {
                if let w = await TalkWall.resolve(e) { wall = w } else { error = e.localizedDescription }
            } catch is CancellationError {
            } catch {
                // Shown in the footer from the job's state.
            }
        }
    }
}

extension ScriptVoiceover {
    /// "Uses 9 min of talk time · 42 min of talk time left" — the one line
    /// every price is shown with.
    static func priceLine(minutes: Int, account: AccountStatus?) -> String {
        [costLabel(minutes: minutes), remainingLabel(account)].compactMap { $0 }.joined(separator: " · ")
    }
}
