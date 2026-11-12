import Foundation

/// Basic app metadata read from an IPA's top-level Info.plist (Foundation only, unit-testable).
public struct IPAInfo: Codable, Equatable {
    public let displayName: String
    public let bundleID: String
    public let version: String

    public init(displayName: String, bundleID: String, version: String) {
        self.displayName = displayName
        self.bundleID = bundleID
        self.version = version
    }

    /// Parses an XML or binary Info.plist. Returns nil when it is not a dictionary or has no bundle id.
    /// `appFolderName` is the `Foo.app` (or `Foo`) folder name, used as the last-resort display name.
    public init?(infoPlist data: Data, appFolderName: String) {
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any] else { return nil }
        func str(_ key: String) -> String? {
            guard let s = (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        guard let bundleID = str("CFBundleIdentifier") else { return nil }
        var folder = appFolderName
        if folder.lowercased().hasSuffix(".app") { folder = String(folder.dropLast(4)) }
        self.displayName = str("CFBundleDisplayName") ?? str("CFBundleName") ?? folder
        self.bundleID = bundleID
        self.version = str("CFBundleShortVersionString") ?? str("CFBundleVersion") ?? ""
    }
}
