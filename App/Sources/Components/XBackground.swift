import SwiftUI

/// Black background with two slowly drifting blurred flares (blue / orange) and a faint light streak.
struct XBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            Theme.background

            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(Theme.blue)
                    .frame(width: 340, height: 340)
                    .blur(radius: 70)
                    .opacity(0.55)
                    .offset(x: -130 + (drift ? 40 : 0), y: -120 + (drift ? 50 : 0))
                    .scaleEffect(drift ? 1.15 : 1)
                Rectangle()
                    .fill(LinearGradient(colors: [Color.clear, Color.white.opacity(0.8), Color.clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 280, height: 2)
                    .blur(radius: 1)
                    .opacity(0.5)
                    .rotationEffect(.degrees(-24))
                    .offset(x: -60, y: 150)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Theme.orange)
                    .frame(width: 300, height: 300)
                    .blur(radius: 70)
                    .opacity(0.4)
                    .offset(x: 140 - (drift ? 40 : 0), y: -40 - (drift ? 50 : 0))
                    .scaleEffect(drift ? 1.15 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            // Reduce Motion: flares stay still.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: Theme.driftDuration).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}
