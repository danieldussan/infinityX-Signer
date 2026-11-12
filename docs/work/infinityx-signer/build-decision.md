# Build decision: Branch B (GitHub Actions)

Decided by user on 2026-11-11. Spike 01 not run.

**Why:** xtool 1.24.0 and Swift 6.4.2 are installed, but `xtool sdk status` = "Not installed". The Darwin SDK needs an Xcode.xip (Apple ID download) and the user does not have it.

**Path:** unit 03 builds on a `macos-latest` runner (`xcodebuild`, `CODE_SIGNING_ALLOWED=NO`, zip `Payload` to `.ipa`, publish to a GitHub Release). Outline in `tasks/01-spike.md` (Fail section).

**Local dev:** `InfinityXCore` is pure Swift, tested with `swift test` on Linux. UI/signing/server only verifiable on CI build + device.

**Revisit:** if the user later gets an Xcode.xip, run spike 01 to add a local build path. Not blocking.
