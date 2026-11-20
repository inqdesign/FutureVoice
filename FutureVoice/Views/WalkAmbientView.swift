import SwiftUI
import CoreMotion
import AVFoundation

/// Walk mode, second cut (2026-11-19, founder): no drawn street. Pick a city
/// from a row of abstract pictures, the screen goes dark, and what is left is
/// that city's own sound. As the learner walks, the fluent self runs into
/// people: on the street, in a shop, at a stall. Each meeting is an ordinary
/// short Watch scene and starts only when tapped. PROTOTYPE.
struct WalkCity: Identifiable, Hashable {
    let id: String
    let name: String
    let area: String
    /// Target language this city belongs to.
    let language: String
    /// Bundled recording, without its extension.
    let sound: String
    let volume: Float
    /// Sky top, sky bottom, glow.
    let colours: [UInt32]
    /// Who made the recording (Radio Aporee, Public Domain Mark).
    let credit: String

    static let all: [WalkCity] = [
        WalkCity(id: "london", name: "London", area: "Soho", language: "en", sound: "walk_ambience",
                 volume: 0.4, colours: [0x1B2A4A, 0x6B4E71, 0xF2A65A], credit: "Pau Monfort"),
        WalkCity(id: "newyork", name: "New York", area: "6th Avenue", language: "en", sound: "walk_newyork",
                 volume: 1, colours: [0x10203A, 0x35507A, 0xFFD166], credit: "Piotrek Zyla"),
        WalkCity(id: "berlin", name: "Berlin", area: "Kreuzberg", language: "de", sound: "walk_berlin",
                 volume: 1, colours: [0x1F2B2E, 0x4F6D5E, 0xE9C46A], credit: "Peter Stets"),
        WalkCity(id: "tokyo", name: "Tokyo", area: "Akihabara", language: "ja", sound: "walk_tokyo",
                 volume: 1, colours: [0x1A1033, 0x5B2A6E, 0xFF5D8F], credit: "maciej janasik"),
        WalkCity(id: "seoul", name: "Seoul", area: "Gangnam", language: "ko", sound: "walk_seoul",
                 volume: 1, colours: [0x0F2238, 0x2F5D7C, 0x7AE7C7], credit: "pyha.bamseom"),
        WalkCity(id: "mexico", name: "Mexico City", area: "Centro", language: "es", sound: "walk_mexico",
                 volume: 1, colours: [0x3A1420, 0xA63D40, 0xF4D35E], credit: "anaerrasti"),
        WalkCity(id: "madrid", name: "Madrid", area: "Plaza Mayor", language: "es", sound: "walk_madrid",
                 volume: 1, colours: [0x2B1B12, 0x9C5B2E, 0xFFC857], credit: "maciej janasik"),
        WalkCity(id: "paris", name: "Paris", area: "Bastille", language: "fr", sound: "walk_paris",
                 volume: 1, colours: [0x1D2440, 0x7A6C9E, 0xF7C6B5], credit: "schuetzsusann"),
        WalkCity(id: "shanghai", name: "Shanghai", area: "Nanjing Road", language: "zh", sound: "walk_shanghai",
                 volume: 0.8, colours: [0x2A0E12, 0x8C1C2B, 0xFFB703], credit: "Wu Tsan-Cheng"),
    ]

    /// The cities of the language being learned first.
    static func ordered(for language: String) -> [WalkCity] {
        let code = String(language.prefix(2))
        return all.filter { $0.language == code } + all.filter { $0.language != code }
    }
}

/// Someone the fluent self can run into on a walk.
struct WalkEncounter: Identifiable, Hashable {
    let id: String
    let who: String
    let place: String
    let symbol: String

    static let all: [WalkEncounter] = [
        .init(id: "barista", who: "a barista", place: "at the counter of a small café", symbol: "cup.and.saucer.fill"),
        .init(id: "baker", who: "a baker", place: "in a bakery with a short queue", symbol: "storefront.fill"),
        .init(id: "stall", who: "a stallholder", place: "at a fruit stall on the street market", symbol: "basket.fill"),
        .init(id: "lost", who: "someone who is lost", place: "on a street corner, asking the way", symbol: "map.fill"),
        .init(id: "busker", who: "a busker", place: "packing up on the pavement", symbol: "guitars.fill"),
        .init(id: "bookshop", who: "a bookshop owner", place: "in a second-hand bookshop", symbol: "books.vertical.fill"),
        .init(id: "florist", who: "a florist", place: "outside a flower shop", symbol: "leaf.fill"),
        .init(id: "dog", who: "a neighbour with a dog", place: "on the pavement", symbol: "pawprint.fill"),
        .init(id: "pharmacy", who: "a pharmacist", place: "in a pharmacy", symbol: "cross.case.fill"),
        .init(id: "tickets", who: "a ticket clerk", place: "at a station ticket window", symbol: "tram.fill"),
        .init(id: "friend", who: "an old friend", place: "bumped into on the street", symbol: "person.2.fill"),
        .init(id: "foodcart", who: "a street food seller", place: "at a food cart", symbol: "fork.knife"),
        .init(id: "photo", who: "a tourist", place: "who wants a photo taken", symbol: "camera.fill"),
        .init(id: "kiosk", who: "a newsstand seller", place: "at a kiosk", symbol: "newspaper.fill"),
        .init(id: "bar", who: "a bartender", place: "at a quiet bar", symbol: "wineglass.fill"),
        .init(id: "cleaner", who: "a dry cleaner", place: "at the counter of a laundry", symbol: "washer.fill"),
    ]
}

/// Steps, and who turns up along the way.
@MainActor
final class WalkWander: ObservableObject {
    @Published var steps = 0
    @Published var walked = 0.0
    /// The person the walker is beside right now.
    @Published var meeting: WalkEncounter?
    @Published var heard: Set<String> = []
    @Published var metCount = 0
    /// A scene is playing: the person stays however far the walker goes.
    var held = false { didSet { if !held { meetingAt = walked } } }

    private let pedometer = CMPedometer()
    private var measured = 0.0
    private var simulated = 0.0
    private var nextAt = Double.random(in: 25...45)
    private var meetingAt = 0.0
    private var recent: [String] = []

    func start() {
        #if DEBUG
        simulated = UserDefaults.standard.double(forKey: "skipWalk")
        #endif
        recount()
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let data else { return }
            let steps = data.numberOfSteps.intValue
            let metres = data.distance?.doubleValue ?? Double(steps) * 0.75
            Task { @MainActor in
                self?.steps = steps
                self?.measured = metres
                self?.recount()
            }
        }
    }

    func stop() { pedometer.stopUpdates() }

    func skipAhead(_ metres: Double) {
        simulated += metres
        recount()
    }

    private func recount() {
        walked = measured + simulated
        if meeting != nil {
            // Walking on leaves them behind; nothing has to be dismissed.
            if !held, walked > meetingAt + 45 {
                meeting = nil
                nextAt = walked + Double.random(in: 40...110)
            }
        } else if walked >= nextAt {
            let pool = WalkEncounter.all.filter { !recent.contains($0.id) }
            guard let pick = pool.randomElement() else { return }
            recent = Array((recent + [pick.id]).suffix(8))
            meeting = pick
            meetingAt = walked
            metCount += 1
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }
}

/// One city's recording, looped. Changing city fades one into the other.
@MainActor
final class WalkCitySound {
    private var player: AVAudioPlayer?
    private var playing: String?

    func play(_ city: WalkCity, level: Float = 1) {
        let target = city.volume * level
        if playing == city.id, let player {
            player.setVolume(target, fadeDuration: 1.2)
            if !player.isPlaying { player.play() }
            return
        }
        let old = player
        old?.setVolume(0, fadeDuration: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { old?.stop() }
        guard let url = Bundle.main.url(forResource: city.sound, withExtension: "m4a"),
              let p = try? AVAudioPlayer(contentsOf: url) else { player = nil; playing = nil; return }
        p.numberOfLoops = -1
        p.volume = 0
        p.play()
        p.setVolume(target, fadeDuration: 1.2)
        player = p
        playing = city.id
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }
}

struct WalkAmbientView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var wander = WalkWander()
    @State private var cities: [WalkCity] = []
    @State private var shown: String?
    @State private var city: WalkCity?
    @State private var sound = WalkCitySound()
    @AppStorage("futurevoice.walk.sound") private var soundOn = true

    @State private var scene: SceneTarget?
    @State private var talk: Scenario?
    @State private var paywall = false
    @State private var wall: TalkWall?

    struct SceneTarget: Identifiable, Hashable {
        let id = UUID()
        let scenario: Scenario
        let fresh: Bool
    }

    private var current: WalkCity? { city ?? cities.first { $0.id == shown } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let city {
                walking(city).transition(.opacity)
            } else {
                picker.transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .sheet(item: $scene) { t in
            NavigationStack {
                SceneWatchView(scenarioId: t.scenario.id, freshTake: t.fresh)
                    .environmentObject(appState)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            BarCloseButton(title: "Done") { scene = nil }
                        }
                    }
            }
            .presentationDetents([.fraction(0.5), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $paywall) { PaywallView(source: "walk_mode") }
        .talkWall($wall, source: "walk_mode_scene_short")
        .fullScreenCover(item: $talk) { s in
            ConversationView(initialTopic: s.displayTitle, initialBlurb: s.promptBlurb,
                             initialOrigin: .scenario, initialScenarioId: s.id,
                             entry: .scenarioBook)
                .environmentObject(appState)
        }
        .onAppear {
            cities = WalkCity.ordered(for: appState.targetLanguage)
            shown = cities.first?.id
            #if DEBUG
            if let id = UserDefaults.standard.string(forKey: "walkCity"),
               let c = cities.first(where: { $0.id == id }) {
                city = c
                wander.start()
            }
            #endif
            UIApplication.shared.isIdleTimerDisabled = true
            syncSound()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            sound.stop()
            wander.stop()
        }
        .onChange(of: shown) { _, _ in syncSound() }
        .onChange(of: soundOn) { _, _ in syncSound() }
        .onChange(of: scene) { _, now in
            if now == nil {
                if let m = wander.meeting { wander.heard.insert(m.id) }
                wander.held = false
            }
            syncSound()
        }
        .onChange(of: talk) { _, now in
            // A call has the mic: the city stands down until it is over.
            if now != nil { sound.stop() } else { syncSound() }
        }
    }

    /// The city is quieter while it is only being looked at, and under a scene.
    private func syncSound() {
        guard soundOn, talk == nil, let c = current else { sound.stop(); return }
        let level: Float = city == nil ? 0.6 : (scene == nil ? 1 : 0.45)
        sound.play(c, level: level)
    }

    // MARK: - Picking a city

    private var picker: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.12), in: Circle())
                }
                Spacer()
                soundButton
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Text("Where do you want to walk?")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.top, 18)

            TabView(selection: $shown) {
                ForEach(cities) { c in
                    cityCard(c).tag(Optional(c.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                guard let c = current else { return }
                withAnimation(.easeInOut(duration: 1.6)) { city = c }
                wander.start()
                syncSound()
            } label: {
                Text("Walk here")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 28)
            .padding(.bottom, 16)
        }
    }

    private func cityCard(_ c: WalkCity) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WalkCityPicture(city: c)
                .clipShape(RoundedRectangle(cornerRadius: 28))
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: c.name).font(.largeTitle.weight(.bold))
                Text(verbatim: "\(c.area) · \(LanguageCatalog.name(c.language, in: LanguageCatalog.currentNative))")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 48)
    }

    private var soundButton: some View {
        Button { soundOn.toggle() } label: {
            Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.12), in: Circle())
        }
        .accessibilityLabel(Text("City sound"))
    }

    // MARK: - Walking

    private func walking(_ c: WalkCity) -> some View {
        ZStack {
            WalkGlow(colours: c.colours).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.8)) { city = nil }
                        wander.stop()
                        syncSound()
                    } label: {
                        Image(systemName: "chevron.down").font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    Spacer()
                    soundButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()
                VStack(spacing: 6) {
                    Text(verbatim: c.area).font(.title.weight(.semibold))
                    Text(verbatim: c.name).font(.subheadline).opacity(0.55)
                }
                Spacer()

                if let m = wander.meeting, scene == nil {
                    meetingCard(m, in: c)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack {
                    Text("\(wander.steps) steps · \(wander.metCount) met")
                        .font(.footnote).opacity(0.5)
                    Spacer()
                    // For a desk or the simulator: move without walking.
                    Button { wander.skipAhead(20) } label: {
                        Label("Skip ahead", systemImage: "figure.walk")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .foregroundStyle(.white)
        }
        .animation(.easeInOut(duration: 0.6), value: wander.meeting)
    }

    /// Someone is here. Nothing starts unless it is tapped.
    private func meetingCard(_ m: WalkEncounter, in c: WalkCity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: m.symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: m.who.prefix(1).uppercased() + m.who.dropFirst()).font(.headline)
                Text(verbatim: m.place.prefix(1).uppercased() + m.place.dropFirst())
                    .font(.subheadline).opacity(0.6).lineLimit(2)
            }
            Spacer(minLength: 4)
            if wander.heard.contains(m.id) {
                Button { stepIn(m, in: c) } label: { Label("Talk", systemImage: "phone.fill") }
                    .buttonStyle(.bordered).tint(.white)
            } else {
                Button { listen(m, in: c) } label: { Label("Listen", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12)))
    }

    // MARK: - Scenes

    /// Each meeting is an ordinary scenario under its own key, so the same
    /// person tomorrow is a fresh take in the same book. The `walk:` key is
    /// what makes `ScenarioCurriculumEngine` write the short walk-by scene.
    private func scenario(for m: WalkEncounter, in c: WalkCity) -> Scenario {
        let key = "walk:\(c.id):\(m.id)"
        if let existing = appState.scenarios.first(where: { $0.starterId == key }) { return existing }
        var s = Scenario(
            environment: "\(m.place), \(c.area), \(c.name)",
            role: m.who,
            notes: "The learner's fluent self is out for a walk in \(c.area), \(c.name) and runs into \(m.who) \(m.place). One small, ordinary exchange between the two: a question, a short errand, or a few friendly words. Invent the details so they are believable for \(c.name). Name no real business.")
        s.starterId = key
        s.category = "Walk"
        s.categoryIcon = "figure.walk"
        s.summary = "\(m.who.prefix(1).uppercased() + m.who.dropFirst()), \(c.name)"
        appState.saveScenario(s)
        return s
    }

    private func listen(_ m: WalkEncounter, in c: WalkCity) {
        BillingGate.startScene(orShow: $paywall, wall: $wall) {
            let s = scenario(for: m, in: c)
            wander.held = true
            scene = SceneTarget(scenario: s, fresh: !(s.curriculum?.dialogue ?? []).isEmpty)
        }
    }

    private func stepIn(_ m: WalkEncounter, in c: WalkCity) {
        BillingGate.start(orShow: $paywall) {
            talk = scenario(for: m, in: c)
        }
    }
}

// MARK: - Pictures

private func walkColour(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
          blue: Double(hex & 0xFF) / 255)
}

/// A city as a few shapes: a sky, a low sun, two rows of blocks.
struct WalkCityPicture: View {
    let city: WalkCity

    var body: some View {
        Canvas { ctx, size in
            let top = walkColour(city.colours[0]), bottom = walkColour(city.colours[1])
            let glow = walkColour(city.colours[2])
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [top, bottom]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            var seed = UInt64(abs(city.id.hashValue % 9973)) &+ UInt64(city.id.utf8.reduce(0) { $0 &+ Int($1) })
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double((seed >> 33) % 10_000) / 10_000
            }
            let sun = CGPoint(x: size.width * (0.25 + next() * 0.5), y: size.height * (0.3 + next() * 0.15))
            let r = size.width * 0.19
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r * 2.4, y: sun.y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                     with: .radialGradient(Gradient(colors: [glow.opacity(0.45), glow.opacity(0)]),
                                           center: sun, startRadius: 0, endRadius: r * 2.4))
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2)),
                     with: .color(glow.opacity(0.9)))
            // Far row, then near row.
            for (row, shade) in [(0, 0.45), (1, 0.8)] {
                var x = -10.0
                while x < size.width {
                    let w = size.width * (0.08 + next() * 0.12)
                    let h = size.height * ((row == 0 ? 0.3 : 0.16) + next() * (row == 0 ? 0.28 : 0.2))
                    let rect = CGRect(x: x, y: size.height - h, width: w, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: next() < 0.3 ? w / 2 : 3),
                             with: .color(.black.opacity(shade)))
                    if row == 1, next() < 0.6 {
                        let lit = CGRect(x: x + w * 0.3, y: size.height - h * (0.4 + next() * 0.4),
                                         width: w * 0.16, height: w * 0.16)
                        ctx.fill(Path(lit), with: .color(glow.opacity(0.8)))
                    }
                    x += w + size.width * 0.012
                }
            }
        }
    }
}

/// The walking screen's only picture: dark, with the city's colours moving
/// slowly underneath.
struct WalkGlow: View {
    let colours: [UInt32]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                let spots: [(UInt32, Double, Double, Double)] = [
                    (colours[1], 0.3, 0.031, 0.0), (colours[2], 0.16, 0.023, 2.1), (colours[0], 0.5, 0.017, 4.2),
                ]
                for (hex, strength, speed, phase) in spots {
                    let c = CGPoint(x: size.width * (0.5 + 0.36 * cos(t * speed * 2 + phase)),
                                    y: size.height * (0.55 + 0.3 * sin(t * speed * 3 + phase)))
                    let radius = max(size.width, size.height) * 0.62
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius,
                                                    width: radius * 2, height: radius * 2)),
                             with: .radialGradient(
                                Gradient(colors: [walkColour(hex).opacity(strength), .clear]),
                                center: c, startRadius: 0, endRadius: radius))
                }
            }
        }
    }
}
