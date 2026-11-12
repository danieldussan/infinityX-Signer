import SwiftUI

/// Black background with blurred blue/orange flares and a faint giant X.
struct XBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.flareBlue.opacity(0.55), Color.clear],
                           center: .topLeading, startRadius: 0, endRadius: 380)
                .blur(radius: 40)
            RadialGradient(colors: [Theme.flareOrange.opacity(0.40), Color.clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 380)
                .blur(radius: 40)
            Image(systemName: "xmark")
                .font(.system(size: 320, weight: .heavy))
                .foregroundColor(Color.white.opacity(0.04))
        }
        .ignoresSafeArea()
    }
}
