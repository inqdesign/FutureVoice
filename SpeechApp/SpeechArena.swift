import SwiftUI
import SceneKit
import UIKit

// The speech app's Challenges tab as a game, not a lesson (2026-11-12,
// founder: "immersive, a bit of gamification, fun from first principles,
// it should challenge you"). A dark stage, real 3D medals, a medal for every
// challenge to collect, and always the next number to beat.

// MARK: - Medals

enum MedalTier: Int, Comparable, CaseIterable {
    case bronze, silver, gold

    static func < (a: MedalTier, b: MedalTier) -> Bool { a.rawValue < b.rawValue }

    /// The score that earns it.
    var bar: Int {
        switch self {
        case .bronze: return 80
        case .silver: return 85
        case .gold: return 90
        }
    }

    init?(score: Int) {
        if score >= 90 { self = .gold } else if score >= 85 { self = .silver }
        else if score >= 80 { self = .bronze } else { return nil }
    }

    init?(rank: Int) {
        switch rank {
        case 1: self = .gold
        case 2: self = .silver
        case 3: self = .bronze
        default: return nil
        }
    }

    var metal: UIColor {
        switch self {
        case .gold: return UIColor(red: 0.9, green: 0.72, blue: 0.36, alpha: 1)
        case .silver: return UIColor(red: 0.8, green: 0.82, blue: 0.85, alpha: 1)
        case .bronze: return UIColor(red: 0.74, green: 0.48, blue: 0.33, alpha: 1)
        }
    }

    var glow: Color { Color(metal) }
}

/// The medal as a 3D object: a metal disc, a raised rim and an embossed
/// label, lit by a soft studio light so the metal catches it. Shared by the
/// live view and the still images the small medals use.
enum MedalScene {
    /// A struck medal (2026-11-12, founder: "more realistic, the number must
    /// read"): a mirror-polished rim and raised number on a frosted field, the
    /// way a proof coin is struck, so the number reads by contrast of finish
    /// rather than by colour. A bead ring inside the rim; on the podium, a
    /// bail and a two-tone ribbon.
    static func make(tier: MedalTier, label: String, ribbon: Bool = false) -> (SCNScene, SCNNode) {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = environment
        scene.lightingEnvironment.intensity = 1.8

        let medal = SCNNode()
        let polished = material(tier.metal.withBrightness(1.06), roughness: 0.1)
        let body = material(tier.metal, roughness: 0.2)
        // Darker and duller than any polished part, so the number stands out
        // even at 34 pt.
        let frosted = material(tier.metal.withBrightness(0.46), roughness: 0.78)
        let relief = material(tier.metal.withBrightness(1.2), roughness: 0.06)

        let disc = SCNNode(geometry: SCNCylinder(radius: 1, height: 0.14))
        disc.geometry?.materials = [body]
        disc.eulerAngles.x = .pi / 2
        medal.addChildNode(disc)

        // The raised rim and its rounded lip.
        let rim = SCNNode(geometry: SCNTube(innerRadius: 0.84, outerRadius: 0.99, height: 0.22))
        rim.geometry?.materials = [polished]
        rim.eulerAngles.x = .pi / 2
        medal.addChildNode(rim)
        for side: Float in [1, -1] {
            let lip = SCNNode(geometry: SCNTorus(ringRadius: 0.915, pipeRadius: 0.075))
            lip.geometry?.materials = [polished]
            lip.eulerAngles.x = .pi / 2
            lip.position.z = 0.075 * side
            medal.addChildNode(lip)
        }

        // The frosted field, front and back.
        for side: Float in [1, -1] {
            let field = SCNNode(geometry: SCNCylinder(radius: 0.84, height: 0.02))
            field.geometry?.materials = [frosted]
            field.eulerAngles.x = .pi / 2
            field.position.z = 0.075 * side
            medal.addChildNode(field)
        }

        // A ring of beads just inside the rim.
        let bead = SCNSphere(radius: 0.028)
        bead.segmentCount = 10
        bead.materials = [polished]
        for i in 0..<44 {
            let a = Float(i) / 44 * 2 * .pi
            let node = SCNNode(geometry: bead)
            node.position = SCNVector3(cos(a) * 0.765, sin(a) * 0.765, 0.085)
            medal.addChildNode(node)
        }

        if !label.isEmpty {
            let text = SCNText(string: label, extrusionDepth: 2.2)
            let base = UIFont.systemFont(ofSize: 10, weight: .black)
            text.font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 10) } ?? base
            text.flatness = 0.05
            text.chamferRadius = 0.35
            text.materials = [relief]
            let node = SCNNode(geometry: text)
            let (lo, hi) = node.boundingBox
            let width = hi.x - lo.x, height = hi.y - lo.y
            let fitWidth: Float = 1.18 / max(width, 1)
            let fitHeight: Float = 0.92 / max(height, 1)
            let scale: Float = min(fitWidth, fitHeight)
            node.scale = SCNVector3(scale, scale, scale * 0.55)
            let x: Float = -(lo.x + width / 2) * scale
            let y: Float = -(lo.y + height / 2) * scale
            node.position = SCNVector3(x, y, 0.08)
            medal.addChildNode(node)
        }

        if ribbon {
            let bail = SCNNode(geometry: SCNTorus(ringRadius: 0.13, pipeRadius: 0.045))
            bail.geometry?.materials = [polished]
            bail.position = SCNVector3(0, 1.08, 0)
            medal.addChildNode(bail)
            let colors: [UIColor] = [UIColor(red: 0.62, green: 0.16, blue: 0.18, alpha: 1),
                                     UIColor(red: 0.12, green: 0.2, blue: 0.4, alpha: 1)]
            for (i, side) in [Float(-1), 1].enumerated() {
                let cloth = SCNMaterial()
                cloth.lightingModel = .physicallyBased
                cloth.diffuse.contents = colors[i]
                cloth.roughness.contents = 0.85
                cloth.metalness.contents = 0.0
                let strip = SCNNode(geometry: SCNBox(width: 0.46, height: 1.5, length: 0.02, chamferRadius: 0.005))
                strip.geometry?.materials = [cloth]
                strip.position = SCNVector3(side * 0.24, 1.78, -0.06)
                strip.eulerAngles.z = side * 0.3
                medal.addChildNode(strip)
            }
            medal.position.y = -0.62
        }
        scene.rootNode.addChildNode(medal)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = ribbon ? 40 : 30
        camera.position = SCNVector3(0, 0, ribbon ? 4.7 : 4.4)
        scene.rootNode.addChildNode(camera)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1100
        key.eulerAngles = SCNVector3(-0.7, -0.6, 0)
        scene.rootNode.addChildNode(key)

        let rimLight = SCNNode()
        rimLight.light = SCNLight()
        rimLight.light?.type = .directional
        rimLight.light?.intensity = 500
        rimLight.eulerAngles = SCNVector3(0.5, 2.4, 0)
        scene.rootNode.addChildNode(rimLight)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 140
        scene.rootNode.addChildNode(fill)
        return (scene, medal)
    }

    private static func material(_ color: UIColor, roughness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = 1.0
        m.roughness.contents = roughness
        return m
    }

    /// A studio in an image: bright soft boxes and strips above, a dark floor
    /// and dark bands, so polished metal shows real highlights and edges.
    static let environment: UIImage = {
        let size = CGSize(width: 1024, height: 512)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(white: 0.9, alpha: 1).cgColor, UIColor(white: 0.35, alpha: 1).cgColor,
                          UIColor(white: 0.04, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(x: 120, y: 40, width: 260, height: 70))
            cg.fill(CGRect(x: 640, y: 90, width: 180, height: 46))
            cg.fill(CGRect(x: 470, y: 20, width: 30, height: 200))
            cg.setFillColor(UIColor(white: 0.02, alpha: 1).cgColor)
            cg.fill(CGRect(x: 0, y: 250, width: size.width, height: 26))
        }
    }()

    /// Stills are made off the main thread (a SceneKit render per new medal
    /// held up the card's zoom into its page) and kept for the session.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: UIImage] = [:]
    private static let queue = DispatchQueue(label: "medal-stills", qos: .userInitiated)
    /// The lights, camera and environment every still is shot in, with no
    /// medal of its own. Touched only on `queue`.
    nonisolated(unsafe) private static var studioScene: SCNScene = {
        let (scene, medal) = make(tier: .gold, label: "")
        medal.removeFromParentNode()
        return scene
    }()
    nonisolated(unsafe) private static var renderer: SCNRenderer? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return SCNRenderer(device: device, options: nil)
    }()

    private static func key(_ tier: MedalTier, _ label: String, _ points: CGFloat) -> String {
        "v3-\(tier.rawValue)-\(label)-\(Int(points))"
    }

    /// A still already made, without waiting.
    static func cachedImage(tier: MedalTier, label: String, points: CGFloat) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return cache[key(tier, label, points)]
    }

    /// A still of the medal, a little turned so the rim shows.
    static func image(tier: MedalTier, label: String, points: CGFloat, scale: CGFloat) async -> UIImage? {
        if let hit = cachedImage(tier: tier, label: label, points: points) { return hit }
        return await withCheckedContinuation { done in
            queue.async {
                if let hit = cachedImage(tier: tier, label: label, points: points) { return done.resume(returning: hit) }
                guard let renderer else { return done.resume(returning: nil) }
                // Every still is shot in ONE studio scene: a new scene per
                // medal made SceneKit work out the lighting environment again
                // each time, the GPU work that made the first seconds after
                // launch stutter.
                let (_, medal) = make(tier: tier, label: label)
                medal.removeFromParentNode()
                medal.eulerAngles.y = -0.32
                medal.eulerAngles.x = 0.12
                let studio = studioScene
                studio.rootNode.addChildNode(medal)
                if renderer.scene !== studio { renderer.scene = studio }
                let pixels = points * scale
                let shot = renderer.snapshot(atTime: 0, with: CGSize(width: pixels, height: pixels),
                                             antialiasingMode: .multisampling4X)
                medal.removeFromParentNode()
                guard let cg = shot.cgImage else { return done.resume(returning: nil) }
                let image = UIImage(cgImage: cg, scale: scale, orientation: .up)
                lock.lock(); cache[key(tier, label, points)] = image; lock.unlock()
                done.resume(returning: image)
            }
        }
    }

    /// The medals every page opens on, made once at launch so the first
    /// zoom into a page doesn't wait for them.
    static func warm(scale: CGFloat) {
        Task.detached(priority: .utility) { await prepare(scale: scale) }
    }

    /// The rank medals every board shows, and the learner's own best scores
    /// at every size a page draws them. The launch curtain waits on this, so
    /// no page meets a medal still being made.
    static func prepare(scale: CGFloat, scores: [Int] = []) async {
        for tier in MedalTier.allCases {
            for rank in 1...3 { _ = await image(tier: tier, label: "\(rank)", points: 34, scale: scale) }
        }
        for score in Set(scores) {
            guard let tier = MedalTier(score: score) else { continue }
            for points: CGFloat in [34, 42, 52, 56] {
                if Task.isCancelled { return }
                _ = await image(tier: tier, label: "\(score)", points: points, scale: scale)
            }
        }
    }
}

extension UIColor {
    func withBrightness(_ factor: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: b * factor, alpha: a)
    }
}

/// A live medal: it sways on its own, follows a finger, and spins on a tap.
struct Medal3D: UIViewRepresentable {
    let tier: MedalTier
    var label: String = ""
    /// Hung from a ribbon (the podium); the view should be taller than wide.
    var ribbon: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        // It turns slowly: 30 frames a second look the same and leave the
        // GPU to the screen.
        view.preferredFramesPerSecond = 30
        let (scene, medal) = MedalScene.make(tier: tier, label: label, ribbon: ribbon)
        view.scene = scene
        view.isPlaying = true
        context.coordinator.medal = medal
        let sway = SCNAction.sequence([
            .rotateBy(x: 0, y: 0.45, z: 0, duration: 1.8),
            .rotateBy(x: 0, y: -0.9, z: 0, duration: 3.6),
            .rotateBy(x: 0, y: 0.45, z: 0, duration: 1.8),
        ])
        sway.timingMode = .easeInEaseOut
        medal.runAction(.repeatForever(sway), forKey: "sway")
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.spin)))
        view.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.turn(_:))))
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    final class Coordinator: NSObject {
        var medal: SCNNode?

        @objc func spin() {
            guard let medal else { return }
            let spin = SCNAction.rotateBy(x: 0, y: .pi * 4, z: 0, duration: 1.1)
            spin.timingMode = .easeOut
            medal.runAction(spin)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        @objc func turn(_ pan: UIPanGestureRecognizer) {
            guard let medal, let view = pan.view else { return }
            let dx = Float(pan.translation(in: view).x) / Float(max(view.bounds.width, 1))
            medal.eulerAngles.y += dx * .pi * 2
            pan.setTranslation(.zero, in: view)
        }
    }
}

/// A small medal: the 3D medal as a still, or an empty slot still to win.
struct MedalBadge: View {
    let tier: MedalTier?
    var label: String = ""
    var size: CGFloat = 44
    @Environment(\.displayScale) private var scale
    /// The empty slot follows the page: nawana's light pages too (the
    /// speech app's stage is always dark, where it is drawn as before).
    @Environment(\.colorScheme) private var scheme
    @State private var still: UIImage?

    var body: some View {
        Group {
            if let tier {
                if let image = still ?? MedalScene.cachedImage(tier: tier, label: label, points: size) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: size, height: size)
                        .shadow(color: .black.opacity(0.5), radius: size * 0.08, y: size * 0.05)
                } else {
                    // A flat stand-in for the moment the still is made.
                    Circle().fill(Color(tier.metal).opacity(0.85))
                        .frame(width: size * 0.92, height: size * 0.92)
                        .frame(width: size, height: size)
                }
            } else {
                let light = scheme == .light
                Circle()
                    .strokeBorder(light ? Color.black.opacity(0.08) : Color.white.opacity(0.14), lineWidth: 1)
                    .background(Circle().fill(light ? Color(white: 0.9) : Color(white: 0.1)))
                    .overlay(Image(systemName: "lock.fill").font(.system(size: size * 0.3))
                        .foregroundStyle(light ? Color.black.opacity(0.3) : Color.white.opacity(0.35)))
                    .frame(width: size * 0.78, height: size * 0.78)
                    .frame(width: size, height: size)
            }
        }
        .task(id: "\(tier?.rawValue ?? -1)-\(label)-\(size)") {
            guard let tier else { still = nil; return }
            still = await MedalScene.image(tier: tier, label: label, points: size, scale: scale)
        }
    }
}

// MARK: - The stage

// The look (2026-11-12, founder, with references): black ground, chrome in
// white and greys only, a serif display face, and colour only in the
// content — muted tiles with a quiet pattern, the medals' metal.

enum Arena {
    static let ink = Color.black
    static let card = Color(white: 0.085)
    static let raised = Color(white: 0.14)
    static let dim = Color.white.opacity(0.55)
    static let gold = Color(red: 0.86, green: 0.71, blue: 0.4)
    /// The app's one action colour: CTAs, the selected tab, highlights. A
    /// colour, never `.primary`: in the dark look `.primary` is white, and a
    /// white fill under a white label (or a white tab label on light glass)
    /// disappears. Reads on black, on the cream cards and under a white label.
    static let accent = Color(red: 0.93, green: 0.45, blue: 0.3)

    static var background: some View { Color.black.ignoresSafeArea() }

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }

    /// Each kind of challenge has a muted colour and a pattern of its own.
    static func tone(_ category: String?, seed: UUID? = nil) -> (top: Color, bottom: Color, pattern: TilePattern) {
        let keys = ["show_host", "famous_speech", "movie_scene", "acceptance", "product_launch", "in_flight", "podcast", "short_talk"]
        var category = category
        if category == nil || !keys.contains(category!), let seed {
            // No kind on file: the challenge still gets a colour of its own.
            let byte = withUnsafeBytes(of: seed.uuid) { $0.reduce(0) { $0 &+ Int($1) } }
            category = keys[byte % keys.count]
        }
        switch category {
        case "show_host": return (rgb(0.83, 0.62, 0.25), rgb(0.66, 0.48, 0.18), .rings)
        case "famous_speech": return (rgb(0.1, 0.19, 0.35), rgb(0.07, 0.14, 0.27), .dots)
        case "movie_scene": return (rgb(0.43, 0.2, 0.33), rgb(0.35, 0.16, 0.27), .lines)
        case "acceptance": return (rgb(0.66, 0.61, 0.52), rgb(0.52, 0.48, 0.41), .arcs)
        case "product_launch": return (rgb(0.44, 0.38, 0.65), rgb(0.27, 0.22, 0.42), .rings)
        case "in_flight": return (rgb(0.58, 0.63, 0.13), rgb(0.33, 0.38, 0.06), .rays)
        case "podcast": return (rgb(0.6, 0.33, 0.24), rgb(0.45, 0.24, 0.17), .lines)
        case "short_talk": return (rgb(0.19, 0.37, 0.35), rgb(0.12, 0.26, 0.25), .dots)
        default: return (rgb(0.3, 0.3, 0.33), rgb(0.2, 0.2, 0.22), .arcs)
        }
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
}

enum TilePattern { case rings, dots, lines, arcs, rays }

/// The quiet pattern inside a tile: thin white lines at low opacity.
struct TilePatternView: View {
    let pattern: TilePattern

    var body: some View {
        Canvas { ctx, size in
            let line = GraphicsContext.Shading.color(.white.opacity(0.09))
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            switch pattern {
            case .rings:
                for i in 1...4 {
                    let r = CGFloat(i) * size.width * 0.16
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: line, lineWidth: 1.2)
                }
            case .dots:
                let step = size.width / 6
                for x in stride(from: step / 2, to: size.width, by: step) {
                    for y in stride(from: step / 2, to: size.height, by: step) {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)),
                                 with: .color(.white.opacity(0.14)))
                    }
                }
            case .lines:
                for (i, y) in stride(from: size.height * 0.15, to: size.height, by: size.height * 0.17).enumerated() {
                    let start = i.isMultiple(of: 2) ? 0 : size.width * 0.3
                    var p = Path()
                    p.move(to: CGPoint(x: start, y: y))
                    p.addLine(to: CGPoint(x: start + size.width * 0.7, y: y))
                    ctx.stroke(p, with: line, lineWidth: 1.4)
                }
            case .arcs:
                for i in 1...4 {
                    var p = Path()
                    let r = size.width * (0.5 + CGFloat(i) * 0.22)
                    p.addArc(center: CGPoint(x: c.x, y: size.height * 1.15), radius: r,
                             startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                    ctx.stroke(p, with: line, lineWidth: 1.2)
                }
            case .rays:
                for i in 0..<9 {
                    var p = Path()
                    p.move(to: CGPoint(x: size.width * 0.15, y: size.height))
                    let x = size.width * (0.2 + CGFloat(i) * 0.12)
                    p.addQuadCurve(to: CGPoint(x: x + size.width * 0.3, y: 0), control: CGPoint(x: x, y: size.height * 0.5))
                    ctx.stroke(p, with: line, lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A challenge's card: one cream paper for every challenge, no pattern
/// (2026-11-12, founder), the figure and dark words on it.
struct ToneTile<Content: View>: View {
    let category: String?
    var seed: UUID? = nil
    var radius: CGFloat = 40
    @ViewBuilder var content: Content

    var body: some View {
        content
            .foregroundStyle(ChallengeArt.inkText)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(ChallengeArt.paper))
    }
}

// nawana compiles this file too, for the cards, the pictures and the medals
// (2026-11-13, founder: one card look in both apps). The pages and pieces
// that lean on the speech app's own groups, calendar and trophy stay in the
// speech app.
#if SPEECH_APP
/// The Challenges tab's whole page.
struct SpeechArenaHome: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var challenges = SpeechChallenges.shared
    @ObservedObject private var store = SpeechStore.shared
    @ObservedObject private var groups = SpeechGroups.shared
    @ObservedObject private var avatar = AvatarStore.shared
    var openRanking: () -> Void
    @State private var filter: SpeechChallengeFilter = .all

    private var every: [SpeechScript] { challenges.live + challenges.past }
    @Environment(\.displayScale) private var displayScale

    /// One challenge a day: each by the day it came out (the newest, if a day
    /// had two).
    private var byDay: [Date: SpeechScript] {
        var days: [Date: SpeechScript] = [:]
        for script in every {
            let day = Calendar.current.startOfDay(for: script.createdAt)
            if let held = days[day], held.createdAt >= script.createdAt { continue }
            days[day] = script
        }
        return days
    }

    /// `-speechCapture cards|grid` (debug): start the page further down, for captures.
    private static var capture: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "speechCapture")
        #else
        return nil
        #endif
    }

    /// The card a tap grows out of into the challenge's page.
    @Namespace private var zoom

    private func best(_ script: SpeechScript) -> Int? {
        [challenges.standings[script.id]?.myBest, store.best(for: script.id)].compactMap { $0 }.max()
    }

    private func hasTried(_ script: SpeechScript) -> Bool {
        best(script) != nil || (challenges.standings[script.id]?.myAttempts ?? 0) > 0
    }

    private func tries(_ script: SpeechScript) -> Int {
        let s = challenges.standings[script.id]
        return s?.attempts ?? s?.entrants ?? 0
    }

    private var medals: Int { every.compactMap { best($0).flatMap(MedalTier.init(score:)) }.count }

    /// Days in a row with a take, up to today (or yesterday, while today is
    /// still open).
    private var streak: Int {
        let calendar = Calendar.current
        let days = Set(store.takes.map { calendar.startOfDay(for: $0.createdAt) })
        var day = calendar.startOfDay(for: Date())
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if let group = groups.selected {
                // A group plays one challenge at a time (2026-11-14,
                // founder); the medal week and every challenge stay on
                // Everyone.
                SpeechGroupSection(group: group)
            } else {
                if Self.capture == nil {
                    // Mine first: a medal a day, the streak, my place.
                    ArenaMedalCalendar(byDay: byDay, best: best,
                                       rank: challenges.overall?.first(where: \.is_me)?.rank,
                                       medals: medals, streak: streak)
                }
                // Then today's challenge and every challenge (2026-11-13,
                // founder: the podium lives on Ranking).
                if Self.capture != "grid", let today = challenges.live.first {
                    ArenaTicket(script: today, category: challenges.standings[today.id]?.category,
                                best: best(today), tries: tries(today), zoom: zoom)
                }
                allChallenges
            }
        }
        .onAppear {
            MedalScene.warm(scale: displayScale)
            ChallengeArt.warm()
        }
        .foregroundStyle(.white)
        #if DEBUG
        // `-speechOpen 002C`: open that challenge's page, for captures.
        .navigationDestination(item: $debugOpen) { script in
            // Through the same zoom a tap on the ticket takes, so a profile
            // of this open is a profile of the real one.
            SpeechArenaDetail(script: script, zoomID: "ticket-\(script.id)", zoom: zoom).environmentObject(appState)
        }
        .task(id: challenges.scripts.count) {
            guard debugOpen == nil, let key = UserDefaults.standard.string(forKey: "speechOpen") else { return }
            // `-speechOpenAfter 4`: wait first, so a profile can see the open alone.
            let wait = UserDefaults.standard.double(forKey: "speechOpenAfter")
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            debugOpen = every.first { $0.id.uuidString.hasSuffix(key) }
        }
        #endif
    }

    #if DEBUG
    @State private var debugOpen: SpeechScript?
    #endif

    private var medalShelf: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack(alignment: .firstTextBaseline) {
                Text("My medals").font(Arena.display(26))
                Spacer()
                Text(verbatim: "\(medals) / \(every.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Arena.dim)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(every) { script in
                        NavigationLink {
                            SpeechArenaDetail(script: script)
                                .environmentObject(appState)
                        } label: {
                            let score = best(script)
                            VStack(spacing: 8) {
                                MedalBadge(tier: score.flatMap(MedalTier.init(score:)),
                                           label: score.map(String.init) ?? "", size: 60)
                                Text(SpeechChallengeCategory.label(challenges.standings[script.id]?.category) ?? script.title)
                                    .font(.caption2)
                                    .foregroundStyle(Arena.dim)
                                    .lineLimit(1)
                                    .frame(width: 68)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
            Text("90 gold · 85 silver · 80 bronze")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var shown: [SpeechScript] {
        switch filter {
        case .all: return every
        case .popular: return every.filter { tries($0) > 0 }.sorted { tries($0) > tries($1) }
        case .notTried: return every.filter { !hasTried($0) }
        case .tried: return every.filter(hasTried)
        }
    }

    private var allChallenges: some View {
        VStack(alignment: .leading, spacing: 14) {
            #if DEBUG
            // `-speechMedalTest 1`: every tier at the sizes the app draws.
            if UserDefaults.standard.bool(forKey: "speechMedalTest") {
                VStack(spacing: 10) {
                    ForEach([60, 40, 34] as [CGFloat], id: \.self) { size in
                        HStack(spacing: 14) {
                            MedalBadge(tier: .gold, label: "96", size: size)
                            MedalBadge(tier: .silver, label: "88", size: size)
                            MedalBadge(tier: .bronze, label: "82", size: size)
                            MedalBadge(tier: .gold, label: "100", size: size)
                        }
                    }
                }
            }
            #endif
            HStack(alignment: .firstTextBaseline) {
                Text("All challenges").font(Arena.display(26))
                Spacer()
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(SpeechChallengeFilter.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(filter.label)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Arena.dim)
                }
            }
            if shown.isEmpty {
                Text(filter == .tried ? "Nothing read yet." : "You've read them all.")
                    .font(.subheadline)
                    .foregroundStyle(Arena.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(shown) { script in
                        NavigationLink {
                            SpeechArenaDetail(script: script, zoomID: "tile-\(script.id)", zoom: zoom)
                                .environmentObject(appState)
                        } label: {
                            ArenaTile(script: script, category: challenges.standings[script.id]?.category,
                                      best: best(script), tries: tries(script),
                                      ended: challenges.isPast(script.id))
                                .zoomSource("tile-\(script.id)", in: zoom, radius: 30)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Pieces

/// The top three: second · first · third, real medals over them.
struct ArenaPodium: View {
    let rows: [SpeechChallenges.BoardRow]

    var body: some View {
        let top = Array(rows.prefix(3))
        Group {
            if top.isEmpty {
                VStack(spacing: 12) {
                    MicTrophy3D(tier: .gold, label: "1").frame(width: 120, height: 192)
                    Text("Be the first on the board").font(Arena.display(20))
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach([1, 0, 2], id: \.self) { i in
                        if i < top.count { place(top[i]) } else { Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func place(_ row: SpeechChallenges.BoardRow) -> some View {
        let first = row.rank == 1
        let tier = MedalTier(rank: row.rank) ?? .bronze
        return VStack(spacing: 8) {
            MicTrophy3D(tier: tier, label: "\(row.rank)")
                .frame(width: first ? 112 : 84, height: first ? 180 : 136)
            SpeechChallengeFace(face: row.face, size: first ? 60 : 48)
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
            Text(row.display_name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Arena.dim)
                .lineLimit(1)
            Text(verbatim: "\(row.score)")
                .font(Arena.display(first ? 34 : 26))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(first ? Arena.raised : Arena.card))
        .accessibilityElement(children: .combine)
    }
}

/// Where I stand, in one line: place, medals, days in a row.
struct ArenaMeStrip: View {
    let rank: Int?
    let medals: Int
    let total: Int
    let streak: Int
    let avatar: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            SpeechChallengeFace(face: .init(display_name: SpeechChallenges.displayName ?? "?",
                                            avatar: avatar == nil ? SpeechChallenges.avatarPayload() : nil),
                                size: 44, localImage: avatar)
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let rank { Text("#\(rank)") } else { Text("Not ranked yet") }
                }
                .font(Arena.display(20))
                Text("\(medals) medals").font(.subheadline).foregroundStyle(Arena.dim)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(verbatim: "\(streak)").font(Arena.display(24)).monospacedDigit()
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(streak > 0 ? Arena.accent : Arena.dim)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(streak)-day streak"))
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Arena.card))
    }
}
#endif

/// A challenge's picture, drawn once in Dear RoRo's coloured-pencil style
/// (`day-cover-style.json`): the person in that role, on plain paper.
///
/// Served from R2 (2026-11-13, founder: a challenge goes up every day, and a
/// picture that waits for an app build is a day late every day):
/// `speech/pictures/<challenge id>.png` in `nawana-shows`, put there by
/// `scripts/speech-picture-upload.sh`. A picture is fetched the first time
/// its challenge is drawn, kept in Caches, and checked again (ETag) once per
/// launch, so a redrawn picture replaces the old one. The pictures the app
/// was built with stay as the fallback, by the last four of the id.
enum ChallengeArt {
    /// The cards are cream (2026-11-12, founder). Constants: these are read
    /// on every frame of a card's zoom, so nothing here may touch storage.
    /// In nawana's light mode they are white, like every other card there
    /// (2026-11-13, founder); the pictures are transparent, so nothing else
    /// changes. Dark mode and the speech app keep the cream.
    #if SPEECH_APP
    static let paper = cream
    #else
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(cream) : .white
    })
    #endif
    static let cream = Color(red: 251 / 255, green: 248 / 255, blue: 240 / 255)
    static let inkText = Color(red: 0.13, green: 0.12, blue: 0.11)
    /// The button's fill and its label, the opposite of the card.
    static let buttonFill = Color(red: 0.13, green: 0.12, blue: 0.11)
    static let buttonText = Color.white

    static let remoteBase = URL(string: "https://pub-83c97a52f2e549718b126bf60f710f1a.r2.dev/speech/pictures")!

    private static let lock = NSLock()
    /// Bundle pictures by the last four of the id.
    private static var decoded: [String: UIImage] = [:]
    /// Downloaded pictures by the whole id (lowercased).
    private static var remote: [String: UIImage] = [:]
    /// Ids already checked against R2 this launch.
    private static var checked: Set<String> = []

    /// Read by `image(for:)` so a view drawing a picture is drawn again when
    /// one arrives. Reading it costs nothing: no storage, no lock.
    @Observable final class Arrivals { var count = 0 }
    static let arrivals = Arrivals()

    /// The picture, already decoded: the downloaded one, else the one the app
    /// was built with. Never touches storage or the network on the caller's
    /// thread; a picture not checked yet this launch is fetched behind it.
    static func image(for id: UUID) -> UIImage? {
        _ = arrivals.count
        let full = id.uuidString.lowercased()
        let key = String(id.uuidString.suffix(4))
        lock.lock()
        let hit = remote[full] ?? decoded[key]
        let needsCheck = checked.insert(full).inserted
        lock.unlock()
        if needsCheck { Task.detached(priority: .utility) { await refresh(full) } }
        if let hit { return hit }
        guard let image = load(key) else { return nil }
        lock.lock(); decoded[key] = image; lock.unlock()
        return image
    }

    private static func load(_ key: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: "challenge-\(key)", withExtension: "png"),
              let raw = UIImage(contentsOfFile: url.path) else { return nil }
        return raw.preparingForDisplay() ?? raw
    }

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("challenge_art", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Fetches one picture if R2 has a newer one than the cached copy.
    private static func refresh(_ full: String) async {
        let file = cacheDir.appendingPathComponent("\(full).png")
        let tagFile = cacheDir.appendingPathComponent("\(full).etag")
        var req = URLRequest(url: remoteBase.appendingPathComponent("\(full).png"))
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        if FileManager.default.fileExists(atPath: file.path),
           let tag = try? String(contentsOf: tagFile, encoding: .utf8) {
            req.setValue(tag, forHTTPHeaderField: "If-None-Match")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let raw = UIImage(data: data) else { return }
        try? data.write(to: file, options: .atomic)
        if let tag = http.value(forHTTPHeaderField: "ETag") {
            try? tag.write(to: tagFile, atomically: true, encoding: .utf8)
        }
        let image = raw.preparingForDisplay() ?? raw
        lock.lock(); remote[full] = image; lock.unlock()
        await MainActor.run { arrivals.count += 1 }
    }

    /// Decode every picture the app carries, off the main thread, at launch.
    static func warm() {
        Task.detached(priority: .utility) { await prepare() }
    }

    /// The same, awaited: the launch curtain waits on it. Also decodes the
    /// pictures downloaded on earlier launches, so they draw at once.
    static func prepare() async {
        await Task.detached(priority: .userInitiated) {
            let urls = Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: nil) ?? []
            for url in urls {
                let name = url.deletingPathExtension().lastPathComponent
                guard name.hasPrefix("challenge-") else { continue }
                let key = String(name.dropFirst("challenge-".count))
                lock.lock(); let have = decoded[key] != nil; lock.unlock()
                if have { continue }
                if let image = load(key) { lock.lock(); decoded[key] = image; lock.unlock() }
            }
            let cached = (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)) ?? []
            for url in cached where url.pathExtension == "png" {
                let full = url.deletingPathExtension().lastPathComponent
                lock.lock(); let have = remote[full] != nil; lock.unlock()
                if have { continue }
                guard let raw = UIImage(contentsOfFile: url.path) else { continue }
                let image = raw.preparingForDisplay() ?? raw
                lock.lock(); remote[full] = image; lock.unlock()
            }
        }.value
    }
}

/// The newest challenge, large, with the next number to beat.
struct ArenaTicket: View {
    @EnvironmentObject private var appState: AppState
    let script: SpeechScript
    let category: String?
    let best: Int?
    let tries: Int
    var zoom: Namespace.ID? = nil

    private var zoomID: String { "ticket-\(script.id)" }

    private var goal: Text {
        guard let best else { return Text("Gold at 90") }
        if best >= 90 { return Text("Gold won · best \(best)") }
        return Text("Best \(best) · \(90 - best) to gold")
    }

    var body: some View {
        NavigationLink {
            SpeechArenaDetail(script: script, zoomID: zoomID, zoom: zoom).environmentObject(appState)
        } label: {
            VStack(spacing: 10) {
                HStack {
                    Text("Today's challenge")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ChallengeArt.inkText.opacity(0.55))
                    Spacer()
                    // Only a medal won: a locked one read as the challenge
                    // being locked (2026-11-13, founder).
                    if let best, let tier = MedalTier(score: best) {
                        MedalBadge(tier: tier, label: "\(best)", size: 40)
                    }
                }
                .frame(height: 40)
                ChallengeCardFace(script: script, category: category, figureHeight: 240, titleSize: 30, titleLines: 3)
                goal.font(.subheadline).foregroundStyle(ChallengeArt.inkText.opacity(0.65))
                // No button: the whole card opens the page, and the page has
                // its own (2026-11-13, founder: two "Take it on"s in a row).
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(ChallengeArt.paper))
            .zoomSource(zoomID, in: zoom, radius: 44)
        }
        .buttonStyle(.plain)
    }
}

/// One challenge in the grid: the figure filling the card, the title under
/// it, and the medal I hold.
struct ArenaTile: View {
    let script: SpeechScript
    let category: String?
    let best: Int?
    let tries: Int
    let ended: Bool
    var mine: Bool = false

    var body: some View {
        ChallengeCardFace(script: script, category: category, titleSize: 17, mine: mine)
            .padding(.top, 20)
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .aspectRatio(0.66, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(ChallengeArt.paper))
            .overlay(alignment: .topTrailing) {
                if let best, let tier = MedalTier(score: best) {
                    MedalBadge(tier: tier, label: "\(best)", size: 34).padding(8)
                } else if let best {
                    // A score short of a medal is a disc the medal's size, in
                    // the medal's place (2026-11-13, founder: a pill beside
                    // the round medals read as something else).
                    Text(verbatim: "\(best)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(ChallengeArt.inkText.opacity(0.6)))
                        .frame(width: 34, height: 34)
                        .padding(8)
                }
            }
            .opacity(ended ? 0.75 : 1)
    }
}


extension View {
    /// The Challenges tab is a dark stage whatever the phone's mode.
    @ViewBuilder func arenaScheme(_ on: Bool) -> some View {
        if on { self.environment(\.colorScheme, .dark) } else { self }
    }
}
