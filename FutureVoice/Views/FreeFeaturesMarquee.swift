import SwiftUI

/// Everything a plan does NOT meter, rolling past under the paywall's
/// subtitle (2026-11-03, founder: "show how much is free" — a sentence
/// listing five things read as a footnote; a row of chips that keeps
/// coming reads as plenty). Each chip is an icon and the feature's own
/// name, the one its tab or chapter uses, so nothing here is a new word.
///
/// Only what is unlimited on EVERY plan belongs in the list. A scene and a
/// speech voiceover are paid out of the talk minutes and are left out on
/// purpose; their price is said on their own buttons (`SceneCostNote`,
/// `ScriptVoiceover.priceLine`).
struct FreeFeaturesMarquee: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Item: Identifiable {
        let id: String
        let symbol: String
        let label: LocalizedStringKey
    }

    static let items: [Item] = [
        .init(id: "book", symbol: "book.closed", label: "Review book"),
        .init(id: "words", symbol: "textformat.abc", label: "Words"),
        .init(id: "expressions", symbol: "quote.bubble", label: "Expressions"),
        .init(id: "sentences", symbol: "rectangle.on.rectangle", label: "Sentences"),
        .init(id: "shadowing", symbol: "waveform", label: "Shadowing"),
        .init(id: "sayagain", symbol: "arrow.counterclockwise", label: "Say it again"),
        .init(id: "replay", symbol: "play.circle", label: "Replay"),
        .init(id: "drills", symbol: "rectangle.stack", label: "Drills"),
        .init(id: "test", symbol: "checklist", label: "Weekly test"),
        .init(id: "week", symbol: "chart.bar.doc.horizontal", label: "Your week"),
        .init(id: "pronunciation", symbol: "mouth", label: "Pronunciation"),
        .init(id: "listening", symbol: "headphones", label: "Listening"),
    ]

    /// `-nomarquee 1` in a DEBUG run draws the still layout, to tell the
    /// animation apart from everything else on the page.
    private static var stillForDebug: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "nomarquee")
        #else
        return false
        #endif
    }

    /// Points per second. Slow enough to read a chip as it passes.
    private static let speed: CGFloat = 28

    @State private var stripWidth: CGFloat = 0
    @State private var stripHeight: CGFloat = 30
    @State private var startedAt = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Unlimited on every plan", systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if reduceMotion || Self.stillForDebug {
                // Still: every chip, wrapped, nothing to chase.
                FlowChips(items: Self.items)
            } else {
                // The strip is an OVERLAY on a clear band, so its own width
                // (two copies of twelve chips) never reaches the page's
                // layout — as a sibling it widened the whole paywall.
                Color.clear
                    .frame(height: stripHeight)
                    .overlay(alignment: .leading) {
                        TimelineView(.animation) { context in
                            let elapsed = context.date.timeIntervalSince(startedAt)
                            let shift = stripWidth > 0
                                ? CGFloat(elapsed).truncatingRemainder(dividingBy: stripWidth / Self.speed) * Self.speed
                                : 0
                            HStack(spacing: 8) {
                                strip
                                    .onGeometryChange(for: CGSize.self) { $0.size } action: {
                                        stripWidth = $0.width + 8
                                        stripHeight = $0.height
                                    }
                                strip
                            }
                            .fixedSize()
                            .offset(x: -shift)
                        }
                    }
                    .clipped()
                .mask(
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .black, location: 0.05),
                                           .init(color: .black, location: 0.95),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear { startedAt = Date() }
    }

    private var strip: some View {
        HStack(spacing: 8) {
            ForEach(Self.items) { chip($0) }
        }
    }

    private func chip(_ item: Item) -> some View {
        Label(item.label, systemImage: item.symbol)
            .font(.footnote.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemFill), in: Capsule())
    }

    /// The chips in rows, for Reduce Motion.
    private struct FlowChips: View {
        let items: [Item]
        var body: some View {
            // Three rows is enough for twelve chips at any width; a Grid
            // keeps it simple and never scrolls.
            let rows = stride(from: 0, to: items.count, by: 4).map { Array(items[$0..<min($0 + 4, items.count)]) }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 8) {
                        ForEach(rows[r]) { item in
                            Label(item.label, systemImage: item.symbol)
                                .font(.footnote.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemFill), in: Capsule())
                        }
                    }
                }
            }
        }
    }
}
