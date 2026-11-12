import SwiftUI

/// Root: global background, one screen at a time (spring transition), floating tab bar,
/// progress overlay and toasts.
struct ContentView: View {
    @EnvironmentObject var coordinator: InstallCoordinator
    @EnvironmentObject var library: AppLibrary
    @EnvironmentObject var updater: UpdateChecker
    @EnvironmentObject var toaster: Toaster
    @EnvironmentObject var imports: ImportStore
    @EnvironmentObject var log: AppLog
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // The batch state lives here so it survives tab switches (screens are re-created for the entrance animation).
    @StateObject private var batch = BatchViewModel()
    @State private var tab = 2

    private var tabs: [TabItem] {
        [
            TabItem(title: "Certificado", systemImage: "key.fill"),
            TabItem(title: "Apps", systemImage: "square.stack.3d.up.fill"),
            TabItem(title: "Firmar", systemImage: "signature"),
            TabItem(title: "Ajustes", systemImage: "gearshape.fill", badge: updater.badgeVisible),
        ]
    }

    var body: some View {
        ZStack {
            XBackground()

            ZStack {
                switch tab {
                case 0:
                    CertificatesView(batch: batch).transition(screenTransition)
                case 1:
                    AppsView().transition(screenTransition)
                case 2:
                    BatchView(vm: batch).transition(screenTransition)
                default:
                    DiagnosticsView().transition(screenTransition)
                }
            }

            VStack {
                Spacer()
                FloatingTabBar(selection: $tab, items: tabs)
                    .padding(.bottom, 8)
            }
            .ignoresSafeArea(.keyboard)

            VStack(spacing: 0) {
                if !imports.activeImports.isEmpty {
                    ImportBanner(jobs: imports.activeImports)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                if coordinator.isRunning {
                    InstallBanner()
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                if updater.bannerVisible, case .available(let version, _, _) = updater.state {
                    UpdateBanner(version: version, onView: {
                        updater.reveal()
                        withAnimation(Theme.spring) { tab = 3 }
                    }, onClose: {
                        updater.dismissBanner()
                        toaster.show("Te avisaremos de nuevo mañana")
                    })
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .zIndex(8)
            .animation(reduceMotion ? nil : Theme.spring, value: updater.bannerVisible)
            .animation(reduceMotion ? nil : Theme.spring, value: imports.activeImports.isEmpty)
            .animation(reduceMotion ? nil : Theme.spring, value: coordinator.isRunning)

            if batch.showOverlay {
                ProgressOverlay(vm: batch)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
            }

            ToastHost().zIndex(10)
        }
        .animation(Theme.spring, value: batch.showOverlay)
        .preferredColorScheme(.dark)
        .task {
            imports.onFinished = { [weak toaster, weak log] job, result in
                switch result {
                case .success(let name):
                    toaster?.show("\(name) importada")
                case .failure(let error):
                    let msg = error.localizedDescription
                    log?.add("Importar \(job.fileName): \(msg)")
                    toaster?.show(msg, isError: true)
                }
            }
            coordinator.onInstalled = { [weak library] app in
                library?.markInstalled(fileName: app.ipaURL.lastPathComponent)
            }
            await updater.autoCheckIfNeeded()
        }
        // The setter only runs on user dismissal (swipe / Listo); programmatic closes don't call it.
        .sheet(item: Binding(get: { coordinator.safariTarget },
                             set: { if $0 == nil { coordinator.safariDismissedByUser() } })) { target in
            SafariInstallSheet(url: target.url).ignoresSafeArea()
        }
    }

    private var screenTransition: AnyTransition {
        AnyTransition.opacity
            .combined(with: .offset(x: 0, y: 14))
            .combined(with: .scale(scale: 0.985))
    }
}
