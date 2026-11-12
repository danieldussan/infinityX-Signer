import SwiftUI

/// All colors and fonts live here so designer assets can be swapped in one place.
enum Theme {
    static let accent = Color(red: 37 / 255.0, green: 211 / 255.0, blue: 102 / 255.0) // #25D366
    static let background = Color.black
    static let flareBlue = Color(red: 0.10, green: 0.35, blue: 1.0)
    static let flareOrange = Color(red: 1.0, green: 0.50, blue: 0.10)
    static let text = Color.white
    static let secondaryText = Color.white.opacity(0.65)
    static let danger = Color(red: 1.0, green: 0.35, blue: 0.35)

    static let title = Font.system(size: 30, weight: .heavy).italic()
    static let headline = Font.system(size: 17, weight: .bold).italic()
    static let body = Font.system(size: 15)
    static let caption = Font.system(size: 12)
    static let mono = Font.system(size: 12, design: .monospaced)

    /// Name of the logo image in the asset catalog (swap the PNG to rebrand).
    static let logoImageName = "Logo"
}
