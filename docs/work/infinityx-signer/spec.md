# Spec: Infinity X Signer v1

## What
A minimal iOS app where a user imports their own .p12 + password, .mobileprovision and an IPA, chooses a name prefix, bundle prefix and a range of numbers, and gets N signed copies ("WAB 21".."WAB 25" / "chip.21".."chip.25") installed on the device one after another.

## Why
Replaces the desktop `signer.py` + `ideviceinstaller` flow so the course audience can do it from the phone, with the "WhatsApp Infinity X" look.

## Acceptance criteria
1. Import: user can pick a .p12, type its password, pick a .mobileprovision and an IPA. Nothing is bundled in the app or repo. Password is not stored in plain files.
2. Batch input: name prefix, bundle prefix, and numbers via range (`21-25`), list (`21,23`), mixed (`21-23,30`) or count ("next K"). Duplicates removed, order kept, invalid input rejected with a clear message. Numbers render with 2-digit minimum (`04`, `12`, `105`).
3. Persistent counter: "next K" continues after the last number used, across app launches, only advancing on successful signs.
4. Signing: for each number, the app copy gets display name `<name prefix> <n>` and bundle id `<bundle prefix>.<n>`, localized name strings cleaned so the name is not overridden, optional removal of PlugIns/Extensions, and is signed with the user's cert/profile. One failed item does not stop the batch; failures are listed at the end.
5. Install: Semi Local (default), Fully Local (optional) and Export (share sheet, always available). Batch installs sequentially, one iOS prompt per app. The app stays alive while installing in the background.
6. Plist host is configurable (default `https://api.palera.in`).
7. Fully Local shows the SSL pack expiry, can refresh it manually and refreshes automatically on a failed handshake.
8. Diagnostics screen shows: current install mode, server status/URL, SSL pack validity ("valid until X"), plist host, counter value.
9. Look: black background, glass cards, white italic bold type, big X, green accent. Placeholders only (SF Symbols, gradient, generated icon) until designer assets arrive.
10. App is buildable into an .ipa by the chosen build path (see plan.md).

## Non-goals (v1)
Repos/sources, tweak/dylib injection, idevice/VPN/pairing mode, localization, iPad polish, UDID messaging.
