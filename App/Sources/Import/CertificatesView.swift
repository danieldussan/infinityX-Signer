import SwiftUI
import UIKit
import InfinityXCore

/// "Certificado" tab: .p12 + password check, and the .mobileprovision details.
struct CertificatesView: View {
    @ObservedObject var batch: BatchViewModel
    @EnvironmentObject var store: ImportStore
    @EnvironmentObject var toaster: Toaster
    @StateObject private var checker = CertChecker()
    @State private var password = ""
    @State private var showPassword = false
    @State private var picking: ImportKind?
    @State private var showDevices = false

    var body: some View {
        XScreen(title: "Certificado",
                subtitle: "Importa tu .p12 y el perfil .mobileprovision.",
                accessory: { headerChip }) {
            certCard.rise(2)
            DropCard(title: "Importar certificado", hint: "solo .p12") { picking = .certificate }.rise(3)
            profileCard.rise(4)
            DropCard(title: "Importar perfil", hint: "solo .mobileprovision") { picking = .profile }.rise(5)
        }
        .importPicker($picking)
        .onAppear {
            loadPassword()
            recheck()
        }
        .onChange(of: store.selectedName(.certificate)) { _ in
            loadPassword()
            recheck()
        }
    }

    // MARK: Header chip

    private var headerChip: some View {
        let hasCert = store.selectedName(.certificate) != nil
        var text = "Falta"
        var color: Color? = nil
        if hasCert {
            switch store.profile?.status() {
            case .some(.expired): text = "Vencido"; color = Theme.red
            case .some(.expiringSoon): text = "Por vencer"; color = Theme.amber
            default: text = "Válido"; color = Theme.green
            }
        }
        return StatusChip(text: text, color: color)
    }

    // MARK: Certificate

    private var certCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                let names = store.names[.certificate] ?? []
                if names.isEmpty {
                    EmptyStateView(systemName: "key.fill", text: "Aún no hay certificado.")
                } else {
                    ForEach(names, id: \.self) { name in
                        ImportFileRow(kind: .certificate, name: name, meta: certMeta(name), icon: "key.fill")
                    }
                    if let cert = store.selectedName(.certificate) {
                        SectionLabel("Contraseña del .p12").padding(.top, 4)
                        HStack(spacing: 10) {
                            XField(placeholder: "Contraseña", text: $password,
                                   bad: isWrong, secure: !showPassword)
                                .onChange(of: password) { newValue in
                                    KeychainStore.setPassword(newValue, for: cert)
                                    recheck()
                                }
                            Button(showPassword ? "Ocultar" : "Ver") {
                                showPassword.toggle()
                            }
                            .buttonStyle(SmallButtonStyle())
                        }
                        Text("Se guarda en el Keychain de tu iPhone, asociada a \(cert).")
                            .font(Theme.meta).foregroundColor(Theme.text2)
                        passwordResult
                    }
                }
            }
        }
    }

    private func certMeta(_ name: String) -> String {
        guard store.selectedName(.certificate) == name else { return "Archivo .p12" }
        if case .correct(_, let expiry, _) = checker.result, let exp = expiry {
            return "Vence \(Fmt.date(exp))"
        }
        return "Archivo .p12"
    }

    private var isWrong: Bool {
        if case .wrong = checker.result { return true }
        return false
    }

    @ViewBuilder
    private var passwordResult: some View {
        switch checker.result {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                SpinnerRing(size: 14, lineWidth: 2)
                Text("Verificando contraseña...").font(Theme.meta).foregroundColor(Theme.text2)
            }
        case .correct(let subject, let expiry, let der):
            VStack(alignment: .leading, spacing: 6) {
                resultLine(icon: "checkmark.circle.fill", color: Theme.green, text: correctText(subject, expiry))
                if let der = der, let profile = store.profile, !profile.developerCertificates.isEmpty,
                   !profile.developerCertificates.contains(der) {
                    resultLine(icon: "exclamationmark.triangle.fill", color: Theme.amber,
                               text: "Este certificado no figura en el perfil: la firma fallará.")
                }
            }
        case .wrong:
            resultLine(icon: "xmark.circle.fill", color: Theme.red, text: "Contraseña incorrecta")
        case .unreadable(let message):
            resultLine(icon: "questionmark.circle.fill", color: Theme.amber, text: message)
        }
    }

    private func correctText(_ subject: String?, _ expiry: Date?) -> String {
        var text = "Contraseña correcta"
        if let subject = subject { text += " · \(subject)" }
        if let expiry = expiry { text += " · vence \(Fmt.date(expiry))" }
        return text
    }

    private func resultLine(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundColor(color)
            Text(text).font(Theme.meta).foregroundColor(color).fixedSize(horizontal: false, vertical: true)
        }
        .transition(.opacity)
    }

    // MARK: Profile

    private var profileCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                let names = store.names[.profile] ?? []
                if names.isEmpty {
                    EmptyStateView(systemName: "doc.text.fill", text: "Aún no hay perfil.")
                } else {
                    ForEach(names, id: \.self) { name in
                        ImportFileRow(kind: .profile, name: name, meta: profileMeta(name),
                                      icon: "doc.text.fill", green: true)
                    }
                    if let profile = store.profile {
                        profileDetails(profile)
                    } else if let error = store.profileError {
                        Text(error).font(Theme.meta).foregroundColor(Theme.red)
                    }
                }
            }
        }
    }

    private func profileMeta(_ name: String) -> String {
        guard store.selectedName(.profile) == name, let p = store.profile else { return "Archivo .mobileprovision" }
        var parts = ["App ID \(p.applicationIdentifier)"]
        if let exp = p.expirationDate { parts.append("vence \(Fmt.date(exp))") }
        return parts.joined(separator: " · ")
    }

    private func profileDetails(_ p: ProvisioningProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(alignment: .firstTextBaseline) {
                Text(p.name.isEmpty ? "Perfil" : p.name).font(Theme.name).foregroundColor(Theme.text)
                Spacer()
                statusBadge(p)
            }
            infoRow("Equipo", p.teamName.isEmpty ? p.teamID : "\(p.teamName) (\(p.teamID))")
            if let exp = p.expirationDate { infoRow("Vence", Fmt.date(exp)) }
            infoRow("App ID", p.applicationIdentifier)
            devicesSection(p)
        }
        .transition(.opacity)
    }

    private var trimmedPrefix: String {
        batch.bundlePrefix.trimmingCharacters(in: .whitespaces)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.meta).foregroundColor(Theme.text3)
            Spacer(minLength: 12)
            Text(value).font(Theme.meta).foregroundColor(Theme.text).multilineTextAlignment(.trailing)
        }
    }

    private func statusBadge(_ p: ProvisioningProfile) -> some View {
        let status = p.status()
        let days = p.daysRemaining() ?? 0
        let color: Color
        let text: String
        switch status {
        case .valid:
            color = Theme.green
            text = "Válido · \(days) días"
        case .expiringSoon:
            color = Theme.amber
            text = days <= 0 ? "Vence hoy" : "Vence en \(days) día\(days == 1 ? "" : "s")"
        case .expired:
            color = Theme.red
            text = "Vencido"
        }
        return Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
    }

    @ViewBuilder
    private func devicesSection(_ p: ProvisioningProfile) -> some View {
        if p.isAllDevices {
            infoRow("Dispositivos", "Todos (perfil de empresa)")
        } else {
            Button {
                Haptics.light()
                withAnimation(Theme.spring) { showDevices.toggle() }
            } label: {
                HStack {
                    Text("Dispositivos").font(Theme.meta).foregroundColor(Theme.text3)
                    Spacer()
                    Text("\(p.provisionedDevices.count)").font(Theme.meta).foregroundColor(Theme.text)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.text2)
                        .rotationEffect(.degrees(showDevices ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDevices {
                VStack(alignment: .leading, spacing: 6) {
                    if p.provisionedDevices.isEmpty {
                        Text("Sin dispositivos registrados.").font(Theme.meta).foregroundColor(Theme.text2)
                    }
                    ForEach(p.provisionedDevices, id: \.self) { udid in
                        Button {
                            UIPasteboard.general.string = udid
                            Haptics.light()
                            toaster.show("UDID copiado")
                        } label: {
                            Text(udid)
                                .font(Theme.mono)
                                .foregroundColor(Theme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.98))
                    }
                    Text("Toca un UDID para copiarlo.").font(Theme.caption).foregroundColor(Theme.text3)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: Password

    private func loadPassword() {
        if let cert = store.selectedName(.certificate) {
            password = KeychainStore.password(for: cert) ?? ""
        } else {
            password = ""
        }
    }

    private func recheck() {
        checker.schedule(url: store.url(for: .certificate), password: password)
    }
}
