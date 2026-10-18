import SwiftUI

/// What to talk about, behind ONE door on the Talk home (draft, 2026-10-18).
/// The home used to carry the whole discover block — a chip row per purpose
/// over a list of cards — under the ring, which made the launcher a feed.
/// Now the home has one button and this page is where topics live: a call on
/// a topic of your own at the top (it opens by asking what to talk about),
/// then the ideas by category (the same
/// `DiscoverSection` the home drew). Every pick still starts the call
/// through the home's own closures, so nothing about a launch changed.
///
/// The page is meant to grow into the place a topic is found, made and
/// suggested; today it is the first two.
struct TalkTopicsPage: View {
    let onPickNews: (SuggestedTopic) -> Void
    let onPickExam: (ExamTopic, ExamKind) -> Void
    let onPickTopic: (SuggestedTopic) -> Void
    let onPickScenario: (Scenario) -> Void
    let onAllScenarios: () -> Void
    let onBuildScenario: () -> Void
    /// A call that opens by asking what to talk about.
    let onOwnTopic: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DoorButton(title: "My own topic",
                           subtitle: explain("Say what you want to talk about, and the call starts there"),
                           icon: "mic.fill",
                           prominent: true,
                           action: onOwnTopic)
                    .padding(.horizontal, 20)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ideas")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    DiscoverSection(
                        onPickNews: onPickNews,
                        onPickExam: onPickExam,
                        onPickTopic: onPickTopic,
                        onPickScenario: onPickScenario,
                        onAllScenarios: onAllScenarios,
                        onBuildScenario: onBuildScenario)
                }
            }
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .contentMargins(.bottom, 24, for: .scrollContent)
        .navigationTitle("Topics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The page's "my own topic" tile.
private struct DoorButton: View {
    let title: LocalizedStringKey
    let subtitle: String
    let icon: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // TOP-aligned, not centred. Two doors side by side are different
            // heights (one subtitle wraps, the other doesn't) and `minHeight`
            // pads the short one, so a centred row floated its icon and title
            // down the card while its neighbour's sat at the top — the two
            // glyphs never lined up with each other.
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(prominent ? Color.accentColor.opacity(0.12)
                                : Color(.secondarySystemGroupedBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
