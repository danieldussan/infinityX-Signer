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
    case invalidIPA
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .wrongType(let ext): return "El archivo debe ser .\(ext)"
        case .emptyFile: return "El archivo está vacío."
        case .invalidProfile: return "El perfil no es válido (no se pudo leer su contenido)."
        case .notAnIPA: return "El archivo no es un IPA válido (no es un zip)."
        case .invalidIPA: return "La IPA no es válida: no se encontró Info.plist"
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
    /// App metadata per imported IPA file name (persisted in Application Support/ipa-info.json).
    @Published private(set) var ipaInfo: [String: IPAInfo] = [:]
    /// Imports in progress or waiting, oldest first (the first one is running).
    @Published private(set) var activeImports: [ImportJob] = []
    /// Called on the main actor when a job ends (toast/log live in the UI layer).
    var onFinished: ((ImportJob, Result<String, Error>) -> Void)?
    private var pending: [(job: ImportJob, url: URL)] = []
    private var worker: Task<Void, Never>?
    private var infoInFlight: Set<String> = []
    private var infoFailed: Set<String> = []
    private static var infoFile: URL { AppPaths.appSupport.appendingPathComponent("ipa-info.json") }

    init() {
        if let data = try? Data(contentsOf: Self.infoFile),
           let saved = try? JSONDecoder().decode([String: IPAInfo].self, from: data) {
            ipaInfo = saved
        }
        ImportWorker.removePartials()
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

    private func saveInfo() {
        if let data = try? JSONEncoder().encode(ipaInfo) { try? data.write(to: Self.infoFile, options: .atomic) }
    }

    /// Lazily reads metadata of IPAs imported before it was stored. Zip work runs in the background.
    func loadInfoIfNeeded(_ name: String) {
        guard ipaInfo[name] == nil, !infoInFlight.contains(name), !infoFailed.contains(name) else { return }
        infoInFlight.insert(name)
        let url = AppPaths.imports.appendingPathComponent(name)
        Task {
            let info = await Task.detached(priority: .utility) { IPAInfoReader.read(at: url) }.value
            infoInFlight.remove(name)
            if let info, FileManager.default.fileExists(atPath: url.path) {
                ipaInfo[name] = info
                saveInfo()
            } else {
                infoFailed.insert(name)
            }
        }
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

    /// Queues the picked file and returns immediately; the work runs off the main thread, one job at a time.
    func enqueue(_ url: URL, kind: ImportKind) {
        let job = ImportJob(id: UUID(), fileName: url.lastPathComponent, kind: kind,
                            phase: .copying, progress: nil, errorText: nil)
        activeImports.append(job)
        pending.append((job, url))
        guard worker == nil else { return }
        // ponytail: one serial worker, no per-job cancellation.
        worker = Task { [weak self] in
            while let self, !self.pending.isEmpty {
                let next = self.pending.removeFirst()
                await self.run(next.job, url: next.url)
            }
            self?.worker = nil
        }
    }

    private func run(_ job: ImportJob, url: URL) async {
        let id = job.id
        let kind = job.kind
        let report: @Sendable (ImportPhase, Double?) -> Void = { [weak self] phase, progress in
            Task { @MainActor in self?.update(id, phase: phase, progress: progress) }
        }
        let result: Result<ImportOutcome, Error> = await Task.detached(priority: .userInitiated) {
            do { return .success(try ImportWorker.perform(source: url, kind: kind, report: report)) }
            catch { return .failure(error) }
        }.value
        activeImports.removeAll { $0.id == id }
        switch result {
        case .success(let outcome):
            if kind == .ipa {
                if let info = outcome.info { ipaInfo[outcome.name] = info; saveInfo() }
                infoFailed.remove(outcome.name)
            }
            selection[kind] = outcome.name
            refresh()
            Haptics.success()
            onFinished?(job, .success(outcome.name))
        case .failure(let error):
            refresh()
            Haptics.error()
            onFinished?(job, .failure(error))
        }
    }

    private func update(_ id: UUID, phase: ImportPhase, progress: Double?) {
        guard let i = activeImports.firstIndex(where: { $0.id == id }) else { return }
        var job = activeImports[i]
        // Monotonic within a phase: hops to the main actor may arrive out of order.
        if phase == job.phase, let old = job.progress, let new = progress { job.progress = max(old, new) }
        else { job.progress = progress }
        job.phase = phase
        if job != activeImports[i] { activeImports[i] = job }
    }

    func delete(_ name: String, kind: ImportKind) {
        try? FileManager.default.removeItem(at: AppPaths.imports.appendingPathComponent(name))
        if kind == .certificate { KeychainStore.deletePassword(for: name) }
        if kind == .ipa, ipaInfo.removeValue(forKey: name) != nil { saveInfo() }
        refresh()
    }
}

enum ImportPhase: Equatable, Sendable {
    case copying, reading

    var text: String { self == .copying ? "Copiando…" : "Leyendo información…" }
}

struct ImportJob: Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let kind: ImportKind
    var phase: ImportPhase
    /// 0...1, nil when indeterminate.
    var progress: Double?
    var errorText: String?
}

// @unchecked: IPAInfo is an immutable value type from Core (not declared Sendable there); handed over once.
struct ImportOutcome: @unchecked Sendable {
    let name: String
    let info: IPAInfo?
}

/// Blocking import work; always call from a background task.
enum ImportWorker {
    private static let chunk = 4 * 1024 * 1024
    private static let partialPrefix = ".partial-"

    /// Partial copies left by a killed app (hidden names, never listed).
    static func removePartials() {
        let fm = FileManager.default
        for n in (try? fm.contentsOfDirectory(atPath: AppPaths.imports.path)) ?? [] where n.hasPrefix(partialPrefix) {
            try? fm.removeItem(at: AppPaths.imports.appendingPathComponent(n))
        }
    }

    static func perform(source: URL, kind: ImportKind,
                        report: @escaping @Sendable (ImportPhase, Double?) -> Void) throws -> ImportOutcome {
        let fm = FileManager.default
        // Harmless with asCopy pickers; needed if a security-scoped URL ever arrives.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var moved = false
        // The picker's temp copy is ours: drop it unless it was moved into Imports.
        defer { if !moved { try? fm.removeItem(at: source) } }

        guard source.pathExtension.lowercased() == kind.rawValue else { throw ImportError.wrongType(kind.rawValue) }
        let size = ((try? fm.attributesOfItem(atPath: source.path))?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw ImportError.emptyFile }
        var info: IPAInfo?
        switch kind {
        case .profile:
            guard let data = try? Data(contentsOf: source), (try? ProvisioningProfile(data: data)) != nil else {
                throw ImportError.invalidProfile
            }
        case .ipa:
            // Header only: IPAs can be hundreds of MB, never load them in memory.
            let header = (try? FileHandle(forReadingFrom: source)).flatMap { h -> Data? in
                defer { try? h.close() }
                return try? h.read(upToCount: 2)
            }
            guard let h = header, h.count == 2, h[h.startIndex] == 0x50, h[h.startIndex + 1] == 0x4B else {
                throw ImportError.notAnIPA
            }
            // Validate before touching the destination so a bad IPA never replaces a good one.
            report(.reading, nil)
            info = IPAInfoReader.read(at: source)
            guard info != nil else { throw ImportError.invalidIPA }
        case .certificate:
            break
        }

        report(.copying, nil)
        let name = source.lastPathComponent
        let dest = AppPaths.imports.appendingPathComponent(name)
        do {
            if (try? install(source, to: dest, move: true, size: size, report: report)) == nil {
                try install(source, to: dest, move: false, size: size, report: report)
            } else {
                moved = true
            }
        } catch {
            throw ImportError.copyFailed(error.localizedDescription)
        }
        return ImportOutcome(name: name, info: info)
    }

    /// Move (instant, same volume) or chunked copy to a hidden partial, then swap into place atomically.
    private static func install(_ source: URL, to dest: URL, move: Bool, size: Int64,
                                report: @Sendable (ImportPhase, Double?) -> Void) throws {
        let fm = FileManager.default
        var staged = source
        if !move {
            staged = AppPaths.imports.appendingPathComponent(partialPrefix + UUID().uuidString)
            do { try chunkedCopy(source, to: staged, size: size, report: report) }
            catch { try? fm.removeItem(at: staged); throw error }
        }
        do {
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: staged)
            } else {
                try fm.moveItem(at: staged, to: dest)
            }
        } catch {
            if !move { try? fm.removeItem(at: staged) }
            throw error
        }
    }

    private static func chunkedCopy(_ source: URL, to dest: URL, size: Int64,
                                    report: @Sendable (ImportPhase, Double?) -> Void) throws {
        guard FileManager.default.createFile(atPath: dest.path, contents: nil) else {
            throw ImportError.copyFailed("no se pudo crear el archivo temporal")
        }
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: dest)
        defer { try? input.close(); try? output.close() }
        var copied: Int64 = 0
        var last = DispatchTime.now().uptimeNanoseconds
        report(.copying, 0)
        while true {
            let data = try autoreleasepool { try input.read(upToCount: chunk) }
            guard let data, !data.isEmpty else { break }
            try output.write(contentsOf: data)
            copied += Int64(data.count)
            let now = DispatchTime.now().uptimeNanoseconds
            if now - last >= 100_000_000 {  // at most ~10 updates per second
                last = now
                report(.copying, min(1, Double(copied) / Double(size)))
            }
        }
        report(.copying, 1)
    }
}
