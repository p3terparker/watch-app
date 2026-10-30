# Watch

A video player that lives in the macOS menu bar. Search YouTube or paste a link and it plays in a small floating window. It also does music and podcasts, keeps a queue, and downloads video or audio when you want a copy.

## Install

Download `Watch-<version>.dmg` from the [latest release](https://github.com/p3terparker/watch-app/releases/latest), open it, drag Watch to Applications and launch it. Click the play icon in the menu bar or press **⌥⌘Y**.

Needs macOS 13 or later. The app is universal (Apple Silicon and Intel).

Watch is signed ad hoc and isn't notarized by Apple, so macOS will block the first launch. Open **System Settings → Privacy & Security**, scroll to Security and click **Open Anyway** next to Watch. You'll have to do this again after each update.

Everything it needs is inside the app: yt-dlp, FFmpeg, ffprobe and Deno. There's nothing else to install, and updating Watch updates those too.

When there's a newer build that passed the tests but isn't released yet, it's posted on the Releases page as the **Current build**.

## What it does

- Search YouTube as you type, or paste a link. YouTube plays up to 1080p60, and other sites work wherever yt-dlp can get a stream.
- Small floating windows that you can tile. Videos resume where you left off.
- An Up Next queue for videos, audio files, podcasts and Spotify songs, with autoplay, repeat and shuffle.
- Shows what Music, Spotify or Podcasts is playing, with the artwork in a floating window.
- Recent links, favourites, watched marks, and YouTube history and playlists if you sign in (optional).
- Downloads: video as MP4 or the original file, audio as MP3 or the original, whole playlists, live recordings.
- Media keys, Control Center and AirPods controls work with whatever Watch is playing.

[docs/FEATURES.md](docs/FEATURES.md) has the full list. Other apps and scripts can play a link with `glasskit-watch://play?url=<encoded link>` or add it to the queue with `glasskit-watch://queue?url=<encoded link>`.

## Known issues

- YouTube sometimes asks to confirm you're not a bot. Signing in under Preferences → YouTube Account usually fixes it.
- Sites change often. If a video stops playing, check for a newer release first.
- The Now Playing row relies on a workaround for the limit macOS 15.4 put on reading what other apps are playing. If a later macOS closes it, the row goes away.
- Automated tests run on macOS 15 on Apple Silicon. Real Intel Macs and macOS 13–14 haven't been tried.

## Building

You need a Mac with the Xcode Command Line Tools and Python 3.9 or later. There are no Swift packages and no Xcode project.

```sh
./build.sh              # build for this Mac into build/native/Watch.app
./build.sh --universal  # Apple Silicon and Intel
./package.sh            # tests, universal build, dist/Watch-<version>.dmg
```

The first build compiles FFmpeg and LAME, which takes a few minutes. Builds never install or launch the app. `./build.sh --install` copies it to `~/Applications` if you want that.

## Tests

```sh
./check.sh                                                       # unit and tooling tests
python3 Tests/panel.py                                           # real UI, needs a macOS GUI session
python3 Tests/bundled.py build/universal/Watch.app/Contents/Helpers
python3 scripts/verify_watch_package.py --canonical              # check the finished DMG
```

The tests use temporary preferences and fixture files, so they never touch your own data. [docs/AUDIT.md](docs/AUDIT.md) lists what's covered and what hasn't been tried.

## More

[CONTRIBUTING.md](CONTRIBUTING.md) · [docs/RELEASE.md](docs/RELEASE.md) · [THIRD_PARTY.md](THIRD_PARTY.md) · [MAP.md](MAP.md) (where things live in the code)

## License

Watch's code is [MIT](LICENSE). The bundled tools keep their own licenses, listed in [THIRD_PARTY.md](THIRD_PARTY.md) and shipped inside the app.
