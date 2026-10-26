# Watch verification

## 3.18 (48) — standalone extraction, 2026-10-26

Watch now has its own repository, root Sources/ and Tests/, dedicated `scripts/watch_build.py`, app-only metadata, bundled helper preparation and DMG verification. No sibling source trees, suite build scripts, credentials, cookies, user libraries or prior Git history are included. Original Watch behavior is retained; the app version changes to identify this standalone packaging. The bundle ID, preferences, hotkey and URL handlers remain compatible.

The source owner selected MIT for Watch code. Bundled tools retain their upstream licenses; notices and sources are included in the app. Large downloaded helpers, build output and DMGs are ignored by Git. The original project remains intact.

Validation results are recorded below after execution. Helper inputs were copied as ordinary files into the new ignored cache to avoid downloading identical archives; prepared binaries were not copied. FFmpeg/LAME are rebuilt for both architectures in this project.

### Remaining acceptance boundaries

- Local builds are ad-hoc signed and not notarized. Open-source publication does not remove Gatekeeper approval requirements.
- Native Apple Silicon and Intel helpers under Rosetta can be tested here; real Intel hardware and macOS 13 acceptance remain pending.
- Browser sign-in, Keychain/Full Disk Access prompts and authenticated History/Playlists require manual acceptance. Tests must not use personal cookies.
- Public metadata checks do not guarantee all videos/sites will play; upstream behavior can change.
- Review complete upstream licensing/source requirements before wider binary distribution; Watch's MIT license does not relicense its bundled dependencies.

### Completed verification

- 14 tooling safety tests, 416 Swift regression checks, 58 isolated full-source AppKit checks, and 11 real-helper integration checks pass (499 checks). The integration fixture covers relocation to a path containing spaces, clean HOME/PATH, Python/EJS tool packaging, offline Deno execution, local HTTP download, MP3 conversion, HEVC VideoToolbox conversion, track merging, and all four Intel helper slices under Rosetta. No production instance was launched and no personal cookies were used. Public network metadata checks were not repeated for this extraction.
- A new `git clone --no-local` into a temporary directory, without build caches or generated binaries, passed all 430 logic/tooling checks and remained clean. The repository has no object alternates, tracked symlinks or remote; its Git history starts with the standalone extraction.
- FFmpeg and LAME were rebuilt from pinned source for both architectures in this project. Only hash-verified downloaded inputs were reused as physical copies.
- `./package.sh` passed under a macOS sandbox policy denying reads from the original checkout. A control read of the original README failed with Operation not permitted, confirming the isolation policy was active. Universal app and helper validation passed.
- `python3 scripts/verify_watch_package.py --canonical` passed: read-only DMG mount, application metadata, universal architectures, helper hashes, app/child signatures, exact first-run guide and disk-image integrity. The app also contains its own MIT license. Gatekeeper rejects this ad-hoc, unnotarized build as expected.
- Logs and snapshots are local ignored artifacts under `build/`; the verified installer, checksum and receipt are under `dist/`. Generated dependencies and installers are not tracked by Git.

Installer: Watch 3.18 (48), 229799718 bytes. SHA-256: `45a34b13ee3541b7f32f6902536863efd6e0e6b8abccb14dc9d1b7cf95b743cf`.
