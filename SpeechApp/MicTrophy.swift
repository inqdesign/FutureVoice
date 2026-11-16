import SwiftUI

/// The speech app's trophy is a stand microphone, not a coin (2026-11-12,
/// founder: "it's voice, so a golden stand mic?"). Since 2026-11-16 it is a
/// picture in the challenge pictures' style (gpt-image-2 + the day-cover
/// style, keyed to alpha), not a live SceneKit model: the 3D one read heavy.
/// Silver and bronze are the gold picture recoloured, so the three are one
/// shape. `label` is kept for callers; the podium's order says the place.
struct MicTrophy: View {
    let tier: MedalTier
    var label: String = ""

    var body: some View {
        Image(imageName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .shadow(color: .black.opacity(0.45), radius: 8, y: 6)
            .accessibilityHidden(true)
    }

    private var imageName: String {
        switch tier {
        case .gold: return "trophy-gold"
        case .silver: return "trophy-silver"
        case .bronze: return "trophy-bronze"
        }
    }
}
