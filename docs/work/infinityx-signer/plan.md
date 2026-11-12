# Plan: Infinity X Signer v1

Spec: [spec.md](spec.md) | Contracts: [contracts.md](contracts.md) | Status: [status.md](status.md)

## Goal
SwiftUI iOS app from scratch (Feather-inspired, not a fork) doing batch signing with consecutive names and sequential install. Zsign-Package (khcrysalis) for signing.

## Non-goals
Repos/sources, tweaks/dylibs, idevice/VPN/pairing, localization, iPad polish, UDID messaging, bundling any IPA.

## Grounded environment (checked read-only)
- `xtool --version` = 1.24.0 (`~/.local/bin/xtool`); `swift --version` = 6.4.2 x86_64-linux (`/usr/bin/swift`); clang and openssl present.
- `xtool sdk status` = **Not installed**: the Darwin Swift SDK is not set up yet. Installing it needs an Xcode.xip obtained from Apple (user action, Apple ID). Spike step 1 must cover this.
- No git repo in `/home/ddussan/IOS-Signing`; do not `git init`.

## Build path: decided by the spike (task 01)
- **Branch A (xtool passes)**: build with `xtool dev build` (SwiftPM, on Linux) -> .ipa. Package layout is SwiftPM-first (`Package.swift` + `xtool.yml`).
- **Branch B (xtool fails)**: GitHub Actions macOS runner, `xcodebuild` with `CODE_SIGNING_ALLOWED=NO`, zip `Payload/` to .ipa, publish to Releases. Same SwiftPM sources are consumed through a thin Xcode project or `xcodebuild -scheme` on the package; the logic core is unaffected.
- Spike pass criteria are in tasks/01-spike.md. Units 02 and 03 contain instructions for both branches.

## Units (max 3, sequential 01 -> 02 -> 03)
| # | Unit | Owned paths | Deps | Test command |
|---|------|-------------|------|--------------|
| 01 | xtool spike (+ writes the build decision) | `spike/` , `docs/work/infinityx-signer/build-decision.md` | none | `bash spike/verify.sh` (checks .ipa exists, contains Zsign symbol) |
| 02 | Logic core `InfinityXCore` (pure Swift, no UIKit) | `Packages/InfinityXCore/**` | 01 (only for toolchain/layout choice) | `cd Packages/InfinityXCore && swift test` (Linux, works on both branches) |
| 03 | App: UI, signing engine glue, server, install, diagnostics | `App/**`, `Package.swift` or `*.xcodeproj` (per branch), `.github/workflows/**` (branch B) | 01, 02 | Branch A: `xtool dev build`; Branch B: Actions run green. Core unit tests: `swift test`. On-device checks listed in task 03 |

## Merge order
01 -> 02 -> 03. Contracts (contracts.md) land with 02 first.

## Verifiable where
- Linux `swift test`: batch parsing, formatting, counter, Info.plist edit, strings cleanup, plan building, plist host URL building.
- Build only (no device): app compiles, links Zsign, .ipa produced.
- Device only: actual signing result, install prompts, Semi/Fully Local server flow, background keep-alive, SSL pack handshake.

## Risks
1. xtool + Zsign-Package (C++/OpenSSL) may not cross-compile, and the Darwin SDK needs an Xcode.xip + Apple login. Mitigation: spike first, Branch B ready.
2. Install flow reliability: Semi Local depends on api.palera.in (third party) and an SFSafariViewController trick; Fully Local depends on backloop.dev cert pack and iOS 18 entitlements unavailable to sideloaded apps (likely only works when app is signed with them). Mitigation: configurable plist host, Export always available, Semi Local default.
3. Sideloaded-app signing on device: Zsign must sign an extracted .app in the app sandbox with a device-bound cert; the app itself must keep running during a long batch (memory/time, background audio). Mitigation: sequential jobs, temp cleanup per job, early device smoke test in task 03.
