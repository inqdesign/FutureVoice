import SwiftUI
import Charts
import PhotosUI

/// The name and face on the boards, the score over time, every take.
struct SpeechMeView: View {
    @ObservedObject private var store = SpeechStore.shared
    @ObservedObject private var avatar = AvatarStore.shared
    @State private var photoItem: PhotosPickerItem?
    @State private var naming = false
    @State private var showingSettings = false
    /// A result is a page of its own, full screen, as in the takes sheet.
    @State private var opened: SpeechTake?
    /// The name lives in defaults, so it is re-read when it can have moved.
    @State private var name = SpeechChallenges.displayName

    private var takes: [SpeechTake] { store.takes.sorted { $0.createdAt > $1.createdAt } }

    private var face: some View {
        SpeechChallengeFace(
            face: .init(display_name: name ?? "?",
                        avatar: avatar.image == nil ? SpeechChallenges.avatarPayload() : nil),
            size: 60, localImage: avatar.image)
    }

    private var profile: some View {
        Section {
            HStack(spacing: 14) {
                PhotosPicker(selection: $photoItem, matching: .images) { face }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Photo"))
                Button { naming = true } label: {
                    HStack {
                        Text(name ?? explain("Set your name"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(name == nil ? Color.accentColor : .primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        } footer: {
            Text("Shown beside your score on every challenge board.")
        }
    }

    private func scores(_ takes: [SpeechTake]) -> some View {
        let recent = Array(takes.prefix(30).reversed())
        return Section("Score") {
            if let best = takes.map(\.metrics.overall).max() {
                LabeledContent("Best") {
                    Text("\(best)")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(SpeechScoreColor.color(best))
                }
            }
            Chart(Array(recent.enumerated()), id: \.element.id) { item in
                LineMark(x: .value("Take", item.offset),
                         y: .value("Score", item.element.metrics.overall))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Take", item.offset),
                          y: .value("Score", item.element.metrics.overall))
                    .symbolSize(24)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .frame(height: 140)
            .padding(.vertical, 6)
        }
    }

    var body: some View {
        let takes = takes
        NavigationStack {
            List {
                profile
                if takes.count >= 2 { scores(takes) }
                Section("Takes") {
                    if takes.isEmpty {
                        Text("Take a challenge and your scores show up here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(takes) { take in
                        Button {
                            opened = take
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                if let title = store.script(id: take.scriptId)?.title {
                                    Text(title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                }
                                SpeechTakeRow(take: take)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for i in offsets { store.deleteTake(id: takes[i].id) }
                    }
                }
            }
            .navigationTitle("Me")
            // The small title, like every tab (2026-11-16, founder).
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
        .onAppear { name = SpeechChallenges.displayName }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    avatar.save(image)
                    await SpeechChallenges.shared.saveProfile()
                }
                photoItem = nil
            }
        }
        .sheet(isPresented: $naming, onDismiss: { name = SpeechChallenges.displayName }) {
            SpeechChallengeNameSheet(suggested: "")
        }
        .sheet(isPresented: $showingSettings) { SpeechSettingsView() }
        .fullScreenCover(item: $opened) { take in
            NavigationStack {
                SpeechResultView(takeId: take.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            BarCloseButton(title: "Done") { opened = nil }
                        }
                    }
            }
        }
    }
}
