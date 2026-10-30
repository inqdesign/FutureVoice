import SwiftUI
import SceneKit

/// The moment a learner takes a seat in the Core, shown once (2026-10-29,
/// founder: "something special — they did something big").
///
/// Four beats on one screen: a cube arrives, the learner picks its colour,
/// engraves it (their name on one face, a hope on another), and it flies
/// into their own cell of the 100-seat grid. Anyone who taps the cell later
/// reads the name; only seated members of the same club read the hope
/// (`core_seat_detail`), and the engraving step says so. The colour IS the
/// app theme: the seat grid draws every member in the palette their app
/// wears (`FutureVoiceApp` publishes it on every foreground), so a colour
/// picked only for the cube would be overwritten on the next launch.
///
/// Shown when the learner is SEATED and this device hasn't celebrated that
/// seat yet (`CoreWelcomeStore`), never "when the entering tick happened":
/// the nightly settlement seats people too, and a build that ships after the
/// seat was taken must still give its owner this moment.
struct CoreWelcomeView: View {
    let seat: CoreWelcomeStore.Seat
    /// What the name field starts with: the name the learner already goes by.
    var initialName: String = ""
    var onDone: () -> Void

    @AppStorage("futureselfTheme") private var themeRaw = 0
    @Namespace private var flight
    @State private var stage: Stage = .arriving
    @State private var flying = false
    @State private var landed = false
    @State private var name = ""
    @State private var hope = ""
    @FocusState private var focus: Field?

    enum Stage { case arriving, picking, engraving, placing, placed }
    enum Field { case name, hope }

    /// The keyboard is up and the learner is writing on the cube.
    private var typing: Bool { stage == .engraving && focus != nil }

    /// The seat is taken today, as the server counts days (UTC).
    private static var todayUTC: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var theme: FutureselfTheme { FutureselfTheme(rawValue: themeRaw) ?? .blue }
    private let columns = 10

    var body: some View {
        ZStack {
            CoreWelcomeSky(color: theme.tint)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.45), value: themeRaw)

            // The grid sits over the top of the screen rather than in the
            // column, so it can fade in without moving the cube underneath.
            // Tapping the Core before Done takes the cube back out of its
            // seat and returns to the colours (founder, 2026-10-29).
            grid
                .opacity(stage == .placing || stage == .placed ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture { if stage == .placed { pickAgain() } }
                .allowsHitTesting(stage == .placed)
                .padding(.top, 96)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 0) {
                // While engraving, the keyboard is up: the cube moves up and
                // shrinks so both fields and the button stay in view.
                Spacer(minLength: typing ? 4 : stage == .engraving ? 56 : 200)

                ZStack {
                    CoreCubeView(color: theme.tint, name: name, hope: hope,
                                 since: Self.todayUTC, days: 1,
                                 flatten: stage == .placing || stage == .placed)
                        .frame(width: CoreCubeView.unit * 2.2, height: CoreCubeView.unit * 2.2)
                        .opacity(flying ? 0 : 1)
                    if flying && !landed {
                        Image(uiImage: CoreCubeView.faceImage(name, color: theme.tint, isName: true))
                            .resizable()
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .matchedGeometryEffect(id: "seat", in: flight)
                            .frame(width: CoreCubeView.unit, height: CoreCubeView.unit)
                    }
                }
                // Writing on it brings it closer: larger, pushed up so the
                // fields stay clear, its top allowed to leave the screen.
                .scaleEffect(typing ? 1.35 : 1)
                .offset(y: typing ? -70 : 0)
                .frame(height: CoreCubeView.unit * (typing ? 1.8 : stage == .engraving ? 2.2 : 2.4))
                .animation(.easeInOut(duration: 0.3), value: typing)
                .contentShape(Rectangle())
                .onTapGesture { focus = nil }

                // While writing, the cube and the fields are the whole screen:
                // with the keyboard up there is no room for the title too.
                if !typing {
                    text.transition(.opacity)
                }
                Spacer(minLength: 16)
                controls
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .environment(\.colorScheme, .dark)
        .task { await run() }
    }

    // MARK: - Pieces

    private var grid: some View {
        let cell = (200 - CGFloat(columns - 1) * 3) / CGFloat(columns)
        return VStack(spacing: 3) {
            ForEach(0..<max(1, seat.seats / columns), id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = row * columns + col
                        seatCell(index)
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .frame(width: 200)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func seatCell(_ index: Int) -> some View {
        if index == seat.index && landed {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(theme.tint)
                .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(.white, lineWidth: 1.5))
                .matchedGeometryEffect(id: "seat", in: flight)
        } else if let raw = otherTheme(at: index) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(FutureselfTheme(rawValue: raw)?.tint ?? .secondary)
        } else {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.12))
        }
    }

    /// Another member's palette at a grid cell, or nil for an empty seat (and
    /// for the learner's own cell, which stays empty until the cube lands).
    private func otherTheme(at index: Int) -> Int? {
        guard index != seat.index else { return nil }
        let i = index > seat.index ? index - 1 : index
        return i < seat.othersThemes.count ? seat.othersThemes[i] : nil
    }

    private var text: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                CoreSeal(font: .subheadline)
                Text("The Core")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.coreClub)
            }
            .opacity(stage == .arriving ? 0 : 1)
            .contentShape(Rectangle())
            .onTapGesture { if stage == .placed { pickAgain() } }

            Group {
                if stage == .placed {
                    Text(explain("Seat \(seat.number) of \(seat.seats)."))
                } else if stage == .engraving {
                    Text(explain("Engrave your cube"))
                } else {
                    Text(explain("You're Core member no. \(seat.number)!"))
                }
            }
            .font(.geistPixel(26))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .contentTransition(.opacity)

            Group {
                if stage == .placed {
                    // The hope, said back as the reason to keep the seat
                    // (founder, 2026-10-29), then the keep rule in full.
                    VStack(spacing: 8) {
                        let shown = hope.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !shown.isEmpty {
                            Text(explain("Keep this seat until “\(shown)” comes true!"))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        Text(explain("Miss one day a month and the seat stays yours. Miss more, and you leave the Core and start again from zero."))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else if stage == .engraving {
                    Text(explain("Your name goes on one face, your hope on another."))
                } else if stage != .placing {
                    Text(explain("\(seat.streak) days in a row, without missing one."))
                }
            }
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.65))
        }
        .animation(.easeInOut(duration: 0.4), value: stage)
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 14) {
            if stage == .picking {
                VStack(spacing: 12) {
                    Text(explain("This cube is your seat in the Core. Pick its colour."))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.65))
                    HStack(spacing: 14) {
                        ForEach(FutureselfTheme.allCases) { option in
                            Button {
                                HapticEngine.selection()
                                withAnimation(.easeInOut(duration: 0.3)) { themeRaw = option.rawValue }
                            } label: {
                                Circle()
                                    .fill(option.tint)
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: option == theme ? 2.5 : 0)
                                        .padding(-5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(option.label))
                            .accessibilityAddTraits(option == theme ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                    Text(explain("Your app takes this colour too."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .transition(.opacity)
            }

            if stage == .engraving {
                engraving
                    .transition(.opacity)
            }

            if stage == .picking || stage == .engraving || stage == .placed {
                Button {
                    switch stage {
                    case .picking: engrave()
                    case .engraving: place()
                    default: finish()
                    }
                } label: {
                    Text(stage == .picking ? explain("Next")
                         : stage == .engraving ? explain("Put it in my seat") : explain("Done"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .controlSize(.large)
                .transition(.opacity)
            }
        }
        .frame(minHeight: 170, alignment: .bottom)
        .animation(.easeInOut(duration: 0.35), value: stage)
    }

    private var engraving: some View {
        VStack(spacing: 10) {
            engraveField(explain("Your name"), text: $name, limit: CoreClubService.engravedNameLimit,
                         field: .name)
            engraveField(explain("Your hope, in one line"), text: $hope,
                         limit: CoreClubService.hopeLimit, field: .hope)
            // Said where the hope is written, before anyone else can read it.
            Label {
                Text(explain("Only Core members can see your hope. Anyone can see your name."))
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
            .padding(.top, 2)
            Button {
                focus = nil
                withAnimation(.easeInOut(duration: 0.35)) { stage = .picking }
            } label: {
                Text(explain("Back to colours"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private func engraveField(_ prompt: String, text: Binding<String>, limit: Int, field: Field) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(.white.opacity(0.4)))
            .focused($focus, equals: field)
            .submitLabel(field == .name ? .next : .done)
            .onSubmit { focus = field == .name ? .hope : nil }
            .onChange(of: text.wrappedValue) { _, new in
                if new.count > limit { text.wrappedValue = String(new.prefix(limit)) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Beats

    private func run() async {
        HapticEngine.success()
        // The cube's own arrival takes 1.2 s; the colours come once it has
        // settled, so the first thing seen is the cube, not a form.
        try? await Task.sleep(for: .milliseconds(1500))
        withAnimation { stage = .picking }
        #if DEBUG
        // `-corewelcomeauto 1`: pick a colour and place it, for a capture run.
        if UserDefaults.standard.bool(forKey: "corewelcomeauto") {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { themeRaw = FutureselfTheme.coral.rawValue }
            try? await Task.sleep(for: .seconds(1.5))
            engrave()
            name = UserDefaults.standard.string(forKey: "corewelcomename") ?? "Minji"
            hope = UserDefaults.standard.string(forKey: "corewelcomehope") ?? "Give a talk in English next year"
            if UserDefaults.standard.bool(forKey: "corewelcometype") { focus = .hope }
            try? await Task.sleep(for: .seconds(4))
            place()
            // `-corewelcomeauto 2`: then tap the Core to pick again.
            if UserDefaults.standard.integer(forKey: "corewelcomeauto") == 2 {
                try? await Task.sleep(for: .seconds(3))
                pickAgain()
            }
        }
        #endif
    }

    private func engrave() {
        HapticEngine.selection()
        if name.isEmpty { name = String(initialName.prefix(CoreClubService.engravedNameLimit)) }
        withAnimation(.easeInOut(duration: 0.35)) { stage = .engraving }
    }

    private func place() {
        HapticEngine.medium()
        focus = nil
        withAnimation(.easeInOut(duration: 0.35)) { stage = .placing }
        let language = seat.language, name = name, hope = hope
        // A preview is not a seat: nothing it picks may reach the account.
        if !seat.isPreview {
            Task {
                await CoreClubService.publishTheme(themeRaw)
                await CoreClubService.setEngraving(language: language, name: name, hope: hope)
            }
        }
        Task { @MainActor in
            // The cube turns to face the learner first (CoreCubeView's
            // flatten), then the square it became flies to its cell.
            try? await Task.sleep(for: .milliseconds(550))
            flying = true
            try? await Task.sleep(for: .milliseconds(40))
            withAnimation(.spring(response: 0.75, dampingFraction: 0.82)) { landed = true }
            try? await Task.sleep(for: .milliseconds(650))
            HapticEngine.rigid()
            withAnimation(.easeInOut(duration: 0.4)) { stage = .placed }
        }
    }

    /// The flight in reverse: the square leaves its cell for the middle of
    /// the screen, turns back into the cube, and the colours come back.
    private func pickAgain() {
        HapticEngine.medium()
        withAnimation(.easeInOut(duration: 0.3)) { stage = .placing }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { landed = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            flying = false
            withAnimation(.easeInOut(duration: 0.4)) { stage = .picking }
        }
    }

    private func finish() {
        HapticEngine.light()
        CoreWelcomeStore.markWelcomed(seat)
        Analytics.capture("core_welcome_done", ["number": seat.number, "theme": themeRaw])
        onDone()
    }
}

/// The light behind the cube, built like the welcome film's sky
/// (`StoryBackdrop`): a wide ellipse centred above the top edge so only its
/// soft lower half comes down into the screen, drifting slowly, with night
/// at the very top so the notch sinks into it. Here it is the colour the
/// learner is picking, and it falls to black instead of cream.
private struct CoreWelcomeSky: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 10_000)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let r = h * 0.62
                ZStack {
                    Color.black
                    Ellipse()
                        .fill(RadialGradient(stops: [
                            .init(color: color, location: 0),
                            .init(color: color.opacity(0.78), location: 0.22),
                            .init(color: color.opacity(0.42), location: 0.48),
                            .init(color: color.opacity(0.14), location: 0.74),
                            .init(color: color.opacity(0), location: 1),
                        ], center: .center, startRadius: 0, endRadius: r))
                        .frame(width: r * 2.4, height: r * 2)
                        .position(x: w * (0.5 + 0.04 * sin(t * 0.05)),
                                  y: -h * 0.06 + h * 0.02 * cos(t * 0.04))
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.9), location: 0),
                        .init(color: .black.opacity(0.45), location: 0.06),
                        .init(color: .black.opacity(0), location: 0.2),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .drawingGroup()
            }
        }
        .accessibilityHidden(true)
    }
}

/// The cube itself. SceneKit, because SwiftUI has no 3D solid: an
/// orthographic camera so the face that turns to the learner is exactly
/// `unit` points — the size of the square that takes over for the flight.
/// The cube spins inside a tilted parent, so its top face is always in view.
struct CoreCubeView: UIViewRepresentable {
    static let unit: CGFloat = 116
    /// One slow turn. 10 s read as busy beside the rising notes (founder).
    static let turnSeconds: TimeInterval = 20

    let color: Color
    var name: String = ""
    var hope: String = ""
    /// The side plaque: the UTC day the seat was taken ("2026-10-29") and
    /// how many days it has been held. Nil leaves that face plain.
    var since: String? = nil
    var days: Int? = nil
    var flatten: Bool = false

    /// Handwriting, as if cut by hand (founder, 2026-10-29): Snell Roundhand
    /// (ships with iOS) for Latin, Nanum Pen Script (bundled, OFL) for Hangul
    /// through the cascade. Kana and Han fall back to the system face.
    static func engravingFont(_ size: CGFloat, for text: String = "") -> UIFont {
        // Nanum Pen draws small for its point size; a Hangul line leads with
        // it, a size up, rather than borrowing Snell's size through the cascade.
        if text.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }),
           let hangul = UIFont(name: "NanumPen-Regular", size: size * 1.3) {
            return hangul
        }
        let latin = UIFont(name: "SnellRoundhand-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
        let hangul = UIFontDescriptor(fontAttributes: [.name: "NanumPen-Regular"])
        let descriptor = latin.fontDescriptor.addingAttributes([.cascadeList: [hangul]])
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Pressed into a face the way the lettering is: the cube's own colour,
    /// much deeper (founder, 2026-10-29: black read as printed on, not cut
    /// in), with a pale lip under it.
    private static func deboss(on base: UIColor, _ draw: (UIColor, CGFloat) -> Void) {
        draw(UIColor.white.withAlphaComponent(0.3), 4)
        draw(carved(base), 0)
    }

    /// The face colour, darker and a little richer: the inside of a cut.
    static func carved(_ base: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard base.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            return UIColor.black.withAlphaComponent(0.6)
        }
        // A grey (Mono) stays grey; everything else deepens in its own hue.
        return UIColor(hue: h, saturation: s < 0.08 ? s : min(1, s * 1.15 + 0.1),
                       brightness: b * 0.42, alpha: 1)
    }

    /// The side plaque, set upright like a dedication plate: SINCE and the
    /// date in the top-left corner, DAY and the count in the bottom-right.
    /// Kept in English on every phone, like the lettering on a monument.
    static func plaqueImage(since: String?, days: Int, color: Color) -> UIImage {
        let side: CGFloat = 512, inset: CGFloat = 48
        let base = resolved(color)
        func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let plain = UIFont.systemFont(ofSize: size, weight: weight)
            return UIFont(descriptor: plain.fontDescriptor.withDesign(.serif) ?? plain.fontDescriptor, size: size)
        }
        func text(_ string: String, _ font: UIFont, kern: CGFloat, _ color: UIColor) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
        }
        let date = (since ?? "").replacingOccurrences(of: "-", with: ".")
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            base.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            deboss(on: base) { color, dy in
                if !date.isEmpty {
                    text("SINCE", serif(30, .semibold), kern: 6, color).draw(at: CGPoint(x: inset, y: inset + dy))
                    text(date, serif(44, .regular), kern: 2, color).draw(at: CGPoint(x: inset, y: inset + 40 + dy))
                }
                let label = text("DAY", serif(30, .semibold), kern: 6, color)
                let count = text("\(days)", serif(96, .regular), kern: 0, color)
                let countSize = count.size(), labelSize = label.size()
                count.draw(at: CGPoint(x: side - inset - countSize.width, y: side - inset - countSize.height + dy))
                label.draw(at: CGPoint(x: side - inset - labelSize.width,
                                       y: side - inset - countSize.height - labelSize.height + 6 + dy))
            }
        }
    }

    /// The nawana mark, small in the middle of a face.
    static func logoImage(color: Color) -> UIImage {
        let side: CGFloat = 512
        let base = resolved(color)
        let mark = UIImage(named: "LaunchLogo", in: .main, compatibleWith: UITraitCollection(userInterfaceStyle: .light))
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            base.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            guard let mark else { return }
            let w: CGFloat = 120, h = w * mark.size.height / max(mark.size.width, 1)
            let rect = CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h)
            deboss(on: base) { color, dy in
                mark.withTintColor(color, renderingMode: .alwaysOriginal).draw(in: rect.offsetBy(dx: 0, dy: dy))
            }
        }
    }

    /// One face of the cube as an image: the colour, with the text pressed
    /// into it (dark letters, a pale lip under them). The name is set large;
    /// the hope smaller, over up to three lines.
    static func faceImage(_ text: String, color: Color, isName: Bool) -> UIImage {
        let side: CGFloat = 512
        let base = resolved(color)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            base.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let size: CGFloat = isName ? (trimmed.count > 12 ? 78 : trimmed.count > 7 ? 96 : 118)
                                       : (trimmed.count > 36 ? 52 : trimmed.count > 20 ? 60 : 72)
            let font = engravingFont(size, for: trimmed)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineBreakStrategy = .hangulWordPriority
            paragraph.lineSpacing = size * 0.2
            let box = CGRect(x: 36, y: 36, width: side - 72, height: side - 72)
            func draw(_ color: UIColor, dy: CGFloat) {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color,
                                                            .paragraphStyle: paragraph]
                let s = NSAttributedString(string: trimmed, attributes: attrs)
                let fit = s.boundingRect(with: box.size, options: [.usesLineFragmentOrigin], context: nil)
                let h = min(fit.height, box.height)
                s.draw(with: CGRect(x: box.minX, y: box.midY - h / 2 + dy, width: box.width, height: h),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            }
            deboss(on: base) { color, dy in draw(color, dy: dy) }
        }
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        // Drag to turn it over; tapping still reaches SwiftUI around it.
        view.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator,
                                                         action: #selector(Coordinator.pan(_:))))

        let scene = SCNScene()
        view.scene = scene

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 1.1          // the view is 2.2 units tall → 1 unit = `unit` pt
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 10)
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-0.7, 0.5, 0)
        scene.rootNode.addChildNode(key)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 420
        scene.rootNode.addChildNode(ambient)

        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.09)
        // Front, right, back, left, top, bottom: the name faces the learner,
        // the hope is on the back, so a full turn shows both.
        box.materials = (0..<6).map { _ in
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.38
            material.metalness.contents = 0.05
            material.diffuse.contents = Self.resolved(color)
            return material
        }
        let tilt = SCNNode()
        tilt.name = "tilt"
        scene.rootNode.addChildNode(tilt)
        let cube = SCNNode(geometry: box)
        cube.name = "cube"
        tilt.addChildNode(cube)
        context.coordinator.tilt = tilt
        context.coordinator.cube = cube

        // Arrives small and tumbling, settles tipped toward the learner, then
        // turns slowly for as long as they look at it.
        tilt.scale = SCNVector3(0.15, 0.15, 0.15)
        tilt.eulerAngles = SCNVector3(2.4, 0, 0)
        let arrive = SCNAction.group([
            .scale(to: 1, duration: 1.2),
            .rotateTo(x: 0.48, y: 0, z: 0, duration: 1.2, usesShortestUnitArc: false),
        ])
        arrive.timingMode = .easeOut
        tilt.runAction(arrive, forKey: "arrive")
        cube.eulerAngles = SCNVector3(0, -4.6, 0)
        let settle = SCNAction.rotateTo(x: 0, y: .pi / 4, z: 0, duration: 1.2, usesShortestUnitArc: false)
        settle.timingMode = .easeOut
        let turn = SCNAction.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: CoreCubeView.turnSeconds))
        cube.runAction(.sequence([settle, turn]), forKey: "idle")
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let tilt = view.scene?.rootNode.childNode(withName: "tilt", recursively: false),
              let cube = tilt.childNode(withName: "cube", recursively: false) else { return }
        if let materials = cube.geometry?.materials, materials.count == 6 {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            for i in [4, 5] { materials[i].diffuse.contents = Self.resolved(color) }
            if days == nil { materials[1].diffuse.contents = Self.resolved(color) }
            SCNTransaction.commit()
            // Redrawn only when what is on them changed: SwiftUI calls this
            // on every keystroke and colour tap.
            let key = "\(color.description)|\(name)|\(hope)|\(since ?? "")|\(days ?? -1)"
            if key != context.coordinator.facesKey {
                context.coordinator.facesKey = key
                materials[0].diffuse.contents = Self.faceImage(name, color: color, isName: true)
                materials[2].diffuse.contents = Self.faceImage(hope, color: color, isName: false)
                if let days {
                    materials[1].diffuse.contents = Self.plaqueImage(since: since, days: days, color: color)
                }
                materials[3].diffuse.contents = Self.logoImage(color: color)
            }
        }
        // Only on a change of state: SwiftUI calls this for every colour tap
        // too, and re-running a turn mid-turn is what lost the tilt.
        guard flatten != context.coordinator.isFlat else { return }
        context.coordinator.isFlat = flatten
        cube.removeAllActions()
        tilt.removeAllActions()
        SCNTransaction.begin()
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if flatten {
            // Face the learner squarely: the nearest whole turn, no tilt.
            let turn = Float.pi * 2
            SCNTransaction.animationDuration = 0.45
            tilt.scale = SCNVector3(1, 1, 1)
            tilt.eulerAngles = SCNVector3(0, 0, 0)
            cube.eulerAngles = SCNVector3(0, (cube.eulerAngles.y / turn).rounded() * turn, 0)
            SCNTransaction.commit()
        } else {
            // Back from its seat: tip toward the learner again and resume turning.
            SCNTransaction.animationDuration = 0.5
            tilt.eulerAngles = SCNVector3(0.48, 0, 0)
            cube.eulerAngles = SCNVector3(0, cube.eulerAngles.y + .pi / 4, 0)
            SCNTransaction.commit()
            let spin = SCNAction.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: CoreCubeView.turnSeconds))
            cube.runAction(.sequence([.wait(duration: 0.5), spin]), forKey: "idle")
        }
    }

    @MainActor final class Coordinator: NSObject {
        var isFlat = false
        var facesKey = ""
        weak var tilt: SCNNode?
        weak var cube: SCNNode?

        /// Sideways turns it, up and down tips it. Let go and it carries the
        /// flick for a moment, then settles back into the slow turn.
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard !isFlat, let tilt, let cube else { return }
            switch gesture.state {
            case .began:
                HapticEngine.selection()
                cube.removeAllActions()
                tilt.removeAllActions()
                tilt.scale = SCNVector3(1, 1, 1)
            case .changed:
                let t = gesture.translation(in: gesture.view)
                gesture.setTranslation(.zero, in: gesture.view)
                cube.eulerAngles.y += Float(t.x) * 0.012
                tilt.eulerAngles.x = max(-1.2, min(1.2, tilt.eulerAngles.x + Float(t.y) * 0.012))
            case .ended, .cancelled:
                let v = gesture.velocity(in: gesture.view)
                let coast = SCNAction.rotateBy(x: 0, y: max(-6, min(6, v.x * 0.0025)), z: 0, duration: 0.9)
                coast.timingMode = .easeOut
                let spin = SCNAction.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: CoreCubeView.turnSeconds))
                cube.runAction(.sequence([coast, spin]), forKey: "idle")
                let tip = SCNAction.rotateTo(x: 0.48, y: 0, z: 0, duration: 0.9, usesShortestUnitArc: true)
                tip.timingMode = .easeOut
                tilt.runAction(tip, forKey: "arrive")
            default:
                break
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func resolved(_ color: Color) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    }
}

/// Whether this device has celebrated the learner's seat yet, per account
/// and per club (a seat is one language's). Device-local on purpose: a
/// second device shows it once too, which is the right number of times for
/// something you only see on a screen you're holding.
enum CoreWelcomeStore {
    struct Seat: Identifiable, Equatable {
        let userId: String
        let language: String
        /// 0-based cell in the seat grid, ordered like `core_seat_map`.
        let index: Int
        let seats: Int
        let streak: Int
        /// Everyone else's palettes, in grid order without the learner.
        let othersThemes: [Int]

        var id: String { userId + ":" + language }
        var number: Int { index + 1 }
        var isPreview: Bool { userId == "preview" }
    }

    private static func key(_ userId: String, _ language: String) -> String {
        "futurevoice.core.welcomed.\(userId.lowercased()).\(language.lowercased())"
    }

    static func markWelcomed(_ seat: Seat) {
        UserDefaults.standard.set(true, forKey: key(seat.userId, seat.language))
    }

    /// The seat to celebrate, or nil: not signed in, not seated, or already
    /// celebrated here. Two reads, both already used by the Core page.
    static func due(language: String) async -> Seat? {
        guard let uid = try? await SupabaseProvider.shared.auth.session.user.id.uuidString.lowercased(),
              !UserDefaults.standard.bool(forKey: key(uid, language)) else { return nil }
        async let mapCall = CoreClubService.fetchSeatMap(language: language)
        async let progressCall = CoreClubService.fetchProgress(language: language)
        guard let map = await mapCall, let mine = map.mine else { return nil }
        let progress = await progressCall
        var others = map.themes
        if mine < others.count { others.remove(at: mine) }
        return Seat(userId: uid, language: language, index: mine, seats: map.seats,
                    streak: progress?.entry_streak ?? 30, othersThemes: others)
    }

    #if DEBUG
    /// `-corewelcome 1`: the first seat of an empty club, nothing remembered.
    static var preview: Seat { preview(language: "en") }

    /// Me → Developer: seat 24 of a club where 23 already sit, in the
    /// learner's own language. Nothing it picks is saved (`isPreview`).
    static func preview(language: String) -> Seat {
        let palettes = FutureselfTheme.allCases.map(\.rawValue)
        let others = (0..<23).map { palettes[($0 * 5 + 2) % palettes.count] }
        return Seat(userId: "preview", language: language, index: 23, seats: 100, streak: 30, othersThemes: others)
    }
    #endif
}
