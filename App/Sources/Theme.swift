import SwiftUI

extension Color {
    /// 0xRRGGBB
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: opacity)
    }
}

/// All colors, fonts, radii and animation constants live here so designer assets can be swapped in one place.
/// Values mirror the approved mockup (docs/work/infinityx-signer/mockups/01-app.html).
enum Theme {
    // MARK: Colors
    static let background = Color.black
    static let blue = Color(hex: 0x2F7BFF)
    static let violet = Color(hex: 0x7A4BFF)
    static let indigo = Color(hex: 0x5B3BFF)
    static let orange = Color(hex: 0xFF7A2F)
    static let green = Color(hex: 0x25D366)
    static let red = Color(hex: 0xFF5A5F)
    static let amber = Color(hex: 0xFFB02E)

    static let glass = Color.white.opacity(0.07)
    static let glass2 = Color.white.opacity(0.11)
    static let line = Color.white.opacity(0.14)
    static let text = Color.white
    static let text2 = Color.white.opacity(0.68)
    static let text3 = Color.white.opacity(0.42)
    static let field = Color.black.opacity(0.35)
    static let tabBarFill = Color(red: 22 / 255.0, green: 24 / 255.0, blue: 30 / 255.0).opacity(0.72)

    // Aliases kept for older call sites.
    static let accent = green
    static let danger = red
    static let flareBlue = blue
    static let flareOrange = orange
    static let secondaryText = text2

    static let brandGradient = LinearGradient(colors: [blue, orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let ctaGradient = LinearGradient(colors: [blue, violet, orange], startPoint: .leading, endPoint: .trailing)
    static let segGradient = LinearGradient(colors: [blue, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let pillGradient = LinearGradient(colors: [blue.opacity(0.55), orange.opacity(0.35)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    static let logoXGradient = LinearGradient(colors: [blue, Color.white, orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let iconGradient = LinearGradient(colors: [blue.opacity(0.35), orange.opacity(0.25)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    static let iconGreenGradient = LinearGradient(colors: [green.opacity(0.4), green.opacity(0.1)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: Radii and spacing
    static let cardRadius: CGFloat = 22
    static let fieldRadius: CGFloat = 14
    static let ctaRadius: CGFloat = 20
    static let screenPadding: CGFloat = 18
    static let cardSpacing: CGFloat = 14

    // MARK: Fonts
    static let logo = Font.system(size: 26, weight: .heavy).italic()
    static let logoX = Font.system(size: 34, weight: .heavy).italic()
    static let screenTitle = Font.system(size: 30, weight: .heavy).italic()
    static let title = screenTitle
    static let headline = Font.system(size: 17, weight: .bold).italic()
    static let name = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15)
    static let sub = Font.system(size: 14)
    static let meta = Font.system(size: 12.5)
    static let caption = Font.system(size: 12)
    static let label = Font.system(size: 11, weight: .bold)
    static let mono = Font.system(size: 12, design: .monospaced)
    static let monoTag = Font.system(size: 12.5, weight: .semibold, design: .monospaced)

    // MARK: Animation
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.72)
    static let riseSpring = Animation.spring(response: 0.55, dampingFraction: 0.78)
    static let press = Animation.spring(response: 0.25, dampingFraction: 0.7)
    static let driftDuration: Double = 14
    static let riseStagger: Double = 0.06

    /// Name of the logo image in the asset catalog (swap the PNG to rebrand).
    static let logoImageName = "Logo"
}
