import SwiftUI

/// A Japanese line with its readings drawn small above the kanji
/// (`Furigana`). SwiftUI's `Text` has no ruby, so the line is laid out as
/// units — one per kanji run with its reading, one per other character —
/// that wrap like Japanese does, anywhere, with closing punctuation held on
/// the unit before it so 。 never starts a line.
///
/// Falls back to `fallback` (the surface's own plain rendering) whenever the
/// setting is off, the target isn't Japanese or the line has no kanji, so
/// every other language and every kana-only line draw exactly as before.
struct FuriganaText<Fallback: View>: View {
    let text: AttributedString
    var rubyFont: Font = .caption2
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder var fallback: () -> Fallback

    @AppStorage(Furigana.key) private var enabled = true

    init(_ text: AttributedString, rubyFont: Font = .caption2,
         alignment: HorizontalAlignment = .leading,
         @ViewBuilder fallback: @escaping () -> Fallback) {
        self.text = text
        self.rubyFont = rubyFont
        self.alignment = alignment
        self.fallback = fallback
    }

    init(_ text: String, rubyFont: Font = .caption2,
         alignment: HorizontalAlignment = .leading,
         @ViewBuilder fallback: @escaping () -> Fallback) {
        self.init(AttributedString(text), rubyFont: rubyFont, alignment: alignment, fallback: fallback)
    }

    var body: some View {
        let plain = String(text.characters)
        if enabled, LanguageScope.active == "ja", Furigana.hasRuby(plain) {
            RubyFlow(alignment: alignment) {
                ForEach(Array(units(plain).enumerated()), id: \.offset) { _, unit in
                    RubyUnit(reading: unit.reading, rubyFont: rubyFont) {
                        Text(slice(unit.range))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(plain)
        } else {
            fallback()
        }
    }

    private struct Unit {
        let range: Range<Int>
        let reading: String?
    }

    /// Where the line may break: around every ruby run and between every
    /// other character, except inside a run of Latin letters or digits, and
    /// never before closing punctuation or after an opening bracket.
    private func units(_ plain: String) -> [Unit] {
        let chars = Array(plain)
        var out: [Unit] = []
        var openPending: Int? = nil
        func push(_ r: Range<Int>, _ reading: String?) {
            var range = r
            if let start = openPending { range = start..<r.upperBound; openPending = nil }
            out.append(Unit(range: range, reading: reading))
        }
        for run in Furigana.runs(in: plain) {
            if let reading = run.reading {
                push(run.range, reading)
                continue
            }
            var i = run.range.lowerBound
            while i < run.range.upperBound {
                let ch = chars[i]
                if Self.closing.contains(ch), let last = out.last, openPending == nil {
                    out[out.count - 1] = Unit(range: last.range.lowerBound..<(i + 1), reading: last.reading)
                    i += 1
                    continue
                }
                if Self.opening.contains(ch) {
                    if openPending == nil { openPending = i }
                    i += 1
                    continue
                }
                var j = i + 1
                if ch.isASCII && (ch.isLetter || ch.isNumber) {
                    while j < run.range.upperBound, chars[j].isASCII, chars[j].isLetter || chars[j].isNumber { j += 1 }
                }
                push(i..<j, nil)
                i = j
            }
        }
        if let start = openPending { out.append(Unit(range: start..<chars.count, reading: nil)) }
        return out
    }

    private static var closing: Set<Character> { ["、", "。", "，", "．", "！", "？", "!", "?", ",", ".", "」", "』", "）", ")", "ー", "っ", "ゃ", "ゅ", "ょ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ッ", "ャ", "ュ", "ョ", "…", "〜", "～"] }
    private static var opening: Set<Character> { ["「", "『", "（", "("] }

    private func slice(_ r: Range<Int>) -> AttributedString {
        let chars = text.characters
        let lo = chars.index(chars.startIndex, offsetBy: r.lowerBound)
        let hi = chars.index(lo, offsetBy: r.count)
        return AttributedString(text[lo..<hi])
    }
}

extension FuriganaText where Fallback == Text {
    init(_ text: String, rubyFont: Font = .caption2, alignment: HorizontalAlignment = .leading) {
        self.init(AttributedString(text), rubyFont: rubyFont, alignment: alignment) { Text(text) }
    }
}

/// Wrapping row for `FuriganaText`: no gap between units, lines aligned as
/// asked, and only as wide as its widest line so a bubble still hugs a
/// short line.
private struct RubyFlow: Layout {
    var alignment: HorizontalAlignment
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(width: bounds.width, subviews: subviews) {
            var x: CGFloat
            switch alignment {
            case .center: x = bounds.minX + (bounds.width - line.width) / 2
            case .trailing: x = bounds.maxX - line.width
            default: x = bounds.minX
            }
            for (index, size) in line.items {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [(Int, CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if !line.items.isEmpty, line.width + s.width > maxWidth {
                lines.append(line)
                line = Line()
            }
            line.items.append((i, s))
            line.width += s.width
            line.height = max(line.height, s.height)
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}

/// One word of a line cut into words elsewhere (the shadow target's
/// karaoke words), with the readings of the WHOLE line laid over it:
/// a word read on its own loses its context (何 before で is なん). Every
/// word of a line that has any ruby reserves the ruby row, so the bases
/// stay on one baseline.
struct FuriganaWord: View {
    let word: String
    /// Where `word` starts in the line `runs` were cut from, in Characters.
    let offset: Int
    let runs: [Furigana.Run]
    var rubyFont: Font = .caption

    var body: some View {
        let chars = Array(word)
        let end = offset + chars.count
        HStack(spacing: 0) {
            ForEach(Array(pieces(end: end).enumerated()), id: \.offset) { _, p in
                RubyUnit(reading: p.reading, rubyFont: rubyFont) {
                    Text(verbatim: String(chars[(p.range.lowerBound - offset)..<(p.range.upperBound - offset)]))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word)
    }

    private func pieces(end: Int) -> [Furigana.Run] {
        var out: [Furigana.Run] = []
        for run in runs where run.range.upperBound > offset && run.range.lowerBound < end {
            let lo = max(run.range.lowerBound, offset), hi = min(run.range.upperBound, end)
            out.append(Furigana.Run(range: lo..<hi,
                                    reading: run.range.lowerBound >= offset ? run.reading : nil))
        }
        if out.isEmpty { out.append(Furigana.Run(range: offset..<end, reading: nil)) }
        return out
    }
}

/// A base with its reading above. The BASE sets the width: a reading wider
/// than its kanji (しゅうまつ over 週末) overhangs the kana beside it, as
/// printed ruby does, instead of opening a gap in the middle of the line.
/// The ruby row is reserved even with no reading, so bases share a line.
private struct RubyUnit<Base: View>: View {
    let reading: String?
    let rubyFont: Font
    @ViewBuilder var base: () -> Base

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: " ").font(rubyFont).hidden()
            base().fixedSize()
        }
        .overlay(alignment: .top) {
            if let reading {
                Text(verbatim: reading)
                    .font(rubyFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}
