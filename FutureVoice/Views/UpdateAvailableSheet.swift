import SwiftUI

/// A newer build is out. Two temperaments in one sheet, because the two cases
/// are not the same request:
///
///   * OPTIONAL — a notice. It can be closed, and it is shown once per build
///     (`AppUpdateService.markSeen`). Nagging is how a notice stops being read.
///   * REQUIRED — the server has moved somewhere this build misreports it, so
///     there is no dismiss and no swipe. That is not a growth device; it is
///     reserved for the case that actually happened here, when the billing
///     model changed under builds already on phones and an old client kept
///     describing allowances that no longer existed.
///
/// The notes come from the release notes shipped to the App Store, so they are
/// a paragraph plus a bullet list — not a sentence. They used to be rendered as
/// one centre-aligned block inside a fixed detent, which ran off the top AND
/// the bottom of the sheet on the very first release that had real notes. The
/// body now SCROLLS under a compact header with the buttons pinned below, and
/// the bullets are parsed out (`ReleaseNotes`) so what's new reads as a list of
/// things rather than a wall of prose.
struct UpdateAvailableSheet: View {
    let update: AppUpdateService.AppUpdate
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var detent: PresentationDetent = .medium

    private var notes: ReleaseNotes { ReleaseNotes(update.notes) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 22) {
                        if let lead = notes.lead {
                            Text(lead)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ForEach(Array(notes.sections.enumerated()), id: \.offset) { _, section in
                            sectionView(section)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 12)
            // A required update carries no notes, so its content is the header
            // alone — top-aligned it leaves a hole above the button. Only ever
            // applied to content that is demonstrably shorter than the sheet;
            // pinning a tall stack to the container height would clip it
            // instead of letting it scroll.
            .centeredWhenShort(notes.isEmpty)
        }
        // Pinned, so the one thing the sheet asks for can never be scrolled
        // off — however long the notes are.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                // Names the store the tap will actually open. A TestFlight
                // install sent to the App Store reads as a broken link, not
                // as an update.
                Button {
                    openURL(AppUpdateService.updateURL)
                } label: {
                    Group {
                        if AppUpdateService.isTestFlight {
                            Text("Open TestFlight")
                        } else {
                            Text("Open the App Store")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // A required update has no way past. Everything else does.
                if !update.required {
                    Button("Later") {
                        onDismiss()
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
            // NO background of its own. A sheet's ground is a material, so
            // anything opaque here — a bar, systemBackground — draws a band
            // the eye reads as a second surface pasted under the notes. The
            // button keeps the sheet's own glass, exactly as a toolbar does.
        }
        // A one-line note fits the half sheet; a real release note is a
        // paragraph plus five bullets, and opening THAT at medium puts the
        // list — the part that answers "what changed?" — below the fold.
        .presentationDetents([.medium, .large], selection: $detent)
        .onAppear { detent = notes.sections.isEmpty ? .medium : .large }
        // Both are set from the same flag so a required sheet can't be escaped
        // by dragging it away — the one gap an `if` around the button leaves.
        .interactiveDismissDisabled(update.required)
        .presentationDragIndicator(update.required ? .hidden : .visible)
    }

    /// One kind of change under its own heading — what's new, what was fixed,
    /// what got faster — so a learner can read the part they care about
    /// without sorting a single list in their head. The heading is the APP's
    /// word for the kind, not the file's, so every release reads the same.
    private func sectionView(_ section: ReleaseNotes.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let kind = section.kind {
                Label {
                    Text(kind.title)
                } icon: {
                    Image(systemName: kind.symbol)
                        .foregroundStyle(.tint)
                }
                .font(.subheadline.weight(.semibold))
            } else {
                Text("What's new")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            ForEach(Array(section.items.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.secondary)
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: update.required ? "exclamationmark.arrow.circlepath" : "arrow.down.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(update.required ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))

            Text(update.required ? "Update to keep going" : "There's a new version")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(buildLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    /// Always names the build being offered. "A new version is available" with
    /// no number can't be checked against what the App Store then shows.
    private var buildLine: String {
        let current = "\(AppUpdateService.currentVersion) (\(AppUpdateService.currentBuild))"
        guard let latest = update.latestVersion else {
            return explain("Build \(AppUpdateService.currentBuild) → \(update.latestBuild)")
        }
        // Numbers and an arrow: nothing here to translate.
        return "\(current) → \(latest) (\(update.latestBuild))"
    }
}

/// Release notes as written for the App Store: an optional paragraph, then
/// SECTIONS — a heading line ("New" / "Fixed" / "Improved", in either
/// language) over a dash list. The store file has always been written this
/// way; the sheet used to flatten it into one "What's new" list because the
/// server copy had its headings stripped for older builds' parser (see
/// `beta.sh sheet_notes`). The headed copy now rides in its own columns
/// (`notes_sections_*`), and flat notes — one list, no headings — still parse
/// as a single section without a title.
struct ReleaseNotes {
    enum Kind: CaseIterable {
        case new, fixed, improved

        var title: LocalizedStringKey {
            switch self {
            case .new: "New features"
            case .fixed: "Bug fixes"
            case .improved: "Improvements"
            }
        }

        var symbol: String {
            switch self {
            case .new: "sparkles"
            case .fixed: "ladybug"
            case .improved: "gauge.with.dots.needle.67percent"
            }
        }

        /// A heading line, read by its words. Fixed is tried first so
        /// "Bug fixes and improvements" files its list as fixes.
        init?(heading: String) {
            let h = heading.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " :：·"))
            guard h.count <= 30 else { return nil }
            func has(_ words: [String]) -> Bool { words.contains { h.contains($0) } }
            if has(["고친", "버그", "수정", "fix", "bug"]) { self = .fixed }
            else if has(["개선", "성능", "향상", "다듬", "improv", "faster", "performance"]) { self = .improved }
            else if has(["새 기능", "새로운", "new"]) { self = .new }
            else { return nil }
        }
    }

    struct Section {
        /// nil = a list with no heading (flat notes).
        let kind: Kind?
        var items: [String]
    }

    let lead: String?
    let sections: [Section]

    var isEmpty: Bool { lead == nil && sections.isEmpty }

    init(_ raw: String?) {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lead = nil
            sections = []
            return
        }

        var leadLines: [String] = []
        var parts: [Section] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                // A blank line inside the lead is a paragraph break; keep it,
                // but never let it open the block with one.
                if !leadLines.isEmpty, parts.isEmpty { leadLines.append("") }
                continue
            }
            if let marker = ["- ", "• ", "· ", "* "].first(where: { trimmed.hasPrefix($0) }) {
                let item = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                if parts.isEmpty { parts.append(Section(kind: nil, items: [])) }
                parts[parts.count - 1].items.append(item)
            } else if let kind = Kind(heading: trimmed) {
                parts.append(Section(kind: kind, items: []))
            } else if let last = parts.indices.last, !parts[last].items.isEmpty {
                // Prose after a list is a wrapped bullet, not a new section.
                parts[last].items[parts[last].items.count - 1] += " " + trimmed
            } else {
                leadLines.append(trimmed)
            }
        }

        // Two headings of the same kind (a file edited twice) read as one.
        var merged: [Section] = []
        for part in parts where !part.items.isEmpty {
            if let i = merged.firstIndex(where: { $0.kind == part.kind }) {
                merged[i].items += part.items
            } else {
                merged.append(part)
            }
        }

        let joined = leadLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        lead = joined.isEmpty ? nil : joined
        sections = merged
    }
}

#Preview("Optional") {
    Text("host").sheet(isPresented: .constant(true)) {
        UpdateAvailableSheet(update: .init(latestBuild: 26, latestVersion: "1.0",
                                           notes: """
                                           새 기능
                                           • 스피치 원고에서 공부하기를 켜면 문법과 표현을 짚어 줘요.
                                           • 원고를 내 목소리로 읽은 오디오를 만들어 들어볼 수 있어요.

                                           고친 점
                                           • 시트를 닫았다 열어도 쓰던 글이 남아요.

                                           성능 향상
                                           • 앱을 처음 열 때 Talk 화면이 더 부드럽게 떠요.
                                           """,
                                           required: false), onDismiss: {})
    }
}

#Preview("Required") {
    Text("host").sheet(isPresented: .constant(true)) {
        UpdateAvailableSheet(update: .init(latestBuild: 15, latestVersion: "1.0.1",
                                           notes: nil, required: true), onDismiss: {})
    }
}

private extension View {
    @ViewBuilder
    func centeredWhenShort(_ active: Bool) -> some View {
        if active {
            containerRelativeFrame(.vertical, alignment: .center)
        } else {
            self
        }
    }
}
