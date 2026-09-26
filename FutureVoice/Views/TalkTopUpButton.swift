import SwiftUI

/// "Add 100 minutes · ₩7,500" — the one button that sells a talk-minute pack.
/// Drawn wherever a spent pool is met (`DailyAllowanceSheet`) and on the
/// Usage page, so the number and the price come from one place: the pack
/// from `talk_topups`, the price from the App Store. Nothing is drawn until
/// both have answered — a button without a price is a promise nobody
/// priced.
///
/// `prominent` picks the button style: the sheet leads with it, the Usage
/// page lists it as a row. `onPurchased` runs after the minutes are on the
/// account (the gate is already invalidated by then).
struct TalkTopUpButton: View {
    var prominent = true
    var onPurchased: () -> Void = {}

    @StateObject private var store = TalkTopUpService()

    var body: some View {
        Group {
            if let pack = store.pack, let price = pack.localizedPrice {
                Button {
                    Task { await store.purchase() }
                } label: {
                    HStack {
                        if store.state == .purchasing {
                            ProgressView()
                        } else if store.state == .purchased {
                            Label(explain("\(pack.minutes) minutes added"), systemImage: "checkmark")
                        } else {
                            Text(explain("Add \(pack.minutes) minutes · \(price)"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(store.state == .purchasing || store.state == .purchased)
                .modifier(Style(prominent: prominent))
            }
        }
        .task { await store.load() }
        .onChange(of: store.state) { _, state in
            if state == .purchased { onPurchased() }
        }
        .alert(Text(explain("Purchase failed")), isPresented: failedBinding) {
            Button(explain("OK")) { store.state = .idle }
        } message: {
            if case .failed(let msg) = store.state { Text(msg) }
        }
    }

    private var failedBinding: Binding<Bool> {
        Binding(get: {
            if case .failed = store.state { return true }
            return false
        }, set: { if !$0 { store.state = .idle } })
    }

    private struct Style: ViewModifier {
        let prominent: Bool
        func body(content: Content) -> some View {
            if prominent {
                content.buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                content.buttonStyle(.bordered).controlSize(.regular)
            }
        }
    }
}
