import XCTest
@testable import InfinityXCore

final class NumbersTests: XCTestCase {
    func testParse() throws {
        XCTAssertEqual(try parseNumbers("21-25"), [21, 22, 23, 24, 25])
        XCTAssertEqual(try parseNumbers("21,23"), [21, 23])
        XCTAssertEqual(try parseNumbers("21-23,30"), [21, 22, 23, 30])
        XCTAssertEqual(try parseNumbers(" 3, 1 ,3,1-2 "), [3, 1, 2])
    }
    func testParseErrors() {
        XCTAssertThrowsError(try parseNumbers("5-3"))
        XCTAssertThrowsError(try parseNumbers("abc"))
        XCTAssertThrowsError(try parseNumbers("-5"))
        XCTAssertThrowsError(try parseNumbers(""))
        XCTAssertThrowsError(try parseNumbers(" , "))
    }
    func testFormat() {
        XCTAssertEqual(formatNumber(4), "04")
        XCTAssertEqual(formatNumber(12), "12")
        XCTAssertEqual(formatNumber(105), "105")
    }
}

final class BatchTests: XCTestCase {
    func testCountFromLast() throws {
        let jobs = try makeJobs(BatchInput(count: 2), lastUsed: 24)
        XCTAssertEqual(jobs.map(\.number), [25, 26])
        XCTAssertEqual(jobs[0], SigningJob(number: 25, displayName: "WAB 25", bundleID: "chip.25",
                                           outputFileName: "WA25-signed.ipa"))
    }
    func testDefaultOneNext() throws {
        XCTAssertEqual(try makeJobs(BatchInput(), lastUsed: 0).map(\.number), [1])
        XCTAssertEqual(try makeJobs(BatchInput(), lastUsed: 0)[0].bundleID, "chip.01")
    }
    func testNumbersText() throws {
        XCTAssertEqual(try makeJobs(BatchInput(numbersText: "21-23"), lastUsed: 99).map(\.number), [21, 22, 23])
    }
    func testErrors() {
        XCTAssertThrowsError(try makeJobs(BatchInput(numbersText: "1", count: 2), lastUsed: 0)) {
            XCTAssertEqual($0 as? BatchError, .bothRangeAndCount)
        }
        XCTAssertThrowsError(try makeJobs(BatchInput(count: 0), lastUsed: 0)) {
            XCTAssertEqual($0 as? BatchError, .countTooSmall)
        }
    }
}

final class CounterTests: XCTestCase {
    struct Mem: CounterStore { var last = 0 }
    func testAdvanceOnlyUp() {
        var s = Mem(last: 10)
        advance(&s, afterSuccess: 5); XCTAssertEqual(s.last, 10)
        advance(&s, afterSuccess: 12); XCTAssertEqual(s.last, 12)
    }
    func testFileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ctr-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var s = JSONFileCounterStore(url: url)
        XCTAssertEqual(s.last, 0)
        advance(&s, afterSuccess: 7)
        XCTAssertEqual(JSONFileCounterStore(url: url).last, 7)
    }
}

final class PlistEditorTests: XCTestCase {
    var app: URL!
    override func setUpWithError() throws {
        app = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID())/X.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

    func writeInfo(_ fmt: PropertyListSerialization.PropertyListFormat) throws {
        let d: [String: Any] = ["CFBundleName": "WhatsApp", "CFBundleDisplayName": "WA", "CFBundleVersion": "9"]
        try PropertyListSerialization.data(fromPropertyList: d, format: fmt, options: 0)
            .write(to: app.appendingPathComponent("Info.plist"))
    }
    func readInfo() throws -> [String: Any] {
        try PropertyListSerialization.propertyList(
            from: Data(contentsOf: app.appendingPathComponent("Info.plist")), format: nil) as! [String: Any]
    }
    func lproj(_ name: String, _ data: Data) throws -> URL {
        let dir = app.appendingPathComponent("\(name).lproj")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("InfoPlist.strings")
        try data.write(to: f)
        return f
    }

    func testSetNameXMLAndBinary() throws {
        for fmt in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            try writeInfo(fmt)
            try PlistEditor.setName(appDir: app, name: "WAB 21", cleanLocalized: false)
            let d = try readInfo()
            XCTAssertEqual(d["CFBundleName"] as? String, "WAB 21")
            XCTAssertEqual(d["CFBundleDisplayName"] as? String, "WAB 21")
            XCTAssertEqual(d["CFBundleVersion"] as? String, "9")
        }
    }
    func testCleanStrings() throws {
        try writeInfo(.xml)
        let src = "\"CFBundleDisplayName\" = \"WhatsApp\";\n\"NSCameraUsageDescription\" = \"cam\";\n"
        let u8 = try lproj("en", Data(src.utf8))
        var u16 = Data([0xFF, 0xFE]); u16.append(src.data(using: .utf16LittleEndian)!)
        let f16 = try lproj("es", u16)
        let bin = try lproj("fr", PropertyListSerialization.data(
            fromPropertyList: ["CFBundleName": "W", "Other": "keep"], format: .binary, options: 0))
        try PlistEditor.setName(appDir: app, name: "WAB 21", cleanLocalized: true)
        XCTAssertFalse(try String(contentsOf: u8).contains("CFBundleDisplayName"))
        XCTAssertTrue(try String(contentsOf: u8).contains("NSCameraUsageDescription"))
        let raw16 = try Data(contentsOf: f16)
        XCTAssertEqual([UInt8](raw16.prefix(2)), [0xFF, 0xFE])
        let t16 = String(data: raw16.dropFirst(2), encoding: .utf16LittleEndian)!
        XCTAssertFalse(t16.contains("CFBundleDisplayName"))
        XCTAssertTrue(t16.contains("NSCameraUsageDescription"))
        let d = try PropertyListSerialization.propertyList(from: Data(contentsOf: bin), format: nil) as! [String: Any]
        XCTAssertNil(d["CFBundleName"]); XCTAssertEqual(d["Other"] as? String, "keep")
    }
    func testBadStringsSkipped() throws {
        try writeInfo(.xml)
        _ = try lproj("de", Data([0xFF, 0xFE, 0x00]))   // odd-length utf16: unreadable
        XCTAssertNoThrow(try PlistEditor.setName(appDir: app, name: "N", cleanLocalized: true))
    }
    func testStripPlugins() throws {
        for d in ["PlugIns", "Extensions", "Frameworks"] {
            try FileManager.default.createDirectory(at: app.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        try PlistEditor.stripPlugins(appDir: app)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("PlugIns").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("Extensions").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Frameworks").path))
    }
}

final class InstallTests: XCTestCase {
    func testURLs() {
        let ipa = URL(string: "http://127.0.0.1:4321/abc.ipa")!
        let plist = genPlistURL(host: URL(string: "https://api.palera.in")!, bundleID: "chip.21",
                                name: "WAB 21", version: "2.24.1", ipaURL: ipa)
        XCTAssertEqual(plist.absoluteString,
            "https://api.palera.in/genPlist?bundleid=chip.21&name=WAB%2021&version=2.24.1&fetchurl=http%3A%2F%2F127.0.0.1%3A4321%2Fabc.ipa")
        let itms = itmsServicesURL(plistURL: plist).absoluteString
        XCTAssertTrue(itms.hasPrefix("itms-services://?action=download-manifest&url=https%3A%2F%2Fapi.palera.in"))
        XCTAssertTrue(itms.contains("WAB%252021"))
    }
    func testHostTrailingSlash() {
        let u = genPlistURL(host: URL(string: "https://x.dev/")!, bundleID: "a", name: "b", version: "1",
                            ipaURL: URL(string: "http://h/i.ipa")!)
        XCTAssertTrue(u.absoluteString.hasPrefix("https://x.dev/genPlist?"))
    }
    func testDefaultMode() { XCTAssertEqual(InstallConfig().mode, .semiLocal) }
}

final class ProvisioningProfileTests: XCTestCase {
    // openssl req -x509 -newkey rsa:1024 -nodes -days 365 -subj /CN=test -outform DER
    // openssl x509 -inform DER -enddate -> Nov 12 01:15:28 2027 GMT (epoch 1825982128)
    private let certB64 = "MIIB2TCCAUKgAwIBAgIULwK2JMbgF0lh97jXgliF5dIYvHEwDQYJKoZIhvcNAQELBQAwDzENMAsGA1UEAwwEdGVzdDAeFw0yNjExMTIwMTE1MjhaFw0yNzExMTIwMTE1MjhaMA8xDTALBgNVBAMMBHRlc3QwgZ8wDQYJKoZIhvcNAQEBBQADgY0AMIGJAoGBAOhzv2UJMtwKGBdK6w/rMF5HHQO50oqZULEABTgqXLsWV7c8NgHJv1n2XOfQHXIe9YQ5k3JugVVm17FP5VDtwpFvfeIWJGA+KcpSeM8lcUDgThPv+UD5CneCg0j1GvGo1tKSl8ytfmHcSV3nu8f+6CmEfkvEOo0yrcvmjQWK7E/jAgMBAAGjMjAwMB0GA1UdDgQWBBQ72+ztLK/rh5MprIJavVn6uUYdITAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4GBAJeaA/QX/OMeEen6SEe6PWm0iLqefl1GG6W31idYd9zN55IozHhDm5XyuFW99OtVdbD6Zod0UXdYlPGdpHROxOeKTs0pUvA0Q6xX9pudX9JZfBTTeZg4oevrdZLvTnFigvNPRIpZKWK1792U5TJAcMSnZ0wk4C3oAqsDuM2IGORp"
    private let exp = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeProfile(appID: String = "TEAM123.chip.*", devices: [String] = ["AAA", "BBB"],
                             all: Bool = false) throws -> Data {
        var plist: [String: Any] = [
            "Name": "My Profile",
            "TeamName": "Some Team",
            "TeamIdentifier": ["TEAM123"],
            "AppIDName": "Wildcard",
            "ExpirationDate": exp,
            "CreationDate": exp.addingTimeInterval(-365 * 86_400),
            "Entitlements": ["application-identifier": appID],
            "DeveloperCertificates": [Data(base64Encoded: certB64)!],
        ]
        if all { plist["ProvisionsAllDevices"] = true } else { plist["ProvisionedDevices"] = devices }
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return Data([0x30, 0x82, 0x01, 0xFF, 0x06, 0x09]) + xml + Data([0x00, 0xFF, 0x30, 0x80])
    }

    func testParse() throws {
        let p = try ProvisioningProfile(data: makeProfile())
        XCTAssertEqual(p.name, "My Profile")
        XCTAssertEqual(p.teamName, "Some Team")
        XCTAssertEqual(p.teamID, "TEAM123")
        XCTAssertEqual(p.appIDName, "Wildcard")
        XCTAssertEqual(p.applicationIdentifier, "chip.*")
        XCTAssertEqual(p.expirationDate, exp)
        XCTAssertEqual(p.provisionedDevices, ["AAA", "BBB"])
        XCTAssertFalse(p.isAllDevices)
        XCTAssertEqual(p.developerCertificates.count, 1)
    }

    func testAllDevices() throws {
        let p = try ProvisioningProfile(data: makeProfile(all: true))
        XCTAssertTrue(p.isAllDevices)
        XCTAssertTrue(p.provisionedDevices.isEmpty)
    }

    func testStatusAndDays() throws {
        let p = try ProvisioningProfile(data: makeProfile())
        XCTAssertEqual(p.status(now: exp.addingTimeInterval(-30 * 86_400)), .valid)
        XCTAssertEqual(p.status(now: exp.addingTimeInterval(-3 * 86_400)), .expiringSoon)
        XCTAssertEqual(p.status(now: exp.addingTimeInterval(60)), .expired)
        XCTAssertEqual(p.daysRemaining(now: exp.addingTimeInterval(-10 * 86_400 - 100)), 10)
        XCTAssertEqual(p.daysRemaining(now: exp.addingTimeInterval(86_400 + 1)), -2)
    }

    func testCovers() throws {
        let wild = try ProvisioningProfile(data: makeProfile())
        XCTAssertTrue(wild.covers(bundleID: "chip.21"))
        XCTAssertFalse(wild.covers(bundleID: "other.21"))
        XCTAssertFalse(wild.covers(bundleID: "chip"))
        let star = try ProvisioningProfile(data: makeProfile(appID: "TEAM123.*"))
        XCTAssertTrue(star.covers(bundleID: "anything.at.all"))
        let exact = try ProvisioningProfile(data: makeProfile(appID: "TEAM123.com.foo.bar"))
        XCTAssertTrue(exact.covers(bundleID: "com.foo.bar"))
        XCTAssertFalse(exact.covers(bundleID: "com.foo.baz"))
    }

    func testNoPlist() {
        XCTAssertThrowsError(try ProvisioningProfile(data: Data([1, 2, 3, 4])))
    }

    func testCertificateNotAfter() throws {
        let der = Data(base64Encoded: certB64)!
        XCTAssertEqual(certificateNotAfter(der: der), Date(timeIntervalSince1970: 1_825_982_128))
        XCTAssertNil(certificateNotAfter(der: Data([0x30, 0x03, 0x01, 0x01])))
    }
}

final class VersionTests: XCTestCase {
    func testNewer() {
        XCTAssertTrue(isNewerVersion(remote: "v0.3.0", local: "0.2.2"))
        XCTAssertTrue(isNewerVersion(remote: "v0.10.0", local: "0.9.9"))
        XCTAssertTrue(isNewerVersion(remote: "1.0.1", local: "1.0"))
        XCTAssertTrue(isNewerVersion(remote: "0.3.0", local: "0.3.0-beta"))
    }
    func testNotNewer() {
        XCTAssertFalse(isNewerVersion(remote: "0.2.2", local: "0.2.2"))
        XCTAssertFalse(isNewerVersion(remote: "1.0", local: "1.0.0"))
        XCTAssertFalse(isNewerVersion(remote: "0.2.1", local: "0.2.2"))
        XCTAssertFalse(isNewerVersion(remote: "0.3.0-beta", local: "0.3.0"))
    }
    func testGarbage() {
        XCTAssertFalse(isNewerVersion(remote: "latest", local: "0.2.2"))
        XCTAssertFalse(isNewerVersion(remote: "", local: "0.2.2"))
        XCTAssertFalse(isNewerVersion(remote: "v1.x", local: "0.2.2"))
        XCTAssertFalse(isNewerVersion(remote: "1.0.0", local: "abc"))
    }
}

final class IPAInfoTests: XCTestCase {
    private func plist(_ dict: [String: Any], format: PropertyListSerialization.PropertyListFormat) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0)
    }

    func testXMLAndBinary() throws {
        let dict: [String: Any] = ["CFBundleDisplayName": "WhatsApp", "CFBundleName": "WA",
                                   "CFBundleIdentifier": "net.whatsapp.WhatsApp",
                                   "CFBundleShortVersionString": "2.24.18", "CFBundleVersion": "99"]
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            let info = IPAInfo(infoPlist: try plist(dict, format: format), appFolderName: "Foo.app")
            XCTAssertEqual(info, IPAInfo(displayName: "WhatsApp", bundleID: "net.whatsapp.WhatsApp", version: "2.24.18"))
        }
    }

    func testFallbacks() throws {
        let noDisplay = IPAInfo(infoPlist: try plist(["CFBundleName": "WA", "CFBundleIdentifier": "a.b",
                                                      "CFBundleVersion": "7"], format: .binary),
                                appFolderName: "Foo.app")
        XCTAssertEqual(noDisplay?.displayName, "WA")
        XCTAssertEqual(noDisplay?.version, "7")
        let onlyId = IPAInfo(infoPlist: try plist(["CFBundleIdentifier": "a.b"], format: .xml), appFolderName: "Foo.app")
        XCTAssertEqual(onlyId?.displayName, "Foo")
        XCTAssertEqual(onlyId?.version, "")
    }

    func testInvalid() throws {
        XCTAssertNil(IPAInfo(infoPlist: try plist(["CFBundleName": "WA"], format: .xml), appFolderName: "Foo.app"))
        XCTAssertNil(IPAInfo(infoPlist: Data("garbage".utf8), appFolderName: "Foo.app"))
    }
}

final class QueueSummaryTests: XCTestCase {
    func testSummary() {
        XCTAssertEqual(queueSummary([.completed, .completed, .failed, .cancelled]), "2 instaladas, 1 fallida, 1 cancelada")
        XCTAssertEqual(queueSummary([.completed]), "1 instalada")
        XCTAssertEqual(queueSummary([.failed, .failed]), "2 fallidas")
        XCTAssertEqual(queueSummary([]), "")
    }
}

final class AppDetailsTests: XCTestCase {
    private func plist(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
    }

    func testDetailsFromInfoPlist() throws {
        let dict: [String: Any] = [
            "CFBundleIdentifier": "a.b", "CFBundleName": "App", "CFBundleShortVersionString": "1.2",
            "CFBundleVersion": "34", "MinimumOSVersion": "15.0", "CFBundleExecutable": "App",
            "NSCameraUsageDescription": "x", "NSMicrophoneUsageDescription": "y", "Other": 1,
            "CFBundleIcons": [
                "CFBundlePrimaryIcon": ["CFBundleIconFiles": ["AppIcon60x60"], "CFBundleIconName": "AppIcon"],
                "CFBundleAlternateIcons": ["Dark": ["CFBundleIconFiles": ["Dark60x60"]]],
            ],
        ]
        let d = try XCTUnwrap(AppDetails(infoPlist: try plist(dict), appFolderName: "App.app"))
        XCTAssertEqual(d.build, "34")
        XCTAssertEqual(d.minOS, "15.0")
        XCTAssertEqual(d.permissions, ["NSCameraUsageDescription", "NSMicrophoneUsageDescription"])
        XCTAssertEqual(d.primaryIconFiles, ["AppIcon60x60", "AppIcon"])
        XCTAssertEqual(d.alternateIcons, [AlternateIcon(name: "Dark", files: ["Dark60x60"])])
    }

    func testPickIconFilePrefersLargest() {
        let files: [(name: String, size: UInt64)] = [("AppIcon60x60@2x.png", 100), ("AppIcon60x60@3x.png", 250),
                                                     ("Other@3x.png", 999), ("AppIcon60x60.txt", 5000)]
        XCTAssertEqual(IconNames.pickFile(bases: ["AppIcon60x60"], from: files), "AppIcon60x60@3x.png")
        XCTAssertNil(IconNames.pickFile(bases: ["Missing"], from: files))
        XCTAssertEqual(IconNames.pickFile(bases: ["AppIcon60x60@2x.png"], from: files), "AppIcon60x60@3x.png")
    }

    func testMachOThin() {
        func le(_ v: UInt32) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24)] }
        func dylibCmd(_ cmd: UInt32, _ path: String) -> [UInt8] {
            var name = Array(path.utf8) + [0]
            while (24 + name.count) % 8 != 0 { name.append(0) }
            return le(cmd) + le(UInt32(24 + name.count)) + le(24) + le(0) + le(0) + le(0) + name
        }
        let cmds = dylibCmd(0xC, "/usr/lib/libSystem.B.dylib") + dylibCmd(0x80000018, "@rpath/Tweak.dylib")
            + le(0x19) + le(8)
        let header = le(0xFEEDFACF) + le(0x0100000C) + le(0) + le(2) + le(3) + le(UInt32(cmds.count)) + le(0) + le(0)
        let libs = MachO.dylibs(in: Data(header + cmds))
        XCTAssertEqual(libs, ["/usr/lib/libSystem.B.dylib", "@rpath/Tweak.dylib"])
        XCTAssertTrue(MachO.isSystem(libs[0]))
        XCTAssertFalse(MachO.isSystem(libs[1]))
        XCTAssertEqual(MachO.dylibs(in: Data("garbage!".utf8)), [])
        XCTAssertEqual(MachO.dylibs(in: Data(header + cmds.prefix(10))), [])
    }

    func testMachOFat() {
        func le(_ v: UInt32) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24)] }
        func be(_ v: UInt32) -> [UInt8] { le(v).reversed() }
        let name = Array("@rpath/A.dylib".utf8) + [0, 0]
        let cmd = le(0xC) + le(UInt32(24 + name.count)) + le(24) + le(0) + le(0) + le(0) + name
        let thin = le(0xFEEDFACF) + le(0) + le(0) + le(2) + le(1) + le(UInt32(cmd.count)) + le(0) + le(0) + cmd
        let fat = be(0xCAFEBABE) + be(1) + be(0x0100000C) + be(0) + be(32) + be(UInt32(thin.count)) + be(14)
            + [UInt8](repeating: 0, count: 4) + thin
        XCTAssertEqual(MachO.dylibs(in: Data(fat)), ["@rpath/A.dylib"])
    }
}

final class IconEditorTests: XCTestCase {
    func testSetPrimaryIcon() {
        let dict: [String: Any] = [
            "CFBundleIconFile": "old.png",
            "CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["X"], "CFBundleIconName": "AppIcon"]],
        ]
        let out = IconEditor.settingPrimaryIcon(dict)
        let primary = (out["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]
        XCTAssertEqual(primary?["CFBundleIconFiles"] as? [String], ["IXIcon60x60"])
        XCTAssertNil(primary?["CFBundleIconName"])
        XCTAssertNil(out["CFBundleIconFile"])
        XCTAssertNil(out["CFBundleIcons~ipad"])
    }

    func testSetPrimaryIconCreatesAndKeepsIPad() {
        let out = IconEditor.settingPrimaryIcon(["CFBundleIcons~ipad": ["CFBundleAlternateIcons": ["A": [:]]]])
        XCTAssertNotNil(out["CFBundleIcons"])
        let pad = (out["CFBundleIcons~ipad"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]
        XCTAssertEqual(pad?["CFBundleIconFiles"] as? [String], ["IXIcon76x76", "IXIcon83.5x83.5"])
    }

    func testRemoveAlternates() {
        let dict: [String: Any] = ["CFBundleIcons": [
            "CFBundlePrimaryIcon": ["CFBundleIconFiles": ["P"]],
            "CFBundleAlternateIcons": ["Dark": ["CFBundleIconFiles": ["Dark60x60"]]],
        ]]
        let (out, bases) = IconEditor.removingAlternateIcons(dict)
        XCTAssertEqual(bases, ["Dark60x60"])
        let icons = out["CFBundleIcons"] as? [String: Any]
        XCTAssertNil(icons?["CFBundleAlternateIcons"])
        XCTAssertNotNil(icons?["CFBundlePrimaryIcon"])
    }
}

final class CertSnapshotTests: XCTestCase {
    func testStatusAndDays() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func snap(_ exp: Date?) -> CertSnapshot {
            var s = CertSnapshot(certificateFile: "a.p12", profile: emptyProfile())
            s.expiresAt = exp
            return s
        }
        XCTAssertEqual(snap(now.addingTimeInterval(309 * 86_400)).daysRemaining(now: now), 309)
        XCTAssertEqual(snap(now.addingTimeInterval(309 * 86_400)).status(now: now), .valid)
        XCTAssertEqual(snap(now.addingTimeInterval(3 * 86_400)).status(now: now), .expiringSoon)
        XCTAssertEqual(snap(now.addingTimeInterval(-1)).status(now: now), .expired)
        XCTAssertNil(snap(nil).daysRemaining(now: now))
    }

    func testReminders() {
        let now = Date(timeIntervalSince1970: 0)
        let far = now.addingTimeInterval(30 * 86_400)
        XCTAssertEqual(expiryReminders(expiry: far, now: now).map { $0.daysBefore }, [7, 1])
        let soon = now.addingTimeInterval(3 * 86_400)
        XCTAssertEqual(expiryReminders(expiry: soon, now: now).map { $0.daysBefore }, [1])
        XCTAssertTrue(expiryReminders(expiry: now.addingTimeInterval(3600), now: now).isEmpty)
    }

    private func emptyProfile() -> ProvisioningProfile {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Name</key><string>P</string>\
        <key>UUID</key><string>U-1</string></dict></plist>
        """
        return try! ProvisioningProfile(data: Data(xml.utf8))
    }
}
