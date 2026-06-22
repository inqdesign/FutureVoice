import SwiftUI

/// The user's personal line archive — every line they bookmarked, newest
/// first. Tap to shadow it again; saved attempts stay attached because the
/// SavedLine keeps the original Turn id.
struct SavedLinesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var shadowTarget: Turn?

    var body: some View {
        Group {
            if appState.savedLines.isEmpty {
                ContentUnavailableView {
                    Label("No saved lines", systemImage: "bookmark")
                } description: {
                    Text("Bookmark a line from shadow practice and it'll live here for repeat reps.")
                }
            } else {
                List {
                    ForEach(appState.savedLines) { line in
                        Button {
                            shadowTarget = Turn(
                                id: line.id, role: .fluentSelf, audioURL: nil,
                                transcript: line.text, durationMs: 0,
                                timestamp: line.savedAt, suggestion: nil
                            )
                        } label: {
                            row(line)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        for i in indexSet { appState.removeSavedLine(id: appState.savedLines[i].id) }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .sheet(item: $shadowTarget) { turn in
            ShadowDrillView(turn: turn, targetLanguage: appState.targetLanguage)
                .environmentObject(appState)
        }
    }

    private func row(_ line: SavedLine) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark.fill")
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(line.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if !line.source.isEmpty {
                        Text(line.source)
                        Text("·")
                    }
                    Text(line.savedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
