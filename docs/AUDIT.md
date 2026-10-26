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
