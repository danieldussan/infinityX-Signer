import Foundation

/// Parsed "v1.2.3-beta" -> ([1, 2, 3], isPreRelease). Nil when any numeric part is invalid.
private func parseVersion(_ raw: String) -> (parts: [Int], pre: Bool)? {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
    let core = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    guard let head = core.first, !head.isEmpty else { return nil }
    let pre = core.count > 1
    var parts: [Int] = []
    for piece in head.split(separator: ".", omittingEmptySubsequences: false) {
        guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(piece) else { return nil }
        parts.append(n)
    }
    return (parts, pre)
}

/// True when `remote` is a strictly newer release than `local`.
/// Missing parts count as 0 ("1.0" == "1.0.0"); a pre-release suffix ("-beta") of the same numbers is older
/// than the release. Unparseable input is never "newer".
public func isNewerVersion(remote: String, local: String) -> Bool {
    guard let r = parseVersion(remote), let l = parseVersion(local) else { return false }
    for i in 0..<max(r.parts.count, l.parts.count) {
        let a = i < r.parts.count ? r.parts[i] : 0
        let b = i < l.parts.count ? l.parts[i] : 0
        if a != b { return a > b }
    }
    // Same numbers: only a final release beats a pre-release of itself.
    return l.pre && !r.pre
}
