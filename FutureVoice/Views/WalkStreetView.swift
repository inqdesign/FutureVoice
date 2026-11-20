import SwiftUI
import SceneKit

/// Walk mode's street, drawn by us (2026-11-16, founder: "build the Soho
/// street as a street, like really walking"). First person, one metre per
/// unit, the real route straightened into one line: the real places stand
/// where they are along it, under their real names, and everything between
/// them is filler. Only the names and the order are real; the buildings are
/// stock shapes. Prototype.
struct WalkStreetView: UIViewRepresentable {
    let stops: [WalkStop]
    let total: Double
    let walked: Double
    let heard: Set<String>
    /// The place the walker has reached: the camera turns to its door.
    let arrived: WalkStop?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.antialiasingMode = .multisampling4X
        view.isUserInteractionEnabled = false
        view.backgroundColor = Street.horizon
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        let key = stops.map(\.id).joined(separator: "|") + "\(Int(total))"
        if c.key != key {
            c.key = key
            c.build(stops: stops, total: total)
            view.scene = c.scene
            view.pointOfView = c.camera
            c.place(walked: walked, arrived: arrived, animated: false)
        } else {
            c.place(walked: walked, arrived: arrived, animated: true)
        }
        for (id, node) in c.markers { node.isHidden = heard.contains(id) }
    }

    @MainActor
    final class Coordinator {
        var key = ""
        var scene = SCNScene()
        let camera = SCNNode()
        var markers: [String: SCNNode] = [:]
        private var sides: [String: Float] = [:]
        private var facing: String?

        func build(stops: [WalkStop], total: Double) {
            scene = SCNScene()
            markers = [:]
            sides = [:]
            scene.background.contents = Street.sky()
            scene.fogColor = Street.horizon
            scene.fogStartDistance = 60
            scene.fogEndDistance = 210

            let cam = SCNCamera()
            cam.fieldOfView = 74
            cam.zNear = 0.2
            cam.zFar = 400
            cam.screenSpaceAmbientOcclusionIntensity = 0.9
            cam.screenSpaceAmbientOcclusionRadius = 1.2
            camera.camera = cam
            scene.rootNode.addChildNode(camera)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 520
            ambient.light?.color = UIColor(red: 0.86, green: 0.9, blue: 1, alpha: 1)
            scene.rootNode.addChildNode(ambient)
            // A low sun from one side: one pavement in the light, the other
            // in the buildings' shade. Most of the depth comes from this.
            let sun = SCNNode()
            let light = SCNLight()
            light.type = .directional
            light.intensity = 900
            light.color = UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
            light.castsShadow = true
            light.shadowMode = .deferred
            light.shadowColor = UIColor(white: 0, alpha: 0.42)
            light.shadowRadius = 3
            light.shadowSampleCount = 8
            light.shadowMapSize = CGSize(width: 2048, height: 2048)
            light.maximumShadowDistance = 90
            light.shadowCascadeCount = 2
            sun.light = light
            sun.eulerAngles = SCNVector3(-0.85, 0.7, 0)
            scene.rootNode.addChildNode(sun)

            let length = CGFloat(total) + 120
            let midZ = -Float(total) / 2 - 20
            ground(width: Street.road, length: length, x: 0, y: 0, z: midZ,
                   image: Street.asphalt(), tile: 4)
            for side in [Float(-1), 1] {
                let x = side * Float(Street.road / 2 + Street.pavement / 2)
                let kerb = SCNBox(width: Street.pavement, height: 0.14, length: length, chamferRadius: 0)
                kerb.firstMaterial?.diffuse.contents = UIColor(white: 0.62, alpha: 1)
                let node = SCNNode(geometry: kerb)
                node.position = SCNVector3(x, 0.07, midZ)
                scene.rootNode.addChildNode(node)
                ground(width: Street.pavement, length: length, x: x, y: 0.142, z: midZ,
                       image: Street.slabs(), tile: 1.1)
                // Double yellow lines along the kerb.
                for offset in [0.16, 0.36] {
                    let line = SCNPlane(width: 0.09, height: length)
                    line.firstMaterial?.diffuse.contents = UIColor(red: 0.93, green: 0.76, blue: 0.2, alpha: 1)
                    let lineNode = SCNNode(geometry: line)
                    lineNode.eulerAngles.x = -.pi / 2
                    lineNode.position = SCNVector3(side * Float(Double(Street.road) / 2 - offset), 0.006, midZ)
                    scene.rootNode.addChildNode(lineNode)
                }
            }

            var rng = Street.Seeded(seed: UInt64(bitPattern: Int64(key.hashValue)) | 1)
            let houses = (0..<26).map { _ in Street.Design.random(shop: false, using: &rng) }
            let overShops = (0..<8).map { _ in Street.Design.random(shop: true, using: &rng) }
            // Real places alternate sides, so the street reads on both.
            for (i, stop) in stops.enumerated() { sides[stop.id] = i.isMultiple(of: 2) ? -1 : 1 }
            for side in [Float(-1), 1] {
                var cursor = -20.0
                let mine = stops.filter { sides[$0.id] == side }.sorted { $0.along < $1.along }
                for stop in mine {
                    fill(from: cursor, to: stop.along - Street.shopWidth / 2, side: side, designs: houses, rng: &rng)
                    shop(stop, side: side, design: overShops[Int.random(in: 0..<overShops.count, using: &rng)], rng: &rng)
                    cursor = max(cursor, stop.along + Street.shopWidth / 2)
                }
                fill(from: cursor, to: total + 80, side: side, designs: houses, rng: &rng)
            }
            // Street lamps, and the odd tree.
            var z = 12.0
            var lampSide: Float = -1
            while z < total + 40 {
                lamp(at: z, side: lampSide)
                z += Double.random(in: 30...40, using: &rng)
                lampSide = -lampSide
            }
            z = 40.0
            var treeSide: Float = 1
            while z < total + 40 {
                tree(at: z, side: treeSide)
                z += Double.random(in: 55...95, using: &rng)
                treeSide = -treeSide
            }
        }

        /// A textured strip of ground, tiled every `tile` metres.
        private func ground(width: CGFloat, length: CGFloat, x: Float, y: Float, z: Float, image: UIImage, tile: CGFloat) {
            let plane = SCNPlane(width: width, height: length)
            let m = plane.firstMaterial!
            m.diffuse.contents = image
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.mipFilter = .linear
            m.diffuse.maxAnisotropy = 8
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(width / tile), Float(length / tile), 1)
            let node = SCNNode(geometry: plane)
            node.eulerAngles.x = -.pi / 2
            node.position = SCNVector3(x, y, z)
            node.castsShadow = false
            scene.rootNode.addChildNode(node)
        }

        /// Filler buildings between the real places.
        private func fill(from start: Double, to end: Double, side: Float, designs: [Street.Design], rng: inout Street.Seeded) {
            var cursor = start
            var last = -1
            while end - cursor > 0.3 {
                let left = end - cursor
                if left < 4.5 {
                    // Too narrow for a house: a gated passage between two.
                    passage(centre: cursor + left / 2, width: left, side: side)
                    return
                }
                var pick = Int.random(in: 0..<designs.count, using: &rng)
                if pick == last { pick = (pick + 1) % designs.count }
                last = pick
                let design = designs[pick]
                var width = Double(design.bays) * Double.random(in: 2.35...2.9, using: &rng)
                if left - width < 4.5 { width = min(left, width * 1.35) }
                building(design, centre: cursor + width / 2, width: width, side: side)
                cursor += width
            }
        }

        private func passage(centre: Double, width: Double, side: Float) {
            let box = SCNBox(width: 10, height: 3.4, length: width, chamferRadius: 0)
            box.firstMaterial?.diffuse.contents = UIColor(white: 0.17, alpha: 1)
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(side * Float(Street.wall + 5.6), 1.7, -Float(centre))
            scene.rootNode.addChildNode(node)
        }

        private func building(_ design: Street.Design, centre: Double, width: Double, side: Float) {
            let depth = 10.0
            let height = design.height
            let box = SCNBox(width: depth, height: height, length: width, chamferRadius: 0)
            let plain = SCNMaterial()
            plain.diffuse.contents = Street.styles[design.style].side
            let face = SCNMaterial()
            face.diffuse.contents = Street.facade(design)
            face.diffuse.mipFilter = .linear
            face.diffuse.maxAnisotropy = 8
            // Box faces: front, right (+x), back, left (-x), top, bottom.
            // The street is on +x for a left-hand building, -x for a right one.
            var materials = Array(repeating: plain, count: 6)
            materials[side < 0 ? 1 : 3] = face
            box.materials = materials
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(side * Float(Street.wall + depth / 2), Float(height / 2), -Float(centre))
            scene.rootNode.addChildNode(node)

            // A cornice that stands out from the wall, so the roofline has
            // an edge and throws a shadow.
            let trim = Street.styles[design.style].trim
            let cornice = SCNBox(width: 0.38, height: 0.3, length: width + 0.04, chamferRadius: 0)
            cornice.firstMaterial?.diffuse.contents = trim
            let corniceNode = SCNNode(geometry: cornice)
            corniceNode.position = SCNVector3(side * Float(Street.wall - 0.19), Float(height - Street.parapet), -Float(centre))
            scene.rootNode.addChildNode(corniceNode)
            if !design.isShop {
                let band = SCNBox(width: 0.2, height: 0.18, length: width + 0.02, chamferRadius: 0)
                band.firstMaterial?.diffuse.contents = trim
                let bandNode = SCNNode(geometry: band)
                bandNode.position = SCNVector3(side * Float(Street.wall - 0.1), Float(Street.groundFloor), -Float(centre))
                scene.rootNode.addChildNode(bandNode)
            }
        }

        /// A real place: a shopfront under its own name, an awning, a sign
        /// that faces the walker, and a marker until it has been heard.
        private func shop(_ stop: WalkStop, side: Float, design: Street.Design, rng: inout Street.Seeded) {
            let colour = Street.shopColours[Int.random(in: 0..<Street.shopColours.count, using: &rng)]
            building(design, centre: stop.along, width: Street.shopWidth, side: side)
            let z = -Float(stop.along)

            let front = SCNPlane(width: Street.shopWidth, height: 4)
            front.firstMaterial?.diffuse.contents = Street.shopfront(name: stop.name, colour: colour)
            front.firstMaterial?.diffuse.mipFilter = .linear
            front.firstMaterial?.diffuse.maxAnisotropy = 8
            let frontNode = SCNNode(geometry: front)
            frontNode.position = SCNVector3(side * Float(Street.wall - 0.03), 2, z)
            frontNode.eulerAngles.y = side < 0 ? .pi / 2 : -.pi / 2
            frontNode.castsShadow = false
            scene.rootNode.addChildNode(frontNode)

            let awning = SCNBox(width: 1.5, height: 0.08, length: Street.shopWidth - 0.6, chamferRadius: 0)
            awning.firstMaterial?.diffuse.contents = Street.stripes(colour)
            awning.firstMaterial?.diffuse.wrapS = .repeat
            awning.firstMaterial?.diffuse.contentsTransform = SCNMatrix4MakeScale(1, 1, 1)
            let awningNode = SCNNode(geometry: awning)
            // Under the fascia, so the name above it stays readable.
            awningNode.position = SCNVector3(side * Float(Street.wall - 0.75), 2.72, z)
            awningNode.eulerAngles.z = side * 0.16
            scene.rootNode.addChildNode(awningNode)

            // The hanging sign: square to the street, so the name can be
            // read from far down it.
            let blade = SCNPlane(width: 2.4, height: 1.1)
            blade.firstMaterial?.diffuse.contents = Street.blade(name: stop.name, symbol: stop.symbol, colour: colour)
            blade.firstMaterial?.lightingModel = .constant
            blade.firstMaterial?.isDoubleSided = true
            let bladeNode = SCNNode(geometry: blade)
            bladeNode.position = SCNVector3(side * Float(Street.wall - 1.5), 4.9, z + Float(Street.shopWidth / 2) - 0.4)
            scene.rootNode.addChildNode(bladeNode)

            let pin = SCNSphere(radius: 0.3)
            pin.firstMaterial?.diffuse.contents = UIColor.systemBlue
            pin.firstMaterial?.emission.contents = UIColor.systemBlue
            let pinNode = SCNNode(geometry: pin)
            pinNode.castsShadow = false
            pinNode.position = SCNVector3(side * Float(Street.wall - 1.5), 6.2, z + Float(Street.shopWidth / 2) - 0.4)
            pinNode.runAction(.repeatForever(.sequence([
                .moveBy(x: 0, y: 0.35, z: 0, duration: 0.9),
                .moveBy(x: 0, y: -0.35, z: 0, duration: 0.9),
            ])))
            scene.rootNode.addChildNode(pinNode)
            markers[stop.id] = pinNode
        }

        private func lamp(at along: Double, side: Float) {
            let x = side * Float(Street.road / 2 + 0.4)
            let black = UIColor(white: 0.1, alpha: 1)
            let post = SCNCylinder(radius: 0.06, height: 4.6)
            post.firstMaterial?.diffuse.contents = black
            let postNode = SCNNode(geometry: post)
            postNode.position = SCNVector3(x, 2.3, -Float(along))
            scene.rootNode.addChildNode(postNode)
            let base = SCNCylinder(radius: 0.11, height: 0.9)
            base.firstMaterial?.diffuse.contents = black
            let baseNode = SCNNode(geometry: base)
            baseNode.position = SCNVector3(x, 0.45, -Float(along))
            scene.rootNode.addChildNode(baseNode)
            let lantern = SCNBox(width: 0.3, height: 0.44, length: 0.3, chamferRadius: 0.04)
            lantern.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.93, blue: 0.74, alpha: 1)
            lantern.firstMaterial?.emission.contents = UIColor(red: 0.9, green: 0.78, blue: 0.5, alpha: 1)
            let lanternNode = SCNNode(geometry: lantern)
            lanternNode.position = SCNVector3(x, 4.82, -Float(along))
            scene.rootNode.addChildNode(lanternNode)
            let cap = SCNPyramid(width: 0.42, height: 0.2, length: 0.42)
            cap.firstMaterial?.diffuse.contents = black
            let capNode = SCNNode(geometry: cap)
            capNode.position = SCNVector3(x, 5.04, -Float(along))
            scene.rootNode.addChildNode(capNode)
        }

        private func tree(at along: Double, side: Float) {
            let x = side * Float(Street.road / 2 + 0.55)
            let trunk = SCNCylinder(radius: 0.1, height: 3)
            trunk.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.24, blue: 0.19, alpha: 1)
            let trunkNode = SCNNode(geometry: trunk)
            trunkNode.position = SCNVector3(x, 1.5, -Float(along))
            scene.rootNode.addChildNode(trunkNode)
            let green = UIColor(red: 0.3, green: 0.47, blue: 0.27, alpha: 1)
            for (dx, dy, dz, r) in [(0.0, 3.7, 0.0, 1.05), (0.5, 3.3, 0.4, 0.8), (-0.45, 3.4, -0.35, 0.85), (0.1, 4.4, -0.2, 0.7)] {
                let crown = SCNSphere(radius: r)
                crown.segmentCount = 14
                crown.firstMaterial?.diffuse.contents = green
                let node = SCNNode(geometry: crown)
                node.position = SCNVector3(x + Float(dx), Float(dy), -Float(along) + Float(dz))
                scene.rootNode.addChildNode(node)
            }
        }

        /// Walking: down the middle, eyes forward, a small bob per step.
        /// Arrived: a few steps short of the place, turned to its door.
        func place(walked: Double, arrived: WalkStop?, animated: Bool) {
            var position = SCNVector3(0, 1.65 + Float(sin(walked * 2 * .pi / 1.5)) * 0.03, -Float(walked))
            var yaw: Float = 0
            if let stop = arrived, let side = sides[stop.id] {
                position = SCNVector3(-side * 2.2, 1.65, -Float(stop.along) + 10)
                yaw = -side * 0.62
            }
            // Step counts arrive every couple of seconds, in a lump. Gliding
            // over the lump at walking pace is what makes it read as walking
            // instead of jumping.
            let moved = abs(Double(position.z - camera.position.z))
            let turning = (arrived?.id) != facing
            facing = arrived?.id
            let duration = turning ? 1.4 : min(3.0, max(0.6, moved / 1.4))
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? duration : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: turning ? .easeInEaseOut : .linear)
            camera.position = position
            camera.eulerAngles = SCNVector3(0.05, yaw, 0)
            SCNTransaction.commit()
        }
    }
}

/// Sizes, colours and the drawn textures of the street.
enum Street {
    static let road: CGFloat = 5
    static let pavement: CGFloat = 2.2
    /// Distance from the centre line to the building line.
    static var wall: Double { Double(road / 2 + pavement) }
    static let shopWidth: Double = 10
    static let groundFloor: Double = 3.6
    static let storey: Double = 3.1
    static let parapet: Double = 0.9
    static let horizon = UIColor(red: 0.84, green: 0.88, blue: 0.92, alpha: 1)

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }

    /// What a house is built of.
    struct Style {
        let wall: UIColor
        let side: UIColor
        let trim: UIColor
        let brick: Bool
        let modern: Bool
    }

    static let styles: [Style] = [
        Style(wall: rgb(0.60, 0.35, 0.28), side: rgb(0.50, 0.30, 0.25), trim: rgb(0.92, 0.90, 0.85), brick: true, modern: false),   // red brick
        Style(wall: rgb(0.70, 0.60, 0.43), side: rgb(0.58, 0.50, 0.37), trim: rgb(0.95, 0.94, 0.90), brick: true, modern: false),   // London stock
        Style(wall: rgb(0.40, 0.28, 0.25), side: rgb(0.33, 0.24, 0.22), trim: rgb(0.84, 0.81, 0.75), brick: true, modern: false),   // dark brick
        Style(wall: rgb(0.91, 0.88, 0.80), side: rgb(0.78, 0.75, 0.69), trim: rgb(0.98, 0.97, 0.94), brick: false, modern: false),  // cream stucco
        Style(wall: rgb(0.77, 0.81, 0.82), side: rgb(0.65, 0.69, 0.70), trim: rgb(0.96, 0.97, 0.97), brick: false, modern: false),  // painted
        Style(wall: rgb(0.30, 0.32, 0.35), side: rgb(0.26, 0.28, 0.30), trim: rgb(0.62, 0.65, 0.68), brick: false, modern: true),   // office
    ]

    /// One house front. A street is built from a small pool of these, so
    /// the textures stay a few dozen however long the walk is.
    struct Design: Hashable {
        let style: Int
        let bays: Int
        let storeys: Int
        /// 0 house door, 1 closed shop, 2 pub, 3 shutter. -1: a real place
        /// goes here, so the ground floor is left to its own shopfront.
        let ground: Int
        let seed: Int

        var isShop: Bool { ground < 0 }
        var height: Double { Street.groundFloor + Double(storeys) * Street.storey + Street.parapet }

        static func random(shop: Bool, using rng: inout Seeded) -> Design {
            // Brick is most of Soho; an office block now and then.
            let style = [0, 0, 1, 1, 2, 3, 3, 4, 5][Int.random(in: 0..<9, using: &rng)]
            return Design(style: style,
                          bays: shop ? 4 : Int.random(in: 2...4, using: &rng),
                          storeys: Int.random(in: 3...(style == 5 ? 5 : 4), using: &rng),
                          ground: shop ? -1 : [0, 0, 1, 1, 2, 3][Int.random(in: 0..<6, using: &rng)],
                          seed: Int.random(in: 0..<10_000, using: &rng))
        }
    }

    static let shopColours: [UIColor] = [
        rgb(0.10, 0.25, 0.22), rgb(0.50, 0.11, 0.13), rgb(0.11, 0.17, 0.33),
        rgb(0.13, 0.13, 0.14), rgb(0.70, 0.48, 0.10), rgb(0.22, 0.30, 0.20),
    ]

    private static let doorColours: [UIColor] = [
        rgb(0.08, 0.08, 0.09), rgb(0.55, 0.10, 0.12), rgb(0.10, 0.18, 0.36),
        rgb(0.12, 0.30, 0.22), rgb(0.85, 0.68, 0.16),
    ]

    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            var x = state
            x ^= x >> 33
            x = x &* 0xff51afd7ed558ccd
            x ^= x >> 33
            return x
        }
    }

    /// Textures are drawn at one pixel per point: the default (the screen's
    /// scale) makes each nine times the memory.
    private static func image(_ size: CGSize, _ draw: (CGContext) -> Void) -> UIImage {
        // An RGBA bitmap of our own: the renderer hands back a one-channel
        // image for a grey drawing (the road, the slabs), which Metal
        // refuses as a texture on the simulator.
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return UIImage() }
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        draw(ctx)
        UIGraphicsPopContext()
        return ctx.makeImage().map { UIImage(cgImage: $0) } ?? UIImage()
    }

    private static func fill(_ colour: UIColor, _ rect: CGRect) {
        colour.setFill()
        UIRectFillUsingBlendMode(rect, .normal)
    }

    private static func gradient(_ ctx: CGContext, _ rect: CGRect, _ top: UIColor, _ bottom: UIColor) {
        ctx.saveGState()
        ctx.clip(to: rect)
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.minY),
                               end: CGPoint(x: rect.minX, y: rect.maxY), options: [])
        ctx.restoreGState()
    }

    static func sky() -> UIImage {
        image(CGSize(width: 16, height: 256)) { ctx in
            gradient(ctx, CGRect(x: 0, y: 0, width: 16, height: 256), rgb(0.50, 0.66, 0.86), horizon)
            fill(horizon, CGRect(x: 0, y: 160, width: 16, height: 96))
        }
    }

    static func asphalt() -> UIImage {
        image(CGSize(width: 256, height: 256)) { _ in
            fill(UIColor(white: 0.27, alpha: 1), CGRect(x: 0, y: 0, width: 256, height: 256))
            var rng = Seeded(seed: 77)
            for _ in 0..<2600 {
                let w = CGFloat.random(in: 0.2...0.42, using: &rng)
                fill(UIColor(white: w, alpha: 0.5),
                     CGRect(x: CGFloat.random(in: 0..<256, using: &rng), y: CGFloat.random(in: 0..<256, using: &rng), width: 2, height: 2))
            }
        }
    }

    /// Two paving slabs by two, 1.1 m across.
    static func slabs() -> UIImage {
        image(CGSize(width: 128, height: 128)) { _ in
            var rng = Seeded(seed: 31)
            for row in 0..<2 {
                for col in 0..<2 {
                    fill(UIColor(white: CGFloat.random(in: 0.64...0.71, using: &rng), alpha: 1),
                         CGRect(x: col * 64, y: row * 64, width: 64, height: 64))
                }
            }
            let joint = UIColor(white: 0.45, alpha: 1)
            for i in 0..<2 {
                fill(joint, CGRect(x: CGFloat(i) * 64, y: 0, width: 2, height: 128))
                fill(joint, CGRect(x: 0, y: CGFloat(i) * 64, width: 128, height: 2))
            }
        }
    }

    static func stripes(_ colour: UIColor) -> UIImage {
        image(CGSize(width: 64, height: 512)) { _ in
            fill(colour, CGRect(x: 0, y: 0, width: 64, height: 512))
            for i in stride(from: 0, to: 512, by: 64) {
                fill(UIColor(white: 0.95, alpha: 1), CGRect(x: 0, y: i, width: 64, height: 32))
            }
        }
    }

    private static var facades: [Design: UIImage] = [:]
    /// Pixels per metre of a house front.
    private static let px: CGFloat = 40

    /// A whole house front: parapet, storeys of sash windows, and a ground
    /// floor.
    static func facade(_ d: Design) -> UIImage {
        if let made = facades[d] { return made }
        let s = styles[d.style]
        let bay: CGFloat = 104
        let W = CGFloat(d.bays) * bay
        let H = CGFloat(d.height) * px
        var rng = Seeded(seed: UInt64(d.seed * 7919 + d.style * 31 + d.bays * 131 + d.storeys * 17 + 1))
        let made = image(CGSize(width: W, height: H)) { ctx in
            fill(s.wall, CGRect(x: 0, y: 0, width: W, height: H))
            if s.brick {
                // Courses, and a scatter of darker and lighter bricks.
                for y in stride(from: CGFloat(0), to: H, by: 3) {
                    fill(UIColor(white: 0, alpha: 0.08), CGRect(x: 0, y: y, width: W, height: 1))
                }
                for _ in 0..<Int(W * H / 90) {
                    let light = Bool.random(using: &rng)
                    fill(UIColor(white: light ? 1 : 0, alpha: light ? 0.06 : 0.1),
                         CGRect(x: CGFloat.random(in: 0..<W, using: &rng),
                                y: floor(CGFloat.random(in: 0..<H, using: &rng) / 3) * 3 + 1, width: 7, height: 2))
                }
            }
            // Grime: darker toward the street.
            gradient(ctx, CGRect(x: 0, y: 0, width: W, height: H), UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.16))

            let top = CGFloat(parapet) * px
            fill(s.trim, CGRect(x: 0, y: 0, width: W, height: 7))
            fill(UIColor(white: 0, alpha: 0.2), CGRect(x: 0, y: top + 6, width: W, height: 5))

            for storey in 0..<d.storeys {
                let floorY = top + CGFloat(storey + 1) * CGFloat(Street.storey) * px
                let isTop = storey == 0
                for b in 0..<d.bays {
                    let cx = (CGFloat(b) + 0.5) * bay
                    if s.modern {
                        let frame = CGRect(x: cx - 44, y: floorY - 112, width: 88, height: 96)
                        fill(s.trim, frame.insetBy(dx: -3, dy: -3))
                        gradient(ctx, frame, rgb(0.62, 0.74, 0.84), rgb(0.24, 0.31, 0.38))
                        fill(s.trim, CGRect(x: frame.midX - 1.5, y: frame.minY, width: 3, height: frame.height))
                        if Int.random(in: 0..<5, using: &rng) == 0 {
                            fill(rgb(1, 0.9, 0.66, 0.5), frame.insetBy(dx: 4, dy: 4))
                        }
                        continue
                    }
                    let wh: CGFloat = isTop ? 56 : 78
                    let frame = CGRect(x: cx - 23, y: floorY - 32 - wh, width: 46, height: wh)
                    window(ctx, frame, style: s, rng: &rng)
                }
            }

            guard d.ground >= 0 else { return }
            let gy = H - CGFloat(groundFloor) * px
            let g = CGRect(x: 0, y: gy, width: W, height: H - gy)
            switch d.ground {
            case 0: house(ctx, g, bays: d.bays, bay: bay, style: s, rng: &rng)
            case 3: shutter(ctx, g, style: s, rng: &rng)
            default: closedShop(ctx, g, pub: d.ground == 2, rng: &rng)
            }
            fill(UIColor(white: 0.12, alpha: 1), CGRect(x: 0, y: H - 6, width: W, height: 6))
        }
        facades[d] = made
        return made
    }

    /// A sash window: reveal, glass that reflects the sky, glazing bars, a
    /// sill, and a brick arch over it.
    private static func window(_ ctx: CGContext, _ frame: CGRect, style s: Style, rng: inout Seeded) {
        if s.brick {
            fill(rgb(0.74, 0.44, 0.33, 0.9), CGRect(x: frame.minX - 6, y: frame.minY - 13, width: frame.width + 12, height: 9))
        } else {
            fill(s.trim, CGRect(x: frame.minX - 8, y: frame.minY - 12, width: frame.width + 16, height: 7))
        }
        fill(s.trim, frame.insetBy(dx: -4, dy: -4))
        gradient(ctx, frame, rgb(0.58, 0.69, 0.78), rgb(0.17, 0.21, 0.26))
        switch Int.random(in: 0..<7, using: &rng) {
        case 0: fill(rgb(1, 0.86, 0.58, 0.75), frame)                                   // a light on
        case 1, 2: fill(rgb(0.93, 0.91, 0.84, 0.9), CGRect(x: frame.minX, y: frame.minY, width: frame.width,
                                                             height: frame.height * CGFloat.random(in: 0.3...0.6, using: &rng)))   // a blind
        default: break
        }
        // Bars: the meeting rail, and six panes over six.
        fill(s.trim, CGRect(x: frame.minX, y: frame.midY - 1.5, width: frame.width, height: 3))
        for i in 1...2 {
            fill(s.trim, CGRect(x: frame.minX + frame.width * CGFloat(i) / 3 - 0.75, y: frame.minY, width: 1.5, height: frame.height))
        }
        fill(s.trim, CGRect(x: frame.minX, y: frame.minY + frame.height / 4 - 0.75, width: frame.width, height: 1.5))
        fill(s.trim, CGRect(x: frame.minX, y: frame.minY + frame.height * 3 / 4 - 0.75, width: frame.width, height: 1.5))
        fill(s.trim, CGRect(x: frame.minX - 7, y: frame.maxY + 4, width: frame.width + 14, height: 5))
        fill(UIColor(white: 0, alpha: 0.25), CGRect(x: frame.minX - 7, y: frame.maxY + 9, width: frame.width + 14, height: 3))
    }

    /// A front door with a fanlight, and a window in every other bay.
    private static func house(_ ctx: CGContext, _ g: CGRect, bays: Int, bay: CGFloat, style s: Style, rng: inout Seeded) {
        let base = s.modern ? rgb(0.2, 0.21, 0.23) : rgb(0.93, 0.92, 0.88)
        fill(base, g)
        for y in stride(from: g.minY + 18, to: g.maxY, by: 18) {
            fill(UIColor(white: 0, alpha: 0.1), CGRect(x: 0, y: y, width: g.width, height: 1.5))
        }
        gradient(ctx, g, UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.14))
        let doorBay = Int.random(in: 0..<bays, using: &rng)
        let stucco = Style(wall: base, side: base, trim: rgb(0.98, 0.98, 0.96), brick: false, modern: false)
        for b in 0..<bays {
            let cx = (CGFloat(b) + 0.5) * bay
            if b == doorBay {
                let door = CGRect(x: cx - 21, y: g.maxY - 94, width: 42, height: 88)
                fill(rgb(0.98, 0.98, 0.96), CGRect(x: door.minX - 7, y: door.minY - 30, width: door.width + 14, height: door.height + 30))
                gradient(ctx, CGRect(x: door.minX, y: door.minY - 24, width: door.width, height: 20), rgb(0.6, 0.7, 0.78), rgb(0.25, 0.3, 0.35))
                let colour = doorColours[Int.random(in: 0..<doorColours.count, using: &rng)]
                fill(colour, door)
                fill(UIColor(white: 1, alpha: 0.1), door.insetBy(dx: 7, dy: 8).divided(atDistance: 30, from: .minYEdge).slice)
                fill(UIColor(white: 0, alpha: 0.18), door.insetBy(dx: 7, dy: 8).divided(atDistance: 36, from: .minYEdge).remainder)
                fill(rgb(0.85, 0.7, 0.3), CGRect(x: door.maxX - 10, y: door.midY, width: 4, height: 4))
                fill(UIColor(white: 0.55, alpha: 1), CGRect(x: door.minX - 9, y: door.maxY, width: door.width + 18, height: 6))
            } else {
                window(ctx, CGRect(x: cx - 23, y: g.maxY - 112, width: 46, height: 76), style: stucco, rng: &rng)
            }
        }
    }

    /// A shop with no name on it: fascia, glass, a door to one side.
    private static func closedShop(_ ctx: CGContext, _ g: CGRect, pub: Bool, rng: inout Seeded) {
        let colour = shopColours[Int.random(in: 0..<shopColours.count, using: &rng)]
        fill(colour, g)
        gradient(ctx, g, UIColor(white: 1, alpha: 0.06), UIColor(white: 0, alpha: 0.2))
        // Fascia with a thin line round it.
        let fascia = CGRect(x: 0, y: g.minY, width: g.width, height: 30)
        fill(rgb(0.86, 0.72, 0.36, pub ? 0.9 : 0.35), fascia.insetBy(dx: 8, dy: 6))
        fill(colour, fascia.insetBy(dx: 9.5, dy: 7.5))
        let doorLeft = Bool.random(using: &rng)
        let doorW: CGFloat = 40
        let glass = CGRect(x: doorLeft ? 14 + doorW + 8 : 14, y: g.minY + 40, width: g.width - 28 - doorW - 8, height: g.height - 40 - 26)
        if pub {
            gradient(ctx, glass, rgb(0.5, 0.56, 0.58), rgb(0.72, 0.7, 0.6))
            fill(rgb(0.9, 0.9, 0.86, 0.75), glass.divided(atDistance: glass.height * 0.55, from: .maxYEdge).slice)
        } else {
            gradient(ctx, glass, rgb(0.5, 0.62, 0.7), rgb(0.2, 0.24, 0.28))
            fill(rgb(1, 0.85, 0.55, 0.4), glass.divided(atDistance: glass.height * 0.45, from: .maxYEdge).slice)
        }
        let panes = max(2, Int(glass.width / 60))
        for i in 1..<panes {
            fill(colour, CGRect(x: glass.minX + glass.width * CGFloat(i) / CGFloat(panes) - 2, y: glass.minY, width: 4, height: glass.height))
        }
        let door = CGRect(x: doorLeft ? 14 : g.width - 14 - doorW, y: g.minY + 40, width: doorW, height: g.height - 46)
        fill(UIColor(white: 0.08, alpha: 1), door)
        gradient(ctx, door.insetBy(dx: 6, dy: 6).divided(atDistance: door.height * 0.6, from: .minYEdge).slice,
                 rgb(0.5, 0.6, 0.68), rgb(0.22, 0.26, 0.3))
    }

    /// A service entrance: a roller shutter and a side door.
    private static func shutter(_ ctx: CGContext, _ g: CGRect, style s: Style, rng: inout Seeded) {
        fill(s.brick ? s.wall : rgb(0.8, 0.79, 0.75), g)
        gradient(ctx, g, UIColor(white: 0, alpha: 0.05), UIColor(white: 0, alpha: 0.22))
        let door: CGFloat = 40
        let roll = CGRect(x: 14, y: g.minY + 24, width: g.width - 28 - door - 12, height: g.height - 30)
        fill(UIColor(white: 0.58, alpha: 1), roll)
        for y in stride(from: roll.minY, to: roll.maxY, by: 6) {
            fill(UIColor(white: 0, alpha: 0.22), CGRect(x: roll.minX, y: y, width: roll.width, height: 1.5))
        }
        fill(UIColor(white: 0.3, alpha: 1), CGRect(x: roll.minX, y: roll.minY - 8, width: roll.width, height: 8))
        let side = CGRect(x: g.width - 14 - door, y: g.minY + 44, width: door, height: g.height - 50)
        fill(doorColours[Int.random(in: 0..<doorColours.count, using: &rng)], side)
        fill(UIColor(white: 0, alpha: 0.2), side.insetBy(dx: 6, dy: 8))
    }

    /// A real place's ground floor, 10 m by 4 m: the name on the fascia,
    /// two windows with the lights on, and a door.
    static func shopfront(name: String, colour: UIColor) -> UIImage {
        let size = CGSize(width: 1000, height: 400)
        return image(size) { ctx in
            fill(colour, CGRect(origin: .zero, size: size))
            gradient(ctx, CGRect(origin: .zero, size: size), UIColor(white: 1, alpha: 0.08), UIColor(white: 0, alpha: 0.22))
            let gold = rgb(0.9, 0.76, 0.42)
            // Fascia: a gold line round the name.
            fill(gold, CGRect(x: 22, y: 12, width: 956, height: 100))
            fill(colour, CGRect(x: 25, y: 15, width: 950, height: 94))
            fill(UIColor(white: 0, alpha: 0.3), CGRect(x: 0, y: 118, width: 1000, height: 6))
            // Pilasters.
            for x in [CGFloat(0), 972] {
                fill(UIColor(white: 0, alpha: 0.22), CGRect(x: x, y: 0, width: 28, height: 400))
            }
            for x in [CGFloat(48), 622] {
                let glass = CGRect(x: x, y: 138, width: 330, height: 200)
                fill(UIColor(white: 0.05, alpha: 1), glass.insetBy(dx: -5, dy: -5))
                gradient(ctx, glass, rgb(0.52, 0.64, 0.72), rgb(0.95, 0.8, 0.5))
                // Shelves of things inside.
                for row in 0..<2 {
                    fill(rgb(0.35, 0.24, 0.16, 0.7), CGRect(x: glass.minX + 14, y: glass.maxY - 34 - CGFloat(row) * 52, width: glass.width - 28, height: 5))
                }
                fill(UIColor(white: 1, alpha: 0.14), CGRect(x: glass.minX, y: glass.minY, width: glass.width, height: 60))
                fill(UIColor(white: 0.05, alpha: 1), CGRect(x: glass.midX - 2.5, y: glass.minY, width: 5, height: glass.height))
            }
            // The door, recessed, with a glass panel and a brass handle.
            let door = CGRect(x: 420, y: 128, width: 160, height: 272)
            fill(UIColor(white: 0.07, alpha: 1), door)
            gradient(ctx, CGRect(x: 440, y: 148, width: 120, height: 150), rgb(0.5, 0.62, 0.7), rgb(0.9, 0.78, 0.52))
            fill(gold, CGRect(x: 546, y: 300, width: 8, height: 34))
            fill(UIColor(white: 0.5, alpha: 1), CGRect(x: 410, y: 392, width: 180, height: 8))
            let fonts = ["Georgia-Bold", "AvenirNext-Heavy", "Didot-Bold", "HelveticaNeue-CondensedBold", "Futura-Bold"]
            let font = fonts[name.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % fonts.count }]
            draw(name, in: CGRect(x: 44, y: 18, width: 912, height: 88), size: 62,
                 colour: rgb(0.97, 0.93, 0.82), font: font)
        }
    }

    /// The hanging sign: icon over the name.
    static func blade(name: String, symbol: String, colour: UIColor) -> UIImage {
        let size = CGSize(width: 480, height: 220)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 24).addClip()
            colour.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let config = UIImage.SymbolConfiguration(pointSize: 54, weight: .semibold)
            if let icon = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                icon.draw(at: CGPoint(x: (size.width - icon.size.width) / 2, y: 22))
            }
            draw(name, in: CGRect(x: 20, y: 100, width: 440, height: 104), size: 46, colour: .white, font: nil)
        }
    }

    private static func draw(_ text: String, in rect: CGRect, size: CGFloat, colour: UIColor, font name: String?) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        var fontSize = size
        var attributes: [NSAttributedString.Key: Any] = [:]
        // Shrink a long name until it fits on two lines at most.
        while fontSize > 20 {
            let font = name.flatMap { UIFont(name: $0, size: fontSize) } ?? UIFont.systemFont(ofSize: fontSize, weight: .bold)
            attributes = [.font: font, .foregroundColor: colour, .paragraphStyle: style]
            let box = (text as NSString).boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
            if box.height <= rect.height { break }
            fontSize -= 4
        }
        let height = (text as NSString).boundingRect(
            with: CGSize(width: rect.width, height: rect.height),
            options: .usesLineFragmentOrigin, attributes: attributes, context: nil).height
        (text as NSString).draw(
            with: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
            options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
    }
}
