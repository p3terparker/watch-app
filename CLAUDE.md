# Watch App

A "plays almost any video" menu-bar player. **Current: v3.19.**
Binary `Watch` · bundle `com.jacob.watch` · hotkey **⌥⌘Y** ·
frameworks: Cocoa, WebKit, Carbon, ServiceManagement, **AVKit, AVFoundation**.

**What it is now:** the dropdown is a **control panel**: one field (search YouTube or paste a link; ⬇ Download beside it), download
progress, videos open in browser tabs (Safari + Chromium via AppleScript + in-page JS), and recently-copied
link history. **Playback pipeline:** a player window opens instantly, `resolveStream` runs one `yt-dlp -j`
and builds ordered plans, and everything plays in **AVPlayer** — YouTube HD (≤1080p60) through
`DashHLSBridge` (split fMP4 → in-memory HLS with byte ranges), live streams via their HLS manifest, other
sites via best HLS/MP4. Fallbacks: next plan → YouTube IFrame embed → the page. **Downloads** run yt-dlp
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
±0.5 s; the YouTube embed fallback now saves its position and marks watched (`time:<id>:<t>:<d>` / `ended:<id>`).

**3.16:** all Recent Links and Favourites are listed in the existing 320×250 scrolling panel; no All/Less button or automatic window growth. Typing searches after a 350 ms pause (`LiveSearch`), with immediate cancellation on edits, no auto-play for links/paths, and Return still searching immediately. See `UX_SPEC.md`. `Tests/panel.py` exercises the real UI with isolated preferences and delayed fixture responses.

**3.17:** self-contained universal helpers in `Contents/Helpers`: yt-dlp/Python/EJS, FFmpeg, ffprobe and Deno. `MediaTools.swift` owns paths, environment and readiness checks; `Welcome.swift` provides the no-Terminal guide. Helpers update only with app replacement. `scripts/watch_helpers.py` verifies pinned inputs and builds FFmpeg/LAME without Homebrew dynamic dependencies. `Tests/bundled.py` exercises real helpers in a clean temporary home.

**3.19 — Now Playing artwork:** while another app plays something (Music, Spotify, Podcasts, a browser video…) the panel's
list starts with a **Now Playing** row (24×24 artwork · title · "Artist · App · Paused"; hidden while filtering, when
nothing plays, or with Preferences ▸ "Show what's playing in other apps" off). Click (or ⤢) opens the artwork in a
floating `ArtworkWindowController` window that takes the panel's spot and **follows the music** (cross-fade, never takes
focus); right-click / "…": Copy · Save… (original bytes, "Artist – Album.jpg") · Open in Preview · Search YouTube · Show
‹App›. Source: macOS Now Playing via the bundled **mediaremote-adapter** (BSD-3, pinned commit in `Dependencies.json`
"sources") — since macOS 15.4 only Apple-signed processes may read MediaRemote, so `/usr/bin/perl` loads
`Contents/Frameworks/MediaRemoteAdapter.framework`. **Read-only:** Watch only ever runs its `stream` command, only while the
panel or the artwork window is showing (`NowPlayingMonitor` demand set, clean perl environment, 2/10/60 s restart
back-off then give up). Pure logic + monitor in `Sources/NowPlaying.swift` (tested by `test.sh`); window and actions in
`Sources/ArtworkWindow.swift`.

**Gotchas (see GOTCHAS.md):** never AppleScript an app by name unless it's running (uninstalled names pop a
"Where is …?" chooser) and never send Apple Events without checking `AEDeterminePermissionToAutomateTarget`
with ask=false first — no unrequested popups. Remote fMP4 in AVFoundation is unusably slow → the HLS bridge.
A stale yt-dlp can cause YouTube failures — replace Watch with a newer build. Media tools are included. Browser-tab detection needs "Allow JavaScript from Apple Events" in the browser. App Nap is disabled while playing.
Now Playing: never run the adapter's `test` (it registers a fake player) or any playback command (`send`/`seek`/…); no
AppleScript to Music/Spotify (3.3 removed it for its Automation prompts).

**Build:** `./build.sh` (build only → `build/native/Watch.app`; add `--install` for an explicit install after quitting the app).

**Records:** feature truth = `docs/FEATURES.md`; per-function code map = `MAP.md`
(3.19; native AVKit pipeline, DashHLSBridge, downloads, permission-safe browser detection and Now Playing).
