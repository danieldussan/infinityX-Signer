import Foundation

public enum PlistEditor {
    static let nameKeys = ["CFBundleDisplayName", "CFBundleName"]
    private static let stringsLine = try! NSRegularExpression(
        pattern: #"^\s*"?CFBundle(?:Display)?Name"?\s*=.*;\s*$"#, options: [.anchorsMatchLines])

    public static func setName(appDir: URL, name: String, cleanLocalized: Bool) throws {
        let plistURL = appDir.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: plistURL)
        guard var dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw CocoaError(.propertyListReadCorrupt) }
        for k in nameKeys { dict[k] = name }
        let out = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try out.write(to: plistURL, options: .atomic)
        if cleanLocalized { cleanStrings(appDir: appDir) }
    }

    public static func stripPlugins(appDir: URL) throws {
        for folder in ["PlugIns", "Extensions"] {
            let target = appDir.appendingPathComponent(folder)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
        }
    }

    /// Returns how many files changed. A weird file is skipped, never thrown.
    @discardableResult
    static func cleanStrings(appDir: URL) -> Int {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: appDir.path) else { return 0 }
        var cleaned = 0
        for item in items where item.hasSuffix(".lproj") {
            let file = appDir.appendingPathComponent(item).appendingPathComponent("InfoPlist.strings")
            guard let raw = try? Data(contentsOf: file) else { continue }
            if let new = cleanedData(raw), new != raw, (try? new.write(to: file, options: .atomic)) != nil {
                cleaned += 1
            }
        }
        return cleaned
    }

    private static func cleanedData(_ raw: Data) -> Data? {
        let head = raw.prefix(6)
        if head.starts(with: Data("bplist".utf8)) || raw.prefix(5).starts(with: Data("<?xml".utf8)) {
            guard var d = (try? PropertyListSerialization.propertyList(from: raw, format: nil)) as? [String: Any],
                  nameKeys.contains(where: { d[$0] != nil }) else { return nil }
            for k in nameKeys { d[k] = nil }
            return try? PropertyListSerialization.data(fromPropertyList: d, format: .binary, options: 0)
        }
        let bytes = [UInt8](raw.prefix(2))
        let encoding: String.Encoding
        let bom: [UInt8]
        let body: Data
        if bytes == [0xFF, 0xFE] { encoding = .utf16LittleEndian; bom = bytes; body = raw.dropFirst(2) }
        else if bytes == [0xFE, 0xFF] { encoding = .utf16BigEndian; bom = bytes; body = raw.dropFirst(2) }
        else { encoding = .utf8; bom = []; body = raw }
        guard let text = String(data: body, encoding: encoding) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let new = stringsLine.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        guard new != text, let encoded = new.data(using: encoding) else { return nil }
        return Data(bom) + encoded
    }
}
