import Foundation
import Network
import Security

enum TLSIdentityError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}

/// Minimal DER walker, just enough for PKCS#8 -> PKCS#1 and the certificate notAfter date.
enum DER {
    typealias Node = (tag: UInt8, start: Int, end: Int)

    static func read(_ d: [UInt8], at i: Int) -> Node? {
        guard i + 2 <= d.count else { return nil }
        let tag = d[i]
        var len = Int(d[i + 1])
        var p = i + 2
        if len & 0x80 != 0 {
            let n = len & 0x7F
            guard n >= 1, n <= 4, p + n <= d.count else { return nil }
            len = 0
            for _ in 0..<n {
                len = (len << 8) | Int(d[p])
                p += 1
            }
        }
        guard p + len <= d.count else { return nil }
        return (tag, p, p + len)
    }

    static func children(_ d: [UInt8], _ node: Node) -> [Node] {
        var out: [Node] = []
        var i = node.start
        while i < node.end, let n = read(d, at: i) {
            out.append(n)
            i = n.end
        }
        return out
    }

    /// RSA private key inside a PKCS#8 wrapper.
    static func pkcs1(fromPKCS8 data: Data) -> Data? {
        let d = [UInt8](data)
        guard let root = read(d, at: 0), root.tag == 0x30 else { return nil }
        let kids = children(d, root)
        guard kids.count >= 3, kids[2].tag == 0x04 else { return nil }
        return Data(d[kids[2].start..<kids[2].end])
    }

    /// notAfter of an X.509 certificate (DER).
    static func notAfter(ofCertificate data: Data) -> Date? {
        let d = [UInt8](data)
        guard let root = read(d, at: 0), root.tag == 0x30 else { return nil }
        let top = children(d, root)
        guard let tbs = top.first, tbs.tag == 0x30 else { return nil }
        let kids = children(d, tbs)
        let offset = (kids.first?.tag == 0xA0) ? 1 : 0
        guard kids.count > offset + 3 else { return nil }
        let validity = children(d, kids[offset + 3])
        guard validity.count == 2 else { return nil }
        let t = validity[1]
        guard let text = String(bytes: d[t.start..<t.end], encoding: .ascii) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = (t.tag == 0x18) ? "yyyyMMddHHmmss'Z'" : "yyMMddHHmmss'Z'"
        return f.date(from: text)
    }
}

enum PEM {
    /// All blocks as (label, DER bytes).
    static func blocks(_ text: String) -> [(label: String, data: Data)] {
        var out: [(label: String, data: Data)] = []
        var label: String?
        var body = ""
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("-----BEGIN ") {
                label = line.replacingOccurrences(of: "-----BEGIN ", with: "").replacingOccurrences(of: "-----", with: "")
                body = ""
            } else if line.hasPrefix("-----END ") {
                if let l = label, let data = Data(base64Encoded: body) { out.append((l, data)) }
                label = nil
            } else if label != nil {
                body += line
            }
        }
        return out
    }
}

/// Builds a SecIdentity from the cached PEM key + certificate. EXPERIMENTAL (Fully Local mode).
enum TLSIdentity {
    private static let keyTag = Data("com.infinityx.signer.tls.key".utf8)
    private static let certLabel = "com.infinityx.signer.tls.cert"

    static func make(certPEM: String, keyPEM: String, caPEM: String?) throws -> sec_identity_t {
        guard let leafDER = PEM.blocks(certPEM).first(where: { $0.label == "CERTIFICATE" })?.data,
              let leaf = SecCertificateCreateWithData(nil, leafDER as CFData) else {
            throw TLSIdentityError.message("Certificado SSL ilegible")
        }
        guard let keyBlock = PEM.blocks(keyPEM).first else {
            throw TLSIdentityError.message("Clave SSL ilegible")
        }
        var keyDER = keyBlock.data
        if keyBlock.label == "PRIVATE KEY" {
            guard let pkcs1 = DER.pkcs1(fromPKCS8: keyDER) else {
                throw TLSIdentityError.message("Clave PKCS#8 no soportada")
            }
            keyDER = pkcs1
        } else if keyBlock.label != "RSA PRIVATE KEY" {
            // ponytail: RSA keys only; EC keys would need X9.63 conversion.
            throw TLSIdentityError.message("Tipo de clave no soportado: \(keyBlock.label)")
        }

        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var cfError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyDER as CFData, keyAttrs as CFDictionary, &cfError) else {
            let reason = cfError?.takeRetainedValue().localizedDescription ?? "desconocido"
            throw TLSIdentityError.message("No se pudo importar la clave SSL: \(reason)")
        }

        // Replace any previous items, then add key + cert so the keychain can pair them into an identity.
        SecItemDelete([kSecClass as String: kSecClassKey,
                       kSecAttrApplicationTag as String: keyTag] as CFDictionary)
        SecItemDelete([kSecClass as String: kSecClassCertificate,
                       kSecAttrLabel as String: certLabel] as CFDictionary)
        let addKey = SecItemAdd([kSecClass as String: kSecClassKey,
                                 kSecValueRef as String: key,
                                 kSecAttrApplicationTag as String: keyTag] as CFDictionary, nil)
        let addCert = SecItemAdd([kSecClass as String: kSecClassCertificate,
                                  kSecValueRef as String: leaf,
                                  kSecAttrLabel as String: certLabel] as CFDictionary, nil)
        guard addKey == errSecSuccess, addCert == errSecSuccess else {
            throw TLSIdentityError.message("Keychain rechazó la clave/certificado (\(addKey)/\(addCert))")
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass as String: kSecClassIdentity,
                                          kSecReturnRef as String: true,
                                          kSecAttrLabel as String: certLabel] as CFDictionary, &result)
        guard status == errSecSuccess, let ref = result, CFGetTypeID(ref) == SecIdentityGetTypeID() else {
            throw TLSIdentityError.message("No se pudo formar la identidad TLS (\(status))")
        }
        let identity = ref as! SecIdentity

        var chain: [SecCertificate] = []
        if let ca = caPEM {
            for block in PEM.blocks(ca) where block.label == "CERTIFICATE" {
                if let c = SecCertificateCreateWithData(nil, block.data as CFData) { chain.append(c) }
            }
        }
        var created: sec_identity_t?
        if !chain.isEmpty {
            created = sec_identity_create_with_certificates(identity, chain as CFArray)
        }
        if created == nil {
            created = sec_identity_create(identity)
        }
        guard let result = created else {
            throw TLSIdentityError.message("sec_identity_create falló")
        }
        return result
    }
}
