import SwiftUI

/// "IPAs" tab.
struct IPAsView: View {
    @EnvironmentObject var store: ImportStore
    @State private var picking: ImportKind?

    var body: some View {
        let names = store.names[.ipa] ?? []
        XScreen(title: "Mis IPAs",
                subtitle: "Trae tu propia IPA. No se incluye ninguna en la app.",
                accessory: {
                    StatusChip(text: names.isEmpty ? "Vacío" : "\(names.count) IPA\(names.count == 1 ? "" : "s")",
                               color: names.isEmpty ? nil : Theme.green)
                }) {
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    if names.isEmpty {
                        EmptyStateView(systemName: "shippingbox.fill", text: "Importa una IPA para empezar.")
                    } else {
                        ForEach(names, id: \.self) { name in
                            ImportFileRow(kind: .ipa, name: name, meta: meta(name), icon: "shippingbox.fill", green: true)
                        }
                    }
                }
            }
            .rise(2)
            DropCard(title: "Importar IPA", hint: "solo .ipa") { picking = .ipa }.rise(3)
        }
        .importPicker($picking)
    }

    private func meta(_ name: String) -> String {
        store.fileSize(name).map { Fmt.size($0) } ?? "IPA"
    }
}
