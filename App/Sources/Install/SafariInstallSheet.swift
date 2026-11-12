import SwiftUI
import SafariServices

struct SafariTarget: Identifiable {
    let id = UUID()
    let url: URL
}

/// Opens the local /install page in Safari so itms-services works without extra entitlements.
struct SafariInstallSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
