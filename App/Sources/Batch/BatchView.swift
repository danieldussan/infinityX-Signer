import SwiftUI
import InfinityXCore

struct BatchView: View {
    @EnvironmentObject var imports: ImportStore
    @EnvironmentObject var coordinator: InstallCoordinator
    @EnvironmentObject var log: AppLog
    @StateObject private var vm = BatchViewModel()

    var body: some View {
        Screen("Firmar") {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    field("Prefijo de nombre", text: $vm.namePrefix)
                    field("Prefijo de bundle id", text: $vm.bundlePrefix)
                    field("Rango (21-25, 21,23)", text: $vm.numbersText)
                    field("o siguientes N", text: $vm.countText, numeric: true)
                    Toggle("Quitar plugins (PlugIns/Extensions)", isOn: $vm.stripPlugins)
                        .font(Theme.body).foregroundColor(Theme.text)
                        .tint(Theme.accent)
                    Text("Último número usado: \(vm.counterLast) (el siguiente será \(vm.counterLast + 1))")
                        .font(Theme.caption).foregroundColor(Theme.secondaryText)
                }
            }
            if let error = vm.errorText {
                Text(error).font(Theme.body).foregroundColor(Theme.danger)
            }
            Button(vm.isRunning ? "Trabajando..." : "Firmar") {
                vm.start(imports: imports, coordinator: coordinator, log: log)
            }
            .buttonStyle(PrimaryButtonStyle(enabled: !vm.isRunning))
            .disabled(vm.isRunning)

            if !vm.rows.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.rows) { row in
                            rowView(row)
                        }
                    }
                }
            }
        }
        .onAppear { vm.refreshCounter() }
    }

    private func field(_ title: String, text: Binding<String>, numeric: Bool = false) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            .keyboardType(numeric ? .numberPad : .default)
    }

    private func rowView(_ row: BatchRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(row.job.displayName)  ·  \(row.job.bundleID)")
                    .font(Theme.body).foregroundColor(Theme.text)
                Spacer()
                if case .signed(let url) = row.state {
                    ExportButton(url: url)
                }
            }
            Text(statusText(row))
                .font(Theme.caption)
                .foregroundColor(isFailure(row) ? Theme.danger : Theme.secondaryText)
        }
    }

    private func installState(_ row: BatchRow) -> InstallState? {
        coordinator.items.first { $0.app.job.number == row.job.number }?.state
    }

    private func isFailure(_ row: BatchRow) -> Bool {
        if case .failed = row.state { return true }
        if let s = installState(row), case .failed = s { return true }
        return false
    }

    private func statusText(_ row: BatchRow) -> String {
        switch row.state {
        case .pending: return "En cola"
        case .signing: return "Firmando..."
        case .failed(let m): return "Error: \(m)"
        case .signed:
            if let s = installState(row) { return "Firmado · \(s.label)" }
            return "Firmado"
        }
    }
}
