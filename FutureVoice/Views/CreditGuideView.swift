import SwiftUI

/// "What uses talk time?" — the transparency page. The rules here MUST stay
/// in sync with the server (talk-tick + elevenlabs-tts routing): a mismatch
/// between what we show and what we meter is a trust-breaker.
///
/// The model in one line: the meter runs only while you're talking (the
/// in-call clock) or watching a scene play in your voice. Everything else —
/// review, browsing, tapping around — is free.
struct CreditGuideView: View {
    var body: some View {
        List {
            Section {
                costRow(icon: "phone.fill",
                        title: "Talking", cost: "clock time",
                        detail: "The call clock is the meter — a 10-minute call uses 10 minutes. Thinking pauses cost the same as talking, just like a phone call.")
                costRow(icon: "play.circle.fill",
                        title: "Watching a scene", cost: "~1 min",
                        detail: "A scene costs its playback length in your voice — about a minute. Re-watching a saved scene generates a fresh take.")
                costRow(icon: "person.wave.2.fill",
                        title: "Re-cloning your voice", cost: "~1 min",
                        detail: "Setup is free, including re-records in the first day. Later re-records cost a little.")
            } header: {
                Text("Uses talk time")
            } footer: {
                Text(explain("Only new audio in your voice uses your minutes. The meter never runs outside a call or a scene."))
            }

            Section {
                freeRow(icon: "rectangle.stack.fill", title: "All reviewing",
                        detail: "Drills, shadowing (including coach feedback), word and expression playback — every review surface is free.")
                freeRow(icon: "repeat", title: "Replays",
                        detail: "Anything already synthesized is cached — loop it, slow it down, replay whole talks.")
                freeRow(icon: "wand.and.stars", title: "Summaries & reports",
                        detail: "Session scorecards, weekly reports, and the daily call are on the house.")
                freeRow(icon: "square.grid.2x2", title: "Exploring",
                        detail: "Building situations, browsing topics, translations, dictionaries — tap freely, nothing here is metered.")
                freeRow(icon: "text.book.closed.fill", title: "Vocabulary & progress",
                        detail: "The word cloud, CEFR estimate, and stats never cost anything.")
            } header: {
                Text("Always free")
            } footer: {
                Text(explain("In short: minutes buy speaking time with your fluent self. Practicing with what already exists is always free."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("What uses talk time?")
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
