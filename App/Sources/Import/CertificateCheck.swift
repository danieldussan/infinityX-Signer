import Foundation
import Security
import InfinityXCore

enum PasswordCheck: Equatable {
    case idle
    case checking
    case correct(subject: String?, expiry: Date?, leafDER: Data?)
    case wrong
    case unreadable(String)
}

/// Validates a .p12 password with the system PKCS#12 importer.
/// ponytail: Zsign's p12_password_check is not in ZsignC's public headers (swift/utils.hpp), so it is not
/// callable from Swift; SecPKCS12Import is the fallback. Only errSecAuthFailed is reported as "incorrect".
enum P12Inspector {
    static func check(url: URL, password: String) -> PasswordCheck {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return .unreadable("No se pudo leer el archivo .p12")
        }
        var options: [String: Any] = [
            kSecImportExportPassphrase as String: password,
        ]
        // ponytail: kSecImportToMemoryOnly exists only on iOS 18+; older iOS may keep the imported key in the keychain.
        if #available(iOS 18.0, *) {
            options[kSecImportToMemoryOnly as String] = true
        }
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        if status == errSecAuthFailed { return .wrong }
        guard status == errSecSuccess else {
            return .unreadable("No se pudo verificar el .p12 (código \(status))")
        }
        guard let list = items as? [[String: Any]],
              let first = list.first,
              let chain = first[kSecImportItemCertChain as String] as? [SecCertificate],
              let leaf = chain.first else {
            return .correct(subject: nil, expiry: nil, leafDER: nil)
        }
        let der = SecCertificateCopyData(leaf) as Data
        let subject = SecCertificateCopySubjectSummary(leaf) as String?
        return .correct(subject: subject, expiry: certificateNotAfter(der: der), leafDER: der)
    }
}

/// Debounced password check for the selected .p12.
@MainActor
final class CertChecker: ObservableObject {
    @Published private(set) var result: PasswordCheck = .idle
    private var task: Task<Void, Never>?

    func schedule(url: URL?, password: String) {
        task?.cancel()
        guard let url = url else {
            result = .idle
            return
        }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            self?.result = .checking
            let r = await Task.detached(priority: .userInitiated) {
                P12Inspector.check(url: url, password: password)
            }.value
            if Task.isCancelled { return }
            self?.result = r
        }
    }
}
