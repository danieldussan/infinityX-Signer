import SwiftUI

/// One imported file: icon, name, meta line, selection dot and delete button.
struct ImportFileRow: View {
    let kind: ImportKind
    let name: String
    let meta: String
    let icon: String
    var green = false
    @EnvironmentObject var store: ImportStore

    var body: some View {
        let selected = store.selectedName(kind) == name
        HStack(spacing: 12) {
            Button {
                Haptics.light()
                store.select(name, kind: kind)
            } label: {
                HStack(spacing: 12) {
                    IconBox(systemName: icon, green: green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(Theme.name).foregroundColor(Theme.text).lineLimit(1).truncationMode(.middle)
                        Text(meta).font(Theme.meta).foregroundColor(Theme.text2).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    SelectDot(on: selected)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.98))
            Button {
                withAnimation(Theme.spring) { store.delete(name, kind: kind) }
            } label: {
                Image(systemName: "trash").font(.system(size: 15)).foregroundColor(Theme.red)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Eliminar \(name)")
        }
        .padding(.vertical, 6)
    }
}
