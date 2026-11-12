import Foundation

/// App metadata and every external URL in one place.
enum AppInfo {
    static let name = "Infinity X Signer"
    static let repoSlug = "danieldussan/infinityX-Signer"
    static let repoURL = URL(string: "https://github.com/danieldussan/infinityX-Signer")!
    static let releasesURL = URL(string: "https://github.com/danieldussan/infinityX-Signer/releases")!
    static let issuesURL = URL(string: "https://github.com/danieldussan/infinityX-Signer/issues")!
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/danieldussan/infinityX-Signer/releases/latest")!
    static let author = "Tech Hub"

    struct Credit {
        let title: String
        let detail: String
        let url: URL
        let icon: String
    }

    static let credits: [Credit] = [
        Credit(title: "Feather", detail: "Inspiración del diseño y la instalación",
               url: URL(string: "https://github.com/claration/Feather")!, icon: "leaf.fill"),
        Credit(title: "Zsign", detail: "Motor de firma",
               url: URL(string: "https://github.com/khcrysalis/Zsign-Package")!, icon: "signature"),
        Credit(title: "ZIPFoundation", detail: "Manejo de archivos .ipa",
               url: URL(string: "https://github.com/weichsel/ZIPFoundation")!, icon: "doc.zipper"),
    ]

    static let disclaimer = "No incluye ninguna IPA ni certificado: traes los tuyos. No está afiliada con Apple ni con WhatsApp."

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
