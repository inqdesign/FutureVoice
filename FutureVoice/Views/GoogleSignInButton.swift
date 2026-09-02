import SwiftUI

/// Sibling of `SignInWithAppleButton`, drawn to its metrics so the two stack
/// at equal height. The Apple control is system-rendered and can't be
/// restyled, and no SwiftUI button style reproduces its exact box (`.bordered`
/// adds its own padding on top of any label frame), so this one matches IT:
/// same capsule, same black/white fill flipped per scheme, title scaled the
/// way the Apple button scales its own.
struct GoogleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme
    var height: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Continue with Google")
                .font(.system(size: height * 0.37, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
        .foregroundStyle(colorScheme == .dark ? .black : .white)
        .background(colorScheme == .dark ? Color.white : Color.black, in: Capsule())
    }
}
