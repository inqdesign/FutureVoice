import SwiftUI

/// The fluent self's spoken goodbye, on the wrap-up board while it plays
/// (`CallGoodbye`). The words on screen are what the voice is saying, with
/// the native-language line under them; Stop silences it and leaves the text.
struct CallGoodbyeCard: View {
    let line: CallGoodbye.Line
    let isPlaying: Bool
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Your future self", systemImage: isPlaying ? "speaker.wave.2.fill" : "speaker.wave.2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.themeAccent)
                Spacer(minLength: 8)
                if isPlaying {
                    Button("Stop", action: onStop)
                        .font(.subheadline)
                }
            }
            Text(line.spoken)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if !line.translation.isEmpty {
                Text(line.translation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 24)
    }
}
