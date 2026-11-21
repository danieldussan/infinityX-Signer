import Foundation
import InfinityXCore
import ZIPFoundation

/// Result of scanning an IPA: metadata plus the icon PNGs found next to Info.plist.
struct ScannedIPA {
    var details: AppDetails
    var primaryIcon: Data?
    var alternateIcons: [String: Data]
}

/// Reads everything the Información sheet needs straight from the IPA zip, without extracting it.
enum IPADetailsReader {
    private struct Stop: Error {}

    private static let appPrefix = try! NSRegularExpression(pattern: "^Payload/([^/]+\\.app)/(.*)$")
    private static let maxPlistSize: UInt64 = 4 * 1024 * 1024
    private static let maxIconSize: UInt64 = 4 * 1024 * 1024
    /// Load commands sit right after the Mach-O header; the first MB is plenty.
    private static let machOHead = 1024 * 1024
    private static let maxNested = 80

    /// Blocking: call off the main thread.
    static func read(at url: URL) -> ScannedIPA? {
        guard let archive = try? Archive(url: url, accessMode: .read) else { return nil }

        var folder: String?
        var rootFiles: [(name: String, size: UInt64)] = []
        var rootEntries: [String: Entry] = [:]
        var frameworkNames: [String] = []
        var frameworkPlists: [String: Entry] = [:]
        var pluginNames: [String] = []
        var pluginPlists: [String: Entry] = [:]

        for entry in archive {
            let path = entry.path
            let range = NSRange(path.startIndex..., in: path)
            guard let m = appPrefix.firstMatch(in: path, range: range),
                  let f = Range(m.range(at: 1), in: path), let r = Range(m.range(at: 2), in: path) else { continue }
            if folder == nil { folder = String(path[f]) }
            let rest = String(path[r])
            let parts = rest.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard let first = parts.first else { continue }
            if parts.count == 1, entry.type == .file {
                rootFiles.append((first, entry.uncompressedSize))
                rootEntries[first] = entry
            } else if first == "Frameworks", parts.count >= 2 {
                let name = parts[1]
                if !frameworkNames.contains(name) { frameworkNames.append(name) }
                if parts.count == 3, parts[2] == "Info.plist" { frameworkPlists[name] = entry }
            } else if first == "PlugIns" || first == "Extensions", parts.count >= 2 {
                let name = parts[1]
                if !pluginNames.contains(name) { pluginNames.append(name) }
                if parts.count == 3, parts[2] == "Info.plist" { pluginPlists[name] = entry }
            }
        }

        guard let folder, let infoEntry = rootEntries["Info.plist"],
              let infoData = extract(infoEntry, from: archive, limit: maxPlistSize),
              var details = AppDetails(infoPlist: infoData, appFolderName: folder) else { return nil }

        details.frameworks = frameworkNames.prefix(maxNested).map { name in
            BundleItem(name: name, bundleID: bundleID(frameworkPlists[name], in: archive))
        }
        details.plugins = pluginNames.prefix(maxNested).map { name in
            BundleItem(name: name, bundleID: bundleID(pluginPlists[name], in: archive))
        }

        if !details.executable.isEmpty, let exe = rootEntries[details.executable] {
            details.dylibs = MachO.dylibs(in: head(of: exe, in: archive))
        }

        func icon(_ bases: [String]) -> Data? {
            guard let name = IconNames.pickFile(bases: bases, from: rootFiles),
                  let e = rootEntries[name] else { return nil }
            return extract(e, from: archive, limit: maxIconSize)
        }
        var primary = icon(details.primaryIconFiles)
        if primary == nil { primary = icon(["AppIcon", "Icon"]) }
        var alternates: [String: Data] = [:]
        for alt in details.alternateIcons.prefix(20) {
            if let data = icon(alt.files + [alt.name]) { alternates[alt.name] = data }
        }
        return ScannedIPA(details: details, primaryIcon: primary, alternateIcons: alternates)
    }

    private static func extract(_ entry: Entry, from archive: Archive, limit: UInt64) -> Data? {
        guard entry.uncompressedSize <= limit else { return nil }
        var data = Data()
        do { _ = try archive.extract(entry) { data.append($0) } } catch { return nil }
        return data
    }

    private static func bundleID(_ entry: Entry?, in archive: Archive) -> String? {
        guard let entry, let data = extract(entry, from: archive, limit: maxPlistSize),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    /// First bytes of a (possibly huge) executable; stops inflating as soon as there is enough.
    private static func head(of entry: Entry, in archive: Archive) -> Data {
        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
                if data.count >= machOHead { throw Stop() }
            }
        } catch {}
        return data
    }
}
