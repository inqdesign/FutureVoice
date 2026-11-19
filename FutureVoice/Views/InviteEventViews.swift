import SwiftUI

/// The friend-invite event on screen: the banner under Settings'
/// subscription row, the sheet that explains it, and the sheet that takes a
/// half-price month. Every word is the server's (`InviteEvent.text`), so a
/// line the server does not send is simply not drawn.

/// Which of the event's two sheets is up.
enum InviteEventSheetKind: String, Identifiable {
    case about, claim
    var id: String { rawValue }
}

// MARK: - Banner

struct InviteEventBanner: View {
    @ObservedObject var event: InviteEvent
    var open: (InviteEventSheetKind) -> Void

    var body: some View {
        switch event.phase {
        case .off:
            EmptyView()
        case .claim:
            result(kicker: event.text("claim_kicker"), title: event.text("claim_title"),
                   body: event.text("claim_body"), button: event.text("claim_cta")) { open(.claim) }
        case .applied(let auto):
            result(kicker: event.text(auto ? "auto_kicker" : "done_kicker"),
                   title: event.text(auto ? "auto_title" : "done_title"),
                   body: event.text(event.monthsWaiting > 0 ? "done_more" : (auto ? "auto_body" : "done_body")),
                   button: event.text("invite_more"), prominent: false) { open(.about) }
        case .invited:
            promo(kicker: event.text("invited_kicker"), title: event.text("invited_title"),
                  body: event.text("invited_body"), button: event.text("invited_cta"))
        case .invite, .needsPlan:
            promo(kicker: event.text("banner_kicker"), title: event.text("banner_title"),
                  body: event.text("banner_body"), button: event.text("banner_cta"))
        }
    }

    /// The offer: text on the left, the two friends on the right, on the
    /// drawing's own paper. The one illustrated block on the Settings page,
    /// so nobody misses it.
    private func promo(kicker: String, title: String, body: String, button: String) -> some View {
        Button { open(.about) } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    if !kicker.isEmpty {
                        Text(verbatim: kicker)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(verbatim: title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(InviteArt.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !button.isEmpty {
                        Text(verbatim: button)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Capsule().fill(Color.accentColor))
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                InviteArt(percent: event.state.percent)
                    .frame(width: 176)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 12)
            .background(InviteArt.paper)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }

    /// What came of it: a plain card, so it reads as news about the plan.
    private func result(kicker: String, title: String, body: String, button: String,
                        prominent: Bool = true, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            line(kicker, font: .caption.weight(.semibold)).foregroundStyle(.green)
            line(title, font: .headline)
            line(body, font: .subheadline).foregroundStyle(.secondary)
            if !button.isEmpty {
                Group {
                    if prominent {
                        Button(action: action) { Text(verbatim: button) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(action: action) { Text(verbatim: button) }
                            .buttonStyle(.bordered)
                    }
                }
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func line(_ text: String, font: Font) -> some View {
        if !text.isEmpty {
            Text(verbatim: text)
                .font(font)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - The picture

/// Two friends, each holding up a board (drawn in the speech challenges'
/// coloured-pencil style, `Assets/InviteArt`). The boards are EMPTY in the
/// drawing: the percentage is the event's, so it is drawn here, on top.
struct InviteArt: View {
    let percent: Int

    /// The drawing is cut out of its paper (transparent around the people),
    /// so the card under it follows the theme: the drawing's own cream paper
    /// in light mode, the system's card in dark mode.
    static let paper = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .secondarySystemGroupedBackground
            : UIColor(red: 252 / 255, green: 249 / 255, blue: 240 / 255, alpha: 1)
    })
    static let ink = Color.primary

    /// Where the two boards are, as fractions of the picture.
    private static let boards = [CGRect(x: 0.024, y: 0.079, width: 0.256, height: 0.252),
                                 CGRect(x: 0.721, y: 0.079, width: 0.258, height: 0.252)]

    var body: some View {
        Image("InviteArt")
            .resizable()
            .aspectRatio(1100.0 / 870.0, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ForEach(Array(Self.boards.enumerated()), id: \.offset) { _, board in
                        Text(verbatim: "\(percent)%")
                            .font(.system(size: geo.size.height * board.height * 0.5, weight: .heavy))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .frame(width: geo.size.width * board.width,
                                   height: geo.size.height * board.height)
                            .position(x: geo.size.width * board.midX,
                                      y: geo.size.height * board.midY)
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - The sheet that explains it

struct InviteEventSheet: View {
    @ObservedObject var event: InviteEvent
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false
    @State private var codeInput = ""
    @State private var codeNote: String?
    @State private var redeeming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                Text(verbatim: event.text("sheet_title"))
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                Text(verbatim: event.text("sheet_body"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(lines("step").enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 12) {
                            Text(verbatim: "\(index + 1)")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.accentColor.opacity(0.12)))
                            Text(verbatim: step).font(.callout)
                        }
                    }
                }
                .padding(.top, 18)

                let rules = lines("rule")
                if !rules.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(rules, id: \.self) { rule in
                            Text(verbatim: "· " + rule)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground)))
                    .padding(.top, 16)
                }

                if event.phase == .needsPlan { codeEntry.padding(.top, 16) }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .safeAreaInset(edge: .bottom) { actions }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingPaywall, onDismiss: { Task { await event.refresh() } }) {
            PaywallView(source: "invite_event")
        }
        .onAppear { Analytics.capture("invite_event_sheet", ["phase": String(describing: event.phase)]) }
    }

    private var hero: some View {
        InviteArt(percent: event.state.percent)
            .frame(maxWidth: 280)
            .frame(maxWidth: .infinity)
            // No box: the two people stand on the sheet itself, in both themes.
            .padding(.vertical, 6)
    }

    /// `step1`, `step2`… for as long as the server sends them.
    private func lines(_ prefix: String) -> [String] {
        (1...6).map { event.text("\(prefix)\($0)") }.filter { !$0.isEmpty }
    }

    /// A friend's code, for someone who did not type it when they joined.
    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField(event.text("code_placeholder"), text: $codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.tertiarySystemFill)))
                Button {
                    Task { await redeem() }
                } label: {
                    Text(verbatim: event.text("code_cta"))
                }
                .buttonStyle(.bordered)
                .disabled(redeeming || codeInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let codeNote {
                Text(verbatim: codeNote).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func redeem() async {
        redeeming = true
        defer { redeeming = false }
        do {
            try await ReferralService.redeem(code: codeInput)
            codeInput = ""
            codeNote = nil
            await event.refresh()
        } catch {
            codeNote = error.localizedDescription
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            switch event.phase {
            case .invite, .applied, .claim:
                ShareLink(item: ReferralService.appStoreURL,
                          subject: Text(verbatim: "nawana"),
                          message: Text(verbatim: event.shareMessage)) {
                    Text(verbatim: event.text("sheet_cta")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            case .invited:
                primary(event.text("invited_cta")) { showingPaywall = true }
            case .needsPlan:
                let note = event.text("sheet_free_note")
                if !note.isEmpty {
                    Text(verbatim: note).font(.footnote).foregroundStyle(.secondary)
                }
                primary(event.text("sheet_cta_free")) { showingPaywall = true }
            case .off:
                EmptyView()
            }
            Button { dismiss() } label: { Text(verbatim: event.text("later")) }
                .padding(.bottom, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .background(.bar)
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(verbatim: title).frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
    }
}

// MARK: - The sheet that takes the month

struct InviteClaimSheet: View {
    @ObservedObject var event: InviteEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(verbatim: event.text("claim_sheet_title"))
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
            if let offer = event.offerPrice, let full = event.fullPrice {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: full).strikethrough().foregroundStyle(.secondary)
                    Text(verbatim: offer).font(.system(size: 40, weight: .heavy))
                }
                .padding(.top, 8)
            }
            Text(verbatim: event.text("claim_sheet_body"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if let error = event.claimError, !error.isEmpty {
                Text(verbatim: error).font(.footnote).foregroundStyle(.red).padding(.top, 8)
            }
            Spacer(minLength: 20)
            Button {
                Task { if await event.claim() { dismiss() } }
            } label: {
                Group {
                    if event.claiming { ProgressView() } else { Text(verbatim: event.text("claim_cta")) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .disabled(event.claiming)
            Button { dismiss() } label: { Text(verbatim: event.text("later")) }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(event.claiming)
        .onAppear { Analytics.capture("invite_claim_sheet") }
    }
}

// MARK: - One line elsewhere

/// A line on a screen that is not the event's own (the code field at sign
/// up): the event's words while it is on, the screen's own otherwise.
struct InviteEventLine: View {
    let key: String
    let fallback: String
    @ObservedObject private var event = InviteEvent.shared

    var body: some View {
        let line = event.state.enabled ? event.text(key) : ""
        Text(verbatim: line.isEmpty ? fallback : line)
            .task { await event.loadPublicIfNeeded() }
    }
}

// MARK: - Hosting

extension View {
    /// The event's two sheets, owned by whichever screen raises them (a
    /// sheet raised by the screen underneath never appears over this one).
    func inviteEventSheets(_ kind: Binding<InviteEventSheetKind?>) -> some View {
        sheet(item: kind) { kind in
            switch kind {
            case .about: InviteEventSheet(event: .shared)
            case .claim: InviteClaimSheet(event: .shared)
            }
        }
    }
}

// MARK: - Preview (debug)

#if DEBUG
/// The event's screens on a made-up account, for looking at them in the
/// simulator before the server has the event:
///   -inviteDemo invite|needsPlan|invited|claim|applied|auto
///   -inviteDemoSheet about|claim        (raise a sheet at once)
///   -inviteDemoTexts <path to scripts/invite-event-texts.json>
///   -inviteDemoLang ko|en
struct InviteEventDemo: View {
    static var isRequested: Bool { UserDefaults.standard.string(forKey: "inviteDemo") != nil }

    @ObservedObject private var event = InviteEvent.shared
    @State private var sheet: InviteEventSheetKind?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label { Text(verbatim: "Subscription") } icon: { Image(systemName: "sparkles") }
                        Spacer()
                        Text(verbatim: "Light").foregroundStyle(.secondary)
                    }
                }
                if event.phase != .off {
                    Section { InviteEventBanner(event: event) { sheet = $0 } }
                }
                Section {
                    Label { Text(verbatim: "Usage") } icon: { Image(systemName: "bolt.fill") }
                    Label { Text(verbatim: "The Core") } icon: { Image(systemName: "seal") }
                }
            }
            .navigationTitle(Text(verbatim: "Settings"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.locale, Locale(identifier: LanguageCatalog.currentNative))
        .inviteEventSheets($sheet)
        .onAppear(perform: seed)
    }

    private func seed() {
        let defaults = UserDefaults.standard
        if let language = defaults.string(forKey: "inviteDemoLang") {
            defaults.set(language, forKey: LanguageCatalog.nativeLanguageDefaultsKey)
        }
        Self.seed(phase: defaults.string(forKey: "inviteDemo") ?? "invite",
                  textsPath: defaults.string(forKey: "inviteDemoTexts"))
        if let raw = defaults.string(forKey: "inviteDemoSheet") {
            sheet = InviteEventSheetKind(rawValue: raw)
        }
    }

    static let phases = ["invite", "needsPlan", "invited", "claim", "applied", "auto"]
    static let phaseKey = "inviteDemoPhase"

    /// Keeps a preview state across refreshes and launches; "off" ends it.
    static func hold(_ phase: String) {
        UserDefaults.standard.set(phase, forKey: phaseKey)
        if phase == "off" {
            Task { await InviteEvent.shared.refresh() }
        } else {
            seed(phase: phase)
        }
    }

    /// Puts a made-up account in the shared state, so the real Settings page
    /// draws the banner for it until the next refresh.
    static func seed(phase: String, textsPath: String? = nil) {
        var state = InviteEventState()
        state.enabled = true
        state.announceVersion = 1
        state.code = "K3MQ9F"
        state.renewsAt = Calendar.current.date(byAdding: .day, value: 25, to: .now)
        let data = textsPath.flatMap { FileManager.default.contents(atPath: $0) }
            ?? Data(InviteEventDemoTexts.json.utf8)
        state.texts = (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
        func reward(_ status: String) -> InviteEventState.Reward? {
            let json = #"{"id":"\#(UUID().uuidString)","role":"inviter","status":"\#(status)","percent":50,"months":1}"#
            return try? JSONDecoder().decode(InviteEventState.Reward.self, from: Data(json.utf8))
        }
        switch phase {
        case "needsPlan":
            break
        case "invited":
            state.invited = true
        case "claim":
            state.canInvite = true
            state.store = "apple"
            state.appleOfferId = "friend_50"
            state.claimable = UUID()
            state.rewards = [reward("ready")].compactMap { $0 }
        case "applied":
            state.canInvite = true
            state.store = "apple"
            state.rewards = [reward("claimed"), reward("ready")].compactMap { $0 }
        case "auto":
            state.canInvite = true
            state.store = "stripe"
            state.rewards = [reward("claimed")].compactMap { $0 }
        default:
            state.canInvite = true
            state.store = "apple"
        }
        InviteEvent.shared.seedDemo(state, offerPrice: "₩7,500", fullPrice: "₩15,000")
    }
}
#endif
