import SwiftUI

/// "What is this page for?" — one sheet per tab, raised the FIRST time the
/// learner opens that tab and never again (2026-10-03). Four tabs, four short
/// introductions, one layout: the tab's name as an eyebrow, one line saying
/// what the page does, three rows of what you'll find on it, one button.
///
/// The copy is a TOUR, not a manual — three rows, one line each. Anything
/// longer belongs on the page itself, which is right underneath.
enum PageIntro {
    enum Page: String, Identifiable, CaseIterable {
        case talk, watch, review, progress
        var id: String { rawValue }
    }

    struct Row: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { symbol + title }
    }

    struct Content {
        let symbol: String
        let eyebrow: String
        let title: String
        let rows: [Row]
    }

    /// Built at render time so every string resolves in the app language.
    static func content(for page: Page) -> Content {
        switch page {
        case .talk:
            return Content(
                symbol: "waveform",
                eyebrow: explain("Talk"),
                title: explain("Call your fluent self"),
                rows: [
                    Row(symbol: "phone.fill",
                        title: explain("Tap the circle to start the call"),
                        detail: explain("Your own voice answers, speaking fluently.")),
                    Row(symbol: "text.bubble.fill",
                        title: explain("See a more natural way to say it"),
                        detail: explain("Every turn shows how a native speaker would say what you just said.")),
                    Row(symbol: "newspaper.fill",
                        title: explain("Something to talk about"),
                        detail: explain("Start from a situation or today's news, or just chat.")),
                ])
        case .watch:
            return Content(
                symbol: "play.circle.fill",
                eyebrow: explain("Watch"),
                title: explain("Rehearse it before it happens"),
                rows: [
                    Row(symbol: "person.2.fill",
                        title: explain("Pick who you're meeting"),
                        detail: explain("A friend, a coworker, even someone famous.")),
                    Row(symbol: "square.and.pencil",
                        title: explain("Describe the situation"),
                        detail: explain("A job interview, a call to the landlord. Attach the posting or your CV.")),
                    Row(symbol: "play.rectangle.fill",
                        title: explain("Watch your fluent self handle it"),
                        detail: explain("Then save the lines you want to use.")),
                ])
        case .review:
            return Content(
                symbol: "book.fill",
                eyebrow: explain("Review"),
                title: explain("Everything you learned, in one place"),
                rows: [
                    Row(symbol: "rectangle.stack.fill",
                        title: explain("Today's cards"),
                        detail: explain("A few minutes a day on the words and sentences that are due.")),
                    Row(symbol: "books.vertical.fill",
                        title: explain("A book for every talk"),
                        detail: explain("Each talk and scene becomes a book of words, expressions and lines to shadow.")),
                    Row(symbol: "checkmark.seal.fill",
                        title: explain("Use it in a talk"),
                        detail: explain("A word you say in a real talk counts as learned.")),
                ])
        case .progress:
            return Content(
                symbol: "chart.bar.fill",
                eyebrow: explain("Progress"),
                title: explain("Your level, from how you really talk"),
                rows: [
                    Row(symbol: "chart.line.uptrend.xyaxis",
                        title: explain("Your CEFR level"),
                        detail: explain("Estimated from your talks, not from a test.")),
                    Row(symbol: "square.grid.2x2.fill",
                        title: explain("Skill by skill"),
                        detail: explain("Vocabulary, grammar and fluency, each with its next step.")),
                    Row(symbol: "calendar",
                        title: explain("Your days"),
                        detail: explain("Minutes talked, your streak and every day you practiced.")),
                ])
        }
    }
}

/// Which introductions this install has seen. Device-local on purpose: a
/// second device is a second first look.
enum PageIntroStore {
    private static func key(_ page: PageIntro.Page) -> String {
        "futurevoice.pageIntro.seen.\(page.rawValue)"
    }
    private static let preparedKey = "futurevoice.pageIntro.prepared"

    static func isDue(_ page: PageIntro.Page) -> Bool {
        prepareOnce()
        return !UserDefaults.standard.bool(forKey: key(page))
    }

    static func markSeen(_ page: PageIntro.Page) {
        UserDefaults.standard.set(true, forKey: key(page))
    }

    /// The introductions shipped after people already knew these pages. An
    /// install that has talked before has opened every tab it cares about,
    /// so it is marked as having seen them all, once, on its first check.
    private static func prepareOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: preparedKey) else { return }
        defaults.set(true, forKey: preparedKey)
        if !SessionStore.shared.loadAcrossLanguages().isEmpty {
            PageIntro.Page.allCases.forEach(markSeen)
        }
    }

    #if DEBUG
    static func resetAll() {
        PageIntro.Page.allCases.forEach {
            UserDefaults.standard.removeObject(forKey: key($0))
        }
    }
    #endif
}

struct PageIntroSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let page: PageIntro.Page
    @State private var revealed = false

    private var content: PageIntro.Content { PageIntro.content(for: page) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 36) {
                    header
                    rows
                }
                .padding(.horizontal, 32)
                .padding(.top, 56)
                .padding(.bottom, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button {
                dismiss()
            } label: {
                Text("Let's go")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: 520)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.easeOut(duration: 0.45).delay(0.1)) { revealed = true }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            hero
            VStack(spacing: 8) {
                // Text only: the hero above already wears the tab's glyph.
                Text(content.eyebrow)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(content.title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 8)
    }

    /// The Talk page's hero is the surface the learner taps to call — the
    /// same living mosaic, clipped to its circle. The other pages wear their
    /// tab glyph on a tinted tile.
    @ViewBuilder
    private var hero: some View {
        if page == .talk {
            Futureself(mode: .speaking, level: 0.35, virtualHeight: 64)
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 96, height: 96)
                .overlay {
                    Image(systemName: content.symbol)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                .accessibilityHidden(true)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(Array(content.rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: row.symbol)
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title)
                            .font(.headline)
                        Text(row.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 10)
                .animation(reduceMotion ? nil
                           : .easeOut(duration: 0.4).delay(0.2 + Double(index) * 0.08),
                           value: revealed)
            }
        }
    }
}
