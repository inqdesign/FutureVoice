import SwiftUI

/// A measured assessment raised the level (AppState.levelUpAnnouncement).
struct LevelUpAnnouncement: Identifiable, Equatable {
    let from: CEFRLevel
    let to: CEFRLevel
    var id: String { "\(from.rawValue)-\(to.rawValue)" }
}

/// One-time celebration sheet for a MEASURED level-up — presented by
/// RootTabView when a weekly assessment raises `AppState.proficiency`.
/// Manual level edits (Me tab, setup) never show this.
struct LevelUpSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let announcement: LevelUpAnnouncement
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.green)
                .opacity(revealed ? 1 : 0)

            VStack(spacing: 12) {
                Text("Level up")
                    .font(.title2.weight(.semibold))

                HStack(spacing: 12) {
                    Text(label(announcement.from))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(label(announcement.to))
                        .font(.largeTitle.weight(.bold))
                        .opacity(revealed ? 1 : 0)
                        .scaleEffect(revealed ? 1 : 0.85)
                }

                Text(explain("Your recent conversations measure at a higher level. Scoring and material difficulty now follow it."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                revealed = true
            }
        }
        .presentationDetents([.medium])
    }

    /// CEFR plus the local exam scale where one exists (TOPIK/JLPT).
    private func label(_ level: CEFRLevel) -> String {
        LanguageCatalog.levelLabel(level, target: appState.targetLanguage)
    }
}
