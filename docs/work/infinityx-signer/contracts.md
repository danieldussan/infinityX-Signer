# Contracts (land in unit 02, consumed by unit 03)

All in Swift package `InfinityXCore` (`Packages/InfinityXCore`), no UIKit/SwiftUI imports.

```swift
public struct BatchInput {            // raw user input
  public var namePrefix: String       // "WAB"
  public var bundlePrefix: String     // "chip"
  public var numbersText: String?     // "21-25" | "21,23" | "21-23,30"
  public var count: Int?              // "next K"; exclusive with numbersText
  public var stripPlugins: Bool
}

public struct SigningJob: Equatable { // one app to produce
  public let number: Int
  public var displayName: String      // "WAB 21"
  public var bundleID: String         // "chip.21"
  public var outputFileName: String   // "WA21-signed.ipa"
}

public enum BatchError: Error { case invalidNumber(String), empty, negative, bothRangeAndCount, countTooSmall }

public func parseNumbers(_ text: String) throws -> [Int]   // dedup, keep order
public func formatNumber(_ n: Int) -> String               // %02d
public func makeJobs(_ input: BatchInput, lastUsed: Int, filePrefix: String) throws -> [SigningJob]

public protocol CounterStore { var last: Int { get set } }  // UserDefaults impl in app; in-memory/JSON impl in core
public func advance(_ store: inout some CounterStore, afterSuccess n: Int) // last = max(last, n)

public enum PlistEditor {                                   // works on a .app directory URL
  static func setName(appDir: URL, name: String, cleanLocalized: Bool) throws
  static func stripPlugins(appDir: URL) throws              // removes PlugIns/, Extensions/
}

public enum InstallMode: String { case semiLocal, fullyLocal, export }
public struct InstallConfig { public var mode: InstallMode; public var plistHost: URL /* default https://api.palera.in */ }
public func genPlistURL(host: URL, bundleID: String, name: String, version: String, ipaURL: URL) -> URL
// -> <host>/genPlist?bundleid=&name=&version=&fetchurl=  (percent-encoded)
public func itmsServicesURL(plistURL: URL) -> URL           // itms-services://?action=download-manifest&url=<plist>
```
Behavior ported from `signer.py`: `parse_numbers` (dedup, `a-b` with a<=b, negatives rejected, empty rejected), `fmt_num` (2-digit min), counter = `max(saved, ...)` only advancing on success, `set_app_name` (CFBundleDisplayName + CFBundleName; clean `*.lproj/InfoPlist.strings` lines for those keys, supports binary/XML plist, utf-8/utf-16 text), `strip_plugins`.
