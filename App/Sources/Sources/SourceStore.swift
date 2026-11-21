import Foundation

// MARK: - Feed models (AltStore v1 + v2 tolerant)

struct SourceRelease: Equatable {
    let version: String
    let downloadURL: URL
    let size: Int64?
    let notes: String?
}

struct SourceApp: Identifiable, Equatable {
    let name: String
    let bundleID: String
    let subtitle: String?
    let iconURL: URL?
    let release: SourceRelease
    var id: String { bundleID + "|" + release.downloadURL.absoluteString }

    /// File name the IPA gets in Imports; also how we know it is already imported.
    var fileName: String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let base = "\(name)-\(release.version)".components(separatedBy: bad).joined(separator: "_")
        return base + ".ipa"
    }
}

struct SourceFeed: Equatable {
    let name: String
    let apps: [SourceApp]
}

private struct RawVersion: Decodable {
    var version: String?
    var date: String?
    var downloadURL: String?
    var size: Int64?
    var localizedDescription: String?
}

private struct RawApp: Decodable {
    var name: String?
    var bundleIdentifier: String?
    var subtitle: String?
    var iconURL: String?
    var versions: [RawVersion]?
    // v1 flat fields
    var version: String?
    var downloadURL: String?
    var size: Int64?
    var versionDescription: String?
}

private struct RawFeed: Decodable {
    var name: String?
    var apps: [RawApp]?
}

enum SourceError: LocalizedError {
    case badURL, notASource, http(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return "La URL debe empezar con https://"
        case .notASource: return "No parece una fuente válida (JSON de AltStore)."
        case .http(let c): return "El servidor respondió \(c)."
        }
    }
}

enum SourceParser {
    /// ponytail: newest = max ISO date string, falling back to the first entry (v2 lists newest first).
    static func parse(_ data: Data) throws -> SourceFeed {
        guard let raw = try? JSONDecoder().decode(RawFeed.self, from: data), let rawApps = raw.apps else {
            throw SourceError.notASource
        }
        let apps: [SourceApp] = rawApps.compactMap { a in
            guard let name = a.name, let bundle = a.bundleIdentifier else { return nil }
            let release: SourceRelease?
            if let v = a.versions?.filter({ $0.downloadURL != nil }).max(by: { ($0.date ?? "") < ($1.date ?? "") }),
               let url = v.downloadURL.flatMap(URL.init(string:)) {
                release = SourceRelease(version: v.version ?? "?", downloadURL: url, size: v.size,
                                        notes: v.localizedDescription)
            } else if let url = a.downloadURL.flatMap(URL.init(string:)) {
                release = SourceRelease(version: a.version ?? "?", downloadURL: url, size: a.size,
                                        notes: a.versionDescription)
            } else {
                release = nil
            }
            guard let release, release.downloadURL.scheme == "https" else { return nil }
            return SourceApp(name: name, bundleID: bundle, subtitle: a.subtitle,
                             iconURL: a.iconURL.flatMap(URL.init(string:)), release: release)
        }
        return SourceFeed(name: raw.name ?? "Fuente", apps: apps)
    }
}

// MARK: - Store

struct Source: Codable, Identifiable, Equatable {
    var url: URL
    var name: String
    var appCount: Int
    var id: String { url.absoluteString }
}

enum DownloadState: Equatable {
    case downloading(Double?)
}

@MainActor
final class SourceStore: ObservableObject {
    static let defaultURL = URL(string: "https://source.fouadraheb.com")!

    @Published private(set) var sources: [Source] = []
    @Published private(set) var feeds: [String: SourceFeed] = [:]
    /// Keyed by `SourceApp.id`.
    @Published private(set) var downloads: [String: DownloadState] = [:]
    @Published private(set) var refreshing: Set<String> = []

    private var tasks: [String: Task<Void, Never>] = [:]
    private let fileURL = AppPaths.appSupport.appendingPathComponent("sources.json")
    private let defaults = UserDefaults.standard
    private static let seededKey = "sources.seeded"

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Source].self, from: data) {
            sources = decoded
        }
        if !defaults.bool(forKey: Self.seededKey) {
            defaults.set(true, forKey: Self.seededKey)
            restoreDefault()
        }
    }

    var defaultMissing: Bool { !sources.contains { $0.url == Self.defaultURL } }

    func restoreDefault() {
        guard defaultMissing else { return }
        sources.insert(Source(url: Self.defaultURL, name: "Fouad's Source", appCount: 0), at: 0)
        save()
    }

    func fetch(_ url: URL) async throws -> SourceFeed {
        guard url.scheme == "https" else { throw SourceError.badURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw SourceError.http(http.statusCode) }
        return try SourceParser.parse(data)
    }

    func add(_ url: URL, feed: SourceFeed) {
        guard !sources.contains(where: { $0.url == url }) else { return }
        sources.append(Source(url: url, name: feed.name, appCount: feed.apps.count))
        feeds[url.absoluteString] = feed
        save()
    }

    func remove(_ source: Source) {
        sources.removeAll { $0.id == source.id }
        feeds[source.id] = nil
        save()
    }

    /// Silent refresh: keeps the old data on failure.
    func refresh(_ source: Source) async {
        guard !refreshing.contains(source.id) else { return }
        refreshing.insert(source.id)
        defer { refreshing.remove(source.id) }
        guard let feed = try? await fetch(source.url) else { return }
        feeds[source.id] = feed
        if let i = sources.firstIndex(where: { $0.id == source.id }) {
            sources[i].name = feed.name
            sources[i].appCount = feed.apps.count
            save()
        }
    }

    func download(_ app: SourceApp, into imports: ImportStore, onError: @escaping (String) -> Void) {
        guard tasks[app.id] == nil else { return }
        downloads[app.id] = .downloading(nil)
        let id = app.id
        tasks[id] = Task { [weak self] in
            let loader = Downloader { p in Task { @MainActor in self?.downloads[id] = .downloading(p) } }
            do {
                let tmp = try await loader.start(app.release.downloadURL, fileName: app.fileName)
                imports.enqueue(tmp, kind: .ipa)
            } catch is CancellationError {
            } catch let e as URLError where e.code == .cancelled {
            } catch {
                onError(error.localizedDescription)
            }
            self?.downloads[id] = nil
            self?.tasks[id] = nil
        }
    }

    func cancel(_ app: SourceApp) { tasks[app.id]?.cancel() }

    private func save() {
        if let data = try? JSONEncoder().encode(sources) { try? data.write(to: fileURL, options: .atomic) }
    }
}

// MARK: - Download to disk with progress

/// Streams to disk (IPAs are hundreds of MB), then moves the file to Application Support/Downloads/<fileName>.
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double?) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var fileName = ""
    private var moved: Result<URL, Error>?

    init(onProgress: @escaping @Sendable (Double?) -> Void) { self.onProgress = onProgress }

    func start(_ url: URL, fileName: String) async throws -> URL {
        self.fileName = fileName
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL, Error>) in
                lock.lock()
                continuation = c
                let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                session = s
                let t = s.downloadTask(with: url)
                task = t
                lock.unlock()
                t.resume()
            }
        } onCancel: {
            lock.lock(); let t = task; lock.unlock()
            t?.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten written: Int64, totalBytesExpectedToWrite total: Int64) {
        onProgress(total > 0 ? min(1, Double(written) / Double(total)) : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this returns: move it now.
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            moved = .failure(SourceError.http(http.statusCode))
            return
        }
        let fm = FileManager.default
        let dir = AppPaths.ensure(AppPaths.appSupport.appendingPathComponent("Downloads"))
        let dest = dir.appendingPathComponent(fileName)
        do {
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: location, to: dest)
            moved = .success(dest)
        } catch {
            moved = .failure(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        session.finishTasksAndInvalidate()
        if let error { c?.resume(throwing: error) }
        else if let moved { c?.resume(with: moved) }
        else { c?.resume(throwing: SourceError.notASource) }
    }
}
