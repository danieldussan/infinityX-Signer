import Foundation
import UIKit
import Security
import InfinityXCore

enum InstallState: Equatable {
    case ready
    case sendingManifest
    case sendingPayload
    case installing
    case completed
    case failed(String)
    /// Rejected / no answer to the iOS prompt, or stopped by the user. Retryable like `.failed`.
    case cancelled(String)

    var label: String {
        switch self {
        case .ready: return "Listo para instalar"
        case .sendingManifest: return "Enviando manifiesto"
        case .sendingPayload: return "Enviando IPA"
        case .installing: return "Instalando"
        case .completed: return "Completado"
        case .failed(let m): return "Error: \(m)"
        case .cancelled(let m): return m
        }
    }

    var isFinal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }

    /// Talking to iOS right now (queued `.ready` items are not active).
    var isActive: Bool {
        switch self {
        case .sendingManifest, .sendingPayload, .installing: return true
        default: return false
        }
    }

    var isRetryable: Bool {
        switch self {
        case .failed, .cancelled: return true
        default: return false
        }
    }

    var outcome: QueueOutcome {
        switch self {
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        default: return .pending
        }
    }
}

struct InstallItem: Identifiable {
    let id: String
    let app: SignedApp
    var state: InstallState
}

/// Sequential install queue: one iOS install prompt per app, waits for each before the next.
@MainActor
final class InstallCoordinator: ObservableObject {
    @Published private(set) var items: [InstallItem] = []
    @Published var safariTarget: SafariTarget?
    @Published private(set) var serverStatus = "Detenido"
    /// True while a queue runs. The single source of truth for "busy".
    @Published private(set) var isRunning = false
    @Published private(set) var cancelling = false
    @Published var mode: InstallMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "install.mode") }
    }
    @Published var plistHostText: String {
        didSet { UserDefaults.standard.set(plistHostText, forKey: "install.plistHost") }
    }

    /// Called when an item reaches `.completed` (the app library marks it as installed).
    var onInstalled: ((SignedApp) -> Void)?

    let ssl = SSLPack()
    private let server = LocalServer()
    private var port: UInt16 = 0
    private var host = "127.0.0.1"
    private let itemTimeout: TimeInterval = 120
    /// iOS gives no signal when the prompt is rejected; no download request within this long = no answer.
    private let noResponseTimeout: TimeInterval = 45
    private var runIDs: [String] = []

    init() {
        let raw = UserDefaults.standard.string(forKey: "install.mode") ?? InstallMode.semiLocal.rawValue
        mode = InstallMode(rawValue: raw) ?? .semiLocal
        plistHostText = UserDefaults.standard.string(forKey: "install.plistHost")
            ?? InstallConfig.defaultPlistHost.absoluteString
    }

    /// Falls back to the default host when the text is not a valid URL.
    var config: InstallConfig {
        let url = URL(string: plistHostText.trimmingCharacters(in: .whitespaces)) ?? InstallConfig.defaultPlistHost
        return InstallConfig(mode: mode, plistHost: url)
    }

    // MARK: Queue

    /// Items of the current (or last) run, in order.
    var runItems: [InstallItem] { runIDs.compactMap { id in items.first { $0.id == id } } }

    /// Last item state for this IPA, if it was ever queued.
    func item(for app: SignedApp) -> InstallItem? { items.first { $0.app.ipaURL == app.ipaURL } }

    func isRetryable(_ app: SignedApp) -> Bool { item(for: app)?.state.isRetryable ?? false }

    /// Only the apps whose last attempt failed or was cancelled.
    func retryable(in apps: [SignedApp]) -> [SignedApp] { apps.filter(isRetryable) }

    /// "3 instaladas, 1 fallida" for the given apps' last attempt; `isError` when any did not install.
    func summary(for apps: [SignedApp]) -> (text: String, isError: Bool) {
        let outcomes = apps.compactMap { item(for: $0)?.state.outcome }
        return (queueSummary(outcomes), outcomes.contains { $0 == .failed || $0 == .cancelled })
    }

    /// Installs `apps`. Items of other apps (e.g. already completed) are kept; these apps restart from `.ready`.
    func installAll(_ apps: [SignedApp]) async {
        guard mode != .export, !isRunning, !apps.isEmpty else { return }
        isRunning = true
        cancelling = false
        let urls = Set(apps.map { $0.ipaURL })
        let fresh = apps.map { InstallItem(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                                           app: $0, state: .ready) }
        items = items.filter { !urls.contains($0.app.ipaURL) } + fresh
        runIDs = fresh.map { $0.id }
        defer { isRunning = false; cancelling = false }
        do {
            try await startServer()
        } catch {
            for id in runIDs { setState(id, .failed(error.localizedDescription)) }
            serverStatus = "Error: \(error.localizedDescription)"
            return
        }
        for id in runIDs {
            if cancelling {
                if !(state(of: id)?.isFinal ?? true) { setState(id, .cancelled("Cancelada")) }
                continue
            }
            await install(itemID: id)
        }
        server.stop()
        serverStatus = "Detenido"
        safariTarget = nil
    }

    /// The user closed the Safari sheet (Listo) while iOS had not yet requested the IPA: treat it as a rejection now.
    func safariDismissedByUser() {
        safariTarget = nil
        guard let id = runIDs.first(where: { state(of: $0) == .sendingManifest }) else { return }
        setState(id, .cancelled("Instalación rechazada"))
    }

    /// Stops the queue: queued apps and the one still waiting for the iOS prompt are cancelled.
    /// An app already downloading/installing is left to finish (iOS is mid-install; interrupting it only leaves a half install).
    func cancelAll() {
        guard isRunning, !cancelling else { return }
        cancelling = true
        for id in runIDs {
            switch state(of: id) {
            case .ready, .sendingManifest: setState(id, .cancelled("Cancelada"))
            default: break
            }
        }
        safariTarget = nil
    }

    private func startServer() async throws {
        server.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        var identity: sec_identity_t?
        if mode == .fullyLocal {
            // ponytail: experimental TLS path; any failure here becomes a per-item error, never a crash.
            try await ssl.ensureFresh()
            identity = try ssl.makeIdentity()
            host = ssl.info?.commonName ?? "localhost"
        } else {
            // ponytail: loopback only; no LAN IP lookup (device installs from itself).
            host = "127.0.0.1"
        }
        port = try await server.start(identity: identity)
        let scheme = mode == .fullyLocal ? "https" : "http"
        serverStatus = "\(scheme)://\(host):\(port)"
    }

    private func install(itemID: String) async {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        let scheme = mode == .fullyLocal ? "https" : "http"
        let path = "/\(item.id).ipa"
        server.setFile(path: path, url: item.app.ipaURL)
        guard let ipaURL = URL(string: "\(scheme)://\(host):\(port)\(path)") else {
            setState(itemID, .failed("URL inválida"))
            return
        }
        let plist = genPlistURL(host: config.plistHost, bundleID: item.app.job.bundleID,
                                name: item.app.job.displayName, version: item.app.version, ipaURL: ipaURL)
        let itms = itmsServicesURL(plistURL: plist)

        setState(itemID, .sendingManifest)
        switch mode {
        case .semiLocal:
            server.setPage(path: "/install", html: Self.installPage(itms: itms))
            if let pageURL = URL(string: "http://127.0.0.1:\(port)/install") {
                safariTarget = SafariTarget(url: pageURL)
            }
        case .fullyLocal:
            _ = await UIApplication.shared.open(itms)
        case .export:
            break
        }

        var phase = state(of: itemID)
        var since = Date()
        while let current = state(of: itemID), !current.isFinal {
            if current != phase { phase = current; since = Date() }
            let waiting = current == .sendingManifest
            if Date().timeIntervalSince(since) > (waiting ? noResponseTimeout : itemTimeout) {
                setState(itemID, waiting ? .cancelled("Sin respuesta (¿cancelaste la instalación?)")
                                         : .failed("Tiempo agotado (\(Int(itemTimeout)) s)"))
                break
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        safariTarget = nil
    }

    // MARK: Events

    private func handle(_ event: ServerEvent) {
        switch event {
        case .page:
            break
        case .fileStarted(let path):
            // Late events for an item that already ended (timeout, cancelled) must not revive it.
            if let id = itemID(forPath: path), !(state(of: id)?.isFinal ?? true) {
                setState(id, .sendingPayload)
                safariTarget = nil
            }
        case .fileFinished(let path, let success):
            guard let id = itemID(forPath: path), !(state(of: id)?.isFinal ?? true) else { return }
            if success {
                setState(id, .installing)
                // ponytail: iOS gives no public signal when an install ends; we assume done 10 s after the payload is sent.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    if self?.state(of: id) == .installing { self?.setState(id, .completed) }
                }
            } else {
                setState(id, .failed("Descarga interrumpida"))
            }
        case .tlsFailed:
            // Auto refresh once per failure: next attempt uses the fresh pack.
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                try? await self.ssl.refresh()
                for id in self.runIDs where !(self.state(of: id)?.isFinal ?? true) {
                    self.setState(id, .failed("Falló el handshake TLS; paquete SSL actualizado, reintenta"))
                }
            }
        }
    }

    private func itemID(forPath path: String) -> String? {
        items.first { "/\($0.id).ipa" == path }?.id
    }

    private func state(of id: String) -> InstallState? {
        items.first { $0.id == id }?.state
    }

    private func setState(_ id: String, _ state: InstallState) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let was = items[i].state
        items[i].state = state
        if state == .completed, was != .completed { onInstalled?(items[i].app) }
    }

    private static func installPage(itms: URL) -> String {
        let raw = itms.absoluteString
        let attr = raw.replacingOccurrences(of: "&", with: "&amp;")
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1"><title>Instalar</title></head>
        <body style="background:#000;color:#fff;font-family:-apple-system,sans-serif;text-align:center;padding-top:30vh">
        <p>Preparando instalación...</p>
        <p><a href="\(attr)" style="color:#25D366">Instalar</a></p>
        <script>window.location = "\(raw)";</script>
        </body></html>
        """
    }
}
