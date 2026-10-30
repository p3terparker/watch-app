# Testing

What's checked automatically, and what hasn't been tried. Update this when either changes.

## On every build

GitHub Actions builds Watch on a macOS 15 (Apple Silicon) runner for each push to `main` or a `claude/*` branch. A build has to get through all of these before it's published as the current build:

1. The whole app type-checks.
2. `./check.sh`: the Swift regression checks (links, search, queue, downloads, Now Playing parsing, podcasts, tiling and click zones, stream selection) and the Python tooling tests.
3. `./package.sh`: a universal (Apple Silicon and Intel) build and DMG.
4. `Tests/bundled.py`: the real bundled tools, run from a copy of the app in a path with spaces and a clean `HOME` and `PATH`. It covers yt-dlp with Python and EJS, Deno offline, a download from a local HTTP server, MP3 conversion, HEVC conversion through VideoToolbox, merging audio and video tracks, the Now Playing adapter, and all four Intel tools under Rosetta.
5. `scripts/verify_watch_package.py --canonical`: mounts the DMG read-only and checks the app's metadata, both architectures, the tool hashes, the code signatures, and that the Read Me matches `FIRST_RUN.txt`. Gatekeeper rejects the build, which is expected while it isn't notarized.
6. `Tests/panel.py`: the real panel, player windows and music window on the runner's screen, with fixture videos made by the bundled FFmpeg and stand-ins for Music and the podcast directory. It covers click zones, keys, volume, resizing and the quality switch, the music-only rule, window placement, search, Up Next, podcasts and the Music tab.

Separately, an informational step asks the bundled yt-dlp to resolve three public YouTube videos. From GitHub's data centre some of them get bot-checked (1 of 3 resolved on the last run), so that step can't fail the build.

None of the tests use real accounts, cookies or your library. Close your own copy of Watch before running the panel tests.

**Last full run (3.25):** [every step passed](https://github.com/p3terparker/watch-app/actions/runs/40995671082), including 261 panel checks with no failures. The installer is `Watch-3.25.dmg`, 230,863,811 bytes, SHA-256 `ff4fca6173d786bedb2d611f663ff24538bfa1050d5d9e959acf6906711d1d73`.

## Not tried yet

These need a person on a real Mac:

- **The music window by hand.** How the hover controls and the click timing feel with a mouse and a trackpad. Real Music, Spotify and Podcasts: the controls, shuffle, repeat and volume, the one-time permission prompt, and handing the queue back to the app at the end of a song.
- **Media keys, Control Center, AirPods and Finder's Open With.**
- **Native full screen** for the artwork window (CI only exercises the menu and the background choice), including on more than one display. Also that no Now Playing adapter process is left running once the panel and artwork window are closed.
- **YouTube with real traffic:** pasted links signed in and signed out, the error card on a bot-checked video, and the quality switching up and down with real renditions as you resize.
- **Signing in to YouTube**, and the Chrome Keychain and Safari Full Disk Access prompts. Tests never use personal cookies.
- **Real Intel hardware, and macOS 13 to 15.3.** The Intel tools have only run under Rosetta. The Now Playing workaround depends on Apple continuing to entitle `/usr/bin/perl`; if that stops, the row stops appearing.
- **A clean Mac** installing from the DMG.
- **Developer ID signing and notarization.** The build is ad hoc signed.

A passing check doesn't mean every video or site plays. YouTube and other sites change, and yt-dlp changes with them.
