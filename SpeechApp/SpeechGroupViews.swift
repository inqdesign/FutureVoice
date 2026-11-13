import SwiftUI

// MARK: - Header

/// The Challenges tab's header (2026-11-10, founder): no large title. On the
/// left, whose board the page is showing, everyone or one of my groups, as a
/// menu; making or joining a group lives in the same menu.
struct SpeechGroupMenuItems: View {
    @ObservedObject private var groups = SpeechGroups.shared
    @Binding var creating: Bool
    @Binding var joining: Bool

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
    }
}

// MARK: - Group mode on the Challenges tab

/// Who leads the group and how I stand in it, then the group's challenges.
struct SpeechGroupSection: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var groups = SpeechGroups.shared
    @ObservedObject private var challenges = SpeechChallenges.shared
    @ObservedObject private var gate = BillingGate.shared
    let group: SpeechGroups.Group
    let tried: Int
    let total: Int
    let takesThisWeek: Int
    @State private var picking = false
    @State private var posting = false
    @State private var inviting = false
    @State private var showingMembers = false
    @State private var errorText: String?

    private let columns = [GridItem(.flexible(), spacing: 12, alignment: .top),
                           GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let leaders = groups.leaders, !leaders.isEmpty {
                ArenaRace(leaders: leaders, openMembers: { showingMembers = true })
            } else {
                HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.vertical, 30)
            }
            Button { inviting = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                    Text("\(group.members) members")
                    Text(verbatim: "·").foregroundStyle(.secondary)
                    Text("Invite")
                        .foregroundStyle(.tint)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)

            HStack {
                Text("Group challenges")
                    .font(Arena.display(26))
                Spacer()
                AppMenu {
                    Button { picking = true } label: {
                        Label("Pick a challenge", systemImage: "trophy")
                    }
                    Button {
                        if gate.account?.canWriteSpeechScripts == true { posting = true }
                        else { errorText = SpeechGroups.GroupError.notSubscribed.errorDescription }
                    } label: {
                        Label("Post my script", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Arena.raised))
                }
                .accessibilityLabel(Text("Add a group challenge"))
            }
            .padding(.horizontal, 4)

            if let items = groups.items {
                if items.isEmpty {
                    VStack(spacing: 10) {
                        Text("Pick one challenge and read it together.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Pick a challenge") { picking = true }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { item in card(item) }
                    }
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 20)
            }
        }
        .sheet(isPresented: $picking) {
            SpeechGroupPickSheet()
        }
        .sheet(isPresented: $posting) {
            SpeechGroupPostSheet()
        }
        .sheet(isPresented: $inviting) {
            SpeechGroupInviteSheet(group: group)
        }
        .sheet(isPresented: $showingMembers) {
            NavigationStack { SpeechGroupMembersView(group: group) }
        }
        .alert(errorText ?? "", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func card(_ item: SpeechGroups.Item) -> some View {
        let script = item.isPick ? challenges.script(id: item.id)
                                 : SpeechGroups.script(item, language: appState.targetLanguage)
        if let script {
            NavigationLink {
                if item.isPick {
                    SpeechChallengeView(script: script)
                        .environmentObject(appState)
                } else {
                    SpeechGroupScriptView(script: script, item: item, group: group)
                        .environmentObject(appState)
                }
            } label: {
                SpeechGroupCard(item: item)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .buttonStyle(.plain)
            .contextMenu {
                if item.added_by_me || group.is_creator {
                    Button(role: .destructive) {
                        Task { await groups.remove(item) }
                    } label: {
                        Label("Take off the group", systemImage: "minus.circle")
                    }
                }
            }
        }
    }
}

/// A group challenge as a card: the book card anatomy of the public ones,
/// with who hung it and the group's own top three.
struct SpeechGroupCard: View {
    let item: SpeechGroups.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                BookIconDisc {
                    Image(systemName: item.isPick ? "trophy.fill" : "doc.text.fill")
                        .font(.title3).foregroundStyle(.tint)
                }
                Spacer()
                if let best = item.my_best {
                    Text("\(best)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(SpeechScoreColor.color(best))
                }
            }
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Spacer(minLength: 16)
            Text(byLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.bottom, 8)
            if let faces = item.top_three, !faces.isEmpty {
                SpeechChallengeFaces(faces: faces, size: 30)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                    Text("Be the first").lineLimit(1)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(height: 30)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(Rectangle())
    }

    var byLineText: String { byLine }

    private var byLine: String {
        if item.added_by_me { return item.isPick ? explain("Picked by you") : explain("Written by you") }
        let who = item.added_by.isEmpty ? explain("Member") : item.added_by
        return item.isPick ? explain("Picked by \(who)") : explain("Written by \(who)")
    }
}

// MARK: - The group's board on a public challenge

/// Shown on a public challenge's page while a group is picked: the group's
/// loose board above the public one.
struct SpeechGroupBoardSection: View {
    @ObservedObject private var groups = SpeechGroups.shared
    let scriptId: UUID
    /// Bumped by the page after a take, so the board re-reads.
    var reloadToken: Int = 0
    @State private var rows: [SpeechGroups.BoardRow]?

    var body: some View {
        if let group = groups.selected {
            Section {
                if let rows {
                    if rows.isEmpty {
                        Text("Nobody in the group has read this yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rows) { row in SpeechGroupBoardLine(row: row) }
                    }
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } header: {
                Text(group.name)
            } footer: {
                Text("In the group every take counts, camera on or off. Your best one stands.")
            }
            .task(id: "\(group.id)-\(reloadToken)") {
                rows = await groups.board(group: group.id, script: scriptId)
            }
        }
    }
}

struct SpeechGroupBoardLine: View {
    let row: SpeechGroups.BoardRow

    var body: some View {
        if row.rank <= 3 {
            SpeechPodiumRow(row: row.row)
        } else {
            HStack(spacing: 12) {
                Text("\(row.rank)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .leading)
                SpeechChallengeFace(face: row.row.face, size: 28)
                Text(row.row.display_name)
                    .fontWeight(row.is_me ? .semibold : .regular)
                    .lineLimit(1)
                if row.is_me {
                    Text("You").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                }
                Spacer()
                Text("\(row.score)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(SpeechScoreColor.color(row.score))
            }
        }
    }
}

// MARK: - A member's own script, posted to the group

struct SpeechGroupScriptView: View {
    let script: SpeechScript
    let item: SpeechGroups.Item
    let group: SpeechGroups.Group
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var groups = SpeechGroups.shared
    @ObservedObject private var store = SpeechStore.shared
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
                HStack(spacing: 6) {
                    Text(SpeechFormat.length(SpeechLibrary.estimatedSeconds(script.body, language: script.language)))
                    Text("·")
                    Text(SpeechGroupCard(item: item).byLineText)
                }
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

// MARK: - Members, whole ranking

struct SpeechGroupMembersView: View {
    let group: SpeechGroups.Group
    @ObservedObject private var groups = SpeechGroups.shared
    @Environment(\.dismiss) private var dismiss
    @State private var inviting = false
    @State private var confirmLeave = false

    var body: some View {
        List {
            Section {
                ForEach(groups.leaders ?? []) { leader in
                    if leader.rank <= 3 {
                        SpeechPodiumRow(row: leader.row)
                    } else {
                        HStack(spacing: 12) {
                            Text("\(leader.rank)").monospacedDigit().foregroundStyle(.secondary)
                                .frame(minWidth: 28, alignment: .leading)
                            SpeechChallengeFace(face: leader.row.face, size: 28)
                            Text(leader.shownName).lineLimit(1)
                            Spacer()
                            Text("\(leader.score)").monospacedDigit().fontWeight(.semibold)
                        }
                    }
                }
            } footer: {
                Text("Each member's best score on every challenge, added up.")
            }
            Section {
                Button { inviting = true } label: {
                    Label("Invite", systemImage: "person.badge.plus")
                }
                Button(role: .destructive) { confirmLeave = true } label: {
                    Label("Leave the group", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $inviting) { SpeechGroupInviteSheet(group: group) }
        .confirmationDialog("Leave \(group.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave the group", role: .destructive) {
                Task {
                    await groups.leave(group.id)
                    dismiss()
                }
            }
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

// MARK: - Adding a group challenge

/// Any member hangs a public challenge on the group.
struct SpeechGroupPickSheet: View {
    @ObservedObject private var challenges = SpeechChallenges.shared
    @ObservedObject private var groups = SpeechGroups.shared
    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
                ForEach(challenges.live + challenges.past) { script in
                    let picked = groups.items?.contains { $0.id == script.id } == true
                    Button {
                        Task {
                            do {
                                try await groups.pick(script.id)
                                dismiss()
                            } catch {
                                errorText = error.localizedDescription
                            }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                if let category = SpeechChallengeCategory.label(challenges.standings[script.id]?.category) {
                                    Text(category).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                                }
                                Text(script.title).foregroundStyle(.primary)
                            }
                            Spacer()
                            if picked {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .disabled(picked)
                }
            }
            .navigationTitle("Pick a challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { BarCloseButton { dismiss() } }
            }
        }
    }
}

/// A subscriber posts one of their own scripts to the group.
struct SpeechGroupPostSheet: View {
    @ObservedObject private var store = SpeechStore.shared
    @ObservedObject private var challenges = SpeechChallenges.shared
    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?
    @State private var working = false

    private var own: [SpeechScript] {
        store.scripts.filter { challenges.script(id: $0.id) == nil && !$0.isBuiltIn }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
                if own.isEmpty {
                    Text("Write a script under My scripts first, then post it here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(own) { script in
                    Button {
                        guard !working else { return }
                        working = true
                        Task {
                            do {
                                try await SpeechGroups.shared.post(script)
                                dismiss()
                            } catch {
                                errorText = error.localizedDescription
                            }
                            working = false
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(script.title).foregroundStyle(.primary)
                            Text(SpeechFormat.length(SpeechLibrary.estimatedSeconds(script.body, language: script.language)))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Post my script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { BarCloseButton { dismiss() } }
                if working { ToolbarItem(placement: .confirmationAction) { ProgressView() } }
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
