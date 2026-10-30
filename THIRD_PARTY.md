# Third-party components

Watch's MIT license covers Watch's own code. The tools bundled in the app keep their own licenses.

| Component | Where it comes from | What's in the app |
| --- | --- | --- |
| yt-dlp | https://github.com/yt-dlp/yt-dlp | The official standalone macOS build, which includes Python and EJS. Upstream licenses that build as GPLv3+. Its source and the notices for what it bundles are included. |
| FFmpeg / ffprobe | https://ffmpeg.org | Built here from pinned source with an LGPL configuration (no `--enable-gpl`, no `--enable-nonfree`). Source, license and build configuration are included. |
| LAME | https://lame.sourceforge.io | Static library for MP3 encoding. LGPL; source and license included. |
| Deno | https://github.com/denoland/deno | The official Apple Silicon and Intel binaries joined into one universal executable. Source archive and notices included. |
| mediaremote-adapter | https://github.com/ungive/mediaremote-adapter | BSD-3-Clause. Built from a pinned commit into `Contents/Frameworks/MediaRemoteAdapter.framework`, with its perl script in `Contents/Resources/NowPlaying`. Watch uses it to read what other apps are playing, and sends it commands only when you click the artwork window's controls. Source and license included. |
| mutagen, certifi | URLs in `SupplementalSources.json` | Pinned sources for these two components bundled inside yt-dlp. |

`Dependencies.json` and `SupplementalSources.json` pin exact versions, URLs and SHA-256 hashes. `scripts/watch_helpers.py` checks them, builds FFmpeg and LAME, rejects any dynamic library that isn't a system one, and copies the notices and sources into the app. In a built app they're in `Contents/Resources/ThirdParty`, which Preferences → Setup Guide → Open Third-Party Notices opens.

The tools run as separate processes. Watch never modifies them inside the signed app; they change when the app is replaced with a newer one. If you swap one for your own build you'll need to re-sign the app.

If you plan to redistribute the binaries, read the upstream licenses for the exact versions pinned here. Putting an MIT license on this repo doesn't make the bundled tools MIT.
