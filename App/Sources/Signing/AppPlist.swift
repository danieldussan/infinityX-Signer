import Foundation

/// App-side Info.plist helpers (Core's PlistEditor only sets the display name).
enum AppPlist {
    static func setBundleID(appDir: URL, bundleID: String) throws {
        let url = appDir.appendingPathComponent("Info.plist")
        var dict = try read(url)
        dict["CFBundleIdentifier"] = bundleID
        let out = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try out.write(to: url, options: .atomic)
    }

    static func version(appDir: URL) -> String {
        let url = appDir.appendingPathComponent("Info.plist")
        guard let dict = try? read(url) else { return "1.0" }
        return (dict["CFBundleShortVersionString"] as? String) ?? (dict["CFBundleVersion"] as? String) ?? "1.0"
    }

    private static func read(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw CocoaError(.propertyListReadCorrupt) }
        return dict
    }
}
