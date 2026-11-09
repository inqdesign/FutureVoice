import NaturalLanguage
import SwiftUI

// MARK: - Study mode

/// The script's paragraphs with the study highlights drawn IN the text and a
/// native-language translation under each paragraph (Script sheet, Study on).
/// Tapping a highlight opens the app's own cards — the word card for a word,
/// the expression card for an expression or a grammar pattern (with the
/// study note as its "In this script" section). Never on the prompter.
struct ScriptStudyText: View {
    let paragraphs: [String]
    let study: ScriptStudy
    let language: String
    /// Words already held down in this script, marked wherever they occur.
    var lookedUp: Set<String> = []
    var onTap: (ScriptStudy.Highlight) -> Void
    /// Any word held down (2026-10-30, founder): its notebook lookup key.
    var onLookUp: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { p, para in
                if p > 0 { Divider() }
                VStack(alignment: .leading, spacing: 6) {
                    ScriptParagraphText(text: para, highlights: study.highlights(in: p),
                                        language: language, lookedUp: lookedUp,
                                        onTap: onTap, onLookUp: onLookUp)
                    if p < study.paragraphNotes.count, !study.paragraphNotes[p].isEmpty {
                        Text(study.paragraphNotes[p])
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// One study paragraph, drawn by UIKit because SwiftUI's `Text` can say which
/// link was TAPPED but not which word is under a long press. A tap on a
/// highlight opens its card as before; holding any word opens the word card.
struct ScriptParagraphText: UIViewRepresentable {
    let text: String
    let highlights: [ScriptStudy.Highlight]
    let language: String
    var lookedUp: Set<String> = []
    var onTap: (ScriptStudy.Highlight) -> Void
    var onLookUp: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = false
        v.isScrollEnabled = false
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator,
                                                      action: #selector(Coordinator.tapped(_:))))
        let hold = UILongPressGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.4
        v.addGestureRecognizer(hold)
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        context.coordinator.parent = self
        v.attributedText = attributed()
        v.accessibilityCustomActions = highlights.map { h in
            UIAccessibilityCustomAction(name: h.text) { _ in onTap(h); return true }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }

    private func attributed() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        let a = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
            .paragraphStyle: style,
        ])
        if !lookedUp.isEmpty {
            for (range, key) in Self.words(in: text, language: language) where lookedUp.contains(key) {
                a.addAttribute(.backgroundColor, value: ScriptStudyStyle.lookedUpFill,
                               range: NSRange(range, in: text))
            }
        }
        for h in highlights {
            guard let r = nsRange(h) else { continue }
            if let fill = ScriptStudyStyle.fill(h.kind) { a.addAttribute(.backgroundColor, value: UIColor(fill), range: r) }
            let (line, color) = Self.underline(h.kind)
            a.addAttributes([.underlineStyle: line.rawValue, .underlineColor: color], range: r)
        }
        return a
    }

    /// `ScriptStudyStyle.line` in UIKit terms.
    private static func underline(_ kind: ScriptStudy.Kind) -> (NSUnderlineStyle, UIColor) {
        switch kind {
        case .expression: return (.single, .systemOrange)
        case .grammar: return (.single, .systemBlue)
        case .word: return ([.single, .patternDot], .secondaryLabel)
        }
    }

    /// A highlight's Character offset/length as the UTF-16 range UIKit uses.
    fileprivate func nsRange(_ h: ScriptStudy.Highlight) -> NSRange? {
        guard let lo = text.index(text.startIndex, offsetBy: h.offset, limitedBy: text.endIndex),
              let hi = text.index(lo, offsetBy: h.length, limitedBy: text.endIndex) else { return nil }
        return NSRange(lo..<hi, in: text)
    }

    @MainActor final class Coordinator: NSObject {
        var parent: ScriptParagraphText
        init(_ parent: ScriptParagraphText) { self.parent = parent }

        /// The UTF-16 offset of the character drawn under `point`, or nil
        /// when the point is in the margin past a line's end.
        private func offset(at point: CGPoint, in v: UITextView) -> Int? {
            guard let pos = v.closestPosition(to: point),
                  let range = v.tokenizer.rangeEnclosingPosition(pos, with: .character, inDirection: .storage(.forward))
                    ?? v.tokenizer.rangeEnclosingPosition(pos, with: .character, inDirection: .storage(.backward)),
                  v.selectionRects(for: range).contains(where: { $0.rect.insetBy(dx: -4, dy: -4).contains(point) })
            else { return nil }
            return v.offset(from: v.beginningOfDocument, to: range.start)
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let v = g.view as? UITextView, let i = offset(at: g.location(in: v), in: v) else { return }
            if let h = parent.highlights.first(where: { parent.nsRange($0).map { NSLocationInRange(i, $0) } ?? false }) {
                parent.onTap(h)
            } else if !parent.lookedUp.isEmpty,
                      let word = ScriptParagraphText.word(at: i, in: parent.text, language: parent.language),
                      parent.lookedUp.contains(word) {
                // A word looked up once opens on a tap from then on, like
                // the study's own highlights.
                parent.onLookUp(word)
            }
        }

        @objc func held(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let v = g.view as? UITextView,
                  let i = offset(at: g.location(in: v), in: v),
                  let word = ScriptParagraphText.word(at: i, in: parent.text, language: parent.language)
            else { return }
            HapticEngine.light()
            parent.onLookUp(word)
        }
    }

    /// The notebook key of the word over UTF-16 offset `i`.
    static func word(at i: Int, in text: String, language: String) -> String? {
        let utf16 = text.utf16
        guard let at = utf16.index(utf16.startIndex, offsetBy: i, limitedBy: utf16.endIndex),
              at < text.endIndex else { return nil }
        return words(in: text, language: language).first { $0.range.contains(at) }?.key
    }

    /// Every word of `text` with its notebook key. Japanese reads whole
    /// chunks (疲れ+た → 疲れる), like every other Japanese lookup; everything
    /// else is the word tokenizer's words.
    static func words(in text: String, language: String) -> [(range: Range<String.Index>, key: String)] {
        if LanguageCatalog.base(language) == "ja" {
            return JapaneseMorph.headwords(in: text, lexicon: CoreVocabulary.set,
                                           forms: JapaneseMorph.bundledForms)
                .map { ($0.range, $0.headword) }
        }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(NLLanguage(rawValue: LanguageCatalog.base(language)))
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).compactMap { r in
            let key = VocabStore.lookupKey(for: String(text[r]))
            return key.isEmpty ? nil : (r, key)
        }
    }
}

enum ScriptStudyStyle {
    /// A word the learner held down to look up: a quiet fill under the
    /// study's own colours, so it reads as "seen", not as a fourth kind.
    static let lookedUpFill = UIColor.systemGreen.withAlphaComponent(0.18)

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

/// Kind · count for each kind present (how to use them is the study
/// switch's footer, so the row never truncates in a long language).
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
            Spacer(minLength: 0)
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
    @MainActor static func resolve(_ error: VoiceError) async -> TalkWall? {
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
    /// Owned by the sheet, so scrolling this row away doesn't stop it.
    @ObservedObject var player: AudioPlayer
    /// Say it under the prompter (a tutor reading): a third button in the
    /// same row, so the sheet has one place for everything done with it.
    var onSpeech: (() -> Void)? = nil
    @State private var wall: TalkWall?
    @State private var error: String?
    @State private var shadowing: ScriptVoiceoverStore.Stored?

    private var voiceId: String? { appState.voiceCloneId }
    private var quote: Int { ScriptVoiceover.quoteMinutes(text: script.body, language: script.language) }

    var body: some View {
        if let voiceId {
            Section {
                // What it costs (or that it's free now) under the heading,
                // before the button it explains — read first, not after.
                VStack(alignment: .leading, spacing: 12) {
                    description(voiceId)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    content(voiceId)
                }
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
                .onAppear { gate.warm() }
            } header: {
                Text("Hear it in my voice")
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
            HStack(spacing: 10) {
                Button {
                    togglePlay(stored)
                } label: {
                    Label(player.isPlaying ? "Pause" : "Play",
                          systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .accentProminent()
                Button {
                    player.stop()
                    shadowing = stored
                } label: {
                    Label("Shadow", systemImage: "waveform")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                speechButton
            }
            // Three pills leave a label ~75 pt: beside its icon, シャドーイング
            // or Nachsprechen came out "シ…", and so did 섀도잉.
            .labelStyle(PillLabelStyle(stacked: onSpeech != nil))
            .buttonRowFitsOneLine()
            .controlSize(.large)
        } else if case .making(let done, let total)? = center.job(for: script, voiceId: voiceId) {
            HStack(spacing: 12) {
                ProgressView()
                Text("Making it in your voice…")
                Spacer()
                Text("\(done)/\(total)").monospacedDigit().foregroundStyle(.secondary)
            }
            if onSpeech != nil {
                speechButton.controlSize(.large).labelStyle(PillLabelStyle(stacked: false))
            }
        } else {
            // The minutes are in the line above; on the button beside the
            // title they read as the recording's length.
            HStack(spacing: 10) {
                Button {
                    start(voiceId)
                } label: {
                    Label("Make it in my voice", systemImage: "person.wave.2")
                        .frame(maxWidth: .infinity)
                }
                .accentProminent()
                .disabled(quote > ScriptVoiceover.maxMinutes)
                speechButton
            }
            .labelStyle(PillLabelStyle(stacked: false))
            .buttonRowFitsOneLine()
            .controlSize(.large)
        }
    }

    @ViewBuilder private var speechButton: some View {
        if let onSpeech {
            Button {
                player.stop()
                onSpeech()
            } label: {
                Label("Speech", systemImage: "music.mic")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder private func description(_ voiceId: String) -> some View {
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
            } catch let e as VoiceError {
                if let w = await TalkWall.resolve(e) { wall = w } else { error = e.localizedDescription }
            } catch is CancellationError {
            } catch {
                // Shown in the footer from the job's state.
            }
        }
    }
}

/// A list row's own label style gives the icon a wide slot of its own and
/// tints it with the accent (invisible on a filled button), so these pills
/// lay out their own label.
private struct PillLabelStyle: LabelStyle {
    let stacked: Bool

    func makeBody(configuration: Configuration) -> some View {
        if stacked {
            VStack(spacing: 3) {
                configuration.icon
                configuration.title.font(.footnote)
            }
        } else {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
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
