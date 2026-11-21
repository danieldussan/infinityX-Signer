import SwiftUI
import InfinityXCore

/// "Apps" tab: Importadas | Firmadas | Instaladas.
struct AppsView: View {
    @EnvironmentObject var store: ImportStore
    @EnvironmentObject var library: AppLibrary
    @EnvironmentObject var coordinator: InstallCoordinator
    @EnvironmentObject var toaster: Toaster
    @EnvironmentObject var details: DetailsStore
    @State private var section = 0
    @State private var infoTarget: AppInfoTarget?
    @State private var resignTarget: AppRecord?
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
            attentionBanner
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
        .sheet(item: $infoTarget) { AppInfoSheet(target: $0) }
        .sheet(item: $resignTarget) { r in
            ResignSheet(record: r, alternateCount: details.details(for: r.ipaURL)?.alternateIcons.count ?? 0)
        }
        .onAppear { details.prune() }
    }

    // MARK: Certificate alerts

    @ViewBuilder
    private var attentionBanner: some View {
        let list = library.needingAttention
        if let first = list.first {
            let expired = list.filter { $0.cert?.status() == .expired }.count
            let color = expired > 0 ? Theme.red : Theme.amber
            let text: String = {
                if expired > 0 { return "\(expired) app\(expired == 1 ? "" : "s") con certificado vencido" }
                let days = first.cert?.daysRemaining() ?? 0
                let when = days <= 0 ? "hoy" : "en \(days) día\(days == 1 ? "" : "s")"
                return "\(list.count) app\(list.count == 1 ? "" : "s") por vencer, la primera \(when)"
            }()
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(color)
                Text(text).font(Theme.meta).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Re-firmar") { resignTarget = first }.buttonStyle(SmallButtonStyle(kind: .primary))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).fill(color.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .strokeBorder(color.opacity(0.5), lineWidth: 1))
            .rise(2)
        }
    }

    // MARK: Actions menu

    private func infoTarget(for r: AppRecord) -> AppInfoTarget {
        AppInfoTarget(url: r.ipaURL, name: r.name, bundleID: r.bundleID, version: r.version ?? "",
                      added: r.signedAt, record: r)
    }

    private func infoTarget(forImported name: String) -> AppInfoTarget {
        let url = AppPaths.imports.appendingPathComponent(name)
        let info = store.ipaInfo[name]
        let added = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.creationDate] as? Date
        return AppInfoTarget(url: url, name: info?.displayName ?? name, bundleID: info?.bundleID ?? "",
                             version: info?.version ?? "", added: added, record: nil)
    }

    /// Same actions as the long-press menu, also reachable from the "..." button.
    @ViewBuilder
    private func recordActions(_ r: AppRecord, installTitle: String) -> some View {
        Button { infoTarget = infoTarget(for: r) } label: { Label("Información", systemImage: "info.circle") }
        Button { install([r]) } label: { Label(installTitle, systemImage: "square.and.arrow.down") }
            .disabled(busy || !r.fileExists)
        Button { resignTarget = r } label: { Label("Re-firmar", systemImage: "signature") }
            .disabled(!r.fileExists)
        Button {
            shareItems = [r.ipaURL]
            showShare = true
        } label: { Label("Exportar", systemImage: "square.and.arrow.up") }
            .disabled(!r.fileExists)
        Button(role: .destructive) {
            withAnimation(Theme.spring) { library.remove(r) }
        } label: { Label("Borrar", systemImage: "trash") }
    }

    private func moreMenu(_ r: AppRecord, installTitle: String) -> some View {
        Menu { recordActions(r, installTitle: installTitle) } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 17)).foregroundColor(Theme.text2)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("Más acciones de \(r.name)")
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
                        let info = store.ipaInfo[name]
                        let size = store.fileSize(name).map { Fmt.size($0) }
                        ImportFileRow(kind: .ipa, name: name, meta: ipaMeta(info, size: size),
                                      icon: "shippingbox.fill", green: true, title: info?.displayName,
                                      iconURL: AppPaths.imports.appendingPathComponent(name),
                                      onInfo: { infoTarget = infoTarget(forImported: name) })
                            .onAppear { store.loadInfoIfNeeded(name) }
                    }
                }
            }
        }
        DropCard(title: "Importar IPA", hint: "solo .ipa") { picking = .ipa }
    }

    private func ipaMeta(_ info: IPAInfo?, size: String?) -> String {
        guard let info else { return size ?? "IPA" }
        var parts = [info.bundleID]
        if !info.version.isEmpty { parts.append("v" + info.version) }
        if let size { parts.append(size) }
        return parts.joined(separator: " · ")
    }

    // MARK: Firmadas

    @ViewBuilder
    private func signedSection(_ records: [AppRecord]) -> some View {
        if !records.isEmpty {
            let failed = records.filter { coordinator.isRetryable($0.signedApp) }
            HStack {
                Text("\(records.count) lista\(records.count == 1 ? "" : "s") para instalar")
                    .font(Theme.meta).foregroundColor(Theme.text2)
                Spacer()
                if busy {
                    Button(coordinator.cancelling ? "Cancelando..." : "Cancelar") { coordinator.cancelAll() }
                        .buttonStyle(SmallButtonStyle(kind: .danger))
                        .disabled(coordinator.cancelling)
                } else {
                    Button("Instalar \(records.count)") { install(records) }
                        .buttonStyle(SmallButtonStyle(kind: .primary))
                }
            }
            .padding(.horizontal, 4)
            if !failed.isEmpty && !busy {
                HStack {
                    Text("\(failed.count) fallida\(failed.count == 1 ? "" : "s") o cancelada\(failed.count == 1 ? "" : "s")")
                        .font(Theme.meta).foregroundColor(Theme.red)
                    Spacer()
                    Button("Reintentar \(failed.count)") { install(failed) }
                        .buttonStyle(SmallButtonStyle(kind: .primary))
                }
                .padding(.horizontal, 4)
            }
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
                            if let st = coordinator.item(for: r.signedApp)?.state, st.isRetryable {
                                Text(st.label).font(Theme.meta).foregroundColor(Theme.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HStack(spacing: 8) {
                                Button { install([r]) } label: {
                                    actionLabel(r, coordinator.isRetryable(r.signedApp) ? "Reintentar" : "Instalar")
                                }
                                    .buttonStyle(SmallButtonStyle(kind: .primary))
                                    .disabled(busy)
                                Button("Compartir") {
                                    shareItems = [r.ipaURL]
                                    showShare = true
                                }
                                .buttonStyle(SmallButtonStyle())
                                Spacer(minLength: 0)
                                moreMenu(r, installTitle: coordinator.isRetryable(r.signedApp) ? "Reintentar" : "Instalar")
                                trash(r)
                            }
                        }
                        .padding(.vertical, 10)
                        .contextMenu { recordActions(r, installTitle: "Instalar") }
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
                                AppIconView(url: r.ipaURL, fallbackSymbol: "iphone")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).font(Theme.name).foregroundColor(Theme.text).lineLimit(1)
                                    Text("\(r.bundleID) · instalada \(r.installedAt.map(RelativeTime.string) ?? "")")
                                        .font(Theme.meta).foregroundColor(Theme.text2).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                certBadge(r) ?? AnyView(installedBadge)
                            }
                            HStack(spacing: 8) {
                                Button { install([r]) } label: { actionLabel(r, "Reinstalar") }
                                    .buttonStyle(SmallButtonStyle())
                                    .disabled(busy || !available)
                                if !available {
                                    Text("Archivo no disponible").font(Theme.caption).foregroundColor(Theme.text3)
                                }
                                Spacer(minLength: 0)
                                moreMenu(r, installTitle: "Reinstalar")
                                Button("Quitar") {
                                    withAnimation(Theme.spring) { library.remove(r) }
                                }
                                .buttonStyle(SmallButtonStyle(kind: .danger))
                            }
                        }
                        .padding(.vertical, 10)
                        .contextMenu { recordActions(r, installTitle: "Reinstalar") }
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
            AppIconView(url: r.ipaURL, fallbackSymbol: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(Theme.name).foregroundColor(Theme.text).lineLimit(1)
                Text(meta).font(Theme.meta).foregroundColor(Theme.text2).lineLimit(2)
            }
            Spacer(minLength: 0)
            certBadge(r)
        }
    }

    private func certBadge(_ r: AppRecord) -> AnyView? {
        guard let c = r.cert else { return nil }
        return AnyView(ExpiryBadge(days: c.daysRemaining(), status: c.status()))
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

    /// Spinner only while iOS is working on this app; "En cola" while it waits its turn.
    @ViewBuilder
    private func actionLabel(_ r: AppRecord, _ title: String) -> some View {
        switch coordinator.item(for: r.signedApp)?.state {
        case .some(let st) where st.isActive:
            SpinnerRing(size: 16, lineWidth: 2).frame(minWidth: 52)
        case .some(.ready):
            Text("En cola")
        default:
            Text(title)
        }
    }

    /// Only one install queue at a time (the coordinator holds a single running queue).
    private var busy: Bool { coordinator.isRunning }

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
            let result = coordinator.summary(for: apps)
            toaster.show(result.text, isError: result.isError)
            if result.isError { Haptics.error() } else { Haptics.success() }
        }
    }
}
