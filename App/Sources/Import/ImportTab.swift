import SwiftUI

/// "Importar" tab: Certificado | Fuentes. The section lives in ContentView so deep links can reset it.
struct ImportTab: View {
    @ObservedObject var batch: BatchViewModel
    @Binding var section: Int

    var body: some View {
        Group {
            if section == 0 { CertificatesView(batch: batch, section: $section) }
            else { SourcesView(section: $section) }
        }
        .transition(.opacity)
        .animation(Theme.spring, value: section)
    }
}
