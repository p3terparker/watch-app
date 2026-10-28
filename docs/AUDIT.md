# Watch verification

## 3.19 (49) — Now Playing artwork, 2026-10-28 (preview; hands-on acceptance pending)

Adds the panel's Now Playing row and a floating artwork window that follows the music, with a full-screen mode over a gradient of the artwork's colours or black (`Sources/NowPlaying.swift`, `Sources/ArtworkWindow.swift`, `Sources/ArtworkStyle.swift`). macOS Now Playing is read through the bundled mediaremote-adapter (BSD-3, commit `0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd`, fetched by git and verified by commit hash), built universal for macOS 13 into `Contents/Frameworks/MediaRemoteAdapter.framework`. Only the adapter's read-only `stream` command is used, and only while the panel or the artwork window is showing. The bundle ID, preference keys (new: `showNowPlaying`, `artworkColourBackground`), hotkey and URL handler are unchanged. The prepared FFmpeg payload's fingerprint is unchanged, so existing helper caches stay valid.

### Completed verification (Linux authoring environment, no Swift toolchain)

- 18 tooling safety tests pass, including the new ones: a dylib's own install name, rejection of foreign `@rpath` libraries, the pinned-source manifest, and cached-archive commit checks.
- The real `fetch_source` path ran against GitHub: the pinned commit fetched and verified, the archive was reused without network, a corrupted cache was rejected, and every upstream build input was present. Watch's source list matches upstream's `CMakeLists.txt`.
- `Sources/NowPlaying.swift`, `Sources/ArtworkStyle.swift` and `Tests/NowPlayingChecks.swift` compiled and ran with Swift 6.1 on Linux (official `swift:6.1-noble` image, `-swift-version 5 -warnings-as-errors`): 80 checks pass, including background colour picking and full-screen layout. That covers parsing, line reassembly, naming, environment scrubbing, and the monitor's start/stop, de-duplication, debounce and back-off against real `/bin/sh` processes. This run caught and fixed a background closure capturing the monitor's weak `self` variable.
- Every Swift file in Sources/ and Tests/ parses. The AppKit files (`main.swift`, `ArtworkWindow.swift`, `PanelMain.swift`) could not be type-checked on Linux.
- Python sources compile and the shell scripts pass `bash -n`.

### Completed verification (GitHub Actions, macos-15 Apple Silicon)

[Run 40648197775](https://github.com/p3terparker/watch-app/actions/runs/40648197775), commit `939dda5`, all steps green on the first attempt:

- The whole app type-checks. The universal build (arm64 + x86_64) passed its bundle verification.
- 18 tooling tests and 496 Swift regression checks pass, including all Now Playing, background-colour and full-screen-layout checks.
- 12 real-helper integration checks pass. These include all four Intel helper slices under Rosetta, and the relocated Now Playing adapter loading under `/usr/bin/perl` and reading MediaRemote (it returned `null`; nothing was playing on CI).
- `verify_watch_package.py --canonical` passed: read-only DMG mount, metadata, both architectures, helper and adapter hashes, signatures. Gatekeeper rejects the ad-hoc, unnotarized build, as expected.
- The isolated AppKit harness passes 83 checks with 0 failures. That includes the Now Playing row (placement, filtering, Preference, menu) and the artwork window: size, aspect following, placeholder, Esc, the full-screen menu entry and the background choice.
- The workflow published the [v3.19-preview pre-release](https://github.com/p3terparker/watch-app/releases/tag/v3.19-preview). The DMG is 230,131,032 bytes, SHA-256 `94db4ba0bdc373ad072db70ac1595d908dec1c5eb3f5c6ccf82794288e27ae06`. "Latest" still resolves to v3.18.

### Pending (hands-on acceptance)

- Music, Spotify and a browser video on a real Mac. Playback must never pause, skip or stutter, and no permission prompt may appear. The artwork must follow track changes.
- No adapter process may run while the panel and artwork window are closed, or after quitting.
- Full screen entered and left by hand (double-click, ⌃⌘F/F, menu, Esc): following track changes, idle hiding, both backgrounds, closing from full screen, multiple displays. Native full screen for this menu-bar (accessory) app has not been observed yet; CI only exercises the menu and background choice.
- macOS 13–15.3 and real Intel hardware. The workaround depends on Apple keeping `/usr/bin/perl` entitled. If that ends, the row stops appearing.
- Developer ID signing and notarization, as for 3.18.

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
