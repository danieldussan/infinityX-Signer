import Foundation
import Security

struct SSLPackInfo {
    let commonName: String
    let expiry: Date?
    let fetchedAt: Date?
}

/// `*.backloop.dev` pack used by Fully Local mode: fetched, cached on disk, refreshed on demand.
@MainActor
final class SSLPack: ObservableObject {
    @Published private(set) var info: SSLPackInfo?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    private static let packURL = URL(string: "https://backloop.dev/pack.json")!
    private var dir: URL { AppPaths.ensure(AppPaths.appSupport.appendingPathComponent("SSLPack")) }

    init() {
        loadCache()
    }

    var isValid: Bool {
        guard let expiry = info?.expiry else { return false }
        return expiry > Date().addingTimeInterval(24 * 3600)
    }

    func ensureFresh() async throws {
        if !isValid { try await refresh() }
    }

    func refresh() async throws {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.packURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cert = json["cert"] as? String,
                  let key1 = json["key1"] as? String,
                  let key2 = json["key2"] as? String,
                  let domains = (json["info"] as? [String: Any])?["domains"] as? [String: Any],
                  let commonName = domains["commonName"] as? String else {
                throw TLSIdentityError.message("Respuesta inesperada de backloop.dev")
            }
            let ca = (json["ca"] as? String) ?? ""
            guard let der = PEM.blocks(cert).first?.data, DER.notAfter(ofCertificate: der) != nil else {
                throw TLSIdentityError.message("No se pudo leer el certificado del paquete")
            }
            try (key1 + key2).write(to: dir.appendingPathComponent("server.pem"), atomically: true, encoding: .utf8)
            try cert.write(to: dir.appendingPathComponent("server.crt"), atomically: true, encoding: .utf8)
            try ca.write(to: dir.appendingPathComponent("ca.crt"), atomically: true, encoding: .utf8)
            try commonName.write(to: dir.appendingPathComponent("commonName.txt"), atomically: true, encoding: .utf8)
            try String(Date().timeIntervalSince1970).write(to: dir.appendingPathComponent("fetchedAt.txt"),
                                                           atomically: true, encoding: .utf8)
            lastError = nil
            loadCache()
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func makeIdentity() throws -> sec_identity_t {
        guard let cert = try? String(contentsOf: dir.appendingPathComponent("server.crt"), encoding: .utf8),
              let key = try? String(contentsOf: dir.appendingPathComponent("server.pem"), encoding: .utf8) else {
            throw TLSIdentityError.message("No hay paquete SSL en caché")
        }
        let ca = try? String(contentsOf: dir.appendingPathComponent("ca.crt"), encoding: .utf8)
        return try TLSIdentity.make(certPEM: cert, keyPEM: key, caPEM: ca)
    }

    private func loadCache() {
        guard let name = try? String(contentsOf: dir.appendingPathComponent("commonName.txt"), encoding: .utf8),
              let cert = try? String(contentsOf: dir.appendingPathComponent("server.crt"), encoding: .utf8) else {
            info = nil
            return
        }
        let expiry = PEM.blocks(cert).first.flatMap { DER.notAfter(ofCertificate: $0.data) }
        let fetched = (try? String(contentsOf: dir.appendingPathComponent("fetchedAt.txt"), encoding: .utf8))
            .flatMap { TimeInterval($0) }
            .map { Date(timeIntervalSince1970: $0) }
        info = SSLPackInfo(commonName: name.trimmingCharacters(in: .whitespacesAndNewlines),
                           expiry: expiry, fetchedAt: fetched)
    }
}
