import SwiftUI

/// "What uses credits?" — the transparency page. Costs here MUST stay in
/// sync with supabase/functions/_shared/credits.ts (priceFor): a mismatch
/// between what we show and what we charge is a trust-breaker.
struct CreditGuideView: View {
    var body: some View {
        List {
            Section {
                costRow(icon: "bubble.left.and.bubble.right.fill",
                        title: "Conversation turn", cost: "~3",
                        detail: "Your future voice's reply (voice + AI). A 10-minute talk is roughly 45 credits.")
                costRow(icon: "play.circle.fill",
                        title: "Watch dialogue", cost: "~10",
                        detail: "Generating one full scenario dialogue in your voice.")
                costRow(icon: "waveform.badge.mic",
                        title: "New shadow line", cost: "1",
                        detail: "Only for lines never spoken before. Lines from your conversations align on-device for free.")
                costRow(icon: "doc.text.fill",
                        title: "Session summary", cost: "2",
                        detail: "The scorecard and drill cards after each talk.")
                costRow(icon: "chart.line.uptrend.xyaxis",
                        title: "Weekly report", cost: "5",
                        detail: "When enough speaking time has accumulated.")
                costRow(icon: "person.wave.2.fill",
                        title: "Voice clone", cost: "5",
                        detail: "One-time, at setup. Re-recording costs the same.")
            } header: {
                Text("Uses credits")
            } footer: {
                Text(explain("1 credit ≈ 100 characters spoken in your voice."))
            }

            Section {
                freeRow(icon: "repeat", title: "Replaying shadow lines",
                        detail: "Audio is cached — loop and slow down as much as you want.")
                freeRow(icon: "rectangle.stack.fill", title: "Review drills",
                        detail: "Spaced repetition and speak-aloud grading run on your device.")
                freeRow(icon: "play.rectangle.on.rectangle", title: "Re-listening Watch dialogues",
                        detail: "Generated once, then cached.")
                freeRow(icon: "text.book.closed.fill", title: "Vocabulary & progress",
                        detail: "The word cloud, CEFR estimate, and stats never cost anything.")
                freeRow(icon: "bookmark.fill", title: "Saved lines",
                        detail: "Saving and browsing your archive is free.")
            } header: {
                Text("Always free")
            } footer: {
                Text(explain("In short: creating new audio in your voice costs credits. Practicing with what already exists doesn't."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("What uses credits?")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func costRow(icon: String, title: String, cost: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text(cost)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 2)
    }

    private func freeRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Free")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        }
        .padding(.vertical, 2)
    }
}
