# 03 - App: UI, signing engine, server, install, diagnostics

## Goal
SwiftUI app "Infinity X Signer" that imports cert/profile/IPA, runs the batch through `InfinityXCore` + Zsign, and installs sequentially. Build path comes from `docs/work/infinityx-signer/build-decision.md` (Branch A xtool or Branch B GitHub Actions). Read that file first.

## Owned paths
`/home/ddussan/IOS-Signing/infinity-x-signer/App/**` (Sources, Resources, placeholder assets), root `Package.swift` + `xtool.yml` (Branch A) or `InfinityXSigner.xcodeproj`/scheme + `.github/workflows/build.yml` (Branch B). Does NOT edit `Packages/InfinityXCore` (request changes via the task owner). Never add any IPA to the repo (add `*.ipa`, `*.p12`, `*.mobileprovision` to `.gitignore`).

## Context (copied)
- Core API: see `contracts.md` (parseNumbers, makeJobs, JSONFileCounterStore/CounterStore, PlistEditor, genPlistURL, itmsServicesURL, InstallMode, InstallConfig).
- Signing: `Zsign.sign(appPath:provisionPath:p12Path:p12Password:entitlementsPath:removeProvision:completion:)` from `https://github.com/khcrysalis/Zsign-Package` (revision pinned in build-decision.md). Feather calls it on an extracted `.app` directory.
- Per job: unzip IPA once -> for each job: `PlistEditor.setName`, set `CFBundleIdentifier` = job.bundleID, zip to a temp IPA, unzip-sign copy, Zsign on the `.app`, zip to `Payload` -> `<outputFileName>`. Mirror signer.py: re-edit the same extracted app per job (clean localized strings only on the first), one failed job does not stop the batch.
- Unzip/zip on iOS has no `/usr/bin/zip`: use a small SwiftPM zip library (e.g. ZIPFoundation, pinned) or Feather's approach (it uses ZIPFoundation + Zip). Keep one dependency only.
- Install, Semi Local (default): plain HTTP server on LAN IP or 127.0.0.1, random port 4000-8000; routes `/<id>.ipa`, `/install`. Plist URL = `genPlistURL(host: config.plistHost, bundleID, name, version, ipaURL: http://<ip>:<port>/<id>.ipa)`. `/install` serves HTML doing `window.location = "<itmsServicesURL>"`, opened in an `SFSafariViewController` sheet (workaround for missing entitlements). Close the sheet when the IPA download starts. States: ready, sendingManifest, sendingPayload, installing, completed. Progress = poll for the installed bundle id.
- Fully Local (optional): HTTPS with `*.backloop.dev` pack from `https://backloop.dev/pack.json` (fields `cert`, `ca`, `key1`+`key2` joined, `info.domains.commonName`); cache to Application Support (server.pem, server.crt, commonName.txt, fetchedAt), parse expiry from the cert, show it, manual refresh button, auto refresh once on handshake failure. Host = commonName. Open via `UIApplication.open(itmsServicesURL)`. Note in UI: may not work on sideloaded builds lacking iOS 18 entitlements; Semi Local is default.
- Export: share sheet (`UIActivityViewController`/`ShareLink`) with the signed IPA, always available.
- Server library: prefer a tiny HTTP server on `Network.framework` (NWListener) over Vapor to avoid a big dependency; HTTPS needs the pem identity (SecIdentity from key+cert) - if too heavy, use a minimal Vapor/Swifter only for Fully Local and note it.
- Keep-alive: silent looping audio (`AVAudioSession` .playback, `UIBackgroundModes: audio`) while a batch/install runs, stop afterwards.
- Cert password: Keychain (`kSecClassGenericPassword`, accessible after first unlock, keyed by cert file name). Counter: `UserDefaults`-backed `CounterStore`; advance only after a successful sign.
- Queue: sequential, one iOS install prompt per app; wait for each to finish (installed bundle id seen or timeout 120s) before the next; per-item status.
- Branding (placeholders only): black background, glass cards (`.ultraThinMaterial`), blue/orange blurred radial "flares" via gradients, white italic heavy type, large SF Symbol "xmark" as X, accent `#25D366`. Generated placeholder app icon (simple X on black) in asset catalog. Easy swap: all colors/fonts in `Theme.swift`, assets named `AppIcon`, `Logo`.

## Steps
1. Scaffold per build-decision branch (A: copy spike layout, add `InfinityXCore` as local package dependency; B: package/Xcode project + workflow). `.gitignore` entries. Keep Info.plist keys: `UIBackgroundModes=[audio]`, `NSLocalNetworkUsageDescription`, `NSAppTransportSecurity` allowing arbitrary loads for the local HTTP server and local networking.
2. `App/Sources/Theme.swift` and `Components/GlassCard.swift`, `XBackground.swift`.
3. `App/Sources/Import/` document pickers for .p12, .mobileprovision, IPA (copy into app container `Documents/Imports/`); `KeychainStore.swift`.
4. `App/Sources/Batch/BatchView.swift` + `BatchViewModel.swift`: name prefix, bundle prefix, range/count field, strip plugins toggle, counter display, validation errors from `BatchError`, Start button.
5. `App/Sources/Signing/SigningEngine.swift`: unzip once, loop jobs, call Zsign, produce signed IPAs in `Documents/Signed/`, report per-job status, advance counter on success, cleanup temp dirs per job.
6. `App/Sources/Install/`: `LocalServer.swift` (HTTP), `SSLPack.swift` (fetch/cache/expiry/refresh), `InstallCoordinator.swift` (queue, modes, state machine), `SafariInstallSheet.swift`, `ExportShare.swift`, `KeepAlive.swift`.
7. `App/Sources/Diagnostics/DiagnosticsView.swift`: install mode picker, plist host field (default `https://api.palera.in`), server status/URL, SSL pack "valid until X" + refresh, counter value, last errors.
8. Build: Branch A `xtool dev build` -> .ipa. Branch B push workflow and confirm a green run + Release asset.

## Test commands
- Core logic (Linux, both branches): `cd Packages/InfinityXCore && swift test`.
- Compile/link: Branch A `xtool dev build` (timeout 600000); Branch B GitHub Actions run `build.yml` green.
- Add small Linux-testable pieces to Core only via a new request; UI/server/Zsign cannot be tested on Linux.
- On-device checklist (user, manual): (1) sign 1 IPA with own cert, name+bundle correct on home screen; (2) Semi Local install of 1 app; (3) batch 21-23 installs 3 apps one prompt each; (4) app survives screen lock during install; (5) Fully Local with SSL refresh (best effort); (6) Export share sheet; (7) counter persists after relaunch.

## Done
Builds to .ipa on the chosen path; all screens exist with placeholders; no IPA/cert in repo; on-device checklist handed to user with results recorded in `status.md`.

## Out of scope
Repos/sources, tweak/dylib injection, idevice/VPN/pairing, localization, iPad polish, UDID messaging, final designer assets, self-hosted plistserver.
