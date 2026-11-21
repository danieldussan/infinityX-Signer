import SwiftUI
import InfinityXCore

/// Green / amber / red capsule with the days left ("309 días"), like the one on each library row.
struct ExpiryBadge: View {
    let days: Int?
    let status: ProfileStatus

    var body: some View {
        let color: Color = status == .valid ? Theme.green : (status == .expiringSoon ? Theme.amber : Theme.red)
        HStack(spacing: 4) {
            Image(systemName: status == .expired ? "exclamationmark.triangle.fill" : "clock")
                .font(.system(size: 10, weight: .bold))
            Text(label).font(.system(size: 11.5, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.16)))
        .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
    }

    private var label: String {
        guard let days else { return "Sin vencimiento" }
        if status == .expired { return "Vencido" }
        if days <= 0 { return "Vence hoy" }
        return "\(days) día\(days == 1 ? "" : "s")"
    }
}

struct AppInfoTarget: Identifiable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let added: Date?
    let record: AppRecord?
    var id: String { url.path }
}

/// "Get Info": all the data we can read from the IPA plus the certificate it was signed with.
struct AppInfoSheet: View {
    let target: AppInfoTarget
    @EnvironmentObject var store: DetailsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = store.revision
        let details = store.details(for: target.url)
        NavigationStack {
            ZStack {
                XBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                        header
                        infoCard(details)
                        certificateCard
                        if let d = details {
                            bundleCard(d)
                            executableCard(d)
                        } else if store.didFail(target.url) || !FileManager.default.fileExists(atPath: target.url.path) {
                            Text("No se pudo leer el IPA (o el archivo ya no está). Solo se muestran los datos guardados.")
                                .font(Theme.meta).foregroundColor(Theme.text2).padding(.horizontal, 4)
                        } else {
                            HStack(spacing: 10) {
                                SpinnerRing(size: 18, lineWidth: 2)
                                Text("Leyendo el IPA…").font(Theme.meta).foregroundColor(Theme.text2)
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Información")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundColor(Theme.text2) }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { store.load(target.url) }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 14) {
            AppIconView(url: target.url, size: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text(target.name).font(Theme.headline).foregroundColor(Theme.text).lineLimit(2)
                Text(target.bundleID).font(Theme.meta).foregroundColor(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private func infoCard(_ d: AppDetails?) -> some View {
        card("Info") {
            row("Nombre", d?.displayName ?? target.name)
            let version = d?.version ?? target.version
            row("Versión", (d?.build.isEmpty ?? true) || d?.build == version ? version : "\(version) (\(d?.build ?? ""))")
            row("Identificador", d?.bundleID ?? target.bundleID)
            if let min = d?.minOS, !min.isEmpty { row("iOS mínimo", min) }
            if let size = fileSize { row("Tamaño", Fmt.size(size)) }
            if let added = target.added { row("Fecha agregado", added.formatted(date: .abbreviated, time: .shortened)) }
            if let installed = target.record?.installedAt {
                row("Instalada", installed.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private var fileSize: Int64? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: target.url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value
    }

    private var certificateCard: some View {
        card("Certificado") {
            if let c = target.record?.cert {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.profileName.isEmpty ? "Perfil" : c.profileName).font(Theme.name).foregroundColor(Theme.text)
                        Text(c.profileUUID).font(Theme.mono).foregroundColor(Theme.text3).lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                }
                ExpiryBadge(days: c.daysRemaining(), status: c.status())
                row("Equipo", c.teamName.isEmpty ? c.teamID : "\(c.teamName) (\(c.teamID))")
                row("Archivo .p12", c.certificateFile)
                if let exp = c.expiresAt { row("Vence", exp.formatted(date: .abbreviated, time: .shortened)) }
            } else if target.record != nil {
                Text("Esta app se firmó antes de que guardáramos el certificado. Re-fírmala para registrarlo.")
                    .font(Theme.meta).foregroundColor(Theme.text2)
            } else {
                Text("IPA importada: aún no está firmada con tu certificado.")
                    .font(Theme.meta).foregroundColor(Theme.text2)
            }
        }
    }

    private func bundleCard(_ d: AppDetails) -> some View {
        card("Bundle", padded: false) {
            NavigationLink { alternateIconsPage(d) } label: { linkRow("Iconos alternativos", d.alternateIcons.count) }
            NavigationLink { frameworksPage(d) } label: {
                linkRow("Frameworks y PlugIns", d.frameworks.count + d.plugins.count)
            }
            NavigationLink { permissionsPage(d) } label: { linkRow("Permisos", d.permissions.count) }
        }
    }

    private func executableCard(_ d: AppDetails) -> some View {
        card("Ejecutable", padded: false) {
            NavigationLink { dylibsPage(d) } label: { linkRow("Dylibs", d.dylibs.count) }
        }
    }

    // MARK: Pages

    private func alternateIconsPage(_ d: AppDetails) -> some View {
        page("Iconos alternativos") {
            if d.alternateIcons.isEmpty {
                empty("Esta app no declara iconos alternativos.")
            } else {
                card(nil) {
                    ForEach(d.alternateIcons, id: \.name) { alt in
                        HStack(spacing: 12) {
                            if let img = store.alternateIcon(for: target.url, name: alt.name) {
                                Image(uiImage: img).resizable().scaledToFill().frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            } else {
                                IconBox(systemName: "app.dashed")
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alt.name).font(Theme.name).foregroundColor(Theme.text)
                                Text(alt.files.joined(separator: ", ")).font(Theme.caption).foregroundColor(Theme.text3)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func frameworksPage(_ d: AppDetails) -> some View {
        page("Frameworks y PlugIns") {
            if d.frameworks.isEmpty && d.plugins.isEmpty { empty("Sin frameworks ni extensiones.") }
            if !d.frameworks.isEmpty {
                card("Frameworks (\(d.frameworks.count))") { ForEach(d.frameworks, id: \.name) { bundleRow($0) } }
            }
            if !d.plugins.isEmpty {
                card("PlugIns (\(d.plugins.count))") { ForEach(d.plugins, id: \.name) { bundleRow($0) } }
            }
        }
    }

    private func permissionsPage(_ d: AppDetails) -> some View {
        page("Permisos") {
            if d.permissions.isEmpty { empty("La app no pide permisos especiales.") }
            else {
                card(nil) {
                    ForEach(d.permissions, id: \.self) { Text($0).font(Theme.mono).foregroundColor(Theme.text).textSelection(.enabled) }
                }
            }
        }
    }

    private func dylibsPage(_ d: AppDetails) -> some View {
        let own = d.dylibs.filter { !MachO.isSystem($0) }
        let system = d.dylibs.filter { MachO.isSystem($0) }
        return page("Dylibs") {
            if d.dylibs.isEmpty { empty("No se encontraron librerías enlazadas.") }
            if !own.isEmpty {
                card("Del paquete o inyectadas (\(own.count))") { ForEach(own, id: \.self) { mono($0) } }
            }
            if !system.isEmpty {
                card("Del sistema (\(system.count))") { ForEach(system, id: \.self) { mono($0) } }
            }
        }
    }

    // MARK: Pieces

    private func page<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        ZStack {
            XBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.cardSpacing) { content() }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 40)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card<C: View>(_ title: String?, padded: Bool = true, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionLabel(title).padding(.horizontal, 4) }
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(padded ? 16 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GlassBackground())
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.sub).foregroundColor(Theme.text)
            Spacer(minLength: 12)
            Text(value).font(Theme.sub).foregroundColor(Theme.text2).multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func linkRow(_ title: String, _ count: Int) -> some View {
        HStack {
            Text(title).font(Theme.body).foregroundColor(Theme.text)
            Spacer()
            Text("\(count)").font(Theme.meta).foregroundColor(Theme.text3)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.text3)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func bundleRow(_ item: BundleItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name).font(Theme.name).foregroundColor(Theme.text)
            if let id = item.bundleID { Text(id).font(Theme.caption).foregroundColor(Theme.text3) }
        }
    }

    private func mono(_ s: String) -> some View {
        Text(s).font(Theme.mono).foregroundColor(Theme.text).textSelection(.enabled)
    }

    private func empty(_ text: String) -> some View {
        GlassCard { EmptyStateView(systemName: "tray", text: text) }
    }
}
