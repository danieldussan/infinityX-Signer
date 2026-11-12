import Foundation

public enum ProfileStatus: Equatable {
    case valid
    case expiringSoon
    case expired
}

public enum ProfileError: Error, Equatable {
    case noPlist
    case invalidPlist
}

/// Parsed contents of a .mobileprovision (CMS wrapper around an XML plist).
public struct ProvisioningProfile: Equatable {
    public var name: String
    public var teamName: String
    public var teamID: String
    public var appIDName: String
    /// Application identifier without the team prefix, e.g. "chip.*".
    public var applicationIdentifier: String
    public var expirationDate: Date?
    public var creationDate: Date?
    public var provisionedDevices: [String]
    public var isAllDevices: Bool
    public var developerCertificates: [Data]

    /// Extracts the `<?xml ... </plist>` block from the raw bytes (the CMS signature is ignored).
    public init(data: Data) throws {
        let bytes = [UInt8](data)
        let start = Array("<?xml".utf8)
        let end = Array("</plist>".utf8)
        guard let s = ProvisioningProfile.find(start, in: bytes, from: 0),
              let e = ProvisioningProfile.find(end, in: bytes, from: s) else {
            throw ProfileError.noPlist
        }
        let xml = Data(bytes[s..<(e + end.count)])
        guard let obj = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil),
              let dict = obj as? [String: Any] else {
            throw ProfileError.invalidPlist
        }
        let ents = dict["Entitlements"] as? [String: Any] ?? [:]
        let teams = dict["TeamIdentifier"] as? [String] ?? []
        let teamID = teams.first ?? ""
        var appID = (ents["application-identifier"] as? String) ?? ""
        if !teamID.isEmpty, appID.hasPrefix(teamID + ".") {
            appID = String(appID.dropFirst(teamID.count + 1))
        } else if let dot = appID.firstIndex(of: "."), teamID.isEmpty {
            appID = String(appID[appID.index(after: dot)...])
        }
        self.name = dict["Name"] as? String ?? ""
        self.teamName = dict["TeamName"] as? String ?? ""
        self.teamID = teamID
        self.appIDName = dict["AppIDName"] as? String ?? ""
        self.applicationIdentifier = appID
        self.expirationDate = dict["ExpirationDate"] as? Date
        self.creationDate = dict["CreationDate"] as? Date
        self.provisionedDevices = dict["ProvisionedDevices"] as? [String] ?? []
        self.isAllDevices = (dict["ProvisionsAllDevices"] as? Bool) ?? false
        self.developerCertificates = dict["DeveloperCertificates"] as? [Data] ?? []
    }

    private static func find(_ needle: [UInt8], in hay: [UInt8], from: Int) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count, from <= hay.count - needle.count else { return nil }
        var i = from
        let last = hay.count - needle.count
        while i <= last {
            if hay[i] == needle[0] {
                var j = 1
                while j < needle.count && hay[i + j] == needle[j] { j += 1 }
                if j == needle.count { return i }
            }
            i += 1
        }
        return nil
    }

    /// Whole days left (negative when expired); nil when the profile has no expiration date.
    public func daysRemaining(now: Date = Date()) -> Int? {
        guard let exp = expirationDate else { return nil }
        return Int((exp.timeIntervalSince(now) / 86_400).rounded(.down))
    }

    public func status(now: Date = Date()) -> ProfileStatus {
        guard let exp = expirationDate else { return .valid }
        if exp <= now { return .expired }
        if exp.timeIntervalSince(now) < 7 * 86_400 { return .expiringSoon }
        return .valid
    }

    /// "*" covers everything, "chip.*" covers any id starting with "chip.", otherwise exact match.
    public func covers(bundleID: String) -> Bool {
        let id = applicationIdentifier
        if id == "*" { return true }
        if id.hasSuffix("*") {
            return bundleID.hasPrefix(String(id.dropLast()))
        }
        return id == bundleID
    }
}

/// notAfter of an X.509 certificate in DER form (minimal DER walker).
public func certificateNotAfter(der: Data) -> Date? {
    let d = [UInt8](der)
    typealias Node = (tag: UInt8, start: Int, end: Int)

    func read(_ i: Int) -> Node? {
        guard i >= 0, i + 2 <= d.count else { return nil }
        let tag = d[i]
        var len = Int(d[i + 1])
        var p = i + 2
        if len & 0x80 != 0 {
            let n = len & 0x7F
            guard n >= 1, n <= 4, p + n <= d.count else { return nil }
            len = 0
            for _ in 0..<n {
                len = (len << 8) | Int(d[p])
                p += 1
            }
        }
        guard p + len <= d.count else { return nil }
        return (tag, p, p + len)
    }
    func children(_ node: Node) -> [Node] {
        var out: [Node] = []
        var i = node.start
        while i < node.end, let n = read(i) {
            out.append(n)
            i = n.end
        }
        return out
    }

    guard let root = read(0), root.tag == 0x30 else { return nil }
    guard let tbs = children(root).first, tbs.tag == 0x30 else { return nil }
    let kids = children(tbs)
    let offset = (kids.first?.tag == 0xA0) ? 1 : 0
    guard kids.count > offset + 3 else { return nil }
    let validity = children(kids[offset + 3])
    guard validity.count == 2 else { return nil }
    let t = validity[1]
    guard let text = String(bytes: d[t.start..<t.end], encoding: .ascii) else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = (t.tag == 0x18) ? "yyyyMMddHHmmss'Z'" : "yyMMddHHmmss'Z'"
    return f.date(from: text)
}
