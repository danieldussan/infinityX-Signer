import SwiftUI
import InfinityXCore

/// "Importar > Fuentes": AltStore-style repositories -> app list -> download into Importadas.
struct SourcesView: View {
    @Binding var section: Int
    @EnvironmentObject var store: SourceStore
    @EnvironmentObject var imports: ImportStore
    @EnvironmentObject var toaster: Toaster
    @State private var selectedID: String?
    @State private var showAdd = false
    @State private var confirmRemove = false
    @State private var expanded: Set<String> = []

    var body: some View {
        let selected = store.sources.first { $0.id == selectedID }
        XScreen(title: "Importar",
                subtitle: selected?.name ?? "Descarga IPAs desde repositorios (fuentes).",
                accessory: {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Theme.glass2))
                            .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Agregar fuente")
                }) {
            XSegmented(options: ["Certificado", "Fuentes"], selection: $section).rise(2)
            if let selected { detail(selected) } else { list }
        }
        .sheet(isPresented: $showAdd) {
            AddSourceSheet().environmentObject(store)
        }
        .task {
            for s in store.sources { await store.refresh(s) }
        }
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if store.sources.isEmpty {
            GlassCard { EmptyStateView(systemName: "shippingbox.and.arrow.backward", text: "Aún no hay fuentes. Toca + para agregar una.") }
        } else {
            GlassCard {
                VStack(spacing: 0) {
                    ForEach(store.sources) { s in
                        Button { withAnimation(Theme.spring) { selectedID = s.id } } label: { sourceRow(s) }
                            .buttonStyle(PressScaleStyle(scale: 0.98))
                            .contextMenu {
                                Button(role: .destructive) { store.remove(s) } label: { Label("Quitar", systemImage: "trash") }
                            }
                        if s.id != store.sources.last?.id { Divider().overlay(Theme.line) }
                    }
                }
            }
        }
        if store.defaultMissing {
            Button { store.restoreDefault(); Haptics.light() } label: { Text("Restaurar fuente predeterminada") }
                .buttonStyle(GhostButtonStyle(height: 50))
        }
        Text("Mantén presionada una fuente para quitarla.")
            .font(Theme.caption).foregroundColor(Theme.text3)
    }

    private func sourceRow(_ s: Source) -> some View {
        HStack(spacing: 12) {
            IconBox(systemName: "shippingbox.fill", green: false)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(s.name).font(Theme.name).foregroundColor(Theme.text).lineLimit(1)
                    if s.url == SourceStore.defaultURL {
                        Text("Predeterminada").font(.system(size: 10.5, weight: .bold)).foregroundColor(Theme.green)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.green.opacity(0.15)))
                    }
                }
                Text("\(s.appCount > 0 ? "\(s.appCount) apps · " : "")\(s.url.host ?? s.url.absoluteString)")
                    .font(Theme.meta).foregroundColor(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 0)
            if store.refreshing.contains(s.id) { ProgressView().tint(.white) }
            else { Image(systemName: "chevron.right").foregroundColor(Theme.text3) }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: Detail

    @ViewBuilder
    private func detail(_ s: Source) -> some View {
        HStack {
            Button { withAnimation(Theme.spring) { selectedID = nil } } label: {
                Label("Fuentes", systemImage: "chevron.left").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(SmallButtonStyle())
            Spacer()
            Button("Actualizar") { Task { await store.refresh(s) } }.buttonStyle(SmallButtonStyle())
            Button { confirmRemove = true } label: { Image(systemName: "trash") }
                .buttonStyle(SmallButtonStyle(kind: .danger)).accessibilityLabel("Quitar fuente")
        }
        .confirmationDialog("¿Quitar \(s.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Quitar", role: .destructive) { selectedID = nil; store.remove(s) }
        }
        if let feed = store.feeds[s.id] {
            if feed.apps.isEmpty {
                GlassCard { EmptyStateView(systemName: "tray", text: "Esta fuente no tiene apps descargables.") }
            } else {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(feed.apps) { app in
                            appRow(app)
                            if app.id != feed.apps.last?.id { Divider().overlay(Theme.line) }
                        }
                    }
                }
                Text("Descargar guarda la IPA en Apps › Importadas. Luego la eliges en Firmar.")
                    .font(Theme.caption).foregroundColor(Theme.text3)
            }
        } else {
            GlassCard {
                HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.vertical, 22)
            }
        }
    }

    private func appRow(_ app: SourceApp) -> some View {
        let imported = (imports.names[.ipa] ?? []).contains(app.fileName)
        let state = store.downloads[app.id]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                AsyncImage(url: app.iconURL) { img in img.resizable().scaledToFill() } placeholder: { Theme.iconGradient }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button {
                    if expanded.contains(app.id) { expanded.remove(app.id) } else { expanded.insert(app.id) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(Theme.name).foregroundColor(Theme.text).lineLimit(1)
                        Text(meta(app)).font(Theme.meta).foregroundColor(Theme.text2).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                trailing(app, imported: imported, state: state)
            }
            if case .downloading(let p) = state {
                ProgressBarView(value: p)
            }
            if expanded.contains(app.id) {
                if let subtitle = app.subtitle { Text(subtitle).font(Theme.meta).foregroundColor(Theme.text2) }
                if let notes = app.release.notes, !notes.isEmpty {
                    Text(notes).font(Theme.caption).foregroundColor(Theme.text2)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func trailing(_ app: SourceApp, imported: Bool, state: DownloadState?) -> some View {
        if case .downloading(let p) = state {
            Button { store.cancel(app) } label: { Text(p.map { "\(Int($0 * 100))%" } ?? "…") }
                .buttonStyle(SmallButtonStyle()).accessibilityLabel("Cancelar descarga")
        } else if imported {
            Text("Importada").font(Theme.meta).foregroundColor(Theme.green)
        } else {
            let update = hasUpdate(app)
            Button {
                store.download(app, into: imports) { toaster.show($0, isError: true) }
            } label: {
                Image(systemName: "arrow.down.to.line").font(.system(size: 15, weight: .bold))
            }
            .buttonStyle(SmallButtonStyle(kind: .primary))
            .overlay(alignment: .topTrailing) {
                if update {
                    Text("Nueva")
                        .font(.system(size: 9.5, weight: .heavy)).foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.red))
                        .offset(x: 8, y: -7)
                }
            }
            .accessibilityLabel(update ? "Descargar nueva versión" : "Descargar")
        }
    }

    private func hasUpdate(_ app: SourceApp) -> Bool {
        store.hasUpdate(app, imported: Array(imports.ipaInfo.values))
    }

    private func meta(_ app: SourceApp) -> String {
        var parts = ["v" + app.release.version]
        if let size = app.release.size, size > 0 { parts.append(Fmt.size(size)) }
        return parts.joined(separator: " · ")
    }
}

private struct ProgressBarView: View {
    let value: Double?
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(Theme.brandGradient).frame(width: g.size.width * CGFloat(value ?? 0.05))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.2), value: value)
    }
}

// MARK: - Add sheet

struct AddSourceSheet: View {
    @EnvironmentObject var store: SourceStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var feed: SourceFeed?
    @State private var verifiedURL: URL?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Agregar fuente").font(Theme.headline).foregroundColor(Theme.text)
            SectionLabel("URL del repositorio")
            XField(placeholder: "https://ejemplo.com/repo.json", text: $text, bad: error != nil, keyboard: .URL)
                .onChange(of: text) { _ in feed = nil; error = nil }
            Text(error ?? "Solo https. Formato AltStore / SideStore / Feather.")
                .font(Theme.caption).foregroundColor(error == nil ? Theme.text3 : Theme.red)
            if let feed {
                GlassCard {
                    HStack(spacing: 12) {
                        IconBox(systemName: "shippingbox.fill", green: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feed.name).font(Theme.name).foregroundColor(Theme.text)
                            Text("\(feed.apps.count) apps").font(Theme.meta).foregroundColor(Theme.text2)
                        }
                        Spacer()
                        StatusChip(text: "Válida")
                    }
                }
            }
            Spacer()
            Button(action: primary) {
                if busy { ProgressView().tint(.white) } else { Text(feed == nil ? "Verificar" : "Agregar") }
            }
            .buttonStyle(CTAButtonStyle(enabled: !text.isEmpty && !busy))
            .disabled(text.isEmpty || busy)
        }
        .padding(Theme.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func primary() {
        if let feed, let url = verifiedURL {
            store.add(url, feed: feed)
            Haptics.success()
            dismiss()
            return
        }
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https" else {
            error = SourceError.badURL.localizedDescription
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                feed = try await store.fetch(url)
                verifiedURL = url
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
