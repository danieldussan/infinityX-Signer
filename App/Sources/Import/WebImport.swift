import Foundation

enum WebImportError: LocalizedError {
    case invalidLink, expired, network

    var errorDescription: String? {
        switch self {
        case .invalidLink: return "Enlace de importación no válido."
        case .expired: return "El enlace venció. Firma de nuevo en la web."
        case .network: return "No se pudo contactar con la web. Revisa tu conexión."
        }
    }
}

/// `infinityx://import?t=<token>` — sent by the web after signing. The token is single-use and lives ~10 min
/// on our server; the certificate itself is fetched over HTTPS from the fixed web host (never from the link).
extension ImportStore {
    func importFromWeb(_ url: URL) async throws {
        guard url.scheme == "infinityx", url.host == "import",
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "t" })?.value,
              token.count == 32, token.allSatisfy({ $0.isHexDigit }) else { throw WebImportError.invalidLink }

        var comps = URLComponents(url: AppInfo.webURL.appendingPathComponent("api/cert"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "t", value: token)]
        guard let endpoint = comps?.url else { throw WebImportError.invalidLink }

        struct Payload: Decodable { let p12: String; let profile: String; let password: String }
        let payload: Payload
        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard let http = response as? HTTPURLResponse else { throw WebImportError.network }
            if http.statusCode == 404 { throw WebImportError.expired }
            guard http.statusCode == 200 else { throw WebImportError.network }
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch let e as WebImportError {
            throw e
        } catch {
            throw WebImportError.network
        }
        guard let p12 = Data(base64Encoded: payload.p12), let profile = Data(base64Encoded: payload.profile) else {
            throw WebImportError.invalidLink
        }

        let stamp = Int(Date().timeIntervalSince1970)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("web-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p12URL = dir.appendingPathComponent("web-\(stamp).p12")
        let profileURL = dir.appendingPathComponent("web-\(stamp).mobileprovision")
        try p12.write(to: p12URL)
        try profile.write(to: profileURL)
        // The password goes under the final file name before the import selects it.
        KeychainStore.setPassword(payload.password, for: p12URL.lastPathComponent)
        enqueue(p12URL, kind: .certificate)
        enqueue(profileURL, kind: .profile)
    }
}
