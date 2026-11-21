import SwiftUI
import UIKit
import InfinityXCore

/// Cache of IPA scans (details + icons) for imported and signed files. Rescans when the file changes.
@MainActor
final class DetailsStore: ObservableObject {
    /// Bumped whenever a scan lands, so views re-read details and icons.
    @Published private(set) var revision = 0
    private var cache: [String: AppDetails] = [:]
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    private let images = NSCache<NSString, UIImage>()

    private static var cacheFile: URL { AppPaths.appSupport.appendingPathComponent("details-cache.json") }
    private static var iconsDir: URL { AppPaths.ensure(AppPaths.appSupport.appendingPathComponent("Icons")) }

    init() {
        if let data = try? Data(contentsOf: Self.cacheFile),
           let saved = try? JSONDecoder.iso.decode([String: AppDetails].self, from: data) {
            cache = saved
        }
    }

    // MARK: Keys

    static func key(for url: URL) -> String {
        url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent
    }

    private static func fileStem(_ key: String) -> String {
        String(key.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
    }

    private static func iconURL(_ key: String, alt: String? = nil) -> URL {
        let suffix = alt.map { ".alt." + fileStem($0) } ?? ""
        return iconsDir.appendingPathComponent(fileStem(key) + suffix + ".png")
    }

    // MARK: Reading

    /// Cached details when they still match the file on disk.
    func details(for url: URL) -> AppDetails? {
        guard let d = cache[Self.key(for: url)], Self.matches(d, url) else { return nil }
        return d
    }

    func didFail(_ url: URL) -> Bool { failed.contains(Self.key(for: url)) }

    func icon(for url: URL) -> UIImage? { image(Self.iconURL(Self.key(for: url))) }

    func alternateIcon(for url: URL, name: String) -> UIImage? {
        image(Self.iconURL(Self.key(for: url), alt: name))
    }

    private func image(_ file: URL) -> UIImage? {
        if let hit = images.object(forKey: file.path as NSString) { return hit }
        guard let data = try? Data(contentsOf: file), let img = UIImage(data: data) else { return nil }
        images.setObject(img, forKey: file.path as NSString)
        return img
    }

    private static func matches(_ d: AppDetails, _ url: URL) -> Bool {
        let (size, date) = fileStamp(url)
        guard size == d.fileSize else { return false }
        guard let a = d.fileModified, let b = date else { return date == nil && d.fileModified == nil }
        return abs(a.timeIntervalSince(b)) < 1
    }

    private static func fileStamp(_ url: URL) -> (Int64, Date?) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return ((attrs?[.size] as? NSNumber)?.int64Value ?? 0, attrs?[.modificationDate] as? Date)
    }

    // MARK: Scanning

    /// Scans in the background unless the cache is fresh. Safe to call from `onAppear`.
    func load(_ url: URL) {
        let key = Self.key(for: url)
        guard details(for: url) == nil, !inFlight.contains(key), !failed.contains(key),
              FileManager.default.fileExists(atPath: url.path) else { return }
        inFlight.insert(key)
        let stamp = Self.fileStamp(url)
        Task {
            let scanned = await Task.detached(priority: .utility) { IPADetailsReader.read(at: url) }.value
            inFlight.remove(key)
            guard var scanned else {
                failed.insert(key)
                revision += 1
                return
            }
            scanned.details.fileSize = stamp.0
            scanned.details.fileModified = stamp.1
            removeIcons(key)
            if let png = scanned.primaryIcon { try? png.write(to: Self.iconURL(key), options: .atomic) }
            for (name, png) in scanned.alternateIcons {
                try? png.write(to: Self.iconURL(key, alt: name), options: .atomic)
            }
            images.removeAllObjects()
            cache[key] = scanned.details
            save()
            revision += 1
        }
    }

    /// Forgets entries whose IPA no longer exists (keeps the cache and icon folder from growing).
    func prune() {
        let gone = cache.keys.filter { !FileManager.default.fileExists(atPath: AppPaths.documents.appendingPathComponent($0).path) }
        guard !gone.isEmpty else { return }
        for key in gone {
            cache[key] = nil
            removeIcons(key)
        }
        save()
    }

    private func removeIcons(_ key: String) {
        let fm = FileManager.default
        let stem = Self.fileStem(key)
        for name in (try? fm.contentsOfDirectory(atPath: Self.iconsDir.path)) ?? []
        where name == stem + ".png" || name.hasPrefix(stem + ".alt.") {
            try? fm.removeItem(at: Self.iconsDir.appendingPathComponent(name))
        }
    }

    private func save() {
        if let data = try? JSONEncoder.iso.encode(cache) { try? data.write(to: Self.cacheFile, options: .atomic) }
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// Real app icon (rounded like iOS), falling back to the old SF Symbol box while it loads or is missing.
struct AppIconView: View {
    @EnvironmentObject var details: DetailsStore
    let url: URL
    var size: CGFloat = 44
    var fallbackSymbol = "shippingbox.fill"

    var body: some View {
        // Reading `revision` makes the view refresh when a scan finishes.
        let _ = details.revision
        Group {
            if let img = details.icon(for: url) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                IconBox(systemName: fallbackSymbol, green: true).scaleEffect(size / 44)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .onAppear { details.load(url) }
    }
}
