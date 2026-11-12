import Foundation
import InfinityXCore

struct BatchRow: Identifiable {
    let job: SigningJob
    var state: RowState
    var id: Int { job.number }
}

@MainActor
final class BatchViewModel: ObservableObject {
    @Published var namePrefix: String = UserDefaults.standard.string(forKey: "batch.name") ?? "WAB" {
        didSet { UserDefaults.standard.set(namePrefix, forKey: "batch.name") }
    }
    @Published var bundlePrefix: String = UserDefaults.standard.string(forKey: "batch.bundle") ?? "chip" {
        didSet { UserDefaults.standard.set(bundlePrefix, forKey: "batch.bundle") }
    }
    @Published var numbersText = ""
    @Published var countText = ""
    @Published var stripPlugins = false
    @Published var rows: [BatchRow] = []
    @Published var errorText: String?
    @Published var isRunning = false
    @Published var counterLast = UserDefaultsCounterStore().last

    private let engine = SigningEngine()

    func refreshCounter() {
        counterLast = UserDefaultsCounterStore().last
    }

    func start(imports: ImportStore, coordinator: InstallCoordinator, log: AppLog) {
        guard !isRunning else { return }
        errorText = nil

        guard let ipa = imports.url(for: .ipa),
              let p12 = imports.url(for: .certificate),
              let profile = imports.url(for: .profile),
              let certName = imports.selectedName(.certificate) else {
            errorText = "Selecciona un certificado, un perfil y un IPA."
            return
        }

        let trimmedCount = countText.trimmingCharacters(in: .whitespaces)
        var count: Int?
        if !trimmedCount.isEmpty {
            guard let n = Int(trimmedCount) else {
                errorText = "La cantidad debe ser un número entero."
                return
            }
            count = n
        }
        let trimmedNumbers = numbersText.trimmingCharacters(in: .whitespaces)
        let input = BatchInput(namePrefix: namePrefix,
                               bundlePrefix: bundlePrefix,
                               numbersText: trimmedNumbers.isEmpty ? nil : trimmedNumbers,
                               count: count,
                               stripPlugins: stripPlugins)

        let jobs: [SigningJob]
        do {
            jobs = try makeJobs(input, lastUsed: UserDefaultsCounterStore().last)
        } catch let e as BatchError {
            errorText = Self.message(for: e)
            return
        } catch {
            errorText = error.localizedDescription
            return
        }

        let request = SigningRequest(ipaURL: ipa, p12URL: p12, profileURL: profile,
                                     password: KeychainStore.password(for: certName) ?? "",
                                     stripPlugins: stripPlugins)
        rows = jobs.map { BatchRow(job: $0, state: .pending) }
        isRunning = true
        KeepAlive.shared.start()

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let signed = await self.engine.run(request: request, jobs: jobs) { [weak self] number, state in
                self?.update(number, state, log: log)
            }
            self.refreshCounter()
            if !signed.isEmpty {
                await coordinator.installAll(signed)
            }
            KeepAlive.shared.stop()
            self.isRunning = false
        }
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
        case .invalidNumber(let s): return "Número inválido: \(s)"
        case .empty: return "Escribe al menos un número o una cantidad."
        case .negative: return "No se permiten números negativos."
        case .bothRangeAndCount: return "Usa el rango o la cantidad, no ambos."
        case .countTooSmall: return "La cantidad debe ser al menos 1."
        }
    }
}
