import SwiftUI
import PhotosUI
import InfinityXCore

@MainActor
final class ResignModel: ObservableObject {
    @Published var name: String
    @Published var bundle: String
    @Published var iconData: Data?
    @Published var removeAlternates = false
    @Published var stripPlugins = false
    @Published var isRunning = false
    @Published var error: String?
    private let engine = SigningEngine()

    init(record: AppRecord) {
        name = record.name
        bundle = record.bundleID
    }

    var iconPreview: UIImage? { iconData.flatMap { UIImage(data: $0) } }

    /// Re-signs the saved IPA in place with the certificate and profile currently selected in Importar.
    func run(record: AppRecord, imports: ImportStore, library: AppLibrary, log: AppLog) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        let bundle = bundle.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !bundle.isEmpty else {
            error = "Escribe el nombre y el bundle de la app."
            return false
        }
        guard let p12 = imports.url(for: .certificate), let profileURL = imports.url(for: .profile),
              let certName = imports.selectedName(.certificate), let profile = imports.profile else {
            error = "Importa y selecciona un certificado y un perfil."
            return false
        }
        if profile.status() == .expired {
            error = "El perfil seleccionado está vencido."
            return false
        }
        guard record.fileExists else {
            error = "El archivo IPA ya no está disponible."
            return false
        }
        error = nil
        isRunning = true
        KeepAlive.shared.start()
        defer {
            KeepAlive.shared.stop()
            isRunning = false
        }
        let request = SigningRequest(ipaURL: record.ipaURL, p12URL: p12, profileURL: profileURL,
                                     password: KeychainStore.password(for: certName) ?? "",
                                     stripPlugins: stripPlugins, iconPNG: iconData,
                                     removeAlternateIcons: removeAlternates)
        let job = SigningJob(number: 0, displayName: name, bundleID: bundle, outputFileName: record.ipaFileName)
        var failure: String?
        let result = await engine.run(request: request, jobs: [job]) { _, state in
            if case .failed(let m) = state { failure = m }
        }
        guard !result.isEmpty else {
            error = failure ?? "No se pudo re-firmar."
            log.add("Re-firmar \(record.name): \(error ?? "")")
            return false
        }
        library.add(result, cert: CertSnapshot(certificateFile: certName, profile: profile))
        return true
    }
}

struct ResignSheet: View {
    let record: AppRecord
    let alternateCount: Int
    @EnvironmentObject var imports: ImportStore
    @EnvironmentObject var library: AppLibrary
    @EnvironmentObject var toaster: Toaster
    @EnvironmentObject var log: AppLog
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ResignModel
    @State private var pickingPhoto = false

    init(record: AppRecord, alternateCount: Int) {
        self.record = record
        self.alternateCount = alternateCount
        _model = StateObject(wrappedValue: ResignModel(record: record))
    }

    var body: some View {
        ZStack {
            XBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                    header
                    identityCard
                    certificateCard
                    iconCard
                    if let error = model.error {
                        Text(error).font(Theme.meta).foregroundColor(Theme.red).padding(.horizontal, 4)
                    }
                    Button { submit() } label: {
                        if model.isRunning {
                            HStack(spacing: 10) { SpinnerRing(size: 18, lineWidth: 2); Text("Firmando…") }
                        } else {
                            Text("Re-firmar")
                        }
                    }
                    .buttonStyle(CTAButtonStyle(enabled: !model.isRunning))
                    .disabled(model.isRunning)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(model.isRunning)
        .sheet(isPresented: $pickingPhoto) {
            PhotoPicker { data in
                pickingPhoto = false
                if let data { model.iconData = data }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Re-firmar").font(Theme.screenTitle).foregroundColor(Theme.text)
                Text(record.name).font(Theme.sub).foregroundColor(Theme.text2).lineLimit(1)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                    .frame(width: 36, height: 36).background(Circle().fill(Theme.glass2))
            }
            .buttonStyle(.plain)
            .disabled(model.isRunning)
        }
    }

    private var identityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Nombre")
                XField(placeholder: "WhatsApp", text: $model.name)
                SectionLabel("Bundle ID")
                XField(placeholder: "com.example.app", text: $model.bundle)
            }
        }
    }

    private var certificateCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Certificado y perfil")
                picker(kind: .certificate, title: "Certificado")
                picker(kind: .profile, title: "Perfil")
                if let p = imports.profile {
                    HStack {
                        Text(p.name.isEmpty ? "Perfil" : p.name).font(Theme.meta).foregroundColor(Theme.text2).lineLimit(1)
                        Spacer()
                        ExpiryBadge(days: p.daysRemaining(), status: p.status())
                    }
                } else {
                    Text("Importa un perfil en la pestaña Importar.").font(Theme.meta).foregroundColor(Theme.amber)
                }
            }
        }
    }

    private func picker(kind: ImportKind, title: String) -> some View {
        let names = imports.names[kind] ?? []
        return HStack {
            Text(title).font(Theme.meta).foregroundColor(Theme.text3)
            Spacer(minLength: 12)
            Menu {
                ForEach(names, id: \.self) { n in
                    Button(n) { imports.select(n, kind: kind) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(imports.selectedName(kind) ?? "Ninguno").font(Theme.meta).foregroundColor(Theme.text)
                        .lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.text2)
                }
            }
            .disabled(names.isEmpty)
        }
    }

    private var iconCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Icono y paquete")
                HStack(spacing: 12) {
                    if let img = model.iconPreview {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        AppIconView(url: record.ipaURL, size: 52)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.iconData == nil ? "Icono actual" : "Icono nuevo").font(Theme.name).foregroundColor(Theme.text)
                        Text("Se recorta al centro en cuadrado.").font(Theme.caption).foregroundColor(Theme.text3)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Button("Elegir imagen") { pickingPhoto = true }.buttonStyle(SmallButtonStyle())
                    if model.iconData != nil {
                        Button("Quitar") { model.iconData = nil }.buttonStyle(SmallButtonStyle(kind: .danger))
                    }
                }
                if alternateCount > 0 {
                    toggleRow("Quitar iconos alternativos (\(alternateCount))", isOn: $model.removeAlternates)
                }
                toggleRow("Quitar extensiones (PlugIns)", isOn: $model.stripPlugins)
            }
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(Theme.sub).foregroundColor(Theme.text)
            Spacer(minLength: 8)
            XSwitch(isOn: isOn)
        }
    }

    private func submit() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task {
            let ok = await model.run(record: record, imports: imports, library: library, log: log)
            if ok {
                Haptics.success()
                toaster.show("\(model.name) re-firmada. Ya puedes instalarla desde Firmadas.")
                dismiss()
            } else {
                Haptics.error()
            }
        }
    }
}

/// Photo library picker (no permission prompt); returns the chosen image as PNG data.
struct PhotoPicker: UIViewControllerRepresentable {
    let onPick: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (Data?) -> Void

        init(onPick: @escaping (Data?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                onPick(nil)
                return
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let data = (object as? UIImage)?.pngData()
                DispatchQueue.main.async { self.onPick(data) }
            }
        }
    }
}
