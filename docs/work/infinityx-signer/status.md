# Status
- [x] 01 xtool spike -> SKIPPED, Branch B (GitHub Actions), see build-decision.md
- [x] 02 InfinityXCore logic + `swift test` green (16 tests pass, no UIKit/SwiftUI imports)
- [ ] 03 App: code written (untested, no local compile); awaiting first green CI run + .ipa
  - [ ] on-device: sign 1 IPA
  - [ ] on-device: Semi Local install 1 app
  - [ ] on-device: batch of 3 sequential installs
  - [ ] on-device: Fully Local + SSL refresh (best effort)
- [x] 04 Round 2 (untested, no local compile): Feather-style document picker import, ProvisioningProfile parser in Core (22 tests green), cert/profile info + password check (SecPKCS12Import), full UI redesign per mockups/01-app.html; awaiting CI compile + on-device check
- [x] 05 Round: Apps tab (Importadas/Firmadas/Instaladas, AppLibrary in library.json), Ajustes > Acerca de, UpdateChecker (GitHub releases, 1 check/day) + banner + tab badge, `isNewerVersion` in Core (25 tests green); typecheck OK; UI behaviour awaiting on-device check
