import SwiftUI

/// The top of the Challenges tab, on the page's own ground (no card,
/// founder 2026-11-10): who leads right now, second · first · third, and
/// under it how this learner is doing. A tap on the leaders opens Ranking.
struct SpeechChallengeHero: View {
    /// The overall board's top rows and the learner's own row; nil or short
    /// before anyone is on it.
    let overall: [SpeechChallenges.BoardRow]?
    let tried: Int
    let total: Int
    let takesThisWeek: Int
    var headline: LocalizedStringKey = "Leading now"
    var openRanking: () -> Void

    private var top: [SpeechChallenges.BoardRow] { Array((overall ?? []).prefix(3)) }
    private var me: SpeechChallenges.BoardRow? { overall?.first { $0.is_me } }

    var body: some View {
        VStack(spacing: 22) {
            if !top.isEmpty {
                Button(action: openRanking) {
                    VStack(spacing: 14) {
                        HStack(spacing: 4) {
                            Text(headline)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach([1, 0, 2], id: \.self) { index in
                                if index < top.count {
                                    place(top[index])
                                } else {
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 0) {
                stat(value: me.map { "#\($0.rank)" } ?? "–", label: "My rank")
                divider
                stat(value: "\(tried)/\(total)", label: "Challenges tried")
                divider
                stat(value: "\(takesThisWeek)", label: "Takes this week")
            }
        }
        .padding(.top, 4)
    }

    private var divider: some View {
        Rectangle().fill(Color(.separator)).frame(width: 1, height: 30)
    }

    private func stat(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Text(verbatim: value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func place(_ row: SpeechChallenges.BoardRow) -> some View {
        let first = row.rank == 1
        return VStack(spacing: 6) {
            SpeechChallengeFace(face: row.face, size: first ? 84 : 64)
                .overlay(alignment: .topTrailing) {
                    Text(verbatim: "#\(row.rank)")
                        .font(.caption.weight(.heavy).monospacedDigit())
                        .foregroundStyle(row.rank == 1 ? Color.black : Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SpeechOverallBanner.medal(row.rank), in: Capsule())
                        .overlay(Capsule().stroke(Color(.systemGroupedBackground), lineWidth: 2))
                        .offset(x: 6, y: -4)
                }
            Text(row.display_name)
                .font(first ? .headline : .subheadline.weight(.semibold))
                .foregroundStyle(row.is_me ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .lineLimit(1)
            Text(verbatim: "\(row.score)")
                .font((first ? Font.title3 : .body).monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// What the Challenges tab's list is narrowed to.
enum SpeechChallengeFilter: String, CaseIterable, Identifiable {
    case all, popular, notTried, tried
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .all: return "All"
        case .popular: return "Popular"
        case .notTried: return "Not tried"
        case .tried: return "Tried"
        }
    }
}

/// The chips over the list, Progress's monochrome pills.
struct SpeechChallengeFilterBar: View {
    @Binding var selected: SpeechChallengeFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SpeechChallengeFilter.allCases) { filter in
                    chip(filter)
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
    }

    private func chip(_ filter: SpeechChallengeFilter) -> some View {
        let on = selected == filter
        let fill: Color = on ? Color(.label) : Color(.secondarySystemGroupedBackground)
        let ink: Color = on ? Color(.systemBackground) : Color.primary
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { selected = filter }
        } label: {
            Text(filter.label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(fill))
                .foregroundStyle(ink)
        }
        .buttonStyle(.plain)
    }
}
