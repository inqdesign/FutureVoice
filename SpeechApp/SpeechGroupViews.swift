import SwiftUI

// MARK: - Header

/// The Challenges tab's header (2026-11-10, founder): no large title. On the
/// left, whose board the page is showing, everyone or one of my groups, as a
/// menu; making or joining a group lives in the same menu.
struct SpeechGroupMenuItems: View {
    @ObservedObject private var groups = SpeechGroups.shared
    @Binding var creating: Bool
    @Binding var joining: Bool
    @Binding var leaving: Bool

    var body: some View {
        Button {
            groups.select(nil)
        } label: {
            if groups.selectedId == nil {
                Label("Everyone", systemImage: "checkmark")
            } else {
                Text("Everyone")
            }
        }
        if !groups.groups.isEmpty {
            Section("My groups") {
                ForEach(groups.groups) { group in
                    Button {
                        groups.select(group.id)
                    } label: {
                        if groups.selectedId == group.id {
                            Label(group.name, systemImage: "checkmark")
                        } else {
                            Text(group.name)
                        }
                    }
                }
            }
        }
        Section {
            Button { creating = true } label: {
                Label("Make a group", systemImage: "person.2.badge.plus")
            }
            Button { joining = true } label: {
                Label("Join with a code", systemImage: "number")
            }
        }
        if let group = groups.selected {
            Section {
                Button(role: .destructive) { leaving = true } label: {
                    Label("Leave \(group.name)", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }
}

// MARK: - Group mode on the Challenges tab

/// A group plays one challenge at a time (2026-11-14, founder): the round on
/// top, who's where in it while it runs, and the group's ranking, which is
/// how many cards each member has won. Nothing else: the medal week and every
/// challenge stay on Everyone.
struct SpeechGroupSection: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var groups = SpeechGroups.shared
    let group: SpeechGroups.Group
    @State private var setting = false
    @State private var inviting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if groups.roundLoaded {
                if let round = groups.round {
                    VStack(spacing: 14) {
                        #if DEBUG
                        // `-speechGroupBelow 1`: start under the card, for captures.
                        if !UserDefaults.standard.bool(forKey: "speechGroupBelow") {
                            SpeechGroupRoundTicket(round: round, group: group)
                        }
                        #else
                        SpeechGroupRoundTicket(round: round, group: group)
                        #endif
                        if round.ended {
                            setNextButton("Set the next challenge")
                        } else {
                            SpeechGroupCheckins(rows: groups.roundBoard)
                        }
                    }
                } else {
                    VStack(spacing: 14) {
                        Text("Pick one challenge and a deadline, and read it together. The best score when time is up takes the card.")
                            .font(.subheadline)
                            .foregroundStyle(Arena.dim)
                            .multilineTextAlignment(.center)
                        setNextButton("Set the first challenge")
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Arena.card))
                }
            } else {
                HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.vertical, 40)
            }
            SpeechGroupCardsWon(holders: groups.holders, invite: { inviting = true })
        }
        .sheet(isPresented: $setting) {
            SpeechGroupRoundSheet().environmentObject(appState)
        }
        #if DEBUG
        // `-speechGroupSet 1`: open the next-challenge sheet, for captures.
        .onAppear { if UserDefaults.standard.bool(forKey: "speechGroupSet") { setting = true } }
        #endif
        .sheet(isPresented: $inviting) {
            SpeechGroupInviteSheet(group: group)
        }
    }

    private func setNextButton(_ title: LocalizedStringKey) -> some View {
        Button { setting = true } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .accentProminent()
    }
}

/// The round's challenge as the big cream card: who set it and the time left
/// while it runs; when it's over, a gold edge and who took the card.
struct SpeechGroupRoundTicket: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var groups = SpeechGroups.shared
    @ObservedObject private var challenges = SpeechChallenges.shared
    let round: SpeechGroups.Round
    let group: SpeechGroups.Group
    @State private var confirmCancel = false

    private var script: SpeechScript? {
        round.isGroupScript ? SpeechGroups.script(round, language: appState.targetLanguage)
                            : challenges.script(id: round.script_id)
    }

    private var tookCard: Bool { round.ended && round.winner_score != nil }

    var body: some View {
        if let script {
            NavigationLink {
                if round.isGroupScript {
                    SpeechGroupScriptView(script: script, group: group).environmentObject(appState)
                } else {
                    SpeechArenaDetail(script: script).environmentObject(appState)
                }
            } label: {
                VStack(spacing: 10) {
                    HStack {
                        Group {
                            if round.ended {
                                Text("Ended \(SpeechGroupTime.day(round.ends_at))")
                            } else if round.set_by_me {
                                Text("Set by you")
                            } else {
                                Text("Set by \(round.setByName)")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ChallengeArt.inkText.opacity(0.55))
                        Spacer()
                        if round.ended {
                            if let score = round.winner_score, let tier = MedalTier(score: score) {
                                MedalBadge(tier: tier, label: "\(score)", size: 40)
                            }
                        } else {
                            Label(SpeechGroupTime.left(until: round.ends_at), systemImage: "clock")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ChallengeArt.inkText.opacity(0.7))
                        }
                    }
                    .frame(height: 40)
                    ChallengeCardFace(script: script, category: challenges.standings[script.id]?.category,
                                      figureHeight: 240, titleSize: 30, titleLines: 3,
                                      mine: round.isGroupScript, showsCrowd: false)
                    if round.ended {
                        winnerLine
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(ChallengeArt.paper))
                .overlay {
                    if tookCard {
                        RoundedRectangle(cornerRadius: 44, style: .continuous)
                            .strokeBorder(Arena.gold, lineWidth: 4)
                    }
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                if !round.ended && (round.set_by_me || group.is_creator) {
                    Button(role: .destructive) { confirmCancel = true } label: {
                        Label("Cancel this challenge", systemImage: "xmark.circle")
                    }
                }
            }
            .confirmationDialog("Cancel this challenge? Nobody gets the card.",
                                isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Cancel the challenge", role: .destructive) {
                    Task { await groups.cancelRound() }
                }
                Button("Keep it", role: .cancel) {}
            }
        } else {
            HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private var winnerLine: some View {
        if let face = round.winnerFace {
            HStack(spacing: 8) {
                SpeechChallengeFace(face: face, size: 26)
                Group {
                    if round.winner_is_me {
                        Text("You take the card")
                    } else {
                        Text("\(face.display_name.isEmpty ? explain("Member") : face.display_name) takes the card")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChallengeArt.inkText)
            }
        } else {
            Text("Nobody read it, so no card this time.")
                .font(.subheadline)
                .foregroundStyle(ChallengeArt.inkText.opacity(0.65))
        }
    }
}

enum SpeechGroupTime {
    /// "2 days left", "5 hours left", "12 min left".
    static func left(until end: Date, now: Date = Date()) -> String {
        let seconds = max(0, end.timeIntervalSince(now))
        let days = Int(seconds / 86_400)
        if days >= 2 { return explain("\(days) days left") }
        if days == 1 { return explain("1 day left") }
        let hours = Int(seconds / 3_600)
        if hours >= 2 { return explain("\(hours) hours left") }
        if hours == 1 { return explain("1 hour left") }
        return explain("\(max(1, Int(seconds / 60))) min left")
    }

    /// The weekday within a week, else the date, in the app's language.
    static func day(_ date: Date, now: Date = Date()) -> String {
        let style = Date.FormatStyle(locale: Locale(identifier: UILanguage.chromeLanguage))
        if now.timeIntervalSince(date) < 6 * 86_400 {
            return date.formatted(style.weekday(.wide))
        }
        return date.formatted(style.month(.abbreviated).day())
    }

    /// When a round set now for so many days would end.
    static func end(afterDays days: Int) -> String {
        Date().addingTimeInterval(Double(days) * 86_400)
            .formatted(Date.FormatStyle(locale: Locale(identifier: UILanguage.chromeLanguage))
                .weekday(.wide).month(.abbreviated).day().hour().minute())
    }
}

/// Who's where in the running round: best so far and takes, and who hasn't
/// started yet (last, greyed).
struct SpeechGroupCheckins: View {
    let rows: [SpeechGroups.RoundRow]?

    var body: some View {
        Group {
            if let rows {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 60) }
                        line(row)
                    }
                }
            } else {
                HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.vertical, 24)
            }
        }
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Arena.card))
    }

    private func line(_ row: SpeechGroups.RoundRow) -> some View {
        HStack(spacing: 12) {
            Group {
                if let rank = row.rank, let tier = MedalTier(rank: rank) {
                    MedalBadge(tier: tier, label: "\(rank)", size: 30)
                } else if let rank = row.rank {
                    Text(verbatim: "\(rank)").font(.subheadline.monospacedDigit()).foregroundStyle(Arena.dim)
                } else {
                    Text(verbatim: "–").foregroundStyle(Arena.dim)
                }
            }
            .frame(width: 30)
            SpeechChallengeFace(face: row.face, size: 32)
                .opacity(row.score == nil ? 0.5 : 1)
            HStack(spacing: 6) {
                Text(row.shownName)
                    .font(.body.weight(row.is_me ? .semibold : .regular))
                    .foregroundStyle(row.score == nil ? Arena.dim : .white)
                    .lineLimit(1)
                if row.is_me {
                    Text("You").font(.caption.weight(.semibold)).foregroundStyle(Arena.accent)
                }
            }
            Spacer(minLength: 8)
            if let score = row.score {
                Text(row.attempts == 1 ? explain("1 take") : explain("\(row.attempts) takes"))
                    .font(.footnote)
                    .foregroundStyle(Arena.dim)
                Text(verbatim: "\(score)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(SpeechScoreColor.color(score))
                    .frame(minWidth: 30, alignment: .trailing)
            } else {
                Text("Not started")
                    .font(.footnote)
                    .foregroundStyle(Arena.dim)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// The group's ranking: how many cards each member holds, the cards
/// themselves under the name. Invite sits in its header.
struct SpeechGroupCardsWon: View {
    let holders: [SpeechGroups.Holder]?
    var invite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cards won").font(Arena.display(26))
                Spacer()
                Button(action: invite) {
                    Label("Invite", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Arena.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            if let holders {
                VStack(spacing: 0) {
                    ForEach(Array(holders.enumerated()), id: \.element.id) { index, holder in
                        if index > 0 { Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 60) }
                        line(holder)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Arena.card))
            } else {
                HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.vertical, 24)
            }
        }
    }

    private func line(_ holder: SpeechGroups.Holder) -> some View {
        HStack(spacing: 12) {
            Group {
                if holder.cards == 0 {
                    Text(verbatim: "–").foregroundStyle(Arena.dim)
                } else if let tier = MedalTier(rank: holder.rank) {
                    MedalBadge(tier: tier, label: "\(holder.rank)", size: 30)
                } else {
                    Text(verbatim: "\(holder.rank)").font(.subheadline.monospacedDigit()).foregroundStyle(Arena.dim)
                }
            }
            .frame(width: 30)
            SpeechChallengeFace(face: holder.face, size: 32)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(holder.shownName)
                        .font(.body.weight(holder.is_me ? .semibold : .regular))
                        .lineLimit(1)
                    if holder.is_me {
                        Text("You").font(.caption.weight(.semibold)).foregroundStyle(Arena.accent)
                    }
                }
                if holder.won.isEmpty {
                    Text("No cards yet").font(.footnote).foregroundStyle(Arena.dim)
                } else {
                    HStack(spacing: 5) {
                        ForEach(holder.won.prefix(6)) { card in SpeechGroupMiniCard(card: card) }
                        if holder.won.count > 6 {
                            Text(verbatim: "+\(holder.won.count - 6)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Arena.dim)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Text(verbatim: "\(holder.cards)")
                .font(Arena.display(24).monospacedDigit())
                .foregroundStyle(holder.cards == 0 ? Arena.dim : .white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// A won card, small: the challenge's picture on cream.
struct SpeechGroupMiniCard: View {
    let card: SpeechGroups.Holder.Won

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(ChallengeArt.paper)
            .frame(width: 26, height: 36)
            .overlay {
                if let art = ChallengeArt.image(for: card.script_id) {
                    Image(uiImage: art).resizable().scaledToFit().padding(3)
                } else {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(ChallengeArt.inkText.opacity(0.6))
                }
            }
            .accessibilityLabel(Text(card.title))
    }
}

// MARK: - The group's standings on a challenge's page

/// On the page of the group's running challenge: who's where in the round.
/// Any other script shows nothing here; the group plays one at a time.
struct SpeechGroupBoardSection: View {
    @ObservedObject private var groups = SpeechGroups.shared
    let scriptId: UUID
    /// Bumped by the page after a take, so the board re-reads.
    var reloadToken: Int = 0

    var body: some View {
        if let group = groups.selected, let round = groups.runningRound(for: scriptId) {
            Section {
                ForEach(groups.roundBoard ?? []) { row in
                    HStack(spacing: 12) {
                        Text(row.rank.map { "\($0)" } ?? "–")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28, alignment: .leading)
                        SpeechChallengeFace(face: row.face, size: 28)
                        Text(row.shownName)
                            .fontWeight(row.is_me ? .semibold : .regular)
                            .lineLimit(1)
                        if row.is_me {
                            Text("You").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                        }
                        Spacer()
                        if let score = row.score {
                            Text("\(score)")
                                .font(.body.monospacedDigit().weight(.semibold))
                                .foregroundStyle(SpeechScoreColor.color(score))
                        } else {
                            Text("Not started").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(verbatim: "\(group.name) · \(SpeechGroupTime.left(until: round.ends_at))")
            } footer: {
                Text("Takes made before the deadline count, camera on or off. The best score then takes the card.")
            }
            .task(id: "\(group.id)-\(reloadToken)") {
                await groups.refreshSelected()
            }
        }
    }
}

// MARK: - A member's own script, set as the group's challenge

struct SpeechGroupScriptView: View {
    let script: SpeechScript
    let group: SpeechGroups.Group
    @EnvironmentObject private var appState: AppState
    @State private var practicing = false
    @State private var showingScript = false
    @State private var showingTakes = false
    @State private var reloadToken = 0

    var body: some View {
        List {
            SpeechGroupBoardSection(scriptId: script.id, reloadToken: reloadToken)
        }
        .navigationTitle(script.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                if !script.summary.isEmpty {
                    Text(script.summary)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                Text(SpeechFormat.length(SpeechLibrary.estimatedSeconds(script.body, language: script.language)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button { showingTakes = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.headline).frame(width: 28).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text("Takes"))
                    Button { showingScript = true } label: {
                        Label("Script", systemImage: "doc.text")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    Button { practicing = true } label: {
                        Text(LocalizedStringKey("speech.challenge.take"))
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .accentProminent()
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showingScript) { SpeechScriptSheet(script: script) }
        .fullScreenCover(isPresented: $showingTakes) { SpeechTakesPager(scriptId: script.id) }
        .fullScreenCover(isPresented: $practicing, onDismiss: {
            // The score is sent after the take is saved; give it a beat.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                reloadToken += 1
            }
        }) {
            SpeechPrompterView(script: script, native: appState.nativeLanguage, level: appState.proficiency)
                .environmentObject(appState)
        }
    }
}

// MARK: - Making, joining, inviting

struct SpeechGroupCreateSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var working = false
    @State private var errorText: String?
    @State private var made: SpeechGroups.Group?

    var body: some View {
        NavigationStack {
            if let made {
                SpeechGroupInviteContent(group: made)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
            } else {
                Form {
                    Section {
                        TextField("Group name", text: $name)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(create)
                    } footer: {
                        Text("Friends, a study group, your team. Only people with the invite code can join.")
                    }
                    if let errorText {
                        Section { Text(errorText).foregroundStyle(.red) }
                    }
                }
                .navigationTitle("Make a group")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { BarCloseButton { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if working { ProgressView() } else {
                            Button("Make", action: create)
                                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !working else { return }
        working = true
        errorText = nil
        Task {
            do {
                made = try await SpeechGroups.shared.create(name: String(trimmed.prefix(40)),
                                                             language: appState.targetLanguage)
            } catch {
                errorText = error.localizedDescription
            }
            working = false
        }
    }
}

struct SpeechGroupJoinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var working = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title3.monospaced())
                        .submitLabel(.join)
                        .onSubmit(join)
                } footer: {
                    Text("Ask someone in the group for its six-letter code.")
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Join a group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { BarCloseButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button("Join", action: join)
                            .disabled(code.trimmingCharacters(in: .whitespaces).count < 6)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func join() {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6, !working else { return }
        working = true
        errorText = nil
        Task {
            do {
                try await SpeechGroups.shared.join(code: trimmed)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            working = false
        }
    }
}

struct SpeechGroupInviteSheet: View {
    let group: SpeechGroups.Group
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SpeechGroupInviteContent(group: group)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .presentationDetents([.medium])
    }
}

/// The code, large, and the share button.
struct SpeechGroupInviteContent: View {
    let group: SpeechGroups.Group

    private var message: String {
        explain("Let's practice speeches together in \(group.name). In nawana speech, go to Challenges, tap the group name at the top, then Join with a code: \(group.invite_code)")
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(group.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            VStack(spacing: 6) {
                Text("Invite code")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verbatim: group.invite_code)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .kerning(4)
                    .textSelection(.enabled)
            }
            ShareLink(item: message) {
                Label("Share the invite", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .accentProminent()
            Button {
                UIPasteboard.general.string = group.invite_code
            } label: {
                Label("Copy the code", systemImage: "doc.on.doc")
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationTitle("Invite")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Setting the next challenge

/// Pick a public challenge or one of the group's own scripts, pick a
/// deadline, start. That's all.
struct SpeechGroupRoundSheet: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var challenges = SpeechChallenges.shared
    @ObservedObject private var groups = SpeechGroups.shared
    @ObservedObject private var gate = BillingGate.shared
    @Environment(\.dismiss) private var dismiss

    enum Choice: Hashable {
        case challenge(UUID)
        /// A script already posted to this group.
        case posted(UUID)
        /// One of my scripts, posted when the round starts.
        case mine(SpeechScript)
    }

    @State private var choice: Choice?
    @State private var days = 7
    @State private var choosingOwn = false
    @State private var working = false
    @State private var errorText: String?

    private static let tileWidth: CGFloat = 168

    private var ownScript: SpeechScript? {
        switch choice {
        case .mine(let script): return script
        case .posted(let id): return groups.script(id: id)
        default: return nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Challenge").font(Arena.display(22))
                        // One row, so the deadline stays on screen however
                        // many challenges there are.
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 10) {
                                ownTile.frame(width: Self.tileWidth)
                                ForEach(challenges.live + challenges.past) { script in
                                    Button { choice = .challenge(script.id) } label: {
                                        ArenaTile(script: script, category: challenges.standings[script.id]?.category,
                                                  best: nil, tries: 0, ended: false)
                                            .overlay { selection(choice == .challenge(script.id)) }
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: Self.tileWidth)
                                }
                            }
                        }
                        .contentMargins(.horizontal, 16, for: .scrollContent)
                        .padding(.horizontal, -16)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deadline").font(Arena.display(22))
                        Picker("Deadline", selection: $days) {
                            Text("3 days").tag(3)
                            Text("1 week").tag(7)
                            Text("2 weeks").tag(14)
                        }
                        .pickerStyle(.segmented)
                        Text("Ends \(SpeechGroupTime.end(afterDays: days))")
                            .font(.footnote)
                            .foregroundStyle(Arena.dim)
                    }
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .background { Arena.background }
            .safeAreaInset(edge: .bottom) {
                Button(action: start) {
                    Group {
                        if working { ProgressView().tint(.white) } else { Text("Start") }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .accentProminent()
                .disabled(choice == nil || working)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle("Next challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { BarCloseButton { dismiss() } }
            }
            .sheet(isPresented: $choosingOwn) {
                SpeechGroupOwnScriptPicker { picked in choice = picked }
            }
        }
        .arenaScheme(true)
    }

    /// "Write our own" until one is picked, then that script's card.
    private var ownTile: some View {
        Button {
            if gate.account?.canWriteSpeechScripts == true || !(groups.items ?? []).filter({ !$0.isPick }).isEmpty {
                choosingOwn = true
            } else {
                errorText = SpeechGroups.GroupError.notSubscribed.errorDescription
            }
        } label: {
            Group {
                if let ownScript {
                    ChallengeCardFace(script: ownScript, category: nil, titleSize: 17, mine: true)
                        .padding(.top, 20)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 14)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(0.66, contentMode: .fit)
                        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(ChallengeArt.paper))
                        .overlay { selection(true) }
                } else {
                    Color.clear
                    .aspectRatio(0.66, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "plus").font(.title2.weight(.semibold))
                            Text("Write our own").font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Arena.dim)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selection(_ on: Bool) -> some View {
        if on {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Arena.accent, lineWidth: 3)
                .overlay(alignment: .topLeading) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Arena.accent)
                        .padding(10)
                }
        }
    }

    private func start() {
        guard let choice, !working else { return }
        working = true
        errorText = nil
        Task {
            do {
                let id: UUID
                switch choice {
                case .challenge(let c): id = c
                case .posted(let p): id = p
                case .mine(let script): id = try await groups.post(script)
                }
                try await groups.start(scriptId: id, days: days)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            working = false
        }
    }
}

/// The group's scripts already posted, and mine to post.
struct SpeechGroupOwnScriptPicker: View {
    var onPick: (SpeechGroupRoundSheet.Choice) -> Void
    @ObservedObject private var store = SpeechStore.shared
    @ObservedObject private var challenges = SpeechChallenges.shared
    @ObservedObject private var groups = SpeechGroups.shared
    @ObservedObject private var gate = BillingGate.shared
    @Environment(\.dismiss) private var dismiss

    private var posted: [SpeechGroups.Item] { (groups.items ?? []).filter { !$0.isPick } }

    private var own: [SpeechScript] {
        store.scripts.filter { challenges.script(id: $0.id) == nil && !$0.isBuiltIn }
    }

    var body: some View {
        NavigationStack {
            List {
                if !posted.isEmpty {
                    Section("This group's scripts") {
                        ForEach(posted) { item in
                            row(title: item.title, seconds: item.target_seconds) {
                                onPick(.posted(item.id))
                            }
                        }
                    }
                }
                if gate.account?.canWriteSpeechScripts == true {
                    Section {
                        if own.isEmpty {
                            Text("Write a script under My scripts first, then pick it here.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(own) { script in
                            row(title: script.title,
                                seconds: SpeechLibrary.estimatedSeconds(script.body, language: script.language)) {
                                onPick(.mine(script))
                            }
                        }
                    } header: {
                        Text("My scripts")
                    } footer: {
                        Text("Only this group sees it.")
                    }
                }
            }
            .navigationTitle("Write our own")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { BarCloseButton { dismiss() } }
            }
        }
    }

    private func row(title: String, seconds: Int, pick: @escaping () -> Void) -> some View {
        Button {
            pick()
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(SpeechFormat.length(seconds)).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// The Challenges tab's bar: my face at the trailing edge (the title, with
/// the system's title menu, says whose board it is).
struct SpeechChallengesHeader: ToolbarContent {
    var openMe: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            SpeechHeaderFace(openMe: openMe)
        }
    }
}

struct SpeechHeaderFace: View {
    @ObservedObject private var avatar = AvatarStore.shared
    var openMe: () -> Void

    var body: some View {
        Button(action: openMe) {
            SpeechChallengeFace(
                face: .init(display_name: SpeechChallenges.displayName ?? "?",
                            avatar: avatar.image == nil ? SpeechChallenges.avatarPayload() : nil),
                size: 34, localImage: avatar.image)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Me"))
    }
}
