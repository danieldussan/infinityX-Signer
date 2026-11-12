# 01 - xtool spike (sequential, blocks 02 and 03)

## Goal
Prove (or disprove) that this Arch Linux machine can build a SwiftPM iOS app with xtool that depends on Zsign-Package (C++/OpenSSL) and produces an .ipa. Result decides the build path.

## Owned paths
`/home/ddussan/IOS-Signing/infinity-x-signer/spike/**` and `/home/ddussan/IOS-Signing/infinity-x-signer/docs/work/infinityx-signer/build-decision.md`. No git init. Do not touch other paths.

## Grounded facts
- xtool 1.24.0 at `~/.local/bin/xtool`; Swift 6.4.2 at `/usr/bin/swift`; clang and openssl exist.
- `xtool sdk status` printed "Not installed": Darwin SDK missing. `xtool setup` / `xtool sdk install <Xcode.xip>` need an Xcode.xip from Apple (needs the user's Apple ID download). If the xip is not available, STOP, mark Branch B, and ask the user (do not log into anything yourself).
- Docs: https://xtool.sh . Zsign API: `Zsign.sign(appPath:provisionPath:p12Path:p12Password:entitlementsPath:removeProvision:completion:)` (Feather uses it from `Feather/Utilities/Handlers/ZsignHandler.swift`).
- Run every command in foreground with explicit timeout (max 600000 ms). No sleep loops, no pgrep/pkill.

## Steps
1. `xtool --version`, `swift --version`, `xtool sdk status` (read-only). Record in build-decision.md.
2. If SDK not installed: ask user for the Xcode.xip path (or say Branch B). Then `xtool sdk install <xip>` (check `xtool help sdk` first).
3. `cd spike && xtool new SpikeApp` (check `xtool help new`). Confirm it builds with `xtool dev build` BEFORE adding Zsign (baseline).
4. Add Zsign-Package dependency in `Package.swift` (`https://github.com/khcrysalis/Zsign-Package`, `import Zsign`; pin to a tag/revision, record it). Add a button/print calling `Zsign.sign(appPath: "", provisionPath: "", p12Path: "", p12Password: "", entitlementsPath: "", removeProvision: false) { _ in }` so the symbol is referenced (link must pull it in).
5. `xtool dev build` -> locate output .ipa (xtool puts it under `xtool/` or `.build`; note the path).
6. Write `spike/verify.sh`: fails unless (a) an .ipa exists, (b) `unzip -l` shows `Payload/*.app/<binary>`, (c) `strings`/`llvm-nm`/`nm` on the binary finds a Zsign symbol (grep `Zsign` or `ZSign`).
7. Run `bash spike/verify.sh`. Write `build-decision.md`: PASS/FAIL, exact commands, versions, pinned Zsign revision, workarounds, time to build.

## Pass / fail (clear)
- PASS (Branch A): verify.sh exits 0: .ipa produced on this machine, links Zsign, binary references the `Zsign.sign` symbol. Running on device is NOT required for the spike.
- FAIL (Branch B): SDK cannot be installed (no xip), OR Zsign-Package fails to compile/link under xtool and a 30 min timeboxed fix attempt (e.g. OpenSSL headers, C++ flags) does not work.
- Time box: 90 min total. On FAIL write the failure log excerpts in build-decision.md and the Branch B workflow outline:
  `.github/workflows/build.yml` on `macos-latest`: `xcodebuild -scheme InfinityXSigner -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO -derivedDataPath build`, `mkdir Payload && cp -R build/Build/Products/Release-iphoneos/*.app Payload/ && zip -qry InfinityXSigner.ipa Payload`, upload to a GitHub Release (`gh release create` / `softprops/action-gh-release`).

## Done
`build-decision.md` exists with PASS/FAIL and the resulting build path; `status.md` item 01 updated.

## Out of scope
App features, UI, logic core, on-device testing, publishing anything.
