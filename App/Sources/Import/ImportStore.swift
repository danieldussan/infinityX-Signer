import Foundation
import InfinityXCore

enum ImportKind: String, CaseIterable, Identifiable {
    case certificate = "p12"
    case profile = "mobileprovision"
    case ipa = "ipa"

    var title: String {
        switch self {
        case .certificate: return "Certificados (.p12)"
        case .profile: return "Perfiles (.mobileprovision)"
        case .ipa: return "IPAs"
        }
    }

    var importLabel: String {
        switch self {
        case .certificate: return "Importar .p12"
        case .profile: return "Importar perfil"
        case .ipa: return "Importar IPA"
        }
    }

    var selectionKey: String { "selected." + rawValue }
    var id: String { rawValue }

    var importedLabel: String {
        switch self {
        case .certificate: return "Certificado importado"
        case .profile: return "Perfil importado"
        case .ipa: return "IPA importada"
        }
    }
}

enum ImportError: LocalizedError {
    case wrongType(String)
    case emptyFile
    case invalidProfile
    case notAnIPA
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .wrongType(let ext): return "El archivo debe ser .\(ext)"
        case .emptyFile: return "El archivo está vacío."
        case .invalidProfile: return "El perfil no es válido (no se pudo leer su contenido)."
        case .notAnIPA: return "El archivo no es un IPA válido (no es un zip)."
        case .copyFailed(let m): return "No se pudo copiar el archivo: \(m)"
        }
    }
}

/// Copies picked files into Documents/Imports and remembers the current selection per kind.
@MainActor
final class ImportStore: ObservableObject {
    @Published private(set) var names: [ImportKind: [String]] = [:]
    @Published private(set) var selection: [ImportKind: String] = [:]
    /// Parsed selected .mobileprovision (nil when none selected or unreadable).
    @Published private(set) var profile: ProvisioningProfile?
    @Published private(set) var profileError: String?

    init() {
        for kind in ImportKind.allCases {
            if let s = UserDefaults.standard.string(forKey: kind.selectionKey) {
                selection[kind] = s
            }
        }
        refresh()
    }

    func refresh() {
        for kind in ImportKind.allCases {
            let all = (try? FileManager.default.contentsOfDirectory(atPath: AppPaths.imports.path)) ?? []
            let filtered = all.filter { $0.lowercased().hasSuffix("." + kind.rawValue) }.sorted()
            names[kind] = filtered
            if let sel = selection[kind], !filtered.contains(sel) { selection[kind] = nil }
            if selection[kind] == nil, let first = filtered.first { selection[kind] = first }
            UserDefaults.standard.set(selection[kind], forKey: kind.selectionKey)
        }
        reloadProfile()
    }

    private func reloadProfile() {
        profile = nil
        profileError = nil
        guard let url = url(for: .profile) else { return }
        do {
            profile = try ProvisioningProfile(data: try Data(contentsOf: url))
        } catch {
            profileError = "No se pudo leer el perfil seleccionado."
        }
    }

    func fileSize(_ name: String) -> Int64? {
        fileSize(at: AppPaths.imports.appendingPathComponent(name))
    }

    private func fileSize(at url: URL) -> Int64? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value
    }

    func selectedName(_ kind: ImportKind) -> String? { selection[kind] }

    func select(_ name: String, kind: ImportKind) {
        selection[kind] = name
        UserDefaults.standard.set(name, forKey: kind.selectionKey)
        if kind == .profile { reloadProfile() }
    }

    func url(for kind: ImportKind) -> URL? {
        guard let name = selection[kind] else { return nil }
        return AppPaths.imports.appendingPathComponent(name)
    }

    /// Copies the picked file into Documents/Imports (replacing a same-named one), validates it and selects it.
    @discardableResult
    func importFile(from url: URL, kind: ImportKind) throws -> String {
        // Harmless with asCopy pickers; needed if a security-scoped URL ever arrives.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.pathExtension.lowercased() == kind.rawValue else {
            throw ImportError.wrongType(kind.rawValue)
        }
        let size = fileSize(at: url) ?? 0
        guard size > 0 else { throw ImportError.emptyFile }
        switch kind {
        case .profile:
            guard let data = try? Data(contentsOf: url), (try? ProvisioningProfile(data: data)) != nil else {
                throw ImportError.invalidProfile
            }
        case .ipa:
            // Header only: IPAs can be hundreds of MB, never load them in memory.
            let header = (try? FileHandle(forReadingFrom: url)).flatMap { h -> Data? in
                defer { try? h.close() }
                return try? h.read(upToCount: 2)
            }
            guard let h = header, h.count == 2, h[h.startIndex] == 0x50, h[h.startIndex + 1] == 0x4B else {
                throw ImportError.notAnIPA
            }
        case .certificate:
            break
        }
        let name = url.lastPathComponent
        let dest = AppPaths.imports.appendingPathComponent(name)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            throw ImportError.copyFailed(error.localizedDescription)
        }
        selection[kind] = name
        refresh()
        return name
    }

    func delete(_ name: String, kind: ImportKind) {
        try? FileManager.default.removeItem(at: AppPaths.imports.appendingPathComponent(name))
        if kind == .certificate { KeychainStore.deletePassword(for: name) }
        refresh()
    }
}
