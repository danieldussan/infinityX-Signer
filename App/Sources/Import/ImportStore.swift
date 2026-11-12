import Foundation

enum ImportKind: String, CaseIterable {
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
}

enum ImportError: LocalizedError {
    case wrongType(String)

    var errorDescription: String? {
        switch self {
        case .wrongType(let ext): return "El archivo debe ser .\(ext)"
        }
    }
}

/// Copies picked files into Documents/Imports and remembers the current selection per kind.
@MainActor
final class ImportStore: ObservableObject {
    @Published private(set) var names: [ImportKind: [String]] = [:]
    @Published private(set) var selection: [ImportKind: String] = [:]

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
    }

    func selectedName(_ kind: ImportKind) -> String? { selection[kind] }

    func select(_ name: String, kind: ImportKind) {
        selection[kind] = name
        UserDefaults.standard.set(name, forKey: kind.selectionKey)
    }

    func url(for kind: ImportKind) -> URL? {
        guard let name = selection[kind] else { return nil }
        return AppPaths.imports.appendingPathComponent(name)
    }

    func importFile(from url: URL, kind: ImportKind) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.pathExtension.lowercased() == kind.rawValue else {
            throw ImportError.wrongType(kind.rawValue)
        }
        let dest = AppPaths.imports.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        selection[kind] = url.lastPathComponent
        refresh()
    }

    func delete(_ name: String, kind: ImportKind) {
        try? FileManager.default.removeItem(at: AppPaths.imports.appendingPathComponent(name))
        if kind == .certificate { KeychainStore.deletePassword(for: name) }
        refresh()
    }
}
