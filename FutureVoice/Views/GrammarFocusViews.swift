import SwiftUI

/// The call's grammar focus, pinned above the transcript beside the studying
/// chips (coach mode, `GrammarFocus`).
///
/// One line of what, one line of how: the name the learner thinks in
/// ("과거 시제") and their own slip beside its fix, so the rule never stands
/// without the example (a rule name alone is what the old coach avoided).
/// Once the slip comes back, the trailing counter says so — orange, not red:
/// it is a reminder, not a failure. Tapping opens `GrammarFocusSheet`.
struct GrammarFocusStrip: View {
    let label: String
    let mistake: String
    let correction: String
    let repeats: Int
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.accentColor.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("This call's focus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    GrammarFocusPair(mistake: mistake, correction: correction)
                        .font(.caption)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if repeats > 0 {
                    Label("\(repeats)", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .accessibilityLabel(explain("Came back \(repeats) times"))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: repeats)
        .accessibilityElement(children: .combine)
    }
}

/// The learner's slip and its fix on one line: what they say, struck
/// through and quiet; what to say, plain. Target-language material.
///
/// Only the part that CHANGED, with one word of context either side
/// (`compact`): the stored pair is a whole sentence, and truncating two
/// sentences to one line kept their ends and cut out the one word that
/// differs ("Yesterda…the office → Yesterda…the office").
struct GrammarFocusPair: View {
    let mistake: String
    let correction: String

    var body: some View {
        let (was, now) = Self.compact(mistake, correction)
        HStack(spacing: 5) {
            Text(was)
                .strikethrough(true, color: .secondary)
                .foregroundStyle(.secondary)
                .truncationMode(.middle)
            Image(systemName: "arrow.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(now)
                .foregroundStyle(.primary)
                .truncationMode(.middle)
        }
    }

    /// Strip what the two share at the start and the end, keeping `context`
    /// units of it on each side. Words for a spaced language; characters for
    /// one without spaces (a Japanese or Chinese sentence is one "word").
    static func compact(_ a: String, _ b: String, context: Int? = nil) -> (String, String) {
        let spaced = a.contains(" ") || b.contains(" ")
        let x = spaced ? a.split(separator: " ").map(String.init) : a.map(String.init)
        let y = spaced ? b.split(separator: " ").map(String.init) : b.map(String.init)
        let keep = context ?? (spaced ? 1 : 2)
        let norm = { (s: String) in s.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        var head = 0
        while head < min(x.count, y.count), norm(x[head]) == norm(y[head]) { head += 1 }
        var tail = 0
        while tail < min(x.count, y.count) - head,
              norm(x[x.count - 1 - tail]) == norm(y[y.count - 1 - tail]) { tail += 1 }
        guard head + tail > 0, head < max(x.count, y.count) else { return (a, b) }
        let from = max(0, head - keep)
        let cut = max(0, tail - keep)
        let join = { (t: [String]) in t.joined(separator: spaced ? " " : "") }
        let xs = join(Array(x[from ..< max(from, x.count - cut)]))
        let ys = join(Array(y[from ..< max(from, y.count - cut)]))
        let lead = from > 0 ? "…" : ""
        let trail = cut > 0 ? "…" : ""
        return (lead + xs + trail, lead + ys + trail)
    }
}

/// What the focus strip opens: the point, when it applies, the learner's
/// own example, and what the call will do about it. The call is still
/// running underneath, so it stays one screen and a medium detent.
struct GrammarFocusSheet: View {
    let label: String
    let tip: String
    let mistake: String
    let correction: String
    let repeats: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(label)
                            .font(.title3.weight(.semibold))
                        if !tip.isEmpty {
                            Text(tip)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    LabeledContent {
                        Text(mistake).strikethrough(true, color: .secondary)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("You said")
                    }
                    LabeledContent {
                        Text(correction).fontWeight(.semibold)
                    } label: {
                        Text("Say")
                    }
                } footer: {
                    Text(explain("Your future self may ask something that needs this. Just answer the way you normally would."))
                }
                if repeats > 0 {
                    Section {
                        Label {
                            Text(explain("Came back \(repeats) times in this call"))
                        } icon: {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle(explain("This call's focus"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(explain("Done")) { dismiss() }
                }
            }
        }
        .fittingDetents([.medium, .large])
    }
}

/// On a correction card whose slip is the focus coming back. Sits above the
/// rewrite so the learner reads WHY this card matters before the card.
struct GrammarFocusRepeatBadge: View {
    let label: String

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text("Again")
                Text("·").foregroundStyle(.tertiary)
                Text(label)
            }
        } icon: {
            Image(systemName: "arrow.counterclockwise")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.orange)
    }
}

/// The book page's line for a talk that had a focus: what it was and how
/// the call went on it. Counted in code; the wording never scolds.
struct GrammarFocusResultRow: View {
    let record: GrammarFocusRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.repeats == 0 ? "checkmark.seal.fill" : "scope")
                .font(.title3)
                .foregroundStyle(record.repeats == 0 ? Color.green : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.label)
                    .font(.subheadline.weight(.semibold))
                GrammarFocusPair(mistake: record.mistake, correction: record.correction)
                    .font(.caption)
                    .lineLimit(2)
                Text(record.repeats == 0
                     ? explain("It didn't come back this call")
                     : explain("Came back \(record.repeats) times — it stays your focus"))
                    .font(.caption)
                    .foregroundStyle(record.repeats == 0 ? Color.green : Color.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
