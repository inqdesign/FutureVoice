import SwiftUI
import MapKit
import CoreMotion
import AVFoundation

/// Walk mode: a PROTOTYPE (2026-11-16, founder's concept). The learner's real
/// steps move them along a real street in a city of the language they are
/// learning; the real places on that street become Watch scenes the fluent
/// self walks into, with the city's sound underneath.
///
/// Deliberately small: one fixed route per language, places from MapKit,
/// each stop an ordinary `Scenario` played by `SceneWatchView`, so the
/// scene, the voice, the billing gate and the book are the ones Watch
/// already has. Not shown to anyone outside a debug build unless the
/// defaults flag is set (`WalkMode.isEnabled`).
enum WalkMode {
    static var isEnabled: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #elseif DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "futurevoice.walkMode")
        #endif
    }

    struct Route {
        let city: String
        let area: String
        let start: CLLocationCoordinate2D
        let end: CLLocationCoordinate2D
        /// Corners the walk must pass, in order: what keeps it on the back
        /// streets when the shortest way is the main road.
        var via: [CLLocationCoordinate2D] = []
    }

    /// One short walk per target language, each down a street dense with
    /// shops and cafés.
    static func route(for language: String) -> Route {
        func c(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        switch language.prefix(2) {
        case "de": return Route(city: "Berlin", area: "Mitte",
                                start: c(52.5226, 13.4022), end: c(52.5297, 13.4014))
        case "ja": return Route(city: "Tokyo", area: "Shibuya",
                                start: c(35.6595, 139.7005), end: c(35.6684, 139.7060))
        case "ko": return Route(city: "Seoul", area: "Hongdae",
                                start: c(37.5571, 126.9245), end: c(37.5509, 126.9215))
        case "es": return Route(city: "Mexico City", area: "Roma Norte",
                                start: c(19.4195, -99.1620), end: c(19.4143, -99.1669))
        case "fr": return Route(city: "Paris", area: "Le Marais",
                                start: c(48.8553, 2.3615), end: c(48.8608, 2.3622))
        case "zh": return Route(city: "Shanghai", area: "Xuhui",
                                start: c(31.2165, 121.4452), end: c(31.2110, 121.4400))
        // Carnaby Street, across Broadwick Street, down Berwick Street,
        // along Old Compton Street, up Greek Street to Soho Square.
        default:   return Route(city: "London", area: "Soho",
                                start: c(51.5142, -0.1390), end: c(51.5148, -0.1308),
                                via: [c(51.5122, -0.1385), c(51.5134, -0.1352),
                                      c(51.5124, -0.1340), c(51.5134, -0.1300)])
        }
    }

    /// What a place is, in plain words, and its icon.
    static func kind(of category: MKPointOfInterestCategory?) -> (name: String, symbol: String) {
        switch category {
        case .cafe?: return ("café", "cup.and.saucer.fill")
        case .bakery?: return ("bakery", "storefront.fill")
        case .restaurant?: return ("restaurant", "fork.knife")
        case .foodMarket?: return ("food shop", "basket.fill")
        case .pharmacy?: return ("pharmacy", "cross.case.fill")
        case .nightlife?, .brewery?, .winery?: return ("bar", "wineglass.fill")
        case .museum?: return ("museum", "building.columns.fill")
        case .publicTransport?: return ("station", "tram.fill")
        case .hotel?: return ("hotel", "bed.double.fill")
        case .theater?, .movieTheater?: return ("theatre", "theatermasks.fill")
        case .postOffice?: return ("post office", "envelope.fill")
        case .library?: return ("library", "books.vertical.fill")
        case .laundry?: return ("laundry", "washer.fill")
        case .bank?: return ("bank", "banknote.fill")
        default: return ("shop", "bag.fill")
        }
    }

    /// Every kind of place a street has. A bank, a hotel desk, a ticket
    /// office are situations too (founder, 2026-11-16).
    static let categories: [MKPointOfInterestCategory] = [
        .cafe, .bakery, .restaurant, .store, .foodMarket, .pharmacy, .nightlife,
        .museum, .publicTransport, .hotel, .theater, .movieTheater, .postOffice,
        .library, .laundry, .bank, .fitnessCenter,
    ]
}

struct WalkStop: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String
    let symbol: String
    let latitude: Double
    let longitude: Double
    /// Metres from the start of the route.
    let along: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@MainActor
final class WalkModel: ObservableObject {
    enum Phase: Equatable { case loading, ready, failed(String) }

    @Published var phase: Phase = .loading
    @Published var stops: [WalkStop] = []
    @Published var walked: Double = 0
    @Published var steps: Int = 0
    /// Stops whose scene was heard or that were walked past.
    @Published var heard: Set<String> = []

    private(set) var route = WalkMode.route(for: "en")
    private(set) var points: [MKMapPoint] = []
    private var cumulative: [Double] = []
    private(set) var total: Double = 0

    private let pedometer = CMPedometer()
    /// Metres added by the "skip ahead" button, on top of real steps.
    private var simulated: Double = 0
    private var measured: Double = 0

    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }

    /// The first place reached and not yet dealt with.
    var arrived: WalkStop? {
        // The place the walker is beside right now. Walking on leaves it
        // behind; nothing has to be dismissed.
        stops.filter { abs($0.along - walked) <= 14 }
            .min { abs($0.along - walked) < abs($1.along - walked) }
    }

    var next: WalkStop? {
        stops.first { $0.along > walked + 14 }
    }

    var finished: Bool { phase == .ready && walked >= total }

    func load(language: String) async {
        route = WalkMode.route(for: language)
        phase = .loading
        do {
            // One leg per corner, joined end to end.
            let corners = [route.start] + route.via + [route.end]
            var joined: [MKMapPoint] = []
            for (from, to) in zip(corners, corners.dropFirst()) {
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
                request.transportType = .walking
                let response = try await MKDirections(request: request).calculate()
                guard let line = response.routes.first?.polyline, line.pointCount > 1 else { continue }
                joined += Array(UnsafeBufferPointer(start: line.points(), count: line.pointCount))
            }
            guard joined.count > 1 else {
                phase = .failed("No walking route came back.")
                return
            }
            points = joined
            cumulative = [0]
            for i in 1..<points.count {
                cumulative.append(cumulative[i - 1] + points[i - 1].distance(to: points[i]))
            }
            total = cumulative.last ?? 0
            stops = await findStops()
            #if DEBUG
            print("WALK route \(Int(total)) m:", stops.map { "\($0.name) [\($0.kind)] \(Int($0.along))" })
            #endif
            phase = .ready
            #if DEBUG
            simulated = UserDefaults.standard.double(forKey: "skipWalk")
            recount()
            #endif
            startPedometer()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Real places beside the route, in walking order, spaced so a scene
    /// has time to end before the next one.
    private func findStops() async -> [WalkStop] {
        var found: [String: (MKMapItem, Double)] = [:]
        // A search returns a couple of dozen places at most, so ask at
        // several points down the street.
        let probes = stride(from: 0.06, through: 0.96, by: 0.1).map { coordinate(at: total * $0) }
        for centre in probes {
            let request = MKLocalPointsOfInterestRequest(center: centre, radius: 120)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: WalkMode.categories)
            guard let items = try? await MKLocalSearch(request: request).start().mapItems else { continue }
            for item in items {
                guard let name = item.name, !name.isEmpty else { continue }
                // Apple Maps carries the odd spam listing ("Buy Xanax bars").
                let lower = name.lowercased()
                guard !lower.hasPrefix("buy "), !lower.contains("pills") else { continue }
                let (along, off) = project(MKMapPoint(item.placemark.coordinate))
                guard off <= 35, along > 60 else { continue }
                if found[name] == nil { found[name] = (item, along) }
            }
        }
        // One place per stretch of street, and of the places in a stretch
        // the kind heard least so far: a café, then a pub, then a shop,
        // not five clothes shops in a row.
        var picked: [WalkStop] = []
        var used: [String: Int] = [:]
        let ordered = found.values.sorted { $0.1 < $1.1 }
        var from = 60.0
        while from < total, picked.count < 30 {
            let stretch = ordered.filter { $0.1 >= from && $0.1 < from + 35 }
            let choice = stretch.min {
                used[WalkMode.kind(of: $0.0.pointOfInterestCategory).name, default: 0]
                    < used[WalkMode.kind(of: $1.0.pointOfInterestCategory).name, default: 0]
            }
            guard let (item, along) = choice else { from += 35; continue }
            let kind = WalkMode.kind(of: item.pointOfInterestCategory)
            let c = item.placemark.coordinate
            picked.append(WalkStop(id: item.name ?? UUID().uuidString, name: item.name ?? "",
                                   kind: kind.name, symbol: kind.symbol,
                                   latitude: c.latitude, longitude: c.longitude, along: along))
            used[kind.name, default: 0] += 1
            from = along + 35
        }
        return picked
    }

    /// Distance along the route of the point on it nearest `p`, and how far
    /// off the route `p` is. Both in metres.
    private func project(_ p: MKMapPoint) -> (along: Double, off: Double) {
        var best = (along: 0.0, off: Double.infinity)
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
            let q = MKMapPoint(x: a.x + dx * t, y: a.y + dy * t)
            let off = q.distance(to: p)
            if off < best.off {
                best = (cumulative[i - 1] + a.distance(to: q), off)
            }
        }
        return best
    }

    func coordinate(at metres: Double) -> CLLocationCoordinate2D {
        guard points.count > 1 else { return route.start }
        let d = max(0, min(total, metres))
        let i = max(1, cumulative.firstIndex { $0 >= d } ?? (points.count - 1))
        let span = cumulative[i] - cumulative[i - 1]
        let t = span == 0 ? 0 : (d - cumulative[i - 1]) / span
        let a = points[i - 1], b = points[i]
        return MKMapPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t).coordinate
    }

    /// Compass heading of the street at `metres`.
    func heading(at metres: Double) -> Double {
        let a = coordinate(at: metres), b = coordinate(at: min(total, metres + 20))
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        guard x != 0 || y != 0 else { return 0 }
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func startPedometer() {
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

    func skipAhead(_ metres: Double) {
        simulated += metres
        recount()
    }

    private func recount() {
        walked = min(total, measured + simulated)
    }

    func stop() { pedometer.stopUpdates() }
}

/// The city underneath: `walk_ambience.m4a`, four minutes of a walk through
/// Soho on a Friday afternoon (Pau Monfort, Radio Aporee, Public Domain Mark,
/// archive.org item aporee_66982_77504). Without the file, a low rumble made
/// here stands in.
@MainActor
final class WalkAmbience {
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil else { player?.play(); return }
        let url = Bundle.main.url(forResource: "walk_ambience", withExtension: "m4a") ?? Self.rumbleFile()
        guard let url, let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.numberOfLoops = -1
        p.volume = 0.45
        p.play()
        player = p
    }

    func stop() { player?.stop(); player = nil }

    private static func rumbleFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("walk_rumble.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let rate = 22_050.0, seconds = 12.0, fade = Int(rate)
        let count = Int(rate * seconds)
        var samples = [Float](repeating: 0, count: count + fade)
        var brown: Float = 0, slow: Float = 0
        for i in samples.indices {
            brown = (brown + Float.random(in: -1...1) * 0.02) * 0.995
            slow = slow * 0.9995 + Float.random(in: -1...1) * 0.0005
            samples[i] = brown * (0.6 + min(0.4, abs(slow) * 20))
        }
        // The tail fades into the head so the loop has no seam.
        for i in 0..<fade {
            let t = Float(i) / Float(fade)
            samples[i] = samples[i] * t + samples[count + i] * (1 - t)
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(count)
        let peak = max(0.001, samples[0..<count].map(abs).max() ?? 1)
        for i in 0..<count { channel[i] = samples[i] / peak * 0.5 }
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return nil }
        try? file.write(from: buffer)
        return url
    }
}

struct WalkModeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = WalkModel()
    @State private var camera: MapCameraPosition = .automatic
    @State private var scene: SceneTarget?
    @State private var playing: WalkStop?
    @State private var talk: Scenario?
    @State private var paywall = false
    @State private var wall: TalkWall?
    @State private var ambience = WalkAmbience()
    @AppStorage("futurevoice.walk.sound") private var sound = true
    /// The drawn street, or the map of the real one.
    @AppStorage("futurevoice.walk.street") private var street = true

    struct SceneTarget: Identifiable, Hashable {
        let id = UUID()
        let scenario: Scenario
        let fresh: Bool
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if street, model.phase == .ready {
                    WalkStreetView(stops: model.stops, total: model.total, walked: model.walked,
                                   heard: model.heard, arrived: playing)
                        .ignoresSafeArea()
                } else {
                    map
                }
                if scene == nil {
                    card
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle(Text(verbatim: "\(model.route.area), \(model.route.city)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BarCloseButton(title: "Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { street.toggle() } label: {
                        Image(systemName: street ? "map" : "building.2")
                    }
                    .accessibilityLabel(Text(street ? "Map" : "Street"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sound.toggle() } label: {
                        Image(systemName: sound ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                    .accessibilityLabel(Text("City sound"))
                }
            }
            // The scene plays in a panel under the street, so the walker
            // stays in front of the place while they listen.
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
                .presentationDetents([.fraction(0.46), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.46)))
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
        }
        .task { await model.load(language: appState.targetLanguage) }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if sound { ambience.start() }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            ambience.stop()
            model.stop()
        }
        .onChange(of: sound) { _, on in on ? ambience.start() : ambience.stop() }
        .onChange(of: model.walked) { _, _ in follow() }
        .onChange(of: model.phase) { _, _ in follow(animated: false) }
        .onChange(of: scene) { _, now in
            // Back from a scene: that place has been heard.
            if now == nil, let stop = playing {
                model.heard.insert(stop.id)
                playing = nil
            }
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera) {
            if model.points.count > 1 {
                MapPolyline(coordinates: model.coordinates)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 6)
            }
            ForEach(model.stops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate) {
                    Image(systemName: model.heard.contains(stop.id) ? "checkmark" : stop.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(model.heard.contains(stop.id) ? Color.green : Color.accentColor,
                                    in: Circle())
                }
            }
            if model.phase == .ready {
                Annotation("", coordinate: model.coordinate(at: model.walked)) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    /// The camera walks the street: low, tilted, facing the way of travel.
    private func follow(animated: Bool = true) {
        guard model.phase == .ready else { return }
        let target = MapCameraPosition.camera(MapCamera(
            centerCoordinate: model.coordinate(at: model.walked),
            distance: 380, heading: model.heading(at: model.walked), pitch: 62))
        if animated {
            withAnimation(.easeInOut(duration: 1.0)) { camera = target }
        } else {
            camera = target
        }
    }

    // MARK: - Card

    @ViewBuilder private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.phase {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding the street…").foregroundStyle(.secondary)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                Button("Try again") { Task { await model.load(language: appState.targetLanguage) } }
            case .ready:
                if model.finished {
                    Text("You walked through \(model.route.area).")
                        .font(.headline)
                    Text("\(Int(model.total)) m · \(model.heard.count) places")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    walkingCard
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var walkingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let stop = model.arrived {
                besideRow(stop)
            } else if let next = model.next {
                Label {
                    Text(verbatim: "\(next.name) · \(Int(next.along - model.walked)) m")
                } icon: {
                    Image(systemName: next.symbol)
                }
                .font(.headline)
            } else {
                Text("Keep walking").font(.headline)
            }
            ProgressView(value: model.walked, total: max(1, model.total))
            HStack {
                Text("\(model.steps) steps · \(Int(model.walked)) of \(Int(model.total)) m")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                // For a desk or the simulator: move without walking.
                Button { model.skipAhead(20) } label: {
                    Label("Skip ahead", systemImage: "figure.walk")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    /// Beside a place: its name and the one thing to do there. Nothing
    /// starts unless it is tapped.
    private func besideRow(_ stop: WalkStop) -> some View {
        HStack(spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: stop.name).font(.headline).lineLimit(1)
                    Text(verbatim: stop.kind.capitalized)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: stop.symbol)
            }
            Spacer()
            if model.heard.contains(stop.id) {
                Button { stepIn(stop) } label: {
                    Label("Talk here", systemImage: "phone.fill")
                }
                .buttonStyle(.bordered)
            } else {
                Button { listen(stop) } label: {
                    Label("Listen in", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Scenes

    /// Each place is an ordinary scenario, kept under its own key so the
    /// same shop tomorrow is a fresh take in the same book.
    private func scenario(for stop: WalkStop) -> Scenario {
        let key = "walk:\(model.route.city):\(stop.name)"
        if let existing = appState.scenarios.first(where: { $0.starterId == key }) { return existing }
        var s = Scenario(
            environment: "\(stop.name), a \(stop.kind) in \(model.route.area), \(model.route.city)",
            role: "",
            notes: "The learner's fluent self is walking through \(model.route.area) and drops in here for one small, ordinary errand: asking about something on sale, ordering, a question for the staff, or a short chat with someone there. Invent the person they talk to and what is on offer so it is believable for this kind of place in \(model.route.city). State nothing as fact about the real business beyond its name and what kind of place it is.")
        s.starterId = key
        s.category = "Walk"
        s.categoryIcon = "figure.walk"
        s.summary = stop.name
        appState.saveScenario(s)
        return s
    }

    private func listen(_ stop: WalkStop) {
        BillingGate.startScene(orShow: $paywall, wall: $wall) {
            let s = scenario(for: stop)
            playing = stop
            scene = SceneTarget(scenario: s, fresh: !(s.curriculum?.dialogue ?? []).isEmpty)
        }
    }

    private func stepIn(_ stop: WalkStop) {
        BillingGate.start(orShow: $paywall) {
            talk = scenario(for: stop)
        }
    }
}
