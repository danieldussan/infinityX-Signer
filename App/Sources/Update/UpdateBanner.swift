import SwiftUI

/// Discreet top pill: "Nueva versión vX.Y.Z". Slides down (no motion when Reduce Motion is on).
struct UpdateBanner: View {
    let version: String
    let onView: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
            Button(action: onView) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nueva versión \(version)").font(.system(size: 13.5, weight: .bold))
                    Text("Toca para ver las novedades").font(.system(size: 12)).opacity(0.85)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("Ver", action: onView)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(Color(red: 16 / 255.0, green: 16 / 255.0, blue: 20 / 255.0))
                .padding(.horizontal, 12).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.95)))
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.25)))
            }
            .accessibilityLabel("Cerrar aviso")
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Theme.blue.opacity(0.85), Theme.violet.opacity(0.8), Theme.orange.opacity(0.75)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        .shadow(color: Theme.blue.opacity(0.6), radius: 16, x: 0, y: 10)
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }
}
