# Watch App

A standalone, native macOS menu-bar video player. Search YouTube as you type, play videos in small floating windows, browse your recent links and favourites, download video or audio, and open the artwork of whatever is playing in another app.

Watch is an independent project. Its source, tests, dependency pins and packaging tools live entirely in this repository. No checkout or installation of another project is required.

## Install

[Download Watch.dmg](https://github.com/p3terparker/watch-app/releases/latest/download/Watch.dmg) from the [latest release](https://github.com/p3terparker/watch-app/releases/latest). Open the disk image, drag Watch to Applications, eject the image, and open Watch. The first-run guide explains watching, included tools and optional YouTube connection. Click the play icon in the menu bar or press **Option–Command–Y**.

The fully bundled app includes yt-dlp (with Python and EJS), FFmpeg, ffprobe and Deno. Recipients do not need Homebrew, Python or Terminal. Existing system installations are left alone. Media tools update with the app.

The downloadable preview and local builds are ad-hoc signed and **not notarized**. macOS may require Privacy & Security → Open Anyway. Making the source public does not change Gatekeeper requirements. See [first-run instructions](FIRST_RUN.txt).

Requires macOS 13+. Universal builds contain Apple Silicon and Intel slices; actual Intel/macOS 13 acceptance remains pending.

## Build

Build prerequisites: macOS, Xcode Command Line Tools, Python 3.9+ and an internet connection for pinned helper downloads. No third-party Swift packages or Xcode project are required. Python is needed by contributors, not app recipients.

```sh
./check.sh                    # metadata and deterministic regression tests
./build.sh                    # current architecture, fully bundled
./build.sh --universal        # Apple Silicon + Intel
./package.sh                  # tests, universal build, dist/Watch.dmg
python3 scripts/verify_watch_package.py --canonical
```

Builds never install or launch Watch. An explicit `./build.sh --install` replaces `~/Applications/Watch.app` after you quit it. Otherwise, use the DMG.

The first build compiles FFmpeg and LAME for both architectures and may take several minutes. Download hashes and prepared helper files are checked before reuse. Generated artifacts and caches stay in ignored `build/` and `dist/` directories. Versions and frameworks are configured once in `Info.plist` and `scripts/app.json`.

## Test

```sh
./check.sh
python3 Tests/panel.py        # isolated AppKit UI; requires a macOS GUI session
python3 Tests/bundled.py build/universal/Watch.app/Contents/Helpers
# Optional public metadata tests, without cookies or account access:
python3 Tests/bundled.py build/universal/Watch.app/Contents/Helpers --live
```

Tests use temporary fixtures and preferences. Do not run another production Watch instance or test with personal browser cookies. See [verification](docs/AUDIT.md) for results and remaining manual checks.

## Project layout

- `Sources/` — native app and media-tool boundary
- `Tests/` — logic, AppKit and real-helper integration fixtures
- `scripts/` — standalone build, dependency preparation and DMG verification
- `Dependencies.json`, `SupplementalSources.json` — pinned upstream inputs
- [MAP.md](MAP.md) — implementation map
- [Features and changelog](docs/FEATURES.md), [UX spec](UX_SPEC.md), [gotchas](GOTCHAS.md)
- [Contributing](CONTRIBUTING.md), [third-party components](THIRD_PARTY.md)

## Compatibility and license

The app retains `com.jacob.watch`, its preference keys and the existing `glasskit-watch://play` URL handler so existing users keep their data and links. Those compatibility identifiers do not depend on any other app or repository.

Watch's own source is licensed under [MIT](LICENSE). Bundled third-party tools retain their respective licenses and notices; they are not relicensed under MIT. The built app includes notices, pinned source archives and build instructions in `Contents/Resources/ThirdParty`.
