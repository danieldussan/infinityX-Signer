import Foundation

/// Info.plist changes to replace the primary icon with loose PNG files, and to drop alternate icons.
public enum IconEditor {
    public struct Target: Equatable {
        public let fileName: String
        public let pixels: Int
    }

    /// Files to write into the .app root (names follow the Xcode "<base>60x60@2x" convention iOS resolves).
    public static let targets: [Target] = [
        Target(fileName: "IXIcon60x60@2x.png", pixels: 120),
        Target(fileName: "IXIcon60x60@3x.png", pixels: 180),
        Target(fileName: "IXIcon76x76@2x~ipad.png", pixels: 152),
        Target(fileName: "IXIcon83.5x83.5@2x~ipad.png", pixels: 167),
    ]

    private static let iPhoneBase = "IXIcon60x60"
    private static let iPadBases = ["IXIcon76x76", "IXIcon83.5x83.5"]

    /// Points the primary icon at the IXIcon files. The asset-catalog icon name is removed so iOS uses the files.
    public static func settingPrimaryIcon(_ dict: [String: Any]) -> [String: Any] {
        var out = dict
        func apply(_ key: String, files: [String], createIfMissing: Bool) {
            guard createIfMissing || dict[key] != nil else { return }
            var icons = dict[key] as? [String: Any] ?? [:]
            var primary = icons["CFBundlePrimaryIcon"] as? [String: Any] ?? [:]
            primary["CFBundleIconFiles"] = files
            primary.removeValue(forKey: "CFBundleIconName")
            icons["CFBundlePrimaryIcon"] = primary
            out[key] = icons
        }
        apply("CFBundleIcons", files: [iPhoneBase], createIfMissing: true)
        apply("CFBundleIcons~ipad", files: iPadBases, createIfMissing: false)
        out.removeValue(forKey: "CFBundleIconFiles")
        out.removeValue(forKey: "CFBundleIconFile")
        return out
    }

    /// Drops CFBundleAlternateIcons; returns the file base names the app should delete.
    public static func removingAlternateIcons(_ dict: [String: Any]) -> (dict: [String: Any], bases: [String]) {
        var out = dict
        let bases = IconNames.alternates(in: dict).flatMap { $0.files }
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            guard var icons = out[key] as? [String: Any] else { continue }
            icons.removeValue(forKey: "CFBundleAlternateIcons")
            out[key] = icons
        }
        return (out, bases)
    }
}
