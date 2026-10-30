# Third-party components

Watch's MIT license covers its own source code. It does not replace the licenses of bundled tools or their dependencies.

| Component | Source / notices | Distribution |
| --- | --- | --- |
| yt-dlp | https://github.com/yt-dlp/yt-dlp | Official standalone macOS executable, including Python and EJS; upstream describes the bundled executable as GPLv3+. Its own source and bundled dependency notices are included. |
| FFmpeg / ffprobe | https://ffmpeg.org | Built from pinned source with LGPL configuration, without `--enable-gpl` or `--enable-nonfree`; source, license and build configuration included. |
| LAME | https://lame.sourceforge.io | Static library used for MP3 encoding; LGPL source and license included. |
| Deno | https://github.com/denoland/deno | Official architecture binaries combined into one universal executable; source archive and supplied notices included. |
| mediaremote-adapter | https://github.com/ungive/mediaremote-adapter | BSD-3-Clause. Built from a pinned commit (fetched with git, verified by commit hash) into `Contents/Frameworks/MediaRemoteAdapter.framework`; its perl entry script is in `Contents/Resources/NowPlaying`. Source archive and license included. Used for Now Playing: reading what plays, and playback commands only when the user clicks the artwork window's controls. |
| mutagen / certifi | Upstream source URLs in SupplementalSources.json | Corresponding pinned sources for these bundled yt-dlp components are included. |

`Dependencies.json` and `SupplementalSources.json` record exact versions, URLs and SHA-256 checksums. `scripts/watch_helpers.py` verifies inputs, builds FFmpeg/LAME, rejects non-system dynamic libraries and stages notices and sources. Built bundles contain `Contents/Resources/ThirdParty`; the Setup Guide opens this folder.

Executables are separate processes. They are updated by replacing the app, not by self-modifying the signed bundle. Modifying a helper requires recreating the local app signature; Watch does not prohibit modified helpers.

Before wider binary redistribution, review the complete upstream license/notice/source requirements for the exact bundled versions. An MIT license on this repository does not make every bundled component MIT-licensed.
