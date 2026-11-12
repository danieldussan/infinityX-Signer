import SwiftUI
import InfinityXCore

struct DiagnosticsView: View {
    @EnvironmentObject var coordinator: InstallCoordinator
    @EnvironmentObject var ssl: SSLPack
    @EnvironmentObject var log: AppLog
    @State private var counter = UserDefaultsCounterStore().last

    var body: some View {
        Screen("Ajustes") {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Modo de instalación").font(Theme.headline).foregroundColor(Theme.text)
                    Picker("Modo", selection: $coordinator.mode) {
                        Text("Semi Local").tag(InstallMode.semiLocal)
                        Text("Fully Local").tag(InstallMode.fullyLocal)
                        Text("Exportar").tag(InstallMode.export)
                    }
                    .pickerStyle(.segmented)
                    Text(modeHelp)
                        .font(Theme.caption).foregroundColor(Theme.secondaryText)
                    Text("Host del plist").font(Theme.body).foregroundColor(Theme.text)
                    TextField("https://api.palera.in", text: $coordinator.plistHostText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Servidor local").font(Theme.headline).foregroundColor(Theme.text)
                    Text(coordinator.serverStatus).font(Theme.mono).foregroundColor(Theme.secondaryText)
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paquete SSL (Fully Local, experimental)").font(Theme.headline).foregroundColor(Theme.text)
                    if let info = ssl.info {
                        Text("Dominio: \(info.commonName)").font(Theme.mono).foregroundColor(Theme.secondaryText)
                        Text("Válido hasta: \(info.expiry.map(Self.format) ?? "desconocido")")
                            .font(Theme.mono).foregroundColor(Theme.secondaryText)
                    } else {
                        Text("Sin paquete en caché.").font(Theme.body).foregroundColor(Theme.secondaryText)
                    }
                    if let err = ssl.lastError {
                        Text(err).font(Theme.caption).foregroundColor(Theme.danger)
                    }
                    Button(ssl.isRefreshing ? "Actualizando..." : "Actualizar paquete") {
                        Task { @MainActor in
                            do { try await ssl.refresh() }
                            catch { log.add("SSL: \(error.localizedDescription)") }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: !ssl.isRefreshing))
                    .disabled(ssl.isRefreshing)
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Contador").font(Theme.headline).foregroundColor(Theme.text)
                    Text("Último número usado: \(counter)").font(Theme.mono).foregroundColor(Theme.secondaryText)
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Últimos errores").font(Theme.headline).foregroundColor(Theme.text)
                    if log.entries.isEmpty {
                        Text("Sin errores.").font(Theme.body).foregroundColor(Theme.secondaryText)
                    }
                    ForEach(log.entries, id: \.self) { entry in
                        Text(entry).font(Theme.mono).foregroundColor(Theme.secondaryText)
                    }
                }
            }
        }
        .onAppear { counter = UserDefaultsCounterStore().last }
    }

    private var modeHelp: String {
        switch coordinator.mode {
        case .semiLocal: return "HTTP en 127.0.0.1 y página de instalación en Safari. Recomendado."
        case .fullyLocal: return "HTTPS con *.backloop.dev. Experimental: puede no funcionar en builds sideloaded sin los entitlements de iOS 18."
        case .export: return "No instala: comparte los IPAs firmados desde la pestaña Firmar."
        }
    }

    private static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
