import SwiftUI
import SceneKit

/// The speech app's trophy is a stand microphone, not a coin (2026-11-12,
/// founder: "it's voice, so a golden stand mic?"). A round grille head on a
/// yoke, a thin stand and a weighted base with the place struck on a plate.
/// Same metals and studio as the medals (`MedalScene`).
enum MicScene {
    static func make(tier: MedalTier, label: String) -> (SCNScene, SCNNode) {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = MedalScene.environment
        scene.lightingEnvironment.intensity = 1.8

        let polished = metal(tier.metal.withBrightness(1.06), roughness: 0.1)
        let body = metal(tier.metal, roughness: 0.22)
        let grilleMetal = metal(tier.metal.withBrightness(0.62), roughness: 0.55)
        let dark = metal(UIColor(white: 0.12, alpha: 1), roughness: 0.35)

        let mic = SCNNode()

        // Weighted base: a low disc with a rounded lip.
        let base = SCNNode(geometry: SCNCylinder(radius: 0.62, height: 0.1))
        base.geometry?.materials = [body]
        base.position.y = -1.45
        mic.addChildNode(base)
        let lip = SCNNode(geometry: SCNTorus(ringRadius: 0.6, pipeRadius: 0.05))
        lip.geometry?.materials = [polished]
        lip.position.y = -1.42
        mic.addChildNode(lip)
        let dome = SCNNode(geometry: SCNCone(topRadius: 0.1, bottomRadius: 0.42, height: 0.16))
        dome.geometry?.materials = [polished]
        dome.position.y = -1.32
        mic.addChildNode(dome)

        // The place, on a dark plate at the front of the base.
        if !label.isEmpty {
            let plate = SCNNode(geometry: SCNBox(width: 0.34, height: 0.16, length: 0.04, chamferRadius: 0.02))
            plate.geometry?.materials = [dark]
            plate.position = SCNVector3(0, -1.43, 0.6)
            plate.eulerAngles.x = -0.25
            mic.addChildNode(plate)
            let text = SCNText(string: label, extrusionDepth: 1)
            let font = UIFont.systemFont(ofSize: 10, weight: .black)
            text.font = font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 10) } ?? font
            text.flatness = 0.05
            text.materials = [polished]
            let node = SCNNode(geometry: text)
            let (lo, hi) = node.boundingBox
            let s: Float = 0.12 / max(hi.y - lo.y, 1)
            node.scale = SCNVector3(s, s, s)
            let x: Float = -(lo.x + (hi.x - lo.x) / 2) * s
            let y: Float = -(lo.y + (hi.y - lo.y) / 2) * s
            node.position = SCNVector3(x, y, 0.025)
            plate.addChildNode(node)
        }

        // The stand.
        let pole = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 1.25))
        pole.geometry?.materials = [polished]
        pole.position.y = -0.62
        mic.addChildNode(pole)
        let collar = SCNNode(geometry: SCNCylinder(radius: 0.06, height: 0.08))
        collar.geometry?.materials = [body]
        collar.position.y = 0.0
        mic.addChildNode(collar)

        // The yoke holding the head.
        let yoke = SCNNode(geometry: SCNTorus(ringRadius: 0.3, pipeRadius: 0.03))
        yoke.geometry?.materials = [polished]
        yoke.eulerAngles.z = .pi / 2
        yoke.position.y = 0.36
        yoke.scale = SCNVector3(1, 1, 1)
        mic.addChildNode(yoke)

        // The head: a body, then a round grille cage with bands.
        let head = SCNNode()
        head.position.y = 0.42
        head.eulerAngles.x = -0.25
        mic.addChildNode(head)
        let neck = SCNNode(geometry: SCNCylinder(radius: 0.17, height: 0.22))
        neck.geometry?.materials = [body]
        neck.position.y = -0.12
        head.addChildNode(neck)
        let grille = SCNNode(geometry: SCNSphere(radius: 0.26))
        grille.geometry?.materials = [grilleMetal]
        grille.position.y = 0.14
        head.addChildNode(grille)
        for i in -2...2 {
            let y = Float(i) * 0.085
            let r = sqrt(max(0.0, 0.27 * 0.27 - y * y))
            let band = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(r), pipeRadius: 0.012))
            band.geometry?.materials = [polished]
            band.position.y = 0.14 + y
            head.addChildNode(band)
        }
        for angle in [Float(0), .pi / 2] {
            let meridian = SCNNode(geometry: SCNTorus(ringRadius: 0.27, pipeRadius: 0.012))
            meridian.geometry?.materials = [polished]
            meridian.position.y = 0.14
            meridian.eulerAngles = SCNVector3(.pi / 2, angle, 0)
            head.addChildNode(meridian)
        }

        mic.position.y = 0.45
        scene.rootNode.addChildNode(mic)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 34
        camera.position = SCNVector3(0, 0.15, 5.2)
        scene.rootNode.addChildNode(camera)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1100
        key.eulerAngles = SCNVector3(-0.7, -0.6, 0)
        scene.rootNode.addChildNode(key)
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 500
        rim.eulerAngles = SCNVector3(0.5, 2.4, 0)
        scene.rootNode.addChildNode(rim)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 140
        scene.rootNode.addChildNode(fill)
        return (scene, mic)
    }

    private static func metal(_ color: UIColor, roughness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = 1.0
        m.roughness.contents = roughness
        return m
    }
}

/// A live stand mic: it turns slowly on its own, follows a finger, spins on
/// a tap. The view should be about 1.6 times taller than wide.
struct MicTrophy3D: UIViewRepresentable {
    let tier: MedalTier
    var label: String = ""

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        // It turns slowly: 30 frames a second look the same and leave the
        // GPU to the screen (it ran at 120 behind every launch and zoom).
        view.preferredFramesPerSecond = 30
        let (scene, mic) = MicScene.make(tier: tier, label: label)
        view.scene = scene
        view.isPlaying = true
        context.coordinator.node = mic
        let sway = SCNAction.sequence([
            .rotateBy(x: 0, y: 0.5, z: 0, duration: 2.0),
            .rotateBy(x: 0, y: -1.0, z: 0, duration: 4.0),
            .rotateBy(x: 0, y: 0.5, z: 0, duration: 2.0),
        ])
        sway.timingMode = .easeInEaseOut
        mic.runAction(.repeatForever(sway))
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.spin)))
        view.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.turn(_:))))
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    final class Coordinator: NSObject {
        var node: SCNNode?

        @objc func spin() {
            guard let node else { return }
            let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.9)
            spin.timingMode = .easeOut
            node.runAction(spin)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        @objc func turn(_ pan: UIPanGestureRecognizer) {
            guard let node, let view = pan.view else { return }
            let dx = Float(pan.translation(in: view).x) / Float(max(view.bounds.width, 1))
            node.eulerAngles.y += dx * .pi * 2
            pan.setTranslation(.zero, in: view)
        }
    }
}
