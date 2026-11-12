import SwiftUI

/// "Change" on a free talk's island (2026-11-12, founder): the same ideas the
/// home's "Find a topic" page shows, so a learner can pick what to talk about
/// mid-call. Not the tutor's list of things to practise — that one belongs
/// to tutor mode. A pick hands back the title and the context the home's
/// launchers would have given a new call.
struct CallTopicIdeasSheet: View {
    /// title, blurb, isNews, news facts
    let onPick: (String, String, Bool, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                DiscoverSection(
                    onPickNews: { t in
                        pick(t.title, "Recent news to discuss (facts from coverage): \(t.blurb)",
                             true, t.facts ?? [])
                    },
                    onPickExam: { t, exam in pick(t.title, t.callBlurb(exam: exam), false, []) },
                    onPickTopic: { t in pick(t.title, t.blurb, false, []) },
                    onPickScenario: { s in pick(s.displayTitle, s.promptBlurb, false, []) },
                    onAllScenarios: {},
                    onBuildScenario: {},
                    showingSettings: $showingSettings,
                    showsScenarios: false)
                    .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BarCloseButton { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Talk settings")
                }
            }
        }
    }

    private func pick(_ title: String, _ blurb: String, _ isNews: Bool, _ facts: [String]) {
        onPick(title, blurb, isNews, facts)
        dismiss()
    }
}
