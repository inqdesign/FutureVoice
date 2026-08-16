import SwiftUI

/// What a dictionary lookup shows while it's working, and when it couldn't.
///
/// A word or expression card's meaning is GENERATED on first ask (`WordLore`
/// falls through to an edge function), so it can fail like any network call —
/// and a failure used to be indistinguishable from "there's no entry": both
/// printed a bare "—" and left the learner with nothing to do but back out and
/// tap the word again. Failure is worth its own state precisely because it has
/// an action attached.
///
/// One view for every lookup surface (word card, expression card, study deck)
/// so the wording and the affordance can't drift apart.
struct LookupFailure: View {
    /// The deck's card is a saturated accent slab; the others sit on system
    /// backgrounds.
    var onCard: Bool = false
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(explain("Couldn't load this one."))
                .font(.subheadline)
                .foregroundStyle(onCard ? AnyShapeStyle(Color.white.opacity(0.72))
                                        : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(onCard ? .white : .accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The in-flight half, same wording everywhere.
struct LookupProgress: View {
    var onCard: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .tint(onCard ? .white : nil)
            Text("Looking it up…")
                .font(.subheadline)
                .foregroundStyle(onCard ? AnyShapeStyle(Color.white.opacity(0.72))
                                        : AnyShapeStyle(.secondary))
        }
    }
}
