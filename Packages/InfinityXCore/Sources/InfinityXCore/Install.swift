import Foundation

public enum InstallMode: String, CaseIterable {
    case semiLocal, fullyLocal, export
}

public struct InstallConfig {
    public static let defaultPlistHost = URL(string: "https://api.palera.in")!
    public var mode: InstallMode
    public var plistHost: URL
    public init(mode: InstallMode = .semiLocal, plistHost: URL = InstallConfig.defaultPlistHost) {
        self.mode = mode
        self.plistHost = plistHost
    }
}

private func encode(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s
}

/// `<host>/genPlist?bundleid=&name=&version=&fetchurl=` with every value percent-encoded.
public func genPlistURL(host: URL, bundleID: String, name: String, version: String, ipaURL: URL) -> URL {
    var base = host.absoluteString
    while base.hasSuffix("/") { base.removeLast() }
    let q = "bundleid=\(encode(bundleID))&name=\(encode(name))&version=\(encode(version))&fetchurl=\(encode(ipaURL.absoluteString))"
    return URL(string: "\(base)/genPlist?\(q)")!
}

/// `itms-services://?action=download-manifest&url=<plist>` (plist URL fully encoded).
public func itmsServicesURL(plistURL: URL) -> URL {
    URL(string: "itms-services://?action=download-manifest&url=\(encode(plistURL.absoluteString))")!
}
