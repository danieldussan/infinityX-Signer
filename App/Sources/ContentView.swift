import SwiftUI

/// Root: global background, one screen at a time (spring transition), floating tab bar,
/// progress overlay and toasts.
struct ContentView: View {
    @EnvironmentObject var coordinator: InstallCoordinator
    // The batch state lives here so it survives tab switches (screens are re-created for the entrance animation).
    @StateObject private var batch = BatchViewModel()
    @State private var tab = 2

    private let tabs = [
        TabItem(title: "Certificado", systemImage: "key.fill"),
        TabItem(title: "IPAs", systemImage: "shippingbox.fill"),
        TabItem(title: "Firmar", systemImage: "signature"),
        TabItem(title: "Ajustes", systemImage: "gearshape.fill"),
    ]

    var body: some View {
        ZStack {
            XBackground()

            ZStack {
                switch tab {
                case 0:
                    CertificatesView(batch: batch).transition(screenTransition)
                case 1:
                    IPAsView().transition(screenTransition)
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

            if batch.showOverlay {
                ProgressOverlay(vm: batch)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
            }

            ToastHost().zIndex(10)
        }
        .animation(Theme.spring, value: batch.showOverlay)
        .preferredColorScheme(.dark)
        .sheet(item: $coordinator.safariTarget) { target in
            SafariInstallSheet(url: target.url).ignoresSafeArea()
        }
    }

    private var screenTransition: AnyTransition {
        AnyTransition.opacity
            .combined(with: .offset(x: 0, y: 14))
            .combined(with: .scale(scale: 0.985))
    }
}
