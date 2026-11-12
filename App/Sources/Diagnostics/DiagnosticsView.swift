import SwiftUI
import InfinityXCore

/// "Ajustes" tab: install method, plist host, SSL pack, counter and the error log.
struct DiagnosticsView: View {
    @EnvironmentObject var coordinator: InstallCoordinator
    @EnvironmentObject var ssl: SSLPack
    @EnvironmentObject var log: AppLog
    @EnvironmentObject var toaster: Toaster
    @State private var counter = UserDefaultsCounterStore().last

    private let modes: [InstallMode] = [.semiLocal, .fullyLocal, .export]

    var body: some View {
        XScreen(title: "Ajustes", subtitle: "Instalación, servidor y diagnóstico.") {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Método de instalación")
                    XSegmented(options: ["Semi Local", "Local", "Exportar"], selection: modeIndex)
                    Text(modeHelp)
                        .font(Theme.meta).foregroundColor(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                    Text("Servidor local: \(coordinator.serverStatus)")
                        .font(Theme.mono).foregroundColor(Theme.text3)
                }
            }
            .rise(2)
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Servidor del plist")
                    XField(placeholder: "https://api.palera.in", text: $coordinator.plistHostText, keyboard: .URL)
                }
            }
            .rise(3)
            sslCard.rise(4)
            GlassCard {
                HStack {
                    SectionLabel("Último consecutivo")
                    Spacer()
                    Text("\(counter)").font(.system(size: 22, weight: .bold)).foregroundColor(Theme.text)
                }
            }
            .rise(5)
            logCard.rise(6)
        }
        .onAppear { counter = UserDefaultsCounterStore().last }
    }

    private var sslCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconBox(systemName: "lock.fill", green: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Certificados SSL").font(Theme.name).foregroundColor(Theme.text)
                        Text(sslMeta).font(Theme.meta).foregroundColor(Theme.text2)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Task { @MainActor in
                            do {
                                try await ssl.refresh()
                                toaster.show("Certificados SSL actualizados")
                                Haptics.success()
                            } catch {
                                log.add("SSL: \(error.localizedDescription)")
                                toaster.show("SSL: \(error.localizedDescription)", isError: true)
                            }
                        }
                    } label: {
                        if ssl.isRefreshing {
                            SpinnerRing(size: 16, lineWidth: 2).frame(minWidth: 52)
                        } else {
                            Text("Actualizar")
                        }
                    }
                    .buttonStyle(SmallButtonStyle())
                    .disabled(ssl.isRefreshing)
                }
                if let err = ssl.lastError {
                    Text(err).font(Theme.caption).foregroundColor(Theme.red)
                }
                Text("Solo se usa en modo Local (experimental).").font(Theme.caption).foregroundColor(Theme.text3)
            }
        }
    }

    private var sslMeta: String {
        guard let info = ssl.info else { return "Sin paquete en caché" }
        if let exp = info.expiry { return "Válido hasta \(Fmt.date(exp))" }
        return info.commonName
    }

    private var logCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Últimos errores")
                if log.entries.isEmpty {
                    Text("Sin errores.").font(Theme.body).foregroundColor(Theme.text2)
                }
                ForEach(log.entries, id: \.self) { entry in
                    Text(entry).font(Theme.mono).foregroundColor(Theme.text2)
                }
            }
        }
    }

    private var modeIndex: Binding<Int> {
        Binding(get: { modes.firstIndex(of: coordinator.mode) ?? 0 },
                set: { coordinator.mode = modes[min(max($0, 0), modes.count - 1)] })
    }

    private var modeHelp: String {
        switch coordinator.mode {
        case .semiLocal: return "Recomendado. Sirve el IPA desde tu iPhone y usa un servidor externo solo para el plist."
        case .fullyLocal: return "Servidor HTTPS en el iPhone con certificado SSL. Experimental: puede fallar en iOS 18."
        case .export: return "No instala. Comparte el .ipa firmado para usarlo con otra herramienta."
        }
    }
}
