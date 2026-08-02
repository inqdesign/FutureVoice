import SwiftUI

/// Who is speaking a dialogue line. Top-level (not nested in `DialogueLine`)
/// so callers can read `alignment` without spelling out generic parameters.
enum DialogueSpeaker {
    /// The learner. Trailing side, accent fill.
    case user
    /// The fluent self, or a Watch counterpart. Leading side, neutral fill.
    case other

    var isUser: Bool { self == .user }

    /// Which side this speaker's content sits on. Exposed so a surface's own
    /// accessory stack (Meaning / Shadow / suggestion chips) lines up with the
    /// bubble instead of re-deriving the rule.
    var alignment: HorizontalAlignment { isUser ? .trailing : .leading }
}

/// The ONE dialogue-line surface, shared by every conversation view — Watch's
/// scripted dialogue, the live call transcript, and past-conversation detail.
///
/// Speaker separation (the name label, which side the line sits on, the bubble
/// fill, the playback ring) is defined HERE and nowhere else, so restyling the
/// conversation UI later is a single-file change. Callers supply only their own
/// line content (plain text, attributed text with tappable words, …) and their
/// per-surface accessories — never the chrome.
struct DialogueLine<Content: View, Accessory: View>: View {

    /// Text size. The call screen is read at arm's length mid-conversation;
    /// the archives are dense, scrollable lists.
    enum Scale {
        case call, standard
        var font: Font { self == .call ? .title3 : .body }
    }

    let speaker: DialogueSpeaker
    /// "You", "Future self", or a counterpart's name.
    let name: String
    var scale: Scale = .standard
    /// Playback cursor (Watch) — an accent ring on the line being spoken.
    var isCurrent: Bool = false
    @ViewBuilder var content: () -> Content
    @ViewBuilder var accessory: () -> Accessory

    @AppStorage("futureselfTheme") private var storedTheme = FutureselfTheme.blue.rawValue

    /// Mono is the one palette whose accent is INK rather than a hue, so the
    /// usual 18%-accent wash landed as a barely-there gray: the learner's own
    /// lines stopped being tellable from the fluent self's, which is the only
    /// job this fill has. In mono the user bubble goes solid instead — the
    /// label colour as fill, the background colour as text. Same monochrome
    /// pairing Practice's selected chip uses, and it inverts correctly in dark
    /// mode (white bubble, dark text) rather than sinking into the background.
    private var isMonoUser: Bool {
        speaker.isUser && FutureselfTheme(rawValue: storedTheme) == .mono
    }

    private var bubbleFill: Color {
        if isMonoUser { return Color(.label) }
        return speaker.isUser ? Color.accentColor.opacity(0.18)
                              : Color(.secondarySystemBackground)
    }

    /// Only forced on the solid mono bubble; elsewhere the default cascade
    /// (and any colour a caller set on its own content) stands.
    private var bubbleForeground: Color {
        isMonoUser ? Color(.systemBackground) : Color.primary
    }

    /// The playback ring is accent-coloured — invisible against a solid ink
    /// bubble, so mono draws it in the bubble's own text colour instead.
    private var ringColor: Color {
        isMonoUser ? Color(.systemBackground) : Color.accentColor
    }

    init(speaker: DialogueSpeaker,
         name: String,
         scale: Scale = .standard,
         isCurrent: Bool = false,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.speaker = speaker
        self.name = name
        self.scale = scale
        self.isCurrent = isCurrent
        self.content = content
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 0) {
            // The opposite-side gutter is what actually separates the two
            // speakers' columns — without it both sides span full width and
            // the fills alone read as stripes, not as a back-and-forth.
            if speaker.isUser { Spacer(minLength: 40) }

            VStack(alignment: speaker.alignment, spacing: 4) {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                content()
                    .font(scale.font)
                    .foregroundStyle(bubbleForeground)
                    // Long lines stay left-ragged even in a trailing bubble —
                    // centre/right-ragged body text is hard to read.
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(bubbleFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isCurrent ? ringColor : .clear, lineWidth: 2)
                    )

                accessory()
            }

            if !speaker.isUser { Spacer(minLength: 40) }
        }
    }
}

extension DialogueLine where Accessory == EmptyView {
    init(speaker: DialogueSpeaker,
         name: String,
         scale: Scale = .standard,
         isCurrent: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(speaker: speaker, name: name, scale: scale, isCurrent: isCurrent,
                  content: content, accessory: { EmptyView() })
    }
}
