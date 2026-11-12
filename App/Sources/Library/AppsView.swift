import SwiftUI

/// "Apps" tab: Importadas | Firmadas | Instaladas.
struct AppsView: View {
    @EnvironmentObject var store: ImportStore
    @EnvironmentObject var library: AppLibrary
    @EnvironmentObject var coordinator: InstallCoordinator
    @EnvironmentObject var toaster: Toaster
    @State private var section = 0
    @State private var picking: ImportKind?
    @State private var shareItems: [URL] = []
    @State private var showShare = false

    var body: some View {
        let imported = store.names[.ipa] ?? []
        let signed = library.signed
        let installed = library.installed
        XScreen(title: "Mis Apps",
                subtitle: "Importadas, firmadas e instaladas desde la app.",
                accessory: {
                    StatusChip(text: "\(signed.count) firmada\(signed.count == 1 ? "" : "s")",
                               color: signed.isEmpty ? nil : Theme.green)
                }) {
            XSegmented(options: ["Importadas", "Firmadas", "Instaladas"], selection: $section,
                       counts: [imported.count, signed.count, installed.count])
                .rise(2)
            Group {
                switch section {
                case 0: importedSection(imported)
                case 1: signedSection(signed)
                default: installedSection(installed)
                }
            }
            .id(section)
            .transition(.opacity.combined(with: .offset(x: 0, y: 8)))
        }
        .animation(Theme.spring, value: section)
        .importPicker($picking)
        .sheet(isPresented: $showShare) { ActivityView(items: shareItems) }
    }

    // MARK: Importadas

    @ViewBuilder
    private func importedSection(_ names: [String]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                if names.isEmpty {
                    EmptyStateView(systemName: "shippingbox.fill", text: "Importa una IPA para empezar.")
                } else {
                    ForEach(names, id: \.self) { name in
                        // ponytail: size only, no version (reading Info.plist would mean unzipping every IPA).
                        ImportFileRow(kind: .ipa, name: name, meta: store.fileSize(name).map { Fmt.size($0) } ?? "IPA",
                                      icon: "shippingbox.fill", green: true)
                    }
                }
            }
        }
        DropCard(title: "Importar IPA", hint: "solo .ipa") { picking = .ipa }
    }

    // MARK: Firmadas

    @ViewBuilder
    private func signedSection(_ records: [AppRecord]) -> some View {
        if !records.isEmpty {
            HStack {
                Text("\(records.count) lista\(records.count == 1 ? "" : "s") para instalar")
                    .font(Theme.meta).foregroundColor(Theme.text2)
                Spacer()
                Button("Instalar \(records.count)") { install(records) }
                    .buttonStyle(SmallButtonStyle(kind: .primary))
                    .disabled(busy)
            }
            .padding(.horizontal, 4)
        }
        GlassCard {
            if records.isEmpty {
                EmptyStateView(systemName: "signature", text: "Aún no has firmado apps.\nVe a la pestaña Firmar.")
            } else {
                VStack(spacing: 0) {
                    ForEach(records) { r in
                        VStack(alignment: .leading, spacing: 10) {
                            recordHeader(r, icon: "signature",
                                         meta: "\(r.bundleID) · \(Fmt.size(r.sizeBytes)) · \(RelativeTime.string(r.signedAt))")
                            HStack(spacing: 8) {
                                Button { install([r]) } label: { actionLabel(r, "Instalar") }
                                    .buttonStyle(SmallButtonStyle(kind: .primary))
                                    .disabled(busy)
                                Button("Compartir") {
                                    shareItems = [r.ipaURL]
                                    showShare = true
                                }
                                .buttonStyle(SmallButtonStyle())
                                Spacer(minLength: 0)
                                trash(r)
                            }
                        }
                        .padding(.vertical, 10)
                        divider(after: r, in: records)
                    }
                }
            }
        }
    }

    // MARK: Instaladas

    @ViewBuilder
    private func installedSection(_ records: [AppRecord]) -> some View {
        GlassCard {
            if records.isEmpty {
                EmptyStateView(systemName: "iphone", text: "Aún no has instalado apps desde aquí.")
            } else {
                VStack(spacing: 0) {
                    ForEach(records) { r in
                        let available = r.fileExists
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                IconBox(systemName: "iphone", green: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).font(Theme.name).foregroundColor(Theme.text).lineLimit(1)
                                    Text("\(r.bundleID) · instalada \(r.installedAt.map(RelativeTime.string) ?? "")")
                                        .font(Theme.meta).foregroundColor(Theme.text2).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                installedBadge
                            }
                            HStack(spacing: 8) {
                                Button { install([r]) } label: { actionLabel(r, "Reinstalar") }
                                    .buttonStyle(SmallButtonStyle())
                                    .disabled(busy || !available)
                                if !available {
                                    Text("Archivo no disponible").font(Theme.caption).foregroundColor(Theme.text3)
                                }
                                Spacer(minLength: 0)
                                Button("Quitar") {
                                    withAnimation(Theme.spring) { library.remove(r) }
                                }
                                .buttonStyle(SmallButtonStyle(kind: .danger))
                            }
                        }
                        .padding(.vertical, 10)
                        divider(after: r, in: records)
                    }
                }
            }
        }
        if !records.isEmpty {
            Text("Historial de instalaciones hechas desde la app. Si borras una app del iPhone, sigue apareciendo aquí.")
                .font(Theme.meta).foregroundColor(Theme.text3)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Pieces

    private var installedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
            Text("Instalada").font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundColor(Theme.green)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Theme.green.opacity(0.14)))
    }

    private func recordHeader(_ r: AppRecord, icon: String, meta: String) -> some View {
        HStack(spacing: 12) {
            IconBox(systemName: icon, green: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(Theme.name).foregroundColor(Theme.text).lineLimit(1)
                Text(meta).font(Theme.meta).foregroundColor(Theme.text2).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private func trash(_ r: AppRecord) -> some View {
        Button {
            withAnimation(Theme.spring) { library.remove(r) }
        } label: {
            Image(systemName: "trash").font(.system(size: 15)).foregroundColor(Theme.red)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Eliminar \(r.name)")
    }

    @ViewBuilder
    private func divider(after r: AppRecord, in list: [AppRecord]) -> some View {
        if r.id != list.last?.id { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    /// Spinner while this app is being installed, otherwise the label.
    @ViewBuilder
    private func actionLabel(_ r: AppRecord, _ title: String) -> some View {
        let working = coordinator.items.contains { $0.app.ipaURL == r.ipaURL && !$0.state.isFinal }
        if working { SpinnerRing(size: 16, lineWidth: 2).frame(minWidth: 52) } else { Text(title) }
    }

    /// Only one install queue at a time (the coordinator holds a single list of items).
    private var busy: Bool {
        coordinator.items.contains { !$0.state.isFinal }
    }

    private func install(_ records: [AppRecord]) {
        guard !busy else { return }
        guard coordinator.mode != .export else {
            toaster.show("Modo Exportar: usa Compartir o cambia el método en Ajustes.", isError: true)
            return
        }
        let apps = records.filter { $0.fileExists }.map { $0.signedApp }
        guard !apps.isEmpty else {
            toaster.show("Archivo no disponible", isError: true)
            return
        }
        KeepAlive.shared.start()
        Task { @MainActor in
            await coordinator.installAll(apps)
            KeepAlive.shared.stop()
            let failed = coordinator.items.filter { if case .failed = $0.state { return true } else { return false } }
            if let f = failed.first {
                toaster.show("\(f.app.job.displayName): \(f.state.label)", isError: true)
                Haptics.error()
            } else {
                toaster.show(apps.count == 1 ? "\(apps[0].job.displayName) instalada" : "\(apps.count) apps instaladas")
                Haptics.success()
            }
        }
    }
}
