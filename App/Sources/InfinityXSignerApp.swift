import SwiftUI

@main
struct InfinityXSignerApp: App {
    @StateObject private var imports = ImportStore()
    @StateObject private var coordinator = InstallCoordinator()
    @StateObject private var log = AppLog()
    @StateObject private var toaster = Toaster()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(imports)
                .environmentObject(coordinator)
                .environmentObject(coordinator.ssl)
                .environmentObject(log)
                .environmentObject(toaster)
        }
    }
}
