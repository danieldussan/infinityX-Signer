import SwiftUI
import InfinityXCore

/// "Firmar" tab: checklist, mode, live preview, prefixes and the main button.
struct BatchView: View {
    @ObservedObject var vm: BatchViewModel
    @EnvironmentObject var imports: ImportStore
    @EnvironmentObject var log: AppLog

    private let maxTags = 8

    var body: some View {
        let preview = vm.preview()
        let gate = vm.gate(imports: imports)

        XScreen(title: "Firmar por lotes",
                subtitle: "Genera WhatsApps con nombre y bundle consecutivos.",
                showSubtitleLogo: true,
                accessory: { StatusChip(text: gate.enabled ? "Listo" : "Pendiente", color: gate.enabled ? Theme.green : nil) }) {
            checklist.rise(2)
            modeCard(preview).rise(3)
            prefixCard.rise(4)
            VStack(spacing: 10) {
                Button {
                    vm.start(imports: imports, log: log)
                } label: {
                    Text(gate.title)
                }
                .buttonStyle(CTAButtonStyle(enabled: gate.enabled))
                .disabled(!gate.enabled)
                if let reason = gate.reason {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.amber)
                        Text(reason).font(Theme.meta).foregroundColor(Theme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
                if let error = vm.errorText {
                    Text(error).font(Theme.meta).foregroundColor(Theme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !vm.rows.isEmpty && !vm.showOverlay {
                    Button("Ver progreso") { vm.showOverlay = true }
                        .buttonStyle(GhostButtonStyle(height: 48))
                }
            }
            .rise(5)
        }
        .onAppear { vm.refreshCounter() }
    }

    // MARK: Checklist

    private var checklist: some View {
        HStack(spacing: 8) {
            step("Cert", ok: imports.url(for: .certificate) != nil)
            step("Perfil", ok: imports.url(for: .profile) != nil)
            step("IPA", ok: imports.url(for: .ipa) != nil)
        }
    }

    private func step(_ title: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(ok ? Theme.green : Color.clear)
                Circle().strokeBorder(ok ? Theme.green : Theme.amber, lineWidth: ok ? 0 : 1.5)
                Image(systemName: ok ? "checkmark" : "exclamationmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(ok ? .black : Theme.amber)
            }
            .frame(width: 20, height: 20)
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.text)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(ok ? Theme.line : Theme.amber.opacity(0.45), lineWidth: 1))
        .animation(Theme.spring, value: ok)
    }

    // MARK: Mode + preview

    private func modeCard(_ preview: BatchPreview) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Modo")
                XSegmented(options: ["Rango", "Siguientes"], selection: modeIndex)
                if vm.mode == .range {
                    XField(placeholder: "21-25 · 21,23 · 21-23,30", text: $vm.numbersText,
                           bad: preview.error != nil, keyboard: .numbersAndPunctuation)
                        .transition(.opacity)
                } else {
                    HStack(spacing: 10) {
                        Text("Último usado: \(vm.counterLast) · Cantidad")
                            .font(Theme.meta).foregroundColor(Theme.text2)
                        Spacer()
                        Button("−") { vm.changeCount(by: -1) }.buttonStyle(SmallButtonStyle())
                        Text("\(vm.count)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.text)
                            .frame(minWidth: 30)
                        Button("+") { vm.changeCount(by: 1) }.buttonStyle(SmallButtonStyle())
                    }
                    .transition(.opacity)
                }
                if let error = preview.error {
                    Text(error).font(.system(size: 13)).foregroundColor(Theme.red)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                if !preview.jobs.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(preview.jobs.prefix(maxTags), id: \.number) { job in
                            PreviewTag(text: job.displayName, accent: job.bundleID)
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                        }
                        if preview.jobs.count > maxTags {
                            PreviewTag(text: "+\(preview.jobs.count - maxTags) más")
                        }
                    }
                }
            }
            .animation(Theme.spring, value: preview.jobs.map { $0.number })
            .animation(Theme.spring, value: preview.error)
        }
    }

    private var modeIndex: Binding<Int> {
        Binding(get: { vm.mode.rawValue },
                set: { vm.mode = BatchMode(rawValue: $0) ?? .range })
    }

    // MARK: Prefixes

    private var prefixCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Prefijo de nombre")
                        XField(placeholder: "WAB", text: $vm.namePrefix)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Prefijo de bundle")
                        XField(placeholder: "chip", text: $vm.bundlePrefix)
                    }
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quitar extensiones").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                        Text("Elimina PlugIns/Extensions").font(Theme.meta).foregroundColor(Theme.text2)
                    }
                    Spacer()
                    XSwitch(isOn: $vm.stripPlugins)
                }
            }
        }
    }
}
