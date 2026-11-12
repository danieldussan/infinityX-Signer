import Foundation
import InfinityXCore

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String, url: URL, notes: String)
    case failed(String)
}

private struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: String
    let body: String?
    let prerelease: Bool?
    let draft: Bool?
}

/// Checks GitHub releases. Manual check shows errors; the automatic one (max once a day) is silent.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var lastChecked: Date?
    /// "version|yyyy-MM-dd" of the banner the user dismissed.
    @Published private var dismissedKey: String?
    @Published private var seenVersion: String?
    /// Set by the banner "Ver"; Settings scrolls to the update card and clears it.
    @Published var revealRequested = false

    private let defaults = UserDefaults.standard
    private let local = AppInfo.version
    private var autoStarted = false

    init() {
        lastChecked = defaults.object(forKey: "update.lastCheck") as? Date
        dismissedKey = defaults.string(forKey: "update.dismissed")
        seenVersion = defaults.string(forKey: "update.seen")
    }

    private var availableVersion: String? {
        if case .available(let v, _, _) = state { return v }
        return nil
    }

    var bannerVisible: Bool {
        guard let v = availableVersion else { return false }
        return dismissedKey != "\(v)|\(Self.today)"
    }

    var badgeVisible: Bool {
        guard let v = availableVersion else { return false }
        return seenVersion != v
    }

    private static var today: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: Actions

    func dismissBanner() {
        guard let v = availableVersion else { return }
        dismissedKey = "\(v)|\(Self.today)"
        defaults.set(dismissedKey, forKey: "update.dismissed")
    }

    /// Banner "Ver": hide banner and badge, ask Settings to show the card.
    func reveal() {
        markSeen()
        revealRequested = true
    }

    func checkManually() async {
        state = .checking
        do {
            let found = try await fetch()
            state = found
            stamp()
            if found != .upToDate { markSeenIfNeeded() }
        } catch {
            state = .failed("No se pudo comprobar")
        }
    }

    /// At most once per 24 h; failures are silent. Within the window only the cached result is shown.
    func autoCheckIfNeeded() async {
        guard !autoStarted else { return }
        autoStarted = true
        // Small delay so the banner slides in after the first frame.
        try? await Task.sleep(nanoseconds: 900_000_000)
        if let last = lastChecked, Date().timeIntervalSince(last) < 24 * 3600 {
            if let cached = loadCache() { state = cached }
            return
        }
        guard let found = try? await fetch() else { return }
        if case .checking = state { return }
        state = found
        stamp()
    }

    // MARK: Network

    private func fetch() async throws -> UpdateState {
        var request = URLRequest(url: AppInfo.latestReleaseAPI)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("InfinityXSigner", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // 404 = private repo or no releases yet. Stamp so the auto check does not retry all day.
            if (response as? HTTPURLResponse)?.statusCode == 404 { stamp() }
            throw URLError(.badServerResponse)
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard release.draft != true, isNewerVersion(remote: release.tag_name, local: local),
              let url = URL(string: release.html_url) else {
            clearCache()
            return .upToDate
        }
        let version = release.tag_name.hasPrefix("v") ? release.tag_name : "v" + release.tag_name
        let notes = Self.firstLines(release.body ?? "")
        saveCache(version: version, url: url, notes: notes)
        return .available(version: version, url: url, notes: notes)
    }

    /// First few lines of the release notes, markdown markers removed.
    static func firstLines(_ body: String, max: Int = 4) -> String {
        body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#-*• \t")) }
            .filter { !$0.isEmpty }
            .prefix(max)
            .joined(separator: "\n")
    }

    // MARK: Cache

    private func stamp() {
        let now = Date()
        lastChecked = now
        defaults.set(now, forKey: "update.lastCheck")
    }

    private func markSeen() {
        guard let v = availableVersion else { return }
        seenVersion = v
        defaults.set(v, forKey: "update.seen")
        dismissedKey = "\(v)|\(Self.today)"
        defaults.set(dismissedKey, forKey: "update.dismissed")
    }

    private func markSeenIfNeeded() {
        if availableVersion != nil { seenVersion = availableVersion; defaults.set(seenVersion, forKey: "update.seen") }
    }

    private func saveCache(version: String, url: URL, notes: String) {
        defaults.set(["version": version, "url": url.absoluteString, "notes": notes], forKey: "update.cache")
    }

    private func clearCache() { defaults.removeObject(forKey: "update.cache") }

    private func loadCache() -> UpdateState? {
        guard let d = defaults.dictionary(forKey: "update.cache") as? [String: String],
              let v = d["version"], let u = d["url"], let url = URL(string: u),
              isNewerVersion(remote: v, local: local) else { return nil }
        return .available(version: v, url: url, notes: d["notes"] ?? "")
    }
}
