import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// "Exportar" button that opens the share sheet for a signed IPA. Always available.
struct ExportButton: View {
    let url: URL
    @State private var showShare = false

    var body: some View {
        Button {
            showShare = true
        } label: {
            Label("Exportar", systemImage: "square.and.arrow.up")
                .font(Theme.caption)
                .foregroundColor(Theme.accent)
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: [url])
        }
    }
}
