# Watch verification

## 3.21 (53) — Up Next under the music window, 2026-10-30 (preview; hands-on acceptance pending)

One app-wide queue that drops down under the music window: Play Next / Play Later everywhere, audio files and links played
by Watch in the music window, queued videos in a video window beside it, Spotify songs/episodes in the Spotify app, and
slotting into Music/Spotify at a song's end with a hand-back when the list runs out (`Sources/Queue.swift`,
`Sources/Handoff.swift`, `Sources/UpNext.swift`, `Sources/QueueDrawer.swift`). No preference keys added; bundle ID, hotkey
and URL handlers unchanged (a new `queue` host joins `play`). The Automation usage description now mentions controlling
Music/Spotify for the queue.

### Verification

- Authored without a local Swift toolchain; GitHub Actions on macOS compiles and tests it.
- First run, [40983777826](https://github.com/p3terparker/watch-app/actions/runs/40983777826) (`7d8195e`): type-check,
  `./check.sh` (unit tests incl. the queue, hand-off and Spotify checks), helpers, package, bundled tools and installer
  verification passed; the GUI harness failed 2 of 192 checks, both from GitHub's 1024×768 screen: the list flipped above a
  477 pt music window and was clamped over it, and a queued video then found no free spot beside them and cascaded.
  Fix: `DrawerLayout` (`Sources/Tiling.swift`, unit-tested) — below, else above, else the window moves up just enough (never
  while you drag or resize it), shrinking the list on a screen too short for both; the harness's video check now uses a
  smaller music window so a free spot exists. Results of the next run are recorded with 3.22.
- Manual (pending, needs a real Mac): slot-in with real Music and Spotify (the boundary pause and rewind, how much of the next
  song is heard, the hand-back), the one-time Automation prompts, Spotify launching in the background, media-key Next
  during a Spotify song, drag-and-drop from Finder/Spotify into the list, and the list's look under small and large windows.

## 3.20 (52) — music window controls, 2026-10-30 (preview; hands-on acceptance pending)

Music window only (video windows unchanged): one row of controls under the caption (`ArtworkLayout.controlRow`), the app's
own shuffle and repeat (`AppVolume` scripts, `MusicAppControl.modes`/`setMode`), reveal on hovering anywhere with a 1 s exit
grace, and the `MusicZone` click model (click anywhere = play/pause after the double-click interval, double-click = open the
source in its app, ∓10 s only in far-edge strips). Full screen moved off double-click to F / ⌃⌘F / the menu. `build.yml`
skips publishing for commits marked `[no preview]`. No preference keys added; bundle ID, hotkey and URL handlers unchanged.

### Verification

- Authored in a Linux cloud session without a Swift toolchain (its download host is blocked there and running downloaded
  compilers isn't permitted), so nothing was compiled locally; GitHub Actions on macOS compiled and tested it.
- [Run 40981479051](https://github.com/p3terparker/watch-app/actions/runs/40981479051), commit `585e422` (macos-15, Xcode 16.4,
  Swift 6.1.2), all gating steps green on the first attempt:
  - The whole app type-checks; the universal build passed its bundle verification.
  - 18 tooling tests and **636** Swift checks pass (562 in build 51). New: the one-row layout (order, one line, no overlaps,
    drop-out order at 376/276/220/200/100 pt, no length, unscriptable app, denied volume, long clock), `MusicZone` strips,
    shuffle/repeat/reveal scripts, repeat cycling and reading the apps' answers.
  - 12 real-helper checks pass, the Now Playing adapter under system perl included. The installer verification passed for
    3.20 (52): 230,529,288 bytes, SHA-256 `834a841223908e1d1f1ca9610e01332b344994b383fecfca214355c7d7e76abd`.
  - The isolated AppKit harness passes **170 checks with 0 failures** (153 in build 51), on the fixture video and the
    music window: controls revealed on hovering anywhere, the one-row geometry, 🔀/🔁 setting the fixture app's shuffle and
    repeat (off → all → one → off) lit accordingly, the 1 s exit grace (and re-entry keeping them), a single click
    waiting out the double-click interval before reaching Music (also from a corner and the bottom edge), a double-click
    opening the source without playing/pausing, edge-strip double-clicks stacking ∓10 s, a double-click a quarter in
    opening instead of skipping, no shuffle/repeat for Podcasts, and every earlier player/panel/music-window check.
  - The informational live YouTube step hit YouTube's bot check for 2 of 3 public videos from GitHub's address (the third
    resolved natively in 3.6 s); it doesn't gate the preview and is unrelated to this change.
  - That commit's message happened to quote the `[no preview]` marker, so the preview was published by the following
    documentation commit's run, [40983135021](https://github.com/p3terparker/watch-app/actions/runs/40983135021) (same checks,
    all green): [v3.20-preview](https://github.com/p3terparker/watch-app/releases/tag/v3.20-preview), "Watch 3.20 preview
    (52)", DMG 230,329,383 bytes, SHA-256 `44bf86551812bdf1d3ea6c6f21ab17a5fb02eea152112d1d265305132ecf7693`.
- Manual (pending, needs a real Mac): reveal and click timing feel; shuffle/repeat changing real Music and Spotify settings
  (and the one-time Automation prompt on the first click); double-click opening/revealing in Music, Spotify and Podcasts.

## 3.19 (49–51) — Now Playing artwork, 2026-10-28/29 (preview; hands-on acceptance pending)

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

### Build 50: playback controls and player volume (GitHub Actions, macos-15)

[Run 40665693935](https://github.com/p3terparker/watch-app/actions/runs/40665693935), commit `17b4862`, all steps green on the first attempt:

- The whole app type-checks. The universal build passed its bundle verification. 18 tooling tests and 523 Swift checks pass; the 27 new ones cover timing from the stream, clock text, command/seek arguments (never `test`), app-volume scripts, value coalescing and the command timeout. The Foundation-only parts also passed on Linux first (Swift 6.1, warnings as errors, 107 checks).
- 12 real-helper checks pass, the Now Playing adapter under system perl included. The installer verification passed for 3.19 (50): 230,277,089 bytes, SHA-256 `3e13a5df8d2e436d550b4d5a887af203e617ac996640028a37eb28369fa30d33`.
- The isolated AppKit harness passes 101 checks with 0 failures. The 18 new ones cover:
  - Artwork controls: the controls stay hidden over the artwork and appear over the caption. Play/pause sends pause and shows paused at once. Next, previous, and a seek at half all send correctly.
  - App volume shows Music's level and sets it, and is absent for Chrome. There's no timeline without a length, nothing is sent without a click, and the controls tuck away on leaving.
  - Player bar: the volume is tucked away at rest, slides out on hover and sets the volume, shows 0 when muted, tucks away afterwards, and never slides out in a narrow bar.
- The workflow replaced the [v3.19-preview pre-release](https://github.com/p3terparker/watch-app/releases/tag/v3.19-preview) with "Watch 3.19 preview (50)". "Latest" still resolves to v3.18.

### Build 51: native YouTube, quality follows the window, music-only music window (GitHub Actions, macos-15)

What changed:
- **YouTube:** no automatic embed or watch-page fallback. Instead there's a failure card, a playback log, and one signed-in retry for bot or age checks.
- **Quality:** an H.264 rendition ladder in DashHLSBridge, with `preferredMaximumResolution` set from the video area.
- **Music window:** takes music sources only, follows Music/Spotify broadcasts and addresses commands to them, and uses the player's click zones.
- **Placement:** players and the music window are placed beside each other.

Results:
- **Linux first** (Swift 6.1, warnings as errors): 146 Foundation-only checks pass. They cover the rendition ladder, the resolution cap, failure reasons, the playback log, the music-source rule, broadcast parsing and the command scripts.
- **[Run 40956720504](https://github.com/p3terparker/watch-app/actions/runs/40956720504), commit `a12ab87`:** everything passed except 4 of 153 GUI checks, so nothing was published.
  - Three placement checks failed because the harness centred the music window on CI's 1024×768 screen, leaving no room beside it. The code then cascades, as designed.
  - The quality switch-up failed because the test's AVPlayer had no video layer. AVFoundation weighs the displaying layer's size, so it stayed on the lowest rendition.
- **[Run 40961215467](https://github.com/p3terparker/watch-app/actions/runs/40961215467), commit `b4b479e`:** the music window sits at its real top-right spot, and the bridge plays in a real `PlayerVideoView`. 562 Swift checks, 18 tooling tests, 12 real-helper checks and the installer verification pass. The GUI step passes **153 checks with 0 failures**:
  - **Player:** the fixture video plays natively, with no web view.
    - A centre click pauses and plays. Double-clicking the sides gives ∓10 s, and a quick run stacks.
    - Space, ←/→ and ↑/↓ work, and so does the bar's volume slider.
    - Resizing resizes the video and doubles the cap. The menu shows "Playing at 360p", and double-clicking the top restores the size.
  - **Bridge:** the two-rendition playlist plays 180p in a 240×135 pt window and switches up to 360p at 880×495 pt.
  - **Music window:**
    - Videos from Chrome, WebKit (with a Safari parent or none) and Watch never replace the song.
    - A centre click reaches Music itself (AppleScript fixture), not the app holding the slot.
    - The click zones send play/pause and stacked ∓10 s seeks; Space and ←/→ work.
    - Podcasts takes over, with no volume or timeline. Its controls dim once a video takes the slot.
    - Music's broadcast changes the song and fetches its artwork; stopping clears it.
  - **Placement:** a new player's spot avoids the music window, and so does the new player. The reopened music window avoids the player.
- **Live YouTube** (informational; bundled yt-dlp 2026.10.26 from GitHub's data centre): 1 of 3 public videos resolved natively (1080p, about 4 s). The other two got "Sign in to confirm you're not a bot", the case build 51 handles with the signed-in retry and the failure card.
- **[Run 40965040032](https://github.com/p3terparker/watch-app/actions/runs/40965040032), commit `beeca02`** (release notes only, same executable hash `30e1d88f…5e45`): all green again (GUI 153/0). It published "Watch 3.19 preview (51)": 230,315,957 bytes, SHA-256 `15dcd2183a5687fe5807021318b396299b3ead8a2c9105dd7488414a70e445fc`. "Latest" still resolves to v3.18.

### Pending (hands-on acceptance)

- Build 51, by hand:
  - Pasted YouTube links play in Watch's player, signed in and signed out.
  - The failure card and its Sign In… on a bot-checked video.
  - Quality switches up and down with real YouTube renditions as the window is resized.
  - With Music playing, opening a video leaves the music window alone and opens beside it.
  - The music window's clicks and keys on real Music/Spotify; the Automation prompt appears once, on the first click.
  - The full-screen double-click, which isn't automated.
- Build 50, by hand:
  - The controls act on the real Music/Spotify.
  - The one-time Automation prompt appears on the first volume release, then Music's own volume moves while the Mac's stays put.
  - The player's volume slide-out feels right with a real pointer and trackpad.
  - The controls in full screen.
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
