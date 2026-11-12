import SwiftUI

/// Settings > "Acerca de": version, update check, links, credits.
struct AboutCard: View {
    @EnvironmentObject var updater: UpdateChecker
    @EnvironmentObject var toaster: Toaster
    @Environment(\.openURL) private var openURL

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Acerca de")
                HStack(spacing: 14) {
                    Text("X")
                        .font(Theme.logoX)
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppInfo.name).font(Theme.name).foregroundColor(Theme.text)
                        Text("Versión \(AppInfo.version) (build \(AppInfo.build))")
                            .font(Theme.meta).foregroundColor(Theme.text2)
                    }
                }
                updateRow
                updateResult
                VStack(spacing: 8) {
                    LinkRow(icon: "chevron.left.forwardslash.chevron.right", title: "Código fuente",
                            detail: "github.com/danieldussan/infinityX-Signer", url: AppInfo.repoURL)
                    LinkRow(icon: "shippingbox.fill", title: "Versiones", detail: "Descargas y novedades",
                            url: AppInfo.releasesURL)
                    LinkRow(icon: "ladybug.fill", title: "Reportar un problema", detail: "Abre un issue en GitHub",
                            url: AppInfo.issuesURL)
                }
                (Text("Creada por ") + Text(AppInfo.author).bold())
                    .font(Theme.meta).foregroundColor(Theme.text2)
                    .padding(.horizontal, 2)
                SectionLabel("Créditos y fuentes").padding(.top, 4)
                VStack(spacing: 8) {
                    ForEach(AppInfo.credits, id: \.title) { c in
                        LinkRow(icon: c.icon, title: c.title, detail: c.detail, url: c.url)
                    }
                }
                Text(AppInfo.disclaimer)
                    .font(Theme.meta).foregroundColor(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }

    private var updateRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Actualizaciones").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                Text(updateMeta).font(Theme.meta).foregroundColor(Theme.text2)
            }
            Spacer(minLength: 0)
            Button {
                Task { await updater.checkManually() }
            } label: {
                if updater.state == .checking {
                    SpinnerRing(size: 16, lineWidth: 2).frame(minWidth: 52)
                } else {
                    Text("Buscar")
                }
            }
            .buttonStyle(SmallButtonStyle())
            .disabled(updater.state == .checking)
        }
    }

    private var updateMeta: String {
        switch updater.state {
        case .checking: return "Consultando GitHub..."
        case .available: return "Hay una versión nueva"
        case .failed(let m): return m
        case .upToDate: return "Última comprobación: ahora"
        case .idle:
            if let d = updater.lastChecked { return "Última comprobación: \(RelativeTime.string(d))" }
            return "Consulta las releases de GitHub"
        }
    }

    @ViewBuilder
    private var updateResult: some View {
        switch updater.state {
        case .available(let version, let url, let notes):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(version) disponible").font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                    Spacer()
                    Text("Nueva").font(.system(size: 11.5, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.segGradient))
                }
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(notes.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").foregroundColor(Theme.text3)
                                Text(String(line)).foregroundColor(Theme.text2)
                            }
                            .font(.system(size: 13))
                        }
                    }
                }
                Button { openURL(url) } label: { Text("Ver en GitHub") }
                    .buttonStyle(CTAButtonStyle(height: 48))
                Text("Descarga el .ipa de la release, impórtalo en Apps › Importadas y fírmalo con tu certificado.")
                    .font(Theme.meta).foregroundColor(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.blue.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.blue.opacity(0.4), lineWidth: 1))
            .transition(.opacity.combined(with: .offset(x: 0, y: 8)))
        case .upToDate:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.green).font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estás al día").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                    Text("Tienes la última versión (\(AppInfo.version)).").font(Theme.meta).foregroundColor(Theme.text2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.green.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.green.opacity(0.35), lineWidth: 1))
            .transition(.opacity)
        default:
            EmptyView()
        }
    }
}

private struct LinkRow: View {
    let icon: String
    let title: String
    let detail: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.iconGradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                    Text(detail).font(Theme.caption).foregroundColor(Theme.text2).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text3)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.glass))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
    }
}
