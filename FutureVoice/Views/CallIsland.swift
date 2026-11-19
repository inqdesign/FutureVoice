import SwiftUI

/// The tutor inside a call (2026-11-11, founder: one call, its modes as
/// settings the tutor holds). Open when the call starts, it folds into a
/// pill in the bar's title slot once the learner speaks, and a tap on the
/// pill opens it again at any point of the call. It lies OVER the bar and
/// the transcript and never pushes them.
///
/// The three ways a call can run (2026-11-12, founder: Free talk · Tutor ·
/// Pronunciation). Coach mode is not one of them and is not on the island:
/// "Try saying" stays a Call settings switch.
enum CallGuidance: Hashable {
    case free, tutor, pronunciation

    var title: String {
        switch self {
        case .free: return explain("Free talk")
        case .tutor: return explain("Tutor")
        case .pronunciation: return explain("Pronunciation")
        }
    }
}

/// ONE view in both states (founder, same day: a pill in the bar and a card
/// under it read as two separate things). The first row is the pill; open,
/// the same shape grows around it and the rows fade in under it.
struct CallIsland: View {
    let title: String
    let level: CEFRLevel
    var minutesLeft: Int? = nil
    var callClock: TalkClock? = nil
    /// A pronunciation call uses half the talk time: "½" beside the clock.
    var halfRate = false
    /// nil hides the row: a scene or a person's call keeps the way it was
    /// launched.
    let guidance: Binding<CallGuidance>?
    /// What the row offers. Pronunciation is English only
    /// (`PronunciationCall.isOffered`), so the call passes two elsewhere.
    var guidanceChoices: [CallGuidance] = [.free, .tutor, .pronunciation]
    /// nil hides "Change": the topic of a scene or a person's call is theirs.
    let onChangeTopic: (() -> Void)?
    let onSettings: () -> Void
    @Binding var expanded: Bool

    @State private var faceSince = Date()
    @State private var showingLevel = false

    static let pillHeight: CGFloat = 34
    /// A spring with a little give: the glass stretches and settles, the way
    /// the system's own glass controls open (founder, 2026-11-11).
    static let motion = Animation.spring(response: 0.42, dampingFraction: 0.74)

    var body: some View {
        VStack(spacing: 0) {
            head
            if expanded {
                rows.transition(.opacity)
            }
        }
        .padding(.horizontal, expanded ? 16 : 0)
        .padding(.bottom, expanded ? 4 : 0)
        .frame(maxWidth: expanded ? 520 : 240)
        .fixedSize(horizontal: !expanded, vertical: true)
        .clipShape(shape)
        .modifier(IslandSurface(shape: shape, expanded: expanded))
        .padding(.horizontal, 16)
        .sheet(isPresented: $showingLevel) {
            LevelInfoSheet(level: level, surface: .talk)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: expanded ? 24 : Self.pillHeight / 2, style: .continuous)
    }

    /// The pill, and the open card's first row: the face, what the call is
    /// about and the call clock stay where they are in both states.
    private var head: some View {
        HStack(spacing: 6) {
            WeeklyTestCharacter(mood: .waiting, since: faceSince, tile: .clear)
                .scaleEffect(22 / WeeklyTestCharacter.size)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if let callClock {
                CallIslandClock(clock: callClock)
            }
            if halfRate {
                Text(verbatim: "½")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
                    .accessibilityLabel(Text(explain("Uses half the talk time")))
            }
            if let minutesLeft {
                Text("\(minutesLeft) min")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(minutesLeft <= 3 ? AnyShapeStyle(.orange)
                                                      : AnyShapeStyle(.secondary))
            }
        }
        // The same paddings and height in both states, centred: the title
        // and the clock don't move when the shape opens around them.
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: Self.pillHeight)
        .frame(maxWidth: expanded ? .infinity : nil)
        .overlay(alignment: .trailing) {
            if expanded {
                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Self.motion) { expanded.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(explain("Call settings")))
    }

    private var rows: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Topic")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if let onChangeTopic {
                    Button("Change") {
                        fold()
                        onChangeTopic()
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
            .padding(.vertical, 10)

            if let guidance {
                Divider()
                Picker("", selection: guidance) {
                    ForEach(guidanceChoices, id: \.self) { g in
                        Text(g.title).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.vertical, 10)
            }

            Divider()
            row(explain("Level"), value: level.rawValue.uppercased()) { showingLevel = true }
            Divider()
            row(explain("Call settings"), value: nil) {
                fold()
                onSettings()
            }
        }
    }

    private func row(_ label: String, value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                Spacer()
                if let value {
                    Text(value).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
    }

    private func fold() {
        withAnimation(Self.motion) { expanded = false }
    }
}

/// Observes the clock on its own, so the once-a-second tick redraws the
/// digits and not the call screen that owns the meter.
private struct CallIslandClock: View {
    @ObservedObject var clock: TalkClock

    var body: some View {
        Text(LevelHeaderTitle.mmss(TimeInterval(clock.seconds)))
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

/// Liquid Glass on iOS 26, where the system bends and settles the surface as
/// the shape changes; before it, white on the light page (the grey tile was
/// nearly the page's own colour) and the raised grey in the dark.
private struct IslandSurface: ViewModifier {
    let shape: RoundedRectangle
    let expanded: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(Color(UIColor { $0.userInterfaceStyle == .dark ? .secondarySystemBackground : .white }),
                            in: shape)
                .overlay(shape.strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(expanded ? 0.16 : 0.06), radius: expanded ? 18 : 6, y: expanded ? 8 : 2)
        }
    }
}
