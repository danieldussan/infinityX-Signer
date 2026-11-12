# Brainstorm: batch IPA signer app (WhatsApp Infinity X branding)

## Decisions (user)
- App from scratch, minimal, SwiftUI. Inspired by Feather (claration/Feather), not a fork.
- Core feature: batch signing with consecutive name/bundle id (port of `signer.py`: `WAB 21` / `chip.21`, ranges `21-25`, persistent counter).
- Users import their own .p12 + .mobileprovision + IPA. IPA never shipped in repo.
- Certs: device-bound, paid (applep12). Users already know; no UDID messaging.
- Build: GitHub Actions or xtool (xtool-org/xtool: SwiftPM -> iOS app on Linux).
- Branding: course "WhatsApp Infinity X" (black bg, glass cards, blue/orange light flares, white italic bold type, big X, WhatsApp green accent).

## Feather findings (verified in source)
- Signing: `khcrysalis/Zsign-Package` (SPM). API: `Zsign.sign(appPath, provisionPath, p12Path, p12Password, entitlementsPath, removeProvision, completion)`.
- Install "Server" mode: Vapor HTTP server on random port 4000-8000, routes `/<id>.plist`, `/<id>.ipa`, `/install`, icons. Streams IPA, status: ready -> sendingManifest -> sendingPayload -> installing -> completed.
- Fully Local: HTTPS with `*.backloop.dev` cert. Pack from `https://backloop.dev/pack.json` -> fields cert, ca, key1+key2, info.domains.commonName. Saved to Documents as server.pem/server.crt/commonName.txt. Host = commonName. Opened via `UIApplication.open(itms-services://?action=download-manifest&url=<plist>)`. Needs iOS 18 entitlements (Associated Domains, Custom Network Protocol, MDM Managed Associated Domains, Network Extensions) -> why it breaks for sideloaded apps.
- Semi Local: plain HTTP local server (LAN IP, or 127.0.0.1 with "only localhost" fix). Plist generated remotely by `https://api.palera.in/genPlist?bundleid&name&version&fetchurl=<local ipa url>` (nekohaxx/plistserver). Local `/install` HTML does `window.location = itms-services://...`, shown in SFSafariViewController sheet (workaround for missing entitlements). Sheet closes on sendingPayload.
- Keep-alive: BackgroundAudioManager during install. Progress via polling installed bundle id.
- Third mode "idevice": VPN (LocalDevVPN) + pairing file + AFC /PublicStaging + installd. Reliable, needs computer once.
- SSL "update" = re-fetch pack.json (button in Server & SSL view).

## Design for ours
- Install modes: Semi Local default (no SSL dependency), Fully Local optional, Export (share sheet) always.
- SSL pack: never embedded; fetch on launch, cache, show expiry, auto-refresh on handshake failure, manual button.
- Plist host: make configurable (default palera.in genPlist; allow own plistserver deploy) to avoid single point of failure.
- Batch queue: sequential install, one iOS prompt per app.

## Decided (round 2)
- App name: **Infinity X Signer**.
- Plist server: start with api.palera.in; self-host plistserver later if needed (keep host configurable).

## Open questions
- Include idevice mode in v1? (needs VPN+pairing; probably v2)
- App name / bundle id / icon.
- Build: GH Actions macOS runner (simple, reproducible) vs xtool (build from Arch locally). Zsign-Package is C++/OpenSSL; xtool compatibility with it untested.
