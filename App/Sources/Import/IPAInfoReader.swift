import Foundation
import InfinityXCore
import ZIPFoundation

/// Reads the app's Info.plist straight out of an IPA (zip) without extracting or loading the archive.
enum IPAInfoReader {
    private static let infoPath = try! NSRegularExpression(pattern: "^Payload/([^/]+\\.app)/Info\\.plist$")
    /// A real Info.plist is a few KB; refuse absurd entries instead of inflating them.
    private static let maxPlistSize: UInt64 = 4 * 1024 * 1024

    /// Blocking: call off the main thread. Returns nil if the file is not a readable IPA.
    static func read(at url: URL) -> IPAInfo? {
        guard let archive = try? Archive(url: url, accessMode: .read) else { return nil }
        for entry in archive {
            guard entry.type == .file, entry.uncompressedSize <= maxPlistSize else { continue }
            let path = entry.path
            let range = NSRange(path.startIndex..., in: path)
            guard let m = infoPath.firstMatch(in: path, range: range),
                  let r = Range(m.range(at: 1), in: path) else { continue }
            var data = Data()
            do {
                _ = try archive.extract(entry) { data.append($0) }
            } catch {
                continue
            }
            if let info = IPAInfo(infoPlist: data, appFolderName: String(path[r])) { return info }
        }
        return nil
    }
}
