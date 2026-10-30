# Packaging Watch

Run `./package.sh`, then `python3 scripts/verify_watch_package.py --canonical`. Deliver `dist/Watch-<version>.dmg` (the release number is in the name); keep its SHA-256 and verification report (`dist/Watch-<version>.dmg.sha256`, `dist/Watch-<version>-verification.json`) together. Packaging the same version again replaces that file — bump the version or build for a new deliverable. The app must include all four pinned media helpers and third-party notices/sources. No system-tool setup is required for recipients.

Before changing dependency pins, read THIRD_PARTY.md. Rebuild and execute the real-helper fixture from a clean temporary home, including format conversion and both architecture slices where possible. Never replace helper binaries inside an already signed app; rebuild the app instead.

Record verification and manual gaps in AUDIT.md. Test installation on a clean recipient Mac, oldest supported macOS and real Intel hardware before claiming those environments are supported by runtime testing.

This project currently produces ad-hoc signed, unnotarized builds. It does not configure or submit Apple notarization. The first-run instructions describe the recipient's macOS approval steps. `--release` is only a validation gate for a future externally signed/notarized bundle, not an automatic signing service.
