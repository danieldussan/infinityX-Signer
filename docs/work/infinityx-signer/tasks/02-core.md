# 02 - Logic core `InfinityXCore` (pure Swift)

## Goal
Port the pure logic of `signer.py` into a Swift package with no UIKit/SwiftUI so it is tested with `swift test` on Linux and reused by the app.

## Owned paths
`/home/ddussan/IOS-Signing/infinity-x-signer/Packages/InfinityXCore/**` (Package.swift, Sources/InfinityXCore, Tests/InfinityXCoreTests). Nothing else.

## Context
Read `/home/ddussan/IOS-Signing/infinity-x-signer/docs/work/infinityx-signer/contracts.md` (types to implement exactly) and `/home/ddussan/IOS-Signing/signer.py` functions `parse_numbers`, `fmt_num`, `last_number`/`save_number`, `set_app_name`, `strip_plugins`. Toolchain: Swift 6.4.2 on Linux. Dependencies: Foundation only (plist via `PropertyListSerialization`; no extra packages). Platforms: `.iOS(.v16)`, builds on Linux.

Spec excerpts to satisfy: batch input as range/list/mixed/count, duplicates removed in order, 2-digit minimum, invalid input gives clear error, counter persists and advances only on success, name -> `<prefix> <n>`, bundle -> `<prefix>.<n>`, localized InfoPlist.strings cleaned, optional strip PlugIns/Extensions, plist host configurable, itms-services link built from plist URL.

## Steps
1. Create `Packages/InfinityXCore/Package.swift` (swift-tools 5.9+, library `InfinityXCore`, test target).
2. `Sources/InfinityXCore/Numbers.swift`: `parseNumbers`, `formatNumber` (mirror signer.py: strip spaces, split ",", `a-b` needs a<=b, negatives error, empty error, dedup keep order).
3. `Sources/InfinityXCore/Batch.swift`: `BatchInput`, `SigningJob`, `BatchError`, `makeJobs` (count mode: start = lastUsed+1; both numbersText and count -> error; count < 1 -> error).
4. `Sources/InfinityXCore/Counter.swift`: `CounterStore` protocol, `JSONFileCounterStore` (`{"last": n}`), `advance` with max semantics.
5. `Sources/InfinityXCore/PlistEditor.swift`: `setName` sets `CFBundleDisplayName` and `CFBundleName` in `<app>/Info.plist` (preserve other keys); when `cleanLocalized`, for each `*.lproj/InfoPlist.strings`: binary/XML plist -> drop the two keys, text -> remove lines matching `^\s*"?CFBundle(Display)?Name"?\s*=.*;\s*$` (utf-8 and utf-16 BOM); an unreadable file is skipped, never throws. `stripPlugins` removes `PlugIns` and `Extensions` dirs.
6. `Sources/InfinityXCore/Install.swift`: `InstallMode`, `InstallConfig` (default host `https://api.palera.in`), `genPlistURL` (query items bundleid, name, version, fetchurl; percent-encoded), `itmsServicesURL`.
7. Tests (`Tests/InfinityXCoreTests`): parseNumbers (`21-25`, `21,23`, `21-23,30`, dups, `5-3` error, `abc` error, empty), formatNumber (4->"04", 105->"105"), makeJobs (count from last=24 gives 25..; file name `WA25-signed.ipa`), counter (advance only up; file round trip), PlistEditor (temp .app with XML and binary Info.plist; strings cleaned in utf-8 and utf-16 fixtures; other keys intact; strip dirs), URL builders (encoding of spaces in "WAB 21").

## Test command
`cd /home/ddussan/IOS-Signing/infinity-x-signer/Packages/InfinityXCore && swift test` (timeout 300000). Same on Branch A or B. Linux only; no device needed.

## Done
All tests pass; public API matches contracts.md; no UIKit/SwiftUI imports (`grep -rn "UIKit\|SwiftUI" Sources` is empty).

## Out of scope
UI, Zsign calls, networking, server, Keychain, zipping (zip/unzip lives in app unit).
