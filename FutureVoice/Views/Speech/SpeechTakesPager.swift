import SwiftUI

/// Every take of one script on one result page, opening on the newest
/// (founder, 2026-11-10: the history button went list → take, one level too
/// deep). Only the picture behind swipes, like Photos with older to the
/// left; the score, the sheet and the buttons stay put and change to the
/// take swiped to. The indicator at the top says where you are, and a tap on
/// it is a menu of every take to jump to, and deleting the one shown — what
/// the list this replaced did. A menu, not a sheet: the page's details are a
/// sheet already, and a page shows one at a time.
/// Android still opens the old takes list from the history button.
struct SpeechTakesPager: View {
    let scriptId: UUID
    @ObservedObject private var store = SpeechStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var current: UUID?

    /// Oldest first, so the newest is the last page and older ones are a
    /// swipe to the right away.
    private var takes: [SpeechTake] {
        store.takes(for: scriptId).sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let takes = takes
        let shown = current.flatMap { id in takes.first { $0.id == id } } ?? takes.last
        NavigationStack {
            Group {
                if let shown {
                    SpeechResultView(takeId: shown.id, pages: takes.map(\.id),
                                     onPage: { current = $0 })
                } else {
                    ContentUnavailableView("No takes yet", systemImage: "record.circle",
                                           description: Text("Your recordings of this script will be here."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    BarCloseButton(title: "Done") { dismiss() }
                }
                if takes.count > 1, let shown, let index = takes.firstIndex(where: { $0.id == shown.id }) {
                    ToolbarItem(placement: .principal) {
                        AppMenu {
                            ForEach(takes.reversed()) { take in
                                Button { current = take.id } label: {
                                    if take.id == shown.id {
                                        Label(menuTitle(take), systemImage: "checkmark")
                                    } else {
                                        Text(menuTitle(take))
                                    }
                                }
                            }
                            Divider()
                            Menu {
                                Button("Delete", role: .destructive) {
                                    store.deleteTake(id: shown.id)
                                    current = nil
                                }
                            } label: {
                                Label("Delete this take", systemImage: "trash")
                            }
                        } label: {
                            TakesIndicator(index: index, count: takes.count)
                        }
                        .accessibilityLabel(Text("Take \(index + 1) of \(takes.count)"))
                    }
                }
            }
        }
        // A picture swiped in shows its first frame before its player draws.
        .task {
            for take in takes.reversed() where take.videoIsCameraOnly && take.videoFilename != nil {
                if let url = SpeechVideoSync.playableURL(take) { await SpeechPosters.shared.warm(url) }
            }
        }
    }

    private func menuTitle(_ take: SpeechTake) -> String {
        "\(take.createdAt.formatted(.dateTime.month().day().hour().minute())) · \(take.metrics.overall)"
    }
}

/// Where you are among the takes: dots while they fit, a count past that.
private struct TakesIndicator: View {
    let index: Int
    let count: Int
    private static let maxDots = 9

    var body: some View {
        Group {
            if count <= Self.maxDots {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle()
                            .fill(.white.opacity(i == index ? 1 : 0.4))
                            .frame(width: 7, height: 7)
                    }
                }
            } else {
                Text(verbatim: "\(index + 1) / \(count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.35), in: Capsule())
        .animation(.easeOut(duration: 0.2), value: index)
    }
}
