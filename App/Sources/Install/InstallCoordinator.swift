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

    var label: String {
        switch self {
        case .ready: return "Listo para instalar"
        case .sendingManifest: return "Enviando manifiesto"
        case .sendingPayload: return "Enviando IPA"
        case .installing: return "Instalando"
        case .completed: return "Completado"
        case .failed(let m): return "Error: \(m)"
        }
    }

    var isFinal: Bool {
        switch self {
        case .completed, .failed: return true
        default: return false
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

    func installAll(_ apps: [SignedApp]) async {
        guard mode != .export else { return }
        items = apps.map { InstallItem(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                                       app: $0, state: .ready) }
        do {
            try await startServer()
        } catch {
            for item in items { setState(item.id, .failed(error.localizedDescription)) }
            serverStatus = "Error: \(error.localizedDescription)"
            return
        }
        for item in items {
            await install(itemID: item.id)
        }
        server.stop()
        serverStatus = "Detenido"
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

        let deadline = Date().addingTimeInterval(itemTimeout)
        while Date() < deadline, !(state(of: itemID)?.isFinal ?? true) {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        if let s = state(of: itemID), !s.isFinal {
            setState(itemID, .failed("Tiempo agotado (120 s)"))
        }
        safariTarget = nil
    }

    // MARK: Events

    private func handle(_ event: ServerEvent) {
        switch event {
        case .page:
            break
        case .fileStarted(let path):
            if let id = itemID(forPath: path) {
                setState(id, .sendingPayload)
                safariTarget = nil
            }
        case .fileFinished(let path, let success):
            guard let id = itemID(forPath: path) else { return }
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
                for item in self.items where !(self.state(of: item.id)?.isFinal ?? true) {
                    self.setState(item.id, .failed("Falló el handshake TLS; paquete SSL actualizado, reintenta"))
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
