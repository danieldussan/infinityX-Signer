import SwiftUI
import InfinityXCore

/// Shown in "Firmar" only with 2+ imported IPAs. One compact row (stays the same height with 3 or 300 IPAs);
/// tapping it opens a searchable sheet.
struct IPASelector: View {
    @EnvironmentObject var imports: ImportStore
    @State private var open = false

    var body: some View {
        let names = imports.names[.ipa] ?? []
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("IPA a firmar")
                Button {
                    Haptics.light()
                    open = true
                } label: {
                    HStack(spacing: 12) {
                        IconBox(systemName: "app.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(imports.selectedName(.ipa))).font(Theme.name).foregroundColor(Theme.text).lineLimit(1)
                            Text("\(names.count) IPAs importadas · toca para cambiar")
                                .font(Theme.meta).foregroundColor(Theme.text2).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.text3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.98))
                .accessibilityLabel("IPA a firmar: \(title(imports.selectedName(.ipa))). Cambiar")
            }
        }
        .sheet(isPresented: $open) {
            IPAPickerSheet().environmentObject(imports)
        }
    }

    private func title(_ name: String?) -> String {
        guard let name else { return "Elige una IPA" }
        return imports.ipaInfo[name]?.displayName ?? name
    }
}

private struct IPAPickerSheet: View {
    @EnvironmentObject var imports: ImportStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var all: [String] { imports.names[.ipa] ?? [] }

    private var shown: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { name in
            name.lowercased().contains(q) || (imports.ipaInfo[name]?.displayName.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        ZStack {
            XBackground()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Elige la IPA").font(.system(size: 22, weight: .bold)).foregroundColor(Theme.text)
                    Spacer()
                    Button("Listo") { dismiss() }.buttonStyle(SmallButtonStyle())
                }
                // Search only pays off with a long list.
                if all.count > 6 {
                    XField(placeholder: "Buscar por nombre", text: $query)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown, id: \.self) { name in row(name) }
                        if shown.isEmpty {
                            EmptyStateView(systemName: "magnifyingglass", text: "Ninguna IPA coincide con “\(query)”.")
                                .padding(.top, 30)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(Theme.screenPadding)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ name: String) -> some View {
        let info = imports.ipaInfo[name]
        let selected = imports.selectedName(.ipa) == name
        var meta = [String]()
        if let v = info?.version, !v.isEmpty { meta.append("v\(v)") }
        if let size = imports.fileSize(name) { meta.append(Fmt.size(size)) }
        return VStack(spacing: 0) {
            Button {
                Haptics.light()
                imports.select(name, kind: .ipa)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info?.displayName ?? name).font(Theme.name).foregroundColor(Theme.text).lineLimit(1)
                        Text(meta.isEmpty ? name : meta.joined(separator: " · "))
                            .font(Theme.meta).foregroundColor(Theme.text2).lineLimit(1)
                        Text(name).font(Theme.caption).foregroundColor(Theme.text3)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    SelectDot(on: selected)
                }
                .padding(.vertical, 12)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.98))
            .onAppear { imports.loadInfoIfNeeded(name) }
            Rectangle().fill(Theme.line).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
