import SwiftUI
import InfinityXCore

/// Full-screen blurred overlay: overall bar, one row per job, and the final actions.
struct ProgressOverlay: View {
    @ObservedObject var vm: BatchViewModel
    @EnvironmentObject var coordinator: InstallCoordinator
    @EnvironmentObject var toaster: Toaster
    @State private var shareItems: [URL] = []
    @State private var showShare = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.72).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        BrandLogo()
                        Spacer()
                        StatusChip(text: chipText, color: vm.isRunning || vm.isInstalling ? Theme.blue : Theme.green)
                    }
                    .padding(.top, 8)
                    Text(titleText).font(Theme.screenTitle).foregroundColor(Theme.text)
                    progressBar
                    ForEach(Array(vm.rows.enumerated()), id: \.element.id) { index, row in
                        jobRow(row).rise(index)
                    }
                    if !vm.isRunning { actions }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: shareItems)
        }
    }

    private var chipText: String {
        if vm.isRunning { return "Firmando..." }
        if vm.isInstalling { return "Instalando..." }
        return "Listo"
    }

    private var titleText: String {
        let n = vm.rows.count
        if vm.isRunning { return "Firmando \(n) app\(n == 1 ? "" : "s")" }
        if vm.signed.isEmpty { return "No se pudo firmar" }
        return "¡Firmado!"
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.blue, Theme.green], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(vm.progress))
            }
        }
        .frame(height: 8)
        .padding(.vertical, 6)
        .animation(.easeOut(duration: 0.5), value: vm.progress)
    }

    private func installState(_ row: BatchRow) -> InstallState? {
        coordinator.items.first { $0.app.job.number == row.job.number }?.state
    }

    private func jobRow(_ row: BatchRow) -> some View {
        HStack(spacing: 12) {
            stateIcon(row).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.job.displayName).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                Text(metaText(row))
                    .font(Theme.meta)
                    .foregroundColor(isFailure(row) ? Theme.red : Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func stateIcon(_ row: BatchRow) -> some View {
        switch row.state {
        case .pending:
            Circle().fill(Theme.text3).frame(width: 10, height: 10)
        case .signing:
            SpinnerRing()
        case .signed:
            if let s = installState(row), case .failed = s {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundColor(Theme.red)
            } else if let s = installState(row), !s.isFinal {
                SpinnerRing()
            } else {
                Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundColor(Theme.green)
            }
        case .failed:
            Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundColor(Theme.red)
        }
    }

    private func isFailure(_ row: BatchRow) -> Bool {
        if case .failed = row.state { return true }
        if let s = installState(row), case .failed = s { return true }
        return false
    }

    private func metaText(_ row: BatchRow) -> String {
        let id = row.job.bundleID
        switch row.state {
        case .pending: return "\(id) · en cola"
        case .signing: return "\(id) · firmando..."
        case .failed(let m): return "Falló: \(m)"
        case .signed:
            if let s = installState(row) { return "\(id) · \(s.label)" }
            return "\(id) · firmada"
        }
    }

    /// True once the install queue ran and every app installed (nothing left to retry).
    private var allInstalled: Bool {
        guard vm.installFinished else { return false }
        return !coordinator.items.contains { item in
            if case .failed = item.state { return true }
            return false
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if !vm.signed.isEmpty && coordinator.mode != .export && !allInstalled {
                Button {
                    vm.install(coordinator: coordinator)
                } label: {
                    Text(vm.isInstalling ? "Instalando..." : (vm.installFinished ? "Reintentar instalación" : "Instalar \(vm.signed.count)"))
                }
                .buttonStyle(CTAButtonStyle(enabled: !vm.isInstalling))
                .disabled(vm.isInstalling)
            }
            if !vm.signed.isEmpty && !allInstalled {
                Button("Exportar IPAs") {
                    shareItems = vm.signed.map { $0.ipaURL }
                    showShare = true
                }
                .buttonStyle(GhostButtonStyle())
            }
            Button(allInstalled ? "Listo" : "Cerrar") {
                let keptForLater = !allInstalled && !vm.signed.isEmpty && !vm.isInstalling
                vm.finish()
                if keptForLater { toaster.show("Guardadas en Apps › Firmadas") }
            }
                .buttonStyle(GhostButtonStyle(height: 48))
        }
        .padding(.top, 12)
    }
}
