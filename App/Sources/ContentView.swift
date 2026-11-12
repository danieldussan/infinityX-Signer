import SwiftUI

struct ContentView: View {
    @EnvironmentObject var coordinator: InstallCoordinator

    var body: some View {
        TabView {
            CertificatesView()
                .tabItem { Label("Certificados", systemImage: "key.fill") }
            IPAsView()
                .tabItem { Label("IPAs", systemImage: "shippingbox.fill") }
            BatchView()
                .tabItem { Label("Firmar", systemImage: "signature") }
            DiagnosticsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .sheet(item: $coordinator.safariTarget) { target in
            SafariInstallSheet(url: target.url).ignoresSafeArea()
        }
    }
}
