import SwiftUI

/// Tab home for reinforcement modes — Drill (SRS) and Shadow. A segmented
/// control switches between them so users can flip mid-session without
/// hopping back to a hub.
struct PracticeTab: View {
    @State private var mode: Mode = .drill

    enum Mode: String, CaseIterable, Identifiable {
        case drill, sessions, shadow
        var id: String { rawValue }
        var label: String {
            switch self {
            case .drill:    return "Due"
            case .sessions: return "Sessions"
            case .shadow:   return "Shadow"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)

                Group {
                    switch mode {
                    case .drill:    DrillView()
                    case .sessions: DrillsBySessionView()
                    case .shadow:   ShadowBrowserView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
