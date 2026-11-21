import Foundation

public struct BundleItem: Codable, Equatable, Hashable {
    public let name: String
    public let bundleID: String?

    public init(name: String, bundleID: String?) {
        self.name = name
        self.bundleID = bundleID
    }
}

public struct AlternateIcon: Codable, Equatable {
    public let name: String
    public let files: [String]

    public init(name: String, files: [String]) {
        self.name = name
        self.files = files
    }
}

/// Everything the "Información" sheet shows about an IPA (Foundation only, unit-testable).
public struct AppDetails: Codable, Equatable {
    public var displayName: String
    public var bundleID: String
    public var version: String
    public var build: String
    public var minOS: String
    public var executable: String
    /// Keys like NSCameraUsageDescription.
    public var permissions: [String]
    public var primaryIconFiles: [String]
    public var alternateIcons: [AlternateIcon]
    public var frameworks: [BundleItem] = []
    public var plugins: [BundleItem] = []
    public var dylibs: [String] = []
    /// Used to know when a cached scan is stale.
    public var fileSize: Int64 = 0
    public var fileModified: Date?

    public init?(infoPlist data: Data, appFolderName: String) {
        guard let info = IPAInfo(infoPlist: data, appFolderName: appFolderName),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any] else { return nil }
        func str(_ key: String) -> String {
            (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        displayName = info.displayName
        bundleID = info.bundleID
        version = info.version
        build = str("CFBundleVersion")
        minOS = str("MinimumOSVersion")
        executable = str("CFBundleExecutable")
        permissions = dict.keys.filter { $0.hasPrefix("NS") && $0.hasSuffix("UsageDescription") }.sorted()
        primaryIconFiles = IconNames.primaryBases(in: dict)
        alternateIcons = IconNames.alternates(in: dict)
    }
}

/// Reads icon names out of an Info.plist dictionary and picks the matching PNG among bundle files.
public enum IconNames {
    private static let iconKeys = ["CFBundleIcons", "CFBundleIcons~ipad"]

    public static func primaryBases(in dict: [String: Any]) -> [String] {
        var out: [String] = []
        for key in iconKeys {
            let primary = (dict[key] as? [String: Any])?["CFBundlePrimaryIcon"]
            if let p = primary as? [String: Any] {
                out += p["CFBundleIconFiles"] as? [String] ?? []
                if let n = p["CFBundleIconName"] as? String { out.append(n) }
            } else if let name = primary as? String {
                out.append(name)
            }
        }
        out += dict["CFBundleIconFiles"] as? [String] ?? []
        if let f = dict["CFBundleIconFile"] as? String { out.append(f) }
        return unique(out)
    }

    public static func alternates(in dict: [String: Any]) -> [AlternateIcon] {
        var byName: [String: [String]] = [:]
        for key in iconKeys {
            guard let alt = (dict[key] as? [String: Any])?["CFBundleAlternateIcons"] as? [String: Any] else { continue }
            for (name, value) in alt {
                let v = value as? [String: Any]
                var files = v?["CFBundleIconFiles"] as? [String] ?? []
                if let n = v?["CFBundleIconName"] as? String { files.append(n) }
                byName[name, default: []] += files
            }
        }
        return byName.keys.sorted().map { AlternateIcon(name: $0, files: unique(byName[$0] ?? [])) }
    }

    /// Largest PNG whose stem (before "@", "~" or the extension) starts with one of the bases.
    public static func pickFile(bases: [String], from files: [(name: String, size: UInt64)]) -> String? {
        let stems = bases.map { stem($0).lowercased() }.filter { !$0.isEmpty }
        var best: (name: String, size: UInt64)?
        for f in files where f.name.lowercased().hasSuffix(".png") {
            let s = stem(f.name).lowercased()
            guard stems.contains(where: { s.hasPrefix($0) }) else { continue }
            if best == nil || f.size > best!.size { best = f }
        }
        return best?.name
    }

    public static func stem(_ name: String) -> String {
        var s = name
        if s.lowercased().hasSuffix(".png") { s = String(s.dropLast(4)) }
        if let i = s.firstIndex(where: { $0 == "@" || $0 == "~" }) { s = String(s[..<i]) }
        return s
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}

/// Load commands of a Mach-O binary (thin or fat: first slice only).
public enum MachO {
    private static let loadCommands: Set<UInt32> = [0xC, 0x80000018, 0x8000001F, 0x20]

    public static func dylibs(in data: Data) -> [String] {
        let b = [UInt8](data)
        guard b.count >= 8 else { return [] }
        var base = 0
        let beMagic = u32(b, 0, big: true)
        if beMagic == 0xCAFEBABE || beMagic == 0xCAFEBABF {
            let archSize = beMagic == 0xCAFEBABE ? 20 : 32
            guard (u32(b, 4, big: true) ?? 0) > 0, b.count >= 8 + archSize else { return [] }
            let offset = beMagic == 0xCAFEBABE ? u32(b, 16, big: true) : u64(b, 16, big: true)
            guard let o = offset, o < b.count else { return [] }
            base = Int(o)
        }
        guard let magic = u32(b, base, big: false) else { return [] }
        let headerSize: Int
        switch magic {
        case 0xFEEDFACF: headerSize = 32
        case 0xFEEDFACE: headerSize = 28
        default: return []
        }
        guard let ncmds = u32(b, base + 16, big: false) else { return [] }
        var pos = base + headerSize
        var out: [String] = []
        for _ in 0..<min(Int(ncmds), 4096) {
            guard let cmd = u32(b, pos, big: false), let size = u32(b, pos + 4, big: false),
                  size >= 8, pos + Int(size) <= b.count else { break }
            if loadCommands.contains(cmd), let nameOff = u32(b, pos + 8, big: false) {
                let start = pos + Int(nameOff)
                let end = pos + Int(size)
                if start < end, let zero = b[start..<end].firstIndex(of: 0),
                   let s = String(bytes: b[start..<zero], encoding: .utf8), !s.isEmpty {
                    out.append(s)
                }
            }
            pos += Int(size)
        }
        return out
    }

    /// System libraries live in /usr/lib or /System; everything else was shipped (or injected) with the app.
    public static func isSystem(_ path: String) -> Bool {
        path.hasPrefix("/usr/lib/") || path.hasPrefix("/System/")
    }

    private static func u32(_ b: [UInt8], _ at: Int, big: Bool) -> UInt32? {
        guard at >= 0, at + 4 <= b.count else { return nil }
        let x = b[at..<at + 4].map { UInt32($0) }
        return big ? x[0] << 24 | x[1] << 16 | x[2] << 8 | x[3] : x[3] << 24 | x[2] << 16 | x[1] << 8 | x[0]
    }

    private static func u64(_ b: [UInt8], _ at: Int, big: Bool) -> UInt32? {
        // Offsets past 4 GB make no sense here; only the low word matters.
        big ? u32(b, at + 4, big: true) : nil
    }
}
