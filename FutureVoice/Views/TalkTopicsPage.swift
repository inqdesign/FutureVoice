import SwiftUI

/// What to talk about, behind ONE door on the Talk home (draft, 2026-10-18).
/// The home used to carry the whole discover block — a chip row per purpose
/// over a list of cards — under the ring, which made the launcher a feed.
/// Now the home has one button and this page is where topics live: the ideas
/// by category, with a call on a topic of your own floating at the bottom
/// (it opens by asking what to talk about). The ideas are the same
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

    /// The ideas' settings (chips, exam, interests), from the page header.
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
                        onBuildScenario: onBuildScenario,
                        showingSettings: $showingSettings)
                }
            }
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // "My own topic" floats at the bottom, drawn like the home's "Find a
        // topic", and the list dissolves under it the way every page with a
        // pinned bottom bar does.
        .fadingBottomBar {
            Button(action: onOwnTopic) {
                Label("My own topic", systemImage: "mic.fill")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .modifier(GlassFloatingButton())
            .fixedSize()
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        // The ideas swipe sideways between chips; iOS 26's back swipe from
        // anywhere in the content took that swipe and closed the page.
        .edgeOnlyBackSwipe()
        .navigationTitle("Topics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Talk settings")
            }
        }
    }
}
