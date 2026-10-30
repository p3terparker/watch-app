# Watch App

A "plays almost any video" menu-bar player. **Current: v3.24.**
Binary `Watch` · bundle `com.jacob.watch` · hotkey **⌥⌘Y** ·
frameworks: Cocoa, WebKit, Carbon, ServiceManagement, **AVKit, AVFoundation, MediaPlayer**.

**What it is now:** the dropdown is a **control panel**: one field (search YouTube or paste a link; ⬇ Download beside it), download
progress, videos open in browser tabs (Safari + Chromium via AppleScript + in-page JS), and recently-copied
link history. **Playback pipeline:** a player window opens instantly, `resolveStream` runs one `yt-dlp -j`
and builds ordered plans, and everything plays in **AVPlayer** — YouTube HD (≤1080p60) through
`DashHLSBridge` (split fMP4 → in-memory HLS with byte ranges), live streams via their HLS manifest, other
sites via best HLS/MP4. Fallbacks: next plan → (YouTube) a failure card with the reason, never YouTube's web page;
(other sites) the page. **Downloads** run yt-dlp
in-app (`DownloadManager`: Video = Original / MP4 highest quality, Audio = Original / MP3 at source bit rate, plus presets, live recording; optional ask-where-to-save per download). **Player windows** are tiled by
`WindowManager`; drop a link/file on a player to replace it, or on the menu-bar icon to open a new one.
**YouTube browsing (3.6, from the retired Tube app):** search results / History / Playlists are in-panel pages (History +
Playlists via the ••• menu); sign-in (cookie browser, account, profile) is in Preferences ▸ YouTube Account.
**Up Next (3.8):** every player window has a queue — the panel list the video came from, the playlist a
`list=` link carried, what youtube.com would play next for a lone video (`YouTubeUpNext` reads the watch
page's own autoplay pick + sidebar), or a local file's folder. The "…"/right-click menu has Previous · Next ·
Up Next ▸ (⌘←/⌘→) and Autoplay · Repeat All · Repeat One · Shuffle (per window, last choice persists).
**3.10:** the panel is short (320×250, was 320×520: 2 recent links; "All ▾" grows the panel downward
to list the rest); the first video opens on the panel's spot and the panel hides; every video resumes where it was
left off (`PlaybackPositions`, `Sources/PlaybackPositions.swift`).
**3.11:** search + paste merged into one pinned field (`OmniboxInput`; ↑/↓/Return/Esc via the field delegate;
recent searches in the magnifier menu); Recent Links are thumbnail rows (`BrowseRowView` compact, resume bar),
one per video, removable; only video links are captured (`VideoLinks.classify`); search has Show More, a 25 s
timeout, cancellation, a 10-min cache and Try Again / Update yt-dlp. Pure logic: `Sources/Links.swift`,
`Sources/SearchSupport.swift` (both covered by `test.sh`).
**3.12:** Recent Links thumbnails are small (32×18); right-click ▸ Pin/Unpin (`ClipboardLink.pinned` — pinned sort
first, skip the cap, survive Clear; pinning a search result adds it); every row has ↗ Open in YouTube beside ⬇
(`rowButtons`, `VideoLinks.webURL` adds the resume `t=`).
**3.13:** player menu starts Close · Pin; Picture in Picture removed (players already float). **Tile Windows** (player
menu + panel •••, shown with 2+ players) grids every player to fill one screen (`WindowManager.tile`; pure math in
`Sources/Tiling.swift`, covered by `test.sh`).
**3.14:** click zones on the player (`PlayerZone`, `Sources/PlayerZones.swift`, tested): centre click = play/pause,
double-click left/right thirds below the top = ∓10 s (stacking via `skipTarget`), top third + bottom middle = resize.
Playback bar is 20 pt, inset 16 pt/6 pt off the resize corners, with ⟲10/⟳10 buttons. Skips seek within ±0.5 s.
Other apps/scripts hand off playback with `glasskit-watch://play?url=<percent-encoded-video-url>`.
**3.15:** library state in `Sources/Library.swift` (tested): **watched marks** (`WatchedVideos`, key `watchedVideos`; 90% or
the last 15 s, or played to the end — ✓ + dimmed thumbnail on every row, dimmed in Up Next ▸, right-click Mark as
Watched/Unwatched), **Favourites** (`Favourites`, key `watchFavourites`; they replace 3.12's Recent Links pins, imported
once and unpinned — panel tabs Recent Links | ★ Favourites, `Prefs.showFavourites`; Add/Remove in row and player menus;
favourites play with the list as Up Next), and **playlist progress** (`PlaylistProgress`, key `playlistProgress`: a
playlist link reopens at the video it was on, or the next if that was finished). Resume made visible: a
"Resumed at 12:34 · Start Over" / "Playlist: 8 of 20 · Start from the Top" chip (6 s, top-left); resume seeks within
±0.5 s.

**3.16:** all Recent Links and Favourites are listed in the existing 320×250 scrolling panel; no All/Less button or automatic window growth. Typing searches after a 350 ms pause (`LiveSearch`), with immediate cancellation on edits, no auto-play for links/paths, and Return still searching immediately. See `UX_SPEC.md`. `Tests/panel.py` exercises the real UI with isolated preferences and delayed fixture responses.

**3.17:** self-contained universal helpers in `Contents/Helpers`: yt-dlp/Python/EJS, FFmpeg, ffprobe and Deno. `MediaTools.swift` owns paths, environment and readiness checks; `Welcome.swift` provides the no-Terminal guide. Helpers update only with app replacement. `scripts/watch_helpers.py` verifies pinned inputs and builds FFmpeg/LAME without Homebrew dynamic dependencies. `Tests/bundled.py` exercises real helpers in a clean temporary home.

**3.19 — Now Playing artwork:** while a music app plays something (Music, Spotify, Podcasts…) the panel's
list starts with a **Now Playing** row (24×24 artwork · title · "Artist · App · Paused"; hidden while filtering, when
nothing plays, or with Preferences ▸ "Show what's playing in other apps" off). Click (or ⤢) opens the artwork in a
floating `ArtworkWindowController` window that takes the panel's spot and **follows the music** (cross-fade, never takes
focus); right-click / "…": Copy · Save… (original bytes, "Artist – Album.jpg") · Open in Preview · Search YouTube · Show
‹App›. **Full screen** (double-click the top/bottom middle, ⌃⌘F/F, menu, or the row's Open Full Screen; Esc leaves): macOS full screen with the
artwork centred over a gradient of its own two main colours or black (Full-Screen Background ▸,
`Prefs.artworkColourBackground`), caption under it, chrome + pointer hidden when idle; colour picking and layout are pure
in `Sources/ArtworkStyle.swift` (tested). Source: macOS Now Playing via the bundled **mediaremote-adapter** (BSD-3, pinned commit in `Dependencies.json`
"sources") — since macOS 15.4 only Apple-signed processes may read MediaRemote, so `/usr/bin/perl` loads
`Contents/Frameworks/MediaRemoteAdapter.framework`. Watch reads with its `stream --micros` command, only while the
panel or the artwork window is showing (`NowPlayingMonitor` demand set, clean perl environment, 2/10/60 s restart
back-off then give up). **Playback controls** (build 50): resting the pointer on the artwork window's caption slides in a
timeline (elapsed / -remaining), ⏮ ⏯ ⏭ and — for Music/Spotify — the app's own volume (`AppVolume` via AppleScript
`sound volume`, Automation asked once on the first drag's release). Commands go out only on a click (`NowPlayingRemote`:
one short adapter `send`/`seek` run each). Thin white sliders (`ThinSlider`, `Sources/ThinSlider.swift`) are shared with the
video player, whose speaker icon now slides out a volume slider on hover (↑/↓ keys too; `Prefs.playerVolume`). Pure logic +
monitor in `Sources/NowPlaying.swift` (tested by `test.sh`); window, controls and actions in `Sources/ArtworkWindow.swift`.
**Build 51:** YouTube never falls back to its web page (that page caused the ads, the missing click zones and the video
thumbnail in the music window): `PlayerFailureView` with yt-dlp's reason, one signed-in retry for bot/age checks when a
YouTube Account is connected, `PlaybackLog`. **Quality follows the window** (`StreamLadder` H.264 ladder in the bridge's
master + `preferredMaximumResolution` on resize; "Playing at 720p" in the menu). The music window is **music only**
(`NowPlayingInfo.isMusicSource`; Music/Spotify distributed notifications keep it current while a video holds the slot;
Music/Spotify commands by AppleScript to that app, `MusicAppControl`) and uses the player's `PlayerSurfaceView`/`PlayerZone`
(centre = play/pause, sides ∓10 s, top/bottom middle = full screen). `WindowManager.freeFrame`/`keepClear`: players and the
music window open beside each other, never on top (cascade only when the screen is full). Pure parts in `Sources/StreamSupport.swift` (tested). UX_SPEC's **Always works** list
is checked by `Tests/panel.py` with an FFmpeg-made fixture video and fixture renditions.
**3.20 (music window only):** the controls are **one row** under the caption (`ArtworkLayout.controlRow`, pure + tested:
⏮ ⏯ ⏭ · elapsed · timeline · remaining · 🔀 🔁 · volume, dropping parts in a fixed order when narrow), shown on hovering
**anywhere** over the window and fading `exitGrace` (1 s) after it leaves. 🔀/🔁 set **Music's/Spotify's own** shuffle and
repeat (`AppVolume.modesScript`/`shuffleScript`/`repeatScript`, `AppRepeat`, `AppModes`; `MusicAppControl.modes`/`setMode`,
same Automation rules as the volume). Clicks use `MusicZone` (`Sources/PlayerZones.swift`): a click anywhere = play/pause
after `clickDelay` (the double-click interval), double-click = `openSource` (bring the app forward / launch it; Music reveals
the track when already allowed), double-click in far-edge strips (15%, ≥36 pt) = ∓10 s. Full screen only via F/⌃⌘F/menu.
Pushes whose commit message contains `[no preview]` are built and tested but don't replace the preview (`build.yml`).
**Versioning:** one version number per **phase** — the batch of changes asked for together — not per change: every push of
that phase keeps the number (each passing one replaces that version's preview); bump it only when a new phase starts or
the user says it's a new version. (3.20–3.24 were one phase numbered per change; they stay as published.) The installer is
named with the release number: `package.sh` makes `dist/Watch-<version>.dmg` (e.g. `Watch-3.24.dmg`).
**3.21 — Up Next under the music window:** `PlayQueue`/`QueueItem` (+ `MediaSource`, `SpotifyLink`) moved to
`Sources/Queue.swift` with Play Next/Later insertion, edits, sections and `handBack` (tested); `Sources/Handoff.swift` has the
pure song-boundary reducer and `QueueRoute` (tested). `UniversalQueue` (`Sources/UpNext.swift`) plays the current item in
Music/Spotify (`.external`, waiting for the song to end, pausing + rewinding the app, handing back), Watch's own AVPlayer
(`.native`, shown in the music window via `NowPlayingInfo` with `OwnPlaybackControl`) or a queue-driven video window
(`PlayerWindowController.onEnded/onStep/onClosed`). `QueueDrawer` (`Sources/QueueDrawer.swift`) is the drop-down list.
AppDelegate: `enqueue`, `enqueueLink`, `showQueue`, `playSpotify`; `setMusic` feeds `upNext.externalChanged`.
**3.22 — Podcasts:** `Sources/Podcasts.swift` (tested): Apple Podcasts links (`PodcastLinks`), iTunes Search/Lookup JSON
(`ITunesPodcasts`), RSS (`PodcastFeed`), `PodcastEpisode.queueItem()` (source `.podcast`, `page` = its Apple Podcasts link);
`PodcastDirectory` does the network calls (no account). Search results have **YouTube | Podcasts** tabs (`searchService`,
`BrowseEntry.search`); `.shows`/`.episodes` pages; a show link or feed in the field opens its episodes (`OmniboxInput.podcast`),
an episode link plays (`playEpisodeLink`; older episodes via yt-dlp in `resolveEpisode`). Episodes play in the music window
(`UniversalQueue.playPodcast` → `playNative`), resume (`QueueItem.resumeKey`, `podcast:<episode id>` in `PlaybackPositions`)
and get ✓ like videos. The harness overrides `performPodcastSearch`/`fetchEpisodes`/`resolveEpisode`. The Up Next list never
sits on the music window (`DrawerLayout`, `Sources/Tiling.swift`: the window moves up for it when needed).
**3.23 — Up Next in video windows + your Music library:** every `PlayerWindowController` can drop its own list down
(`toggleUpNextList`, ⌥⌘U / "…" menu; `QueueDrawer` with `emptyHint`/`idleHint`; drops via `insertIntoUpNext`, a late
playlist/recommendations list `merged(into:)` around them; queue-driven windows' `onShowList` opens the music window's list
instead; lists hide for Tile Windows and count in `freeFrame`). Search's third tab **Music** (`SearchService.music`):
`Sources/MusicLibrary.swift` (tested) builds the escaped library-search script and parses Music's answer
(`LibrarySong`, `LibraryAnswer`); `MusicAppControl.searchLibrary` runs it only while Music runs and Watch is already allowed
(never asks; the page's Open Music / Allow… / Open System Settings buttons act on a click). Songs are `music:<persistent ID>`
queue items Music plays via `MusicLibrary.playScript` (`MusicAppControl.playScript`, which also plays Spotify URIs). A queue
started with a Music/Spotify song hands back to that app at its end.
**3.24 — system integration:** `Sources/SystemNowPlaying.swift` publishes Watch's own playback to macOS's Now Playing
(`MPNowPlayingInfoCenter`) and takes media keys / Control Center / headphone commands (`MPRemoteCommandCenter`, on only while
it publishes). `AppDelegate.systemTick` (1 s, only while something of Watch's is open) picks the source with the pure
`OwnPlayback.pick` (`Sources/Handoff.swift`, tested): the queue's own item or the latest video window; nothing while only a
music app plays. Preferences ▸ "Pause Music or Spotify while Watch plays" / "…and play it again when Watch's videos are
closed" (`Prefs.pauseMusicWhilePlaying`, `resumeMusicAfter`, both on; `MusicPause`, tested): a click that starts playback may
ask Automation once (`perform`); anything else only acts if already allowed (`MusicAppControl.performIfAllowed`). Up Next is
saved (`PlayQueue.snapshot`/`QueueSnapshot`, key `upNextQueue`) and offered back ("Up Next from before — Resume") after the
music window closes or Watch relaunches; a list played to its end is forgotten. Finder ▸ Open With ▸ Watch
(`CFBundleDocumentTypes`, Alternate rank; `application(_:open:)` → `openFiles`): one video plays in a window, audio, folders and
several files go to Up Next.

**Gotchas (see GOTCHAS.md):** never AppleScript an app by name unless it's running (uninstalled names pop a
"Where is …?" chooser) and never send Apple Events without checking `AEDeterminePermissionToAutomateTarget`
with ask=false first — no unrequested popups. Remote fMP4 in AVFoundation is unusably slow → the HLS bridge.
A stale yt-dlp can cause YouTube failures — replace Watch with a newer build. Media tools are included. Browser-tab detection needs "Allow JavaScript from Apple Events" in the browser. App Nap is disabled while playing.
Now Playing: never run the adapter's `test` (it registers a fake player); `send`/`seek` only from a click on the artwork
window (controls, click zones, keys), never automatically. Never auto-load YouTube's embed or watch page; never send cookies
except the one retry after YouTube asked for a signed-in viewer with an account connected. AppleScript to Music/Spotify only for their volume, playback commands,
artwork, shuffle/repeat, playing a queued song (Spotify URI / Music persistent ID, validated) and the Music library search
(3.23: only while Music runs and Watch is already allowed), addressed by bundle id, asking Automation only on the user's own
drag or click (artwork and search only when already allowed; 3.3 removed the automatic probes for their prompts).

**Build:** `./build.sh` (build only → `build/native/Watch.app`; add `--install` for an explicit install after quitting the app).

**Records:** feature truth = `docs/FEATURES.md`; per-function code map = `MAP.md`
(3.19; native AVKit pipeline, DashHLSBridge, downloads, permission-safe browser detection and Now Playing).
