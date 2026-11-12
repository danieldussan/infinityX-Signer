import Foundation
import InfinityXCore

struct BatchRow: Identifiable {
    let job: SigningJob
    var state: RowState
    var id: Int { job.number }
}

enum BatchMode: Int {
    case range = 0
    case count = 1
}

/// Live preview of the jobs the current inputs would produce.
struct BatchPreview {
    var jobs: [SigningJob]
    var error: String?
}

/// What the main button shows and whether signing is allowed.
struct SignGate {
    let title: String
    /// Extra explanation under the button (profile expired, bundle not covered...).
    let reason: String?
    let enabled: Bool
}

@MainActor
final class BatchViewModel: ObservableObject {
    @Published var namePrefix: String = UserDefaults.standard.string(forKey: "batch.name") ?? "WAB" {
        didSet { UserDefaults.standard.set(namePrefix, forKey: "batch.name") }
    }
    @Published var bundlePrefix: String = UserDefaults.standard.string(forKey: "batch.bundle") ?? "chip" {
        didSet { UserDefaults.standard.set(bundlePrefix, forKey: "batch.bundle") }
    }
    @Published var mode: BatchMode = .range
    @Published var numbersText = ""
    @Published var count = 3
    @Published var stripPlugins = false
    @Published var rows: [BatchRow] = []
    @Published var errorText: String?
    @Published var isRunning = false
    @Published var isInstalling = false
    @Published var showOverlay = false
    @Published private(set) var signed: [SignedApp] = []
    @Published var counterLast = UserDefaultsCounterStore().last

    private let engine = SigningEngine()

    func refreshCounter() {
        counterLast = UserDefaultsCounterStore().last
    }

    func changeCount(by delta: Int) {
        count = min(30, max(1, count + delta))
    }

    // MARK: Preview and gating

    private var trimmedNamePrefix: String { namePrefix.trimmingCharacters(in: .whitespaces) }
    private var trimmedBundlePrefix: String { bundlePrefix.trimmingCharacters(in: .whitespaces) }

    func preview() -> BatchPreview {
        let input: BatchInput
        switch mode {
        case .range:
            let text = numbersText.trimmingCharacters(in: .whitespaces)
            // Empty text would mean "next 1" in makeJobs; here it just means "nothing typed yet".
            if text.isEmpty { return BatchPreview(jobs: [], error: nil) }
            input = BatchInput(namePrefix: trimmedNamePrefix, bundlePrefix: trimmedBundlePrefix,
                               numbersText: text, count: nil, stripPlugins: stripPlugins)
        case .count:
            input = BatchInput(namePrefix: trimmedNamePrefix, bundlePrefix: trimmedBundlePrefix,
                               numbersText: nil, count: count, stripPlugins: stripPlugins)
        }
        do {
            return BatchPreview(jobs: try makeJobs(input, lastUsed: counterLast), error: nil)
        } catch let e as BatchError {
            return BatchPreview(jobs: [], error: Self.message(for: e))
        } catch {
            return BatchPreview(jobs: [], error: error.localizedDescription)
        }
    }

    func gate(imports: ImportStore) -> SignGate {
        if isRunning { return SignGate(title: "Trabajando...", reason: nil, enabled: false) }
        if imports.url(for: .certificate) == nil || imports.url(for: .profile) == nil || imports.url(for: .ipa) == nil {
            return SignGate(title: "Falta importar archivos", reason: nil, enabled: false)
        }
        guard let profile = imports.profile else {
            return SignGate(title: "Perfil ilegible",
                            reason: imports.profileError ?? "No se pudo leer el perfil.", enabled: false)
        }
        if profile.status() == .expired {
            let when = profile.expirationDate.map { " el \(Fmt.date($0))" } ?? ""
            return SignGate(title: "Perfil vencido",
                            reason: "El perfil venció\(when). Importa uno nuevo en la pestaña Certificado.", enabled: false)
        }
        if trimmedBundlePrefix.isEmpty || trimmedNamePrefix.isEmpty {
            return SignGate(title: "Faltan prefijos", reason: "Escribe el prefijo de nombre y el de bundle.", enabled: false)
        }
        let p = preview()
        if p.error != nil {
            return SignGate(title: mode == .range ? "Revisa el rango" : "Revisa la cantidad", reason: nil, enabled: false)
        }
        if p.jobs.isEmpty {
            return SignGate(title: "Escribe un rango", reason: nil, enabled: false)
        }
        // ponytail: no App ID coverage check. Profiles with an exact App ID still install with a different
        // bundle id when re-signed with Zsign -b (verified with signer.py and Feather), so a check only blocks valid use.
        let n = p.jobs.count
        return SignGate(title: "Firmar \(n) app\(n == 1 ? "" : "s")", reason: nil, enabled: true)
    }

    // MARK: Run

    func start(imports: ImportStore, log: AppLog) {
        guard !isRunning else { return }
        errorText = nil

        guard let ipa = imports.url(for: .ipa),
              let p12 = imports.url(for: .certificate),
              let profile = imports.url(for: .profile),
              let certName = imports.selectedName(.certificate) else {
            errorText = "Selecciona un certificado, un perfil y un IPA."
            return
        }
        let p = preview()
        guard p.error == nil, !p.jobs.isEmpty else {
            errorText = p.error ?? "Escribe al menos un número o una cantidad."
            return
        }
        let jobs = p.jobs

        let request = SigningRequest(ipaURL: ipa, p12URL: p12, profileURL: profile,
                                     password: KeychainStore.password(for: certName) ?? "",
                                     stripPlugins: stripPlugins)
        rows = jobs.map { BatchRow(job: $0, state: .pending) }
        signed = []
        isRunning = true
        showOverlay = true
        KeepAlive.shared.start()

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let result = await self.engine.run(request: request, jobs: jobs) { [weak self] number, state in
                self?.update(number, state, log: log)
            }
            self.signed = result
            self.refreshCounter()
            KeepAlive.shared.stop()
            self.isRunning = false
            if !result.isEmpty { Haptics.success() } else { Haptics.error() }
        }
    }

    /// Runs the existing install queue for the signed apps (Semi Local / Local).
    func install(coordinator: InstallCoordinator) {
        guard !isRunning, !isInstalling, !signed.isEmpty else { return }
        isInstalling = true
        KeepAlive.shared.start()
        let apps = signed
        Task { @MainActor [weak self] in
            await coordinator.installAll(apps)
            KeepAlive.shared.stop()
            self?.isInstalling = false
            Haptics.success()
        }
    }

    // MARK: Progress

    var finishedCount: Int {
        rows.filter {
            switch $0.state {
            case .signed, .failed: return true
            default: return false
            }
        }.count
    }

    var progress: Double {
        rows.isEmpty ? 0 : Double(finishedCount) / Double(rows.count)
    }

    private func update(_ number: Int, _ state: RowState, log: AppLog) {
        if let i = rows.firstIndex(where: { $0.job.number == number }) {
            rows[i].state = state
        }
        if case .failed(let message) = state {
            log.add("Firma #\(number): \(message)")
        }
    }

    private static func message(for error: BatchError) -> String {
        switch error {
        case .invalidNumber(let s): return "Formato inválido: \(s). Ejemplo: 21-25 o 21,23"
        case .empty: return "Escribe al menos un número o una cantidad."
        case .negative: return "No se permiten números negativos."
        case .bothRangeAndCount: return "Usa el rango o la cantidad, no ambos."
        case .countTooSmall: return "La cantidad debe ser al menos 1."
        }
    }
}
