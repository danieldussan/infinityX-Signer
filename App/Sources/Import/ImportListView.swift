import SwiftUI
import UniformTypeIdentifiers

/// File list for one kind (select, delete, import with the system document picker).
struct ImportListView: View {
    let kind: ImportKind
    @EnvironmentObject var store: ImportStore
    @EnvironmentObject var log: AppLog
    @State private var showImporter = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(kind.title).font(Theme.headline).foregroundColor(Theme.text)
                let list = store.names[kind] ?? []
                if list.isEmpty {
                    Text("Aún no hay archivos.").font(Theme.body).foregroundColor(Theme.secondaryText)
                }
                ForEach(list, id: \.self) { name in
                    HStack {
                        Button {
                            store.select(name, kind: kind)
                        } label: {
                            HStack {
                                Image(systemName: store.selectedName(kind) == name ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(Theme.accent)
                                Text(name).font(Theme.body).foregroundColor(Theme.text).lineLimit(1)
                            }
                        }
                        Spacer()
                        Button {
                            store.delete(name, kind: kind)
                        } label: {
                            Image(systemName: "trash").foregroundColor(Theme.danger)
                        }
                    }
                }
                Button(kind.importLabel) { showImporter = true }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            Task { @MainActor in
                switch result {
                case .success(let url):
                    do { try store.importFile(from: url, kind: kind) }
                    catch { log.add("Importar: \(error.localizedDescription)") }
                case .failure(let error):
                    log.add("Importar: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct CertificatesView: View {
    @EnvironmentObject var store: ImportStore
    @State private var password = ""

    var body: some View {
        Screen("Certificados") {
            ImportListView(kind: .certificate)
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contraseña del .p12").font(Theme.headline).foregroundColor(Theme.text)
                    if let cert = store.selectedName(.certificate) {
                        SecureField("Contraseña", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: password) { newValue in
                                KeychainStore.setPassword(newValue, for: cert)
                            }
                        Text("Se guarda en el Keychain, asociada a \(cert).")
                            .font(Theme.caption).foregroundColor(Theme.secondaryText)
                    } else {
                        Text("Selecciona un certificado primero.")
                            .font(Theme.body).foregroundColor(Theme.secondaryText)
                    }
                }
            }
            ImportListView(kind: .profile)
        }
        .onAppear { loadPassword() }
        .onChange(of: store.selectedName(.certificate)) { _ in loadPassword() }
    }

    private func loadPassword() {
        if let cert = store.selectedName(.certificate) {
            password = KeychainStore.password(for: cert) ?? ""
        } else {
            password = ""
        }
    }
}

struct IPAsView: View {
    var body: some View {
        Screen("IPAs") {
            ImportListView(kind: .ipa)
        }
    }
}
