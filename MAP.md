# Watch — where everything lives

A menu-bar **"plays almost any video" player** for macOS. Swift (`Sources/main.swift` plus `Downloads.swift`, `PlaybackPositions.swift`, `Library.swift`, `Links.swift`, `SearchSupport.swift`, `Tiling.swift`, `PlayerZones.swift`, `MediaTools.swift`, `Welcome.swift`, `NowPlaying.swift`, `ArtworkWindow.swift`, `ArtworkStyle.swift`, `StreamSupport.swift`, `Queue.swift`, `Handoff.swift`, `UpNext.swift`, `QueueDrawer.swift`, `Podcasts.swift`, `MusicLibrary.swift`, `SystemNowPlaying.swift`, `Marquee.swift` and `MenuBarTicker.swift`), compiled with `swiftc`, locally signed (ad-hoc by default). Current version **3.26** — native AVKit playback for YouTube (HD + live), in-app
downloads, YouTube search / History / Playlists in the panel (absorbed from the retired Tube app), an
**Up Next** list per player window (Next/Previous · Autoplay · Repeat All/One · Shuffle), and a small library:
watched marks, Favourites and playlist progress — plus a **Now Playing** row showing what other apps play, whose artwork
opens in a window that follows the music. See `docs/FEATURES.md` for the feature changelog and
`./CLAUDE.md` for gotchas/build notes; this file is the function-level code map.

## Files
- `Sources/main.swift` — AppKit UI, playback, browser integration, and yt-dlp boundary.
- `Sources/Downloads.swift` — download queue and format/probe decisions; `test.sh` tests it against a fake process boundary.
- `Sources/PlaybackPositions.swift` — resume positions (see below); `test.sh` tests it against a throwaway defaults suite.
- `Sources/Library.swift` — watched marks (`WatchedVideos`), Favourites (`FavouriteVideo` / `Favourites`) and playlist
  progress (`PlaylistProgress`), plus the `.watchLibraryChanged` notification name (see "Library" below). Foundation
  only; `test.sh` covers it against a throwaway defaults suite.
- `Sources/Links.swift` — URL helpers, which copied links count as videos (`VideoLinks`), `LinkInfo`, and the Recent Links
  store (`ClipboardLink` / `ClipboardLinkStore`). Foundation only; `test.sh` covers it.
- `Sources/SearchSupport.swift` — the field's input rules (`OmniboxInput`), main-thread `LiveSearch` debounce (350 ms; cancellation revision; no automatic links/paths/composition), `RecentSearches`, `SearchFailure`, `SearchCache`.
  Foundation only; `test.sh` covers it.
- `Sources/Tiling.swift` — Tile Windows geometry: `Tiling.grid(count:in:)` (the column count giving the largest 16:9
  windows, centred, short last row centred) and `readingOrder(_:columns:)` (which window takes which slot).
  Foundation + CoreGraphics only; `test.sh` covers it.
- `Sources/PlayerZones.swift` — `PlayerZone.at(_:in:)`: which third of the player a click hit (top row + bottom middle
  = resize, centre = play/pause, left/right below the top = skip back/forward), and the music window's `MusicZone.at(_:in:)`
  (3.20: far-edge strips, 15% of the width ≥ 36 pt, skip; the rest is `.main`). 3.25: `MusicZone.doubleClickWindow` (0.3 s) /
  `clickMargin` (0.02 s) / `window(system:)` and `MusicClicks` (`press(at:first:)` → the click run's length: a click joins the run
  only within the window of the one before). Foundation + CoreGraphics; `test.sh` covers it.
- `Sources/NowPlaying.swift` — what another app is playing (see "Now Playing" below): `NowPlayingInfo` (+ `parse(line:ignoring:)`,
  file naming), `LineBuffer`, `NowPlayingAdapter` (bundled paths, arguments, clean environment) and `NowPlayingMonitor` (the
  demand-driven adapter process). Foundation only; `test.sh` covers it with fixture lines and a `/bin/sh` stand-in.
- `Sources/ArtworkWindow.swift` — `ArtworkActions` (Copy / Save / Open in Preview / Show ‹App› / the shared menu items) and
  `ArtworkWindowController` (the floating artwork window, incl. full screen) with its views.
- `Sources/ArtworkStyle.swift` — full-screen look: `ArtworkPalette.gradient` (the artwork's two main colours from a small RGBA
  sample, toned for white text), `ArtworkLayout.fullScreen` (artwork + caption rects) and `ArtworkLayout.controlRow` (the music
  window's one row of controls, 3.20) and `ArtworkLayout.revealZone` (3.25: where the pointer reveals/keeps the controls).
  Foundation (+ CoreGraphics);
  `test.sh` covers it.
- `Sources/Queue.swift` (3.21) — `MediaSource` (`web`/`file`/`audio`/`spotify`/`music`/`podcast`, `of(_:)`), `SpotifyLink` (song/episode URIs,
  `webURL`), `QueueItem` (id, url, title, subtitle, artwork, duration, source, `added`, `page`, `resumeKey`; Codable), `RepeatMode`, `QueueSections`
  and `PlayQueue` (see "Up Next"). Foundation only; `test.sh` covers it (`Tests/QueueChecks.swift`).
- `Sources/Handoff.swift` (3.21) — `Handoff.judge` (what a music app's next report means while one of its songs is the
  queue's current item), `Handoff.spotifyPlayScript`, `QueueRoute.pick`; 3.24 `OwnPlayback.pick` (which of Watch's players
  owns macOS's Now Playing) and `MusicPause` (pause a music app while Watch plays / resume it). Foundation only; `test.sh`
  covers it.
- `Sources/UpNext.swift` (3.21) — `UniversalQueue` (the app-wide queue under the music window and where its item plays),
  `OwnPlaybackControl` (the music window's volume/commands for Watch's own item), `SpotifyOEmbed`.
- `Sources/QueueDrawer.swift` (3.21) — `QueueDrawer` (the drop-down list: child window, `NSTableView`, drag/drop),
  `QueueTableView`, `QueueRowView`. Its placement is `DrawerLayout` in `Sources/Tiling.swift` (3.22, tested).
- `Sources/Podcasts.swift` (3.22) — `PodcastEpisode` (+ `page`, `queueItem()`), `PodcastShow`, `PodcastLinks` (Apple Podcasts
  show/episode ids, feed-looking links, the Search/Lookup URLs), `ITunesPodcasts` (Search/Lookup JSON), `PodcastFeed` (RSS via
  `XMLParser`, durations, RFC 822 dates) — Foundation only, `test.sh` covers it (`Tests/PodcastChecks.swift`) — and
  `PodcastDirectory` (the network calls: search, a show's episodes via its lookup or feed, one episode by its link).
- `Sources/SystemNowPlaying.swift` (3.24) — `SystemNowPlaying`: `publish(_:)` (MPNowPlayingInfoCenter: title, artist, album,
  length, position, rate, artwork, playback state; nil clears it and turns the commands off), `handle(_:)`, the
  MPRemoteCommandCenter targets (play, pause, toggle, next, previous, change position) → `onCommand`.
- `Sources/MusicLibrary.swift` (3.23) — `LibrarySong` (+ `queueItem`: `music:<persistent ID>`), `LibraryAnswer`,
  `MusicLibrary` (`escaped` AppleScript string text, `searchScript`, `parse`, `isPersistentID`, `persistentID(_:)`,
  `playScript`). Foundation only; `test.sh` covers it (`Tests/MusicLibraryChecks.swift`).
- `Sources/StreamSupport.swift` — `StreamLadder` (the lower H.264 renditions to offer beside yt-dlp's pick; the resolution cap
  for a video area; the "720p" label), `PlaybackFailure` (does yt-dlp's error want a signed-in viewer; the reason worth
  showing) and `PlaybackLog` (`~/Library/Logs/Watch/playback.log`, 256 KB, whole lines). Foundation (+ CoreGraphics); `test.sh` covers it.
- `UX_SPEC.md` — 3.16 interaction contract, 3.17 self-contained distribution acceptance, 3.19 Now Playing, and the
  **always works** checklist every change is checked against.
- `Tests/panel.py` / `Tests/PanelMain.swift` — isolated real-AppKit harness; scratch source copies redirect all app defaults to a throwaway suite, replace the entry point, and override search/playback. Run separately in a macOS GUI session; snapshots in `build/watch-panel-checks/`.
- `Info.plist` — bundle metadata. `LSUIElement` = menu-bar-only. Bundle id `com.jacob.watch`.
- `build.sh` — delegates to the shared build-only tool; output `build/native/Watch.app`. Add `--install` only for an explicit install.

## What it does
Click the menu-bar icon (▶, or **⌥⌘Y**) for a control-panel dropdown with one field: type to automatically
search YouTube after a 350 ms pause (Return searches immediately) (results open as a page under the field), or paste any video link and press Return to play it (⬇
beside the field downloads it). Below: Recent Links (copied/played videos with thumbnails and resume bars; typing
filters them), download progress, and videos open in your browser tabs (section only appears when one exists)
(Safari/Chrome/Brave/Edge/Arc, via AppleScript+JS). A player window opens
immediately with a spinner while yt-dlp resolves the stream, then plays natively in AVKit (YouTube up to
1080p60, live streams via HLS). Drop a link/file onto the menu-bar icon to open it, or onto a player window to
replace what's playing. The hotkey plays a copied link directly (configurable). Other apps/scripts can launch playback
through `glasskit-watch://play?url=...`. Frameworks: Cocoa, WebKit, Carbon, ServiceManagement, AVKit,
AVFoundation.

## Guided tour of `main.swift`

### Settings — `Prefs` (enum)
UserDefaults-backed: `hotkeyKeyCode`/`hotkeyCarbon`/`hotkeyDisplay` (default **⌥⌘Y**), `detached`,
`pinned`, `downloadDir` (default `~/Downloads`), `autoUpdate` (legacy stored key, retained but no longer acted upon),
`hotkeyPlaysClipboard` (default on), `launchAtLogin` (persistent user intent, default on), and
`showBrowserTabs` (browser-tab detection, default on), `showNowPlaying` (the panel's Now Playing row, default on), `playerVolume` (what a new player window starts at, default 1),
`artworkColourBackground` (full-screen artwork backdrop: artwork
colours, default, or black), `showFavourites` (the panel's list tab, default Recent Links), `hasSeenWelcome`, `youtubeConnected` (default off), and the YouTube sign-in trio `cookieSource`
(`auto`|`safari`|`chrome`), `youtubeAccount` (`authuser`), `browserProfile`. (3.7.1 dropped the old `com.jacob.tube`
fallback; Tube's values were migrated into `com.jacob.watch`.) Playback modes — `autoplay` (default **on**),
`repeatMode` (`off`|`all`|`one`) and `shuffle` — are per player window; these keys hold the last choice made
anywhere, which is what a **new** window starts with.

### Small helpers
`carbonModifiers` / `keyName` / `shortcutDisplay` — hotkey capture/display formatting.
`sym(_:)` — SF Symbol lookup. `makeGlassContentView()` — the panel's vibrant-dark glass background.
`parseYouTube` / `parseSeconds` / `looksLikeURL` / `isLocalMedia` live in `Links.swift` (see "Recent Links").

### yt-dlp — `YtDlp` (enum)
- `path` / `process(_:)` delegate to `MediaTools.bundled` (`Sources/MediaTools.swift`). Only `Contents/Helpers` is used; all four helpers must be present.
- Arguments explicitly select bundled Deno and FFmpeg, ignore host configuration/plugins and disable remote component downloads. PATH excludes Homebrew; Deno caches outside the app. Argument arrays preserve paths with spaces.
- `capture(_:completion:)` — run to completion off-main, stdout on main (nil on failure).
- Self-update is removed. `showMediaToolUpdateHelp` explains whole-app replacement so signatures remain valid.
- `resolveTitle(_:completion:)` — `--get-title`, used by the download queue for untitled jobs.
- `probeLink(_:completion:)` — `-J --flat-playlist --no-playlist -I 1` → `LinkInfo` (title, thumbnail, duration,
  live, `isList`) for a Recent Links row; nil when yt-dlp finds nothing. `-I 1` keeps a channel page from making
  yt-dlp walk every video on it. 40 s timeout.

### Stream resolution — `StreamRef` / `StreamPlan` / `ResolvedStream` / `resolveStream(_:cookies:completion:)`
One `yt-dlp -j` call (`captureWithError`, 60 s; `cookies` only for the signed-in retry) → title, `is_live`, thumbnail +
duration (for the link's Recent Links row, via `WindowManager.onInfo`), and an **ordered list of plans** (primary +
fallbacks); the completion's second value is yt-dlp's last ERROR line ("" on success):
- live → `.single` master HLS manifest (`manifest_url`), so AVPlayer adapts quality itself;
- `requested_formats` pair → `.split(videos: ladder, audio:)` with `StreamLadder.renditions` (yt-dlp's H.264 ≤1080p pick,
  then the best https H.264 MP4 at each lower 720/480/360p), then `.split(videos: [pick], audio:)`;
- otherwise the selected format → `.single`;
- safety net → best muxed format AVPlayer can open alone (`avPlayableMuxed`, e.g. YouTube "18").
`StreamRef.assetOptions` forwards yt-dlp's User-Agent/Referer/Origin to `AVURLAsset`.

### Split video+audio → `DashHLSBridge` (AVAssetResourceLoaderDelegate)
- `make(videos:audio:completion:)` — for fMP4, `fetchIndex` reads the first 64 KB of every rendition and the audio in
  parallel (more if the `sidx` is longer), `parse` walks `ftyp/moov/sidx` into init length + segment byte ranges,
  `mediaPlaylist` emits a VOD HLS playlist per file (`/video<i>.m3u8`, `/audio.m3u8`) with `EXT-X-MAP`/`EXT-X-BYTERANGE`
  pointing at the real https URL, and one master lists every video rendition (BANDWIDTH, CODECS, RESOLUTION) sharing audio
  group "a" — AVPlayer picks among them by bandwidth and the item's `preferredMaximumResolution`. A rendition whose index
  can't be read is left out. Split HLS pairs just get a master pointing at both.
- Playlists are served from memory under the `glasskit-hls://` scheme (`resourceLoader(_:shouldWaitFor…)`);
  segments go straight to the CDN as bounded range requests. Why: AVFoundation otherwise walks the whole remote
  fMP4 before playing (see GOTCHAS).

### YouTube browsing — `YtDlp.captureWithError` / `YTVideo` / `YTPlaylist` / `YTFormat` / `YouTube` (adapted from Tube)
- `captureWithError(_:timeout:completion:)` — like `capture`, plus yt-dlp's last `ERROR` line (stderr drained live).
  Returns a `YtDlpTask` whose `cancel()` terminates the process; `timeout` terminates a hung call and reports
  `YtDlp.timedOutError` (a missing binary reports `notFoundError`).
- `YouTube.loadJSON` — `--dump-single-json --flat-playlist`; `loadSignedIn` retries each `cookieSources()` browser
  with `cookieArgs` (`--cookies-from-browser chrome:<profile>` / `safari`); `accountURL` adds `authuser`.
- `search(_:limit:)` (`ytsearch<limit>:`, 18 a page up to `maxSearchResults` 90, `searchTimeout` 25 s, returns the
  cancellable task), `history` (feed/history, 50), `playlists` (feed/playlists), `playlistVideos` (80),
  `checkSignIn` (Preferences "Check"), `formats` (`-J`, http formats best-first; video-only get `+ba`).
- `playlist(_:completion:)` — a link's whole playlist **with its title** (via `playlistJSON`, 100 entries,
  signed-in when connected): what a player window's Up Next is built from.
- `isPlaylistLink` (→ `VideoLinks.isYouTubePlaylist`), `formatDuration`, `formatViews` — helpers. `video(_:)` falls
  back to `VideoLinks.thumbnail` and sets `YTVideo.isLive` from `live_status`.

### Up Next — `QueueItem` / `RepeatMode` / `PlayQueue` (`Sources/Queue.swift`) / `YouTubeUpNext`
The list Next/Previous walk through; one per player window (see `PlayerWindowController.ensureQueue`) and the universal
queue under the music window (`UniversalQueue`, below).
- `PlayQueue` — `kind` (`.list` a panel page or playlist · `.recommended` · `.folder`), `name` (the Up Next
  heading), `items`, `order` (play order — identity unless shuffled), `pos`, `handBack` (the app the universal queue hands
  back to). `peek`/`step(_:wrap:)` (wrap = Repeat All), `jump(toItem:)` / `jump(to:)`, `setShuffle` (randomizes the list
  around whatever is playing — which keeps playing — except Playing Next, which stays right after it; off restores the real
  order at the same item), `append` (dedupes by URL — recommendation top-ups). 3.21: `insert(_:_:)` (`.next` right after
  Now Playing, `.later` after the other additions, `.at(position)` a drop; marks `added`; goes into `items` right after the
  item it follows so unshuffling keeps it there), `remove(ids:)` (never Now Playing), `move(ids:to:)`, `clearAdded`,
  `update(_:_:)` (keeps the id), `addedAhead`, `continues(autoplay:repeatMode:)` (additions always play on),
  `merged(into:)` (a lone video's late list with your additions after its current item), `sections(historyLimit:)`.
- `PlayQueue.folder(for:shuffled:)` — a local file's neighbours: same-kind media in its folder, Finder order
  (`videoExts`/`audioExts` — only what AVFoundation can open).
- `YouTubeUpNext.load(id:)` — **what youtube.com itself would play next.** yt-dlp can't list recommendations
  and `list=RD…` mixes only exist for music videos, so this fetches the watch page (desktop-Safari UA,
  `SOCS=CAI` to skip the consent page) and reads `ytInitialData`: `parse` takes the autoplay pick first, then
  the sidebar (`collect` handles both `lockupViewModel` and older `compactVideoRenderer` shapes; `dig`/`text`/
  `ytInitialData` are its helpers — the last brace-matches the object after the marker). Empty on any change
  YouTube makes; only the recommended list depends on it.

### Universal queue — `UniversalQueue` / `QueueDrawer` (3.21)
- `UniversalQueue` (AppDelegate's lazy `upNext`) — `queue`, `engine` (`.idle` · `.external(app)` · `.native` · `.video`),
  `held`. `add(_:_:route:current:)` (`QueueRoute`: `.add` inserts; `.slotIn(app)` makes the app's song Now Playing — a
  `spotify:`/`music:` mirror item — with `handBack`, following it; `.start` begins at the first item), `playNow`, `jump`,
  `remove`, `move`, `insert(_:at:)`, `clearAdded`, `resume`, `advance`/`previous` → `start` (bumps `token`; `leave(for:)`
  stops Watch's player, closes the queue's video window unless the next item is a video, pauses the app unless the next
  item plays there) → `playNative` / `playExternal` / `playVideo`. `finish` hands back (`control.perform(.play)`).
  `externalChanged` (from `AppDelegate.setMusic`) waits for the first report of a started song (`awaiting`, Spotify by
  title for up to 4 s), then runs `Handoff.judge` against `followed`: finished/skipped → pause + `seek(0)` the app, advance;
  detached → `held`. `.native`: AVPlayer, 1 s refresh into a `NowPlayingInfo` (bundle id = Watch's own) pushed through
  `show` (AppDelegate `showQueueItem`: the music window with `OwnPlaybackControl`), tags/artwork via `commonMetadata`, a
  folder cover as fallback. `.video`: `openVideo` (WindowManager, beside the music window), `onEnded`/`onStep`/`onClosed`
  hooks, a 1 s refresh and the thumbnail. `command`, `setVolume`, `openSource` serve the music window for its own item;
  `musicWindowClosed` ends the queue.
- `QueueDrawer` — child window of the music window (`show(under:)`, `place()` → `DrawerLayout.place`: under it, else above,
  else the window moves up just enough — never while it's dragged or resized — shrinking the list on a short screen; follows
  resize/move; hides on full screen and close). `reload()` builds `rows` (`.header`, `.historyToggle`, `.item(item, section)`,
  `.note`) and `dropTargets` (the play-order position a drop above each row means). Drag rows (private pasteboard type with
  the ids) → `onMove`; external drops (`items(from:)`: files, folders' media, links/Spotify, one per line) → `onInsert`; ⌫ →
  `onRemove`; double-click/Return → `onPlay`; right-click → Play Now · Play Next · Remove + `extraMenu`.
- AppDelegate — `enqueue(_:_:)` (route; Automation asked on the action before a slot-in; flashes what happened),
  `enqueueLink` (a playlist link queues its videos), `fillDetails` (Recent Links, Spotify oEmbed, `probeLink`), `showQueue`,
  `toggleQueueDrawer`, `makeQueueDrawer`, `queueItemMenu`, `playSpotify`, `showQueueItem`, `presentMusicWindow`,
  `refreshControllable`. `send(_:to:)` routes Watch's own id to the queue. Row menus have Play Next / Play Later, `rowButtons`
  a + (⌥ = next), the field ⌥Return, `DragReceiverView.onDropMany`, `handleURLEvent` the `queue` host.

### Podcasts — `Podcasts.swift` + the panel (3.22)
- Search: `searchService` (`.youtube`/`.podcasts`, kept until quit) picks what `search(_:)` opens; search pages carry their
  query (`BrowseEntry.search`) and render `searchTabs()` (YouTube | Podcasts, `searchServiceChosen` re-runs the query).
  `podcastSearchFetch` → `performPodcastSearch` (boundary; `PodcastDirectory.search`) → `.shows(q, shows)`, cached 10 min in
  `podcastCache`. `showRow` → `openPodcast(link)` (`Self.showLink`: the Apple Podcasts id, else the feed) → `fetchEpisodes`
  (boundary; the lookup's newest 200, else the feed) → `.episodes(show, episodes)` → `episodeRow` (square art, date ·
  length, resume bar, ✓, + / ↗ Apple Podcasts / ⬇) and `episodeMenu` (Play / Next / Later, Download, Copy Link, Open in Apple
  Podcasts, Mark as Played).
- Playing: `playEpisode` (a row) → `upNext.playNow([episode.queueItem()])`; `playEpisodeLink` (`play()` of an Apple Podcasts
  episode link, Recent Links, the URL scheme) queues the bare link. `UniversalQueue.playPodcast` looks a bare link up
  (`resolveEpisode`: the show's lookup, else `yt-dlp -J`; AppDelegate names the Recent Links row), then `playNative`: for
  `.podcast` items the episode's picture, the resume seek once the item is ready (±0.5 s), `savePosition` every 5 s / on
  pause / on stop (`PlaybackPositions` + `WatchedVideos.noteProgress`), ✓ and a cleared position at the end.
  `openSource` opens the episode's Apple Podcasts page.
- Keys: `QueueItem.resumeKey` — `PlaybackPositions.key` gives every Apple Podcasts link to one episode `podcast:<id>`, so a
  pasted link, Recent Links and the episodes page share one resume point and ✓.

### System Now Playing, pausing music, saved Up Next, Open With (3.24)
- `AppDelegate.ensureSystemTick` / `systemTick` (1 s while a player window is open, the queue shows its own item or a paused
  app waits to be resumed): `lastPlayed` per window, `OwnPlayback.pick` → `systemSource` → `systemNowPlaying.publish`
  (`playerInfo` for a window, with `artwork(for:)` fetching its thumbnail once) — and `MusicPause`: Watch starting to play →
  `pauseMusicForWatch(asking: false)`; nothing of Watch's left → `performIfAllowed(.play)` on `pausedForWatch`. `play()`,
  `playEpisode` and `openFiles` call `pauseMusicForWatch(asking: true)` (the user's click). `musicPlaying` follows Music's and
  Spotify's broadcasts and every report (`setMusic`), whatever the Now Playing preference. `systemCommand` routes media keys:
  the queue → `upNext.command`; a window → `setPaused` / `nextItem` / `previousItem` / `seek(toSeconds:)`.
- `UniversalQueue.queue`'s `didSet` keeps `saved` (`PlayQueue.snapshot`, minus the music app's mirror item) in UserDefaults
  `upNextQueue`; `finish()` clears it; `resumeSaved()` rebuilds it (`PlayQueue(snapshot:)`) and plays its current item.
  `QueueDrawer.savedCount` / `onResumeSaved` show "Up Next from before — Resume" when no queue runs. `quitting()` saves an
  episode's position.
- `application(_:open:)` (file URLs; queued in `pendingFiles` until launch finishes) → `openFiles`: folders expand to their
  media (`PlayQueue.media(inFolder:)`), one video → `play`, anything else → `upNext.playNow` + `showQueue`. Info.plist
  `CFBundleDocumentTypes`: public.movie / public.audio, Viewer, Alternate (never the default app).
- Preferences: `pauseMusicCheck`, `resumeMusicCheck` (enabled with the first).

### Music library tab + video-window lists (3.23)
- `SearchService` is an `Int` enum (`youtube`/`podcasts`/`music` = the tab index). `.music` → `librarySearchFetch` →
  `performLibrarySearch` (boundary; `MusicAppControl.searchLibrary`: `.notRunning` / `.needsAccess` / `.denied` / `.failed` /
  `.songs`) → `.songs(q, songs)` or a message page whose button is `MessageAction.openMusic` (`openMusicForSearch`: opens
  Music in the background, searches again once it runs), `.allowMusic` (`allowMusicForSearch` → `requestAccess`, the one
  prompt) or `.automationSettings`. `songRow` (+ / menu) and `playLibrarySong` → `upNext.playNow([song.queueItem])`.
- `UniversalQueue.playExternal` starts a `music:<id>` item with `MusicLibrary.playScript` and a Spotify item with
  `Handoff.spotifyPlayScript`, both through `MusicAppControl.playScript(_:app:)` (opens the app in the background first);
  `.start` sets `handBack` when the first item is the app's, so it carries on after the list.
- `PlayerWindowController.toggleUpNextList` (⌥⌘U in `handleKey`, "Show/Hide Up Next List" in `addUpNext`) →
  `makeUpNextList` (a `QueueDrawer` over the window's `queue`; Now Playing from `sourceURL` while there's no list) →
  `ensureQueue` then `reload`. `insertIntoUpNext` (drops; Music/Spotify items refused) makes a provisional list for a lone
  video; `finishQueue` merges a late list around it (`PlayQueue.merged(into:)`). `startLoad`, `finishQueue` and
  `toggleShuffle` reload it. `onShowList` (set by `UniversalQueue.playVideo`) sends ⌥⌘U to `AppDelegate.showQueue`.
  `WindowManager.tile` hides lists; `freeFrame` treats a shown list as part of its window (`upNextListFrame`).

### Downloads — `DownloadKind` / `DownloadJob` / `DownloadManager`
- `DownloadKind` — `.originalVideo` (`bv*+ba/b`, source container) · `.mp4Best` · `.originalAudio` (`-x`, no
  re-encode) · `.mp3` (source bit rate) · `.video` (H.264 MP4 ≤1080p) · `.videoUpTo(h)` · `.audio` (m4a) ·
  `.playlist` · `.exact(selector, label)`.
- `DownloadJob.dir` — the folder for that job (Preferences folder, or the one picked in `AppDelegate.downloadFolder`).
- **Probes before launch:** `.mp3` runs `yt-dlp -j -f ba/b` → `abr` → `mp3Rate` (next legal MP3 rate ≥ source, max
  320) → `--audio-quality NK`. `.mp4Best` runs `-j` with `mp4BestFormat` (`-S res,fps,hdr:sdr,+codec:avc:m4a`) →
  `mp4RecodeArgs`: H.264/HEVC → plain mp4 merge; VP9/AV1 → merge to mkv + `--recode-video mp4` with
  `hevc_videotoolbox` at the source video bit rate (`-tag:v hvc1`, AAC copied). `[VideoConvertor]`/`[ExtractAudio]`
  lines set `job.converting` → row shows "Converting…".
- `start(url:title:kind:dir:)` — adds a **queued** job (resolves title if missing); `pump()` starts queued jobs oldest
  first, max 3 at once (launches directly; no helper self-update); every finish/failure pumps again.
- `launch(_:)` — yt-dlp with `--progress-template "download:WATCHPROG …"` + `--print "after_move:WATCHFILE …"`;
  video = H.264+AAC merged to `.mp4` (falls back to best), audio = `.m4a`/`.mp3`. Output `%(title)s [%(id)s].%(ext)s`
  in `job.dir`; playlists go to a `%(playlist_title)s/` folder with `NNN ` index prefixes. stdout/stderr parsed via `readabilityHandler`; `handle(_:_:)` tracks percent/part/file.
- `stop` (SIGINT — finalizes a live recording) / `remove` / `stopAll` (on quit); `changed(now:)` coalesces
  progress UI refreshes to ~4/s. `onChange` → panel rebuild, `onFinish` → status flash.

### Hotkey capture UI — `HotkeyRecorderView` (NSButton subclass)
Captures a new global-shortcut keystroke inside Preferences; calls `onCapture(keyCode, carbonMods, display)`.

### Preferences — `SettingsController`
**General:** hotkey recorder, "hotkey plays a copied link", "show videos open in browser tabs" + **Allow Browser
Access…** (`MediaMonitor.requestAccessForRunningBrowsers`), "show what's playing in other apps" (`Prefs.showNowPlaying` →
`nowPlayingSettingsChanged`), download folder chooser, **Ask where to save each download** (`Prefs.askDownloadDir`),
launch at login, "Media Tool Updates…", **Setup Guide…**. **YouTube Account** (the sign-in): "Signed in via" cookie browser, account
email, browser profile (`controlTextDidChange` saves live), **Sign In…** (`openSignIn` opens Google's YouTube
sign-in in that browser, only if installed) and **Check** (`YouTube.checkSignIn`).

### First-launch setup guide — `WelcomeController` (`Sources/Welcome.swift`)
Opens once (`Prefs.hasSeenWelcome`); Preferences ▸ **Setup Guide…** reopens it. Scrollable native guide with Start Watching, optional Connect YouTube, browser-tab permissions and third-party notices. `MediaTools.check()` runs each bundled tool's version command off-main with a timeout; missing/broken tools explain app replacement. No install commands. The installer also includes `FIRST_RUN.txt` as Read Me.txt. Tests inject fixture tools without accessing accounts.

### YouTube sign-in assistant — `YouTubeSignInController`
Opened by `AppDelegate.openYouTubeSignIn()` from Preferences ▸ Sign In…, from the Welcome guide, and from
the History/Playlists pages when signed out. Four steps:
1. Browser picker (Chrome/Safari; browsers that aren't installed are disabled) + Chrome profile.
2. `openSignInPage` opens Google's YouTube sign-in in that browser.
3. Help text for the Chrome Safe Storage prompt, or Safari's Full Disk Access (`openFullDiskAccess`).
4. `connect` saves the prefs and runs `YouTube.checkSignIn`. It sets `Prefs.youtubeConnected` and posts
   `.watchYouTubeAccountChanged`.
Sign Out (Preferences) only clears `youtubeConnected`, so the browser stays signed in. While signed out,
`showHistory`/`showPlaylists` show `showSignedOut` pages, and `playlistVideos` for pasted links runs without
cookies.

### Recent Links — `VideoLinks` / `LinkInfo` / `ClipboardLink` / `ClipboardLinkStore` (`Sources/Links.swift`)
- `VideoLinks.classify` — what the clipboard watcher keeps: `.video` (YouTube video/playlist shapes, media file
  extensions) right away; `.maybe` (other `videoSites`: Vimeo, Twitch, TikTok, SoundCloud, X, Reddit, Instagram…)
  only when `probeLink` finds a single video (`!isList`); `.other` (incl. YouTube channel/home pages) ignored.
  `isVideoSite` (also YouTube — used by `OmniboxInput` for links typed without a scheme), `isYouTubePlaylist`,
  `key` (= `PlaybackPositions.key`, so `yt:<id>` for any YouTube link shape), `thumbnail` (`i.ytimg.com/…/mqdefault.jpg`),
  `site` ("YouTube", host without `www.`, "File"), `webURL(_:resumeAt:)` (the ↗ button's page: the link, a YouTube
  non-Short with `t=<s>s` replacing any `t`/`start`; nil for local files).
- `LinkInfo(json:)` — title/thumbnail/duration/live/`isList` from a video's or playlist's JSON (a playlist without
  its own thumbnail uses its first entry's).
- `ClipboardLink` — url, title, date, thumbnail, duration, isLive (new in 3.11), pinned (3.12, `isPinned`); all
  optional, so older entries decode. **Since 3.15 nothing sets `pinned` from the UI:** `Favourites.importPins` turns
  pins into favourites once and unpins them; the store's pin handling (sort first, skip the cap, survive Clear) stays
  for that import and older data. `ClipboardLinkStore(defaults:)` / `.shared`, UserDefaults `watchClipboardLinks` (unchanged key):
  `add` (removes entries for the same video, inserts on top with the new link and date, carries known metadata
  over, incl. the pin; `capped` keeps every pinned link + the newest `limit` 100 unpinned), `update(_:with:)` (by
  video key; nil fields leave values alone), `setPinned(_:_:info:)` (pinning an unlisted video adds it, filled from
  `info`), `remove` (pinned too), `clear` (keeps pinned), `link(for:)`, `matching` (every word in title/link/site;
  case- and accent-insensitive). `all()` shows each video once (merging details of legacy duplicates; pinned if
  either copy is), pinned first, **without rewriting** what's stored.

### Resume positions — `PlaybackPositions` (`Sources/PlaybackPositions.swift`)
One UserDefaults dictionary `playbackPositions`: key → `[seconds, saved-at]`, newest 300 kept. `key(source:youtubeID:)`
= `yt:<id>` for YouTube (any link shape resumes), the standardized path for local files, else the URL. `save` forgets
a video under 5 s in or within 15 s of the end (so finished videos start over); unknown duration still saves.

### Library — `WatchedVideos` / `Favourites` / `PlaylistProgress` (`Sources/Library.swift`, 3.15)
- `WatchedVideos` — UserDefaults `watchedVideos`: video key → marked-at, newest 2000 kept. `threshold(duration:)` =
  90% of the video or its last 15 s (`PlaybackPositions.endMargin`), whichever comes first, never before half-way;
  `noteProgress` (called with every position save; true when it newly marked), `mark` / `unmark`, `isWatched`, `keys()`
  (one read per list redraw). Unknown-length videos are marked only by playing to the end.
- `Favourites` — UserDefaults `watchFavourites`: JSON `[FavouriteVideo]` (url, title, thumbnail, duration, isLive,
  added), newest first, one per video key, no cap. `add` (already there: stays put, details filled in), `remove`,
  `update`, `contains`, `matching` (same rule as Recent Links), `importPins(from:)` — once (`favouritesImportedPins`):
  3.12–3.14 pins become favourites in listed order with their details and date, then lose the pin.
- `PlaylistProgress` — UserDefaults `playlistProgress`: JSON list id → (video key, date), newest 200 kept.
  `startIndex(keys:saved:finished:)`: the saved video, or the one after it when it was finished (watched, no resume
  point left), the top after the last; a video no longer listed starts at the top.
- `.watchLibraryChanged` — posted by the app (players, row menus) when a mark or favourite changes; the panel redraws.

### Browser-tab detection — `MediaItem` / `Browser` / `automationPermission` / `MediaMonitor`
Polls every 1.8s **only while the panel is open** (background `DispatchSourceTimer`), and **never shows a
system prompt by itself**:
- only browsers that are **running** (`NSWorkspace.runningApplications`) are touched, addressed by bundle id
  (`tell application id …`) — naming an uninstalled app in AppleScript pops a "Where is …?" chooser;
- `automationPermission(_:ask:false)` (`AEDeterminePermissionToAutomateTarget`) gates each probe: granted →
  `browserTabs(_:)` injects JS per tab; not yet decided (-1744) → reported as "awaiting access"; denied → silent.
- `requestAccessForRunningBrowsers(completion:)` — Preferences ▸ "Allow Browser Access…"; asks only running
  browsers still undecided (-1744), once each.
Requires **"Allow JavaScript from Apple Events"** in the browser. (Local-app probes for Music/Spotify/TV/
QuickTime/VLC were removed in 3.3 — they triggered Automation prompts and their rows weren't playable. 3.19's Now
Playing row shows what those apps play through MediaRemote instead, with no Apple Events.)

### Now Playing — `NowPlayingInfo` / `NowPlayingMonitor` / `ArtworkWindowController` (3.19)
What another app is playing, from macOS's Now Playing information. Since macOS 15.4 MediaRemote answers only Apple-signed
processes, so the bundled **mediaremote-adapter** runs inside `/usr/bin/perl` (see GOTCHAS). It reads with `stream`; `send`/`seek`
run only from a click on the artwork window's controls (`NowPlayingRemote`); `test` (registers a fake player) never runs.
- `NowPlayingAdapter` — `Contents/Frameworks/MediaRemoteAdapter.framework` + `Contents/Resources/NowPlaying/mediaremote-adapter.pl`;
  `isAvailable` (also needs system perl; missing → feature off, never an error); `arguments` = `stream --no-diff --debounce=150 --micros`
  (every line a full state, times in µs); `arguments(for:)` = `send <id>` / `seek <µs>` for a `NowPlayingRequest`; `environment` drops `PERL*`, `DYLD_*`, `MEDIAREMOTEADAPTER_*`, `ADAPTER_TEST_MODE`, PATH `/usr/bin:/bin`.
- `NowPlayingInfo.parse(line:ignoring:)` — `{"type":"data","diff":false,"payload":{…}}` → `.info` (title, artist, album, bundle id,
  parent bundle id, playing, base64 artwork + MIME), `.nothing` (empty payload, no title, or Watch's own bundle as either id), or
  `.invalid` (bad JSON, diff lines; ignored). `appBundleID` = parent ?? bundle (a browser's web-content process → the browser).
  `itemKey` (app|title|artist|album), `artworkExtension` (MIME, else signature sniffing, else nil → saved as PNG),
  `suggestedFileName` ("Artist – Album.ext", `safeFileName`), `youtubeQuery`.
- `LineBuffer` — stdout chunks → lines (a line with artwork is several hundred KB; 32 MB cap).
- `NowPlayingMonitor` — `want(.panel / .viewer, on)`: starts the adapter when any client wants it, SIGTERMs it when none do.
  Parses off-main, delivers `onUpdate` on main only on change (artwork bytes shared when identical; elapsed time ignored, so
  seeks don't redraw). "Nothing playing" must hold `clearDelay` (0.6 s — start-up's first `{}` and track changes). Keeps the
  last info across a stop so reopening the panel doesn't flicker. Unexpected exit → restart after 2 / 10 / 60 s (an exit within
  15 s counts as a quick failure), then `gaveUp` for the session. `generation` drops output/exits from stopped processes.
- **Panel row** (`AppDelegate.nowPlayingRow`, first in the main list above the tabs; outside `clipSection`, so not in ↑/↓):
  `rebuildNowPlayingRow` (from `nowPlayingChanged` and `rebuildClipSection`) — `BrowseRowView(compact, image:, square:)` with the
  decoded `nowPlayingImage` (else the app icon), meta "Artist · App · Paused", album in the tooltip, ⤢ "Open Artwork"
  (only with artwork). Click → `openArtwork` (no artwork → `ArtworkActions.showApp`); right-click → `ArtworkActions.menuItems`
  (Open Artwork · **Open Full Screen** → `openArtwork(fullScreen: true)` · Copy · Save… · Open in Preview · Search YouTube · Show ‹App›).
  `startPanelMonitors` / `stopPanelMonitors` replace the bare `mediaMonitor.start/stop` at every panel show/hide.
- **Music only** (build 51) — `nowPlayingChanged` records `electedApp` (whoever holds macOS's single "now playing" slot, often a
  video) but only `NowPlayingInfo.isMusicSource` reports reach `setMusic` (row, image, window): music apps by bundle id, else a
  non-browser app reporting a music/audio media type; never a browser, a `com.apple.WebKit…` process or Watch. Nothing playing
  clears the music only if the music app was the elected one. `musicBroadcast` (Music's `com.apple.Music.playerInfo`, Spotify's
  `com.spotify.client.PlaybackStateChanged`, distributed notifications, no permission) keeps the song right while a video holds
  the slot (`NowPlayingInfo.broadcast` / `merge`); a new track seen only that way gets its artwork from `MusicAppControl.artwork`
  when Automation is already allowed. Commands: `send(_:to:)` — Music/Spotify via `MusicAppControl.perform` (AppleScript to that
  bundle id; Automation asked on the click), falling back to `NowPlayingRemote` only if that app holds the slot; other apps only
  while they hold it (`canControl` → `setControllable` dims the buttons otherwise).
- `openArtwork` — `nowPlaying.want(.viewer, true)` first, then `ArtworkWindowController.present` on the panel's spot
  (`WindowManager.frame(replacing:size:)`) unless a player is there, else `WindowManager.freeFrame` (beside the players), and the
  panel hides. The controller is reused (`makeArtworkWindow` also sets `WindowManager.keepClear` to its frame, so players avoid
  it); `onClose` releases `.viewer`, `onSearch` → `searchYouTube(for:)` (opens the panel and searches).
- `ArtworkWindowController` — borderless/black/floating like the players. `present` sizes to the artwork's pixels at the screen's
  scale (240 pt … min(600 pt, 70% of the screen height)). `show(_:)` (every update while visible): new artwork cross-fades
  (0.25 s); a new track without artwork keeps the old picture `placeholderDelay` (1.5 s) then shows the app icon; nothing
  playing keeps the picture and says "Not playing"; `fitAspect` keeps the top-left corner when the ratio changes. Hover fades
  in the caption (`GradientView`) and "…". Input goes through the player's own `PlayerSurfaceView` (`surface`) with the
  music window's `MusicZone` (3.20) and `MusicClicks` (3.25): `clicked(at:)` (a first click, timed from its mouse-down →
  `startToggle`: `pendingClick` after `clickDelay` = `clickRun.window` (the system interval, at most 0.3 s) + 0.02 s →
  `togglePlayback` = `playPause` + `CentreFlashView` ▶/⏸; an earlier click still waiting plays/pauses first), `multiClicked(at:)`
  (re-times AppKit's repeat with `clickRun.press`; too late to join the run → a fresh single click; otherwise it cancels the
  pending click; far-edge strips → `skip(∓10)`, stacking on `seekTarget`; anywhere else a run of 2 → `openSource`:
  `onOpenSource` hook in tests, else `ArtworkActions.showApp` + `MusicAppControl.reveal`), `handleKey` (Space, ←/→ ±5 s, F / ⌃⌘F, Esc, ⌘W), right-click → menu,
  `onPointer` → `pointerMoved(at:)`. `ArtworkContentView` only lays everything out on every size change (`setFrameSize` →
  `layoutViews`); `ArtworkImageView` never takes clicks; `windowShouldZoom` is false. `close()` leaves
  full screen first. Menu (`makeMenu`): Close · Enter/Exit Full Screen · Full-Screen Background ▸ Artwork Colours / Black · actions.
- **Full screen** (`toggleFullScreen`) — macOS full screen on its own Space. Before entering it sets aside what would fight it: the
  aspect lock (`contentResizeIncrements` clears it; `savedAspect`), the floating level and `.fullScreenAuxiliary` (→ `.fullScreenPrimary`);
  `restoreWindowed` puts them back on exit/failure/close and re-fits the shape if the track changed meanwhile. `layoutViews` in full
  screen uses `ArtworkLayout.fullScreen`: artwork centred (`artHolder` casts the shadow, the image view rounds its corners),
  caption centred under it (larger, no gradient), "…" clear of the menu bar. `ArtworkBackgroundView` shows
  `ArtworkWindowController.palette` (16×16 sRGB sample → `ArtworkPalette`) as a diagonal gradient, or black (placeholder / Black),
  cross-fading on changes. Idle: caption, "…" and the pointer hide after `idleDelay` (2.5 s) of no movement.
- **Playback controls** (`ArtworkControlsView`; one row since 3.20) — `pointerMoved(at:)` (from `surface.onPointer`), windowed
  (3.25): any point over the window shows the chrome (caption, "…", ≡: `fadeChrome`) at once, but the controls only when the
  pointer has rested `revealDwell` (0.08 s, `revealWork`) in `ArtworkLayout.revealZone(window:revealed: false)` — the caption
  band (64 pt) plus a 40 pt reach above it (≤ 30% of a small window's height), full width. Revealed, the larger zone
  (`revealed: true`: the grown band + the same reach) keeps them. Leaving the keep zone (or the window, for the chrome) schedules
  `hideWork` after `hideDelay` (0.4 s; re-entering cancels it, a drag on the timeline/volume re-arms it). `setControls` animates in
  `revealDuration` 0.25 s ease-out / out `hideDuration` 0.3 s ease-in-out (alpha, the band's growth and the text's lift in one
  `NSAnimationContext` group). Full screen keeps its own rules (`fullScreenPointerMoved`: everything at once, `exitWork` after
  `exitGrace` (1 s), idle hiding `idleWork` 2.5 s unless on `controlsZone`). Revealing grows the window's band by
  `ArtworkLayout.controlsHeight` (26 pt) and lifts the text (`layoutViews(animated:revealing:)`). Layout: `ArtworkLayout.controlRow` (pure, `ArtworkStyle.swift`) places
  ⏮ ⏯ ⏭ · elapsed · timeline · remaining · shuffle · repeat · speaker · slider on one line and drops, in order, the elapsed
  time, shuffle/repeat, the slider, the remaining time and ⏮/⏭ until a 48 pt timeline fits. Timeline: `refreshControls` every
  0.5 s while shown, from `NowPlayingInfo.position(at:)`; a drag previews the time and its release sends `.seek` and shows the
  target until the app reports it (`seekHold`, 2 s). ⏯ sends play or pause from the shown state and updates the shown info at
  once; ⏮ ⏭ send previous/next. Everything goes through `onCommand` (AppDelegate `send(_:to:)`). Volume:
  `MusicAppControl.check` (off-main, never prompts) when revealed → `.granted` (slider at the app's level; drags coalesce
  through `CoalescingSender`), `.undetermined` (slider; the first drag's release calls `requestAccess` — macOS asks once),
  `.denied` (dimmed icon whose tooltip names the Automation setting), `.unsupported` (not Music/Spotify, or not running:
  nothing). The icon toggles mute (0 ↔ last level). **Shuffle/repeat** (3.20): `refreshModes` after each volume check —
  `MusicAppControl.modes` (only when granted) → `appModes` → `setModes` (lit `GlyphButton`s, `repeat.1` for repeat-one,
  hidden when `.unsupported`, dimmed when `.denied`); a click → `changeMode` shows the new value at once, runs
  `AppVolume.shuffleScript`/`repeatScript` through `MusicAppControl.setMode` (asks once if undetermined), reverts and beeps on
  failure, then re-reads. `AppRepeat.next(for:)`: Music off → all → one, Spotify off ↔ all.
- `ArtworkActions` — `copy` (original bytes under their UTI + TIFF), `save` (`NSSavePanel.runModal`, original bytes),
  `openInPreview` (one reused file in `~/Library/Caches/com.jacob.watch/artwork/`), `showApp` (`NSRunningApplication.activate`),
  `appName` / `appIcon` (cached), `menuItems`.

### Player windows — `PlayerWindowController`
One borderless 440×247 (16:9) window per video. The only top button is "…" (`dotButton`, a `FadingButton`
shown on hover via `fadeDot(visible:)`), plus a loading
spinner/title (`showLoading` / `hideLoading`). `window.minSize` is 68×38 (16:9, ~1.6x cursor-arrow height).
There are no Auto Layout floors, so the window really shrinks that far (see GOTCHAS: AVPlayerView min height).
Z-order: video/web view → loading → `surface` → `controls` → "…".
- `load(_:queue:)` — **single entry point** for new windows and drop-to-replace; it resets the Up Next list
  (`queue`, given by the panel or built later) and hands off to `startLoad`. A playlist link goes to
  `loadPlaylist` first (one flat yt-dlp read → queue → play entry 1), so nothing waits for yt-dlp to resolve
  every entry.
- `load` also sets `playlistID` — the `list=` of a YouTube playlist or video link opened without a panel list — which
  the window's steps record in `PlaylistProgress` (`recordPlaylistSpot`, from `startLoad`; only while the queue is that
  list, not the recommendations an unreadable list falls back to). `loadPlaylist` → `startPlaylist(name:items:)` starts
  at `PlaylistProgress.startIndex` and sets `playlistStart` (index, count, load token) for the start chip.
- `startLoad(_:title:)` — the actual load, and where stepping through Up Next re-enters (it keeps `queue`).
  Local file → AVPlayer. Link → spinner, `resolve(_:signedIn:)` (`resolveStream`, then `tryNextPlan`; after 25 s the label says
  "Still loading…", yt-dlp's own limit is 60 s). A YouTube failure that `PlaybackFailure.wantsSignIn` with a connected YouTube
  Account retries once with `YouTube.cookieArgs`; otherwise `couldNotPlay`.
  `loadToken` drops stale callbacks. Sets `resumeAt` from `PlaybackPositions` unless the link has `t=`. It only raises the window when it isn't on screen yet, so autoplay can't
  yank a player in front of what you're doing.
- `tryNextPlan(_:)` — `.single` → `playAsset`; `.split` → `DashHLSBridge.make` → `playAsset`; failure → next plan; none left
  → `couldNotPlay`. `playAsset` sets `preferredMaximumResolution = qualityCap()` (`StreamLadder.cap` of the content size ×
  backing scale), and `windowDidResize` updates it, so the rendition follows the window; `playerMenu` shows "Playing at Np".
- `couldNotPlay(_:error:signedIn:)` — logs to `PlaybackLog`; other sites → their page in the web view; YouTube → never a web
  page: `PlayerFailureView` (reason from `PlaybackFailure.reason`; Sign In… when a sign-in would help and no account is
  connected → `openYouTubeSignIn`; Try Again → `startLoad`; Open in Browser; Copy Details with version, macOS, URL, error).
- `playAsset(_:bridge:token:)` — `PlayerVideoView` (AVPlayerLayer), a 0.25s
  periodic time observer → `prefetchUpNext` + `refreshControls`, an `AVPlayerItemDidPlayToEndTime` observer
  (`endObserver`) → `itemDidEnd`; KVO on item status: ready → hide spinner + seek to `t=` or `resumeAt` (its completion sets `positionReady`);
  failed before ready → next plan. The start/resume seek uses `skipTolerance` (±0.5 s), then `showStartChip`.
- **Start chip** (`resumeChip`, a `FadingButton` above the surface, top-left, 6 s — `showResumeChip` / `hideResumeChip`,
  skipped in windows too small for it): "Playlist: 8 of 20 [at 3:10] · Start from the Top" when `playlistStart` belongs
  to this load (→ `queue.jump(toItem: 0)`), else "Resumed at 12:34 · Start Over" when a saved position (not a `t=`)
  was used (→ seek to 0). `startLoad` hides it.
- **Controls:** `refreshControls` / `togglePlay` / `seek(toFraction:)` / `skip(_:)` / `handleKey` (space, ←/→ 5s,
  ⌘←/⌘→ = Previous/Next in Up Next). `skip` seeks within ±0.5 s (`skipTolerance` — a default seek snaps to a
  keyframe) and stacks rapid skips on `skipTarget` (cleared when the seek lands, on a scrub, and in `teardownAVPlayer`).
- **Click zones:** `surface.onClick` (a click that didn't drag) → web view if in web mode, else `togglePlay` when it hit
  `PlayerZone.playPause`. `multiClick(at:clicks:)` (clickCount ≥ 2) → skip ∓10 s per click in the side zones,
  `toggleSavedSize` on the double-click in `.resize`, nothing in the centre; in web mode/loading a double-click anywhere resizes.
  `showControls` on hover → `scheduleControlsHide` (2.5s) → `autoHideControls` (stays while paused, scrubbing,
  or the cursor is on the bar) → `hideControls` (also on mouse exit).
- **Up Next (the queue Next/Previous walk):** `canQueue` (a YouTube link or a local file) → `ensureQueue` builds
  one on demand — the playlist from a `list=` link (`YouTube.playlist`), `loadRecommended` (`YouTubeUpNext.load`)
  for a lone video or an unreadable list (an `RD…` mix, a private playlist), or `PlayQueue.folder` for a local file — with `queueLoading`/`queueWaiters`/`queueTried`/`queueToken`
  (a new video in this window drops an in-flight list) and `finishQueue`. `prefetchUpNext` loads it in the
  video's last minute when Autoplay/Repeat is on. `advance(_:auto:)` steps (wrapping when Repeat All) and,
  at the end of a recommended list, appends the current video's own recommendations and keeps going;
  `deadEnd` beeps only for a manual Next. `itemDidEnd`: Repeat One replays, else Autoplay/Repeat All →
  `advance(1, auto: true)`. `nextItem` / `previousItem` / `queueItemChosen` (Up Next ▸ jumps by item index).
  Modes are per window, seeded from `Prefs` and written back on every toggle: `toggleAutoplay` /
  `toggleRepeatAll` / `toggleRepeatOne` / `toggleShuffle` (reorders the live queue via `PlayQueue.setShuffle`).
- **Resume:** `positionKey` is set in `playAsset` (nil for live) and belongs to the player actually playing, so
  `startLoad` of the next video doesn't disturb it. `savePosition()` runs every 5 s from the time observer, on
  pause, in `teardownAVPlayer` (replace, web fallback, close) and from `applicationWillTerminate`; nothing is
  saved before `positionReady`.
- **Watched:** `savePosition` also calls `WatchedVideos.noteProgress`; `itemDidEnd` marks `positionKey` (`markWatched`);
  both post `.watchLibraryChanged`. (A site's page in the web view saves nothing.)
- `toggleSavedSize()` — double-click (top third / bottom middle) returns to `previousSize`, the size before the latest resize. `windowWillStartLiveResize` /
  `windowDidEndLiveResize` update it on every manual resize, and the double-click sets it to the size it's leaving, so repeated
  double-clicks toggle between the two sizes. Before any resize, it goes to the standard 440×247.
- `ensureWebView()` / `teardownWebView()` / `teardownAVPlayer()` — swap WebKit ⇄ AVKit. The web view
  unregisters drag types so drops fall through to `PlayerDropView`. In web mode, `surface` forwards plain
  clicks and scrolls to the web view.
- `playerMenu()` → Close · Pin · **Tile Windows** (only with 2+ players → `tileWindows` → `WindowManager.tile`) · **Add to /
  Remove from Favourites** (`toggleFavourite`, keeps the resolved `info`; not for a playlist link) / **Previous ⌘← · Next: ‹title› ⌘→ · Up Next ▸** (`addUpNext`, `queueMenu` — the list
  in play order, current item checked, watched entries dimmed (secondary label colour, "Watched" tooltip), 60 max;
  opening the menu with no list yet kicks off `ensureQueue`) /
  **Autoplay · Repeat All · Repeat One · Shuffle** (`addPlaybackModes`, checkmarks + tooltips) / **Download Video ▸** Original · MP4 (Highest Quality) (or **Record Live Stream**) / **Download Audio ▸**
  Original Audio · MP3 (Source Bit Rate) (`downloadKindChosen`) / Copy Link / Open in Browser. The menu sets
  `autoenablesItems = false` so Previous/Next can grey out. `showMenu()` pops it from "…"; `surface.onRightClick`
  pops it as a context menu. Downloads go through `WindowManager.onDownload`. (Picture in Picture was removed in 3.13.)
- `moveToTile(_:)` — animates to a Tile Windows slot and records the old size in `previousSize`, so a double-click
  returns to it.
- `windowWillClose` invalidates the load and queue tokens, tears down, and calls `WindowManager.removed`.

### Player window views
- `PlayerVideoView` — its backing layer is an `AVPlayerLayer` (`.resizeAspect`). It has no internal
  constraints.
- `PlayerSurfaceView` — transparent overlay. `mouseDown`: clickCount ≥ 2 → `onMultiClick(point, count)`. A click that moves
  more than 3pt drags the window manually (`setFrameOrigin`); otherwise `onClick(down, up)`. A
  tracking area drives `onHover` and `onPointer` (the point, nil on exit); `rightMouseDown` → `onRightClick`. Shared with the
  music window. `mouseDownCanMoveWindow = false` keeps
  title-bar-area clicks here.
- `FadingButton` — an `NSButton` whose `hitTest` ignores clicks while faded out.
- `PlayerControlBar` — 20pt bar, inset `barInset` (16pt) from the sides and 6pt from the bottom so it stays off the
  window's resize corners: ⟲10 · play/pause · ⟳10 (`onSkip`) · `ThinSlider` scrubber · time · volume. The volume is the
  speaker button (glyph from `volumeSymbol` — slash / 1 / 2 / 3 waves; click = `onMute`); hovering it (`pointerMoved(at:)`, the
  bar's own tracking area) slides a 50pt `ThinSlider` out to its **left** — so the icon stays under the pointer — taking room
  from the scrubber (`volumeOpen`, animated `layoutParts(animated:)`), and it tucks away 0.6 s after the pointer leaves, never
  mid-drag. (3.26: the slider is a vertical pop-up panel above the speaker, `VolumePopupView`, at any bar width.) `onVolume` → `PlayerWindowController.setVolume` (rounded to 1%, unmutes above
  0, saved to `Prefs.playerVolume`, which new players start at; ↑/↓ in `handleKey` ±10%). Frame-based `layoutParts` hides the
  skip buttons below 150pt wide, the time below 210pt and the volume below 100pt; the time label widens for hour-plus videos
  (`longClock`, `clockWidth`). Live (no duration) → "LIVE" instead of the scrubber. `isScrubbing` = either slider is being
  dragged. `hitTest` ignores clicks while faded out.
- `ThinSlider` / `GlyphButton` (`Sources/ThinSlider.swift`) — the shared minimal slider (2pt white line, brighter played part,
  dot only while hovered/dragged, whole view is the hit area, `onChange(value, finished)`) and borderless SF Symbol button
  (85% white, full on hover, `dimmed`, `onPress`); both ignore clicks while faded out.

### Window layout/lifecycle — `WindowManager`
`open(_:anchor:queue:replacing:)` creates a player, `place`s it (or, with `replacing`, `take`s the panel's spot — the usual
player size centred on the panel's top edge, `takeFrame(replacing:)`; AppDelegate only does that when the spot doesn't cover
the music window), and calls `load`. `freeFrame(size:anchor:remembered:excluding:)` is the shared placement: with no players,
the remembered spot unless `keepClear` (the music window) is there, else under the status item / centred; otherwise
right/left/below/above a player or the music window without overlapping any, else a cascade. The placement math is shared with the artwork window as statics:
`frame(replacing:size:)`, `frame(under:size:)`, `screen(for:)`, `clamp(_:to:)`. `onInfo` (resolved `LinkInfo` → the link's Recent Links row) and
`onDownload` (→ `AppDelegate.startDownload`) callbacks. `place(_:anchor:)` — first window opens at the remembered
frame (`rememberedFrame`, UserDefaults `lastPlayerFrame`; under the status item the very first time); further
windows take the remembered size and sit right/left/below/above an existing player without overlap (cascade
fallback). Existing windows are never moved — except by `tile(on:)` (**Tile Windows**): every visible, non-minimized,
non-full-screen player goes into one `Tiling.grid` on the given screen (the invoking player's, or the panel's; else the
last player's), assigned by `Tiling.readingOrder` and animated together (0.25 s). `rememberFrame(_:)` is called from the player's
`windowDidMove` / `windowDidResize` / `windowWillClose`. `beginPlaybackActivity` /
`endPlaybackActivity` — disables App Nap while any player is open.

### Drag-and-drop targets
- `DragReceiverView` — transparent overlay on the **status-item button**; drop a link/file to open a new player.
- `PlayerDropView` — a **player window's** content view; drop to replace what that window is playing. Views
  above it don't register drag types, so drops land here.

### Browse rows — `ThumbView` / `BrowseRowView` / `BrowsePage` / `BrowseEntry` / `SearchPage` / `DownloadRequest` / `FormatsMenu` / `FlippedView` / `ClosureButton` / `ClosureMenuItem`
- `FlippedView` — the scroll document of the main list **and** of browse pages (flipped, pinned at zero, padding
  inside) so short content starts at the top (see GOTCHAS) and "Show More Results" keeps the scroll position.
- `ThumbView` — async thumbnail with a main-thread cache; ignores late loads for a reused view.
- `BrowseRowView(thumb:title:meta:accessory:compact:favourite:watched:progress:image:square:)` — the one row style: 80×45 thumb · 2-line
  title · meta · accessory; `compact` (Recent Links / Favourites) = 32×18 thumb, 1-line title, 2 pt resume bar; `favourite`
  puts a yellow `star.fill` and `watched` a `checkmark.circle.fill` before the meta line (tooltips "Favourite" /
  "Watched"), and `watched` dims the thumbnail to 50%. `progress` draws a red resume bar along the thumbnail's bottom. `image` shows an in-memory picture (`ThumbView.show`) and
  `square` a 24×24 thumbnail (the Now Playing row). Hover highlight; `isHighlighted` = keyboard selection (accent); click → `onClick`;
  right-click → `onMenu` (`menu(for:)`).
- `BrowsePage` — `.loading(title, note:)` · `.videos` · `.results(query, SearchPage)` · `.playlists` ·
  `.message(title, text, action: MessageAction)` (`.none` / `.signIn` / `.retry` / `.updateAndRetry` → the button
  under the text). `BrowseEntry` = a page + the `BrowseFetch` that loads it (Try Again reruns it). `SearchPage` =
  videos so far, `requested`, `more` (YouTube had that many → offer another page).
- `ClosureMenuItem` — a menu item that runs a closure (row context menus).

### Control panel + app lifecycle — `AppDelegate`
- `applicationDidFinishLaunching` — status item, panel, main menu, hotkey, login item, the one-time pin import
  (`favourites.importPins`), clipboard watcher, the `.watchLibraryChanged` observer, and the media-monitor /
  window-manager (`onInfo` also updates Favourites) / download-manager callbacks. `applicationWillTerminate` stops downloads.
- `applicationWillFinishLaunching` / `handleURLEvent(_:reply:)` — `glasskit-watch://play?url=...` handoff.
- `setupStatusItem()` / `statusClicked()` — ▶ icon (⬇ while a download runs); left-click toggles the panel,
  right-click shows `appMenu()`.
- `setupPanel()` — a short **320×250 panel**: header (hide `menubar.arrow.up.rectangle` · status · •••), then the
  **field row** (`fieldH` 34, pinned under the header): `searchField` (NSSearchField, delegate = AppDelegate,
  `sendsWholeSearchString`, `sendsActionOnEndEditing` off, magnifier menu from `rebuildSearchMenu`) + ⬇ →
  `showPasteDownloadMenu`. Under it `mainScroll` (**Recent Links | ★ Favourites** tabs — `listTabs` of `listTab` buttons,
  `showRecentList` / `showFavouritesList` → `selectList` → `Prefs.showFavourites`, `updateListTabs` brightens the
  selected one; `clipTitle` "Matching Links" replaces them while filtering). Both tabs list every stored item
  inside the scroll area, with no All/Less control or automatic resizing; reopening starts at the top — then **Downloads**
  (hidden when empty) and "Open in Browser Tabs" (+ Open All; hidden unless a tab has a video). `setupBrowseView(in:)`
  builds the hidden browse page (back chevron · title · Download-All ⬇ · scrolling list) in the same area, so the
  field stays visible over results.
- `rebuildClipSection()` — the selected tab, or with text in the field "Matching Links" (`favourites.matching` first,
  then `links.matching` minus those videos, 40 in all) under `returnHint` (what Return will do). `LibraryMarks` (the
  favourite and watched key sets, read once per redraw) feeds every row. `compactRow` builds the compact `BrowseRowView`:
  YouTube mqdefault (else the stored) thumbnail, title (or the bare link), "site · LIVE / m:ss / m:ss (resume point /
  length) / duration · relative date" (`relativeDate`; favourites show no date), resume bar from `PlaybackPositions`,
  ★/✓ marks, `rowButtons` accessory. `linkRow` (Recent Links: click = play) and `favouriteRow` (click = play with the
  Favourites videos as Up Next from that row, `PlayQueue` named "Favourites"; a favourite playlist link just plays as a
  playlist and stays out of that list) add the click and `linkMenu`. Empty Favourites shows how to add one.
- `libraryChanged()` — `.watchLibraryChanged` observer and the row-menu actions: redraws the tab and any open browse
  page while the panel is visible (`togglePanel` redraws both on open).
  `rowButtons(_:title:)` — ↗ (`VideoLinks.webURL` at the current resume point → `NSWorkspace.open`; "Open in YouTube"
  / "Open on <site>"; omitted for files) + ⬇ (`popDownloadMenu`); used by Recent Links and browse-page video rows. Keeps a still-valid
  keyboard highlight.
- `rebuildMediaSection()` / `rebuildDownloadsSection()` — repopulate those rows. `rebuildMediaSection` hides header
  + list when there's nothing open. Download rows: Queued / % / ✓; click → reveal in Finder (done) / show error
  (failed); trailing button stops or removes.
- **The field:** `control(_:textView:doCommandBy:)` takes ↓/↑ (`moveHighlight` / `setHighlight` over `navRows` — the
  browse page's rows when one shows, else Recent Links), Return (`insertNewline:` → the highlighted row's `onClick`,
  else `submitField`) and Esc (`cancelOperation:` → `escapePressed`: clear text → `browseBack` → `minimizeToMenuBar`).
  `submitField` → `OmniboxInput.parse`: empty → `playClipboard`, link/file → `play`, playlist → `openPlaylist`,
  text → `search`. `controlTextDidChange` → `fieldTextChanged` invalidates the old request immediately, returns to local matches, and schedules `LiveSearch`. Composing text waits; links and paths never auto-search. Clearing/escaping returns home and cancels work. `searchFieldAction` only handles the ✕ button (Return never
  sends the action). `rebuildSearchMenu` builds the magnifier menu from `RecentSearches` (`recentSearchChosen`,
  `clearRecentSearches`) — our store, not NSSearchField's recents, so links are never remembered.
- `linkMenu(_:title:removable:info:play:)` — row right-click: Play (a result's own click, keeping its Up Next) ·
  Download ▸ (`downloadMenu`) · Copy Link (updates `lastClipboardChangeCount` so it isn't re-captured) · Open in
  Browser · **Add to / Remove from Favourites** (`setFavourite`, with the row's `info`; flashes the status line) ·
  **Mark as Watched / Unwatched** (not for playlist links; also clears the resume point) · Remove from Recent Links
  (Recent rows only). `clearRecentLinks` (••• menu) confirms with an alert first; favourites and marks are separate.
- `downloadMenu(for:title:)` / `popDownloadMenu(for:title:from:)` — the one download menu (field ⬇, every row's ⬇,
  and right-click ▸ Download): **Video** header
  (Original · MP4 Highest Quality), **Audio** header (Original Audio · MP3 Source Bit Rate), Whole Playlist
  (playlist links), **More ▸** (Compatible MP4, 1080/720/480p, M4A), and **Advanced Formats** (`FormatsMenu`, filled by `menuWillOpen` on
  first open). Items carry a `DownloadRequest` → `downloadChosen`.
- `startDownload` / `downloadAllPlaylists` get the folder from `downloadFolder(for:)` — `Prefs.downloadDir`, or an
  `NSOpenPanel` ("Download Here") when `Prefs.askDownloadDir`; Cancel = no download.
- **Browse pages** (`browseStack` of `BrowseEntry`; video rows carry ★/✓ from `LibraryMarks.current()`): `search(_:remember:)` (records only explicitly submitted `RecentSearches`; `activeSearchQuery` prevents duplicate Return requests; a `searchCache` hit —
  10 min — shows at once; else `searchFetch` → `performSearch`, the injectable service boundary; stale replies cannot cache or render), `loadMoreResults` (Show More Results: re-asks with one more page,
  appends only new URLs, `renderBrowse(keepScroll:)`), `showHistory` / `showPlaylists` (••• menu, open the panel
  first via `presentPanel`), `openPlaylist`. `openPage(_:root:initial:note:_:)` cancels `browseTask`, pushes a
  spinner page (or `initial`) and `runFetch` swaps in the result unless `browseToken` moved on; `reloadPage` (Try
  Again) / `updateAndReloadPage` (now opens whole-app update help) rerun the top page's fetch in place; `browseBack` cancels
  and pops (empty stack → main view, field cleared). Failures: `failureText` (timeout / missing yt-dlp / "YouTube may
  have changed" when `SearchFailure.suggestsUpdate`) + `failureAction`. `renderBrowse` draws `BrowseRowView`s
  (thumbnail · title · meta incl. LIVE · resume bar · `rowButtons` ↗ ⬇ · `linkMenu`; click = play with the page as
  Up Next / open playlist). Sign-in failures show `signInHelp` + a "YouTube Account…" button. `downloadAllPlaylists`
  queues every playlist.
- `mediaSettingsChanged()` — Preferences toggle for browser-tab detection.
- `play(_:queue:)` — validates input, `windowManager.open(_:anchor:queue:replacing:)` — when the panel is showing
  and no player is open, the player opens on the panel's spot and the panel hides (the first video "becomes" the
  panel); otherwise normal placement — records the link (`recordLink(_:probe: false)`; details arrive via
  `onInfo`). `queue` is the list a video was picked from: `renderBrowse` hands every video page (search results,
  History, a playlist) to the player as its Up Next, starting at the clicked row;
  `duplicateFrontPlayer` (⌘D) passes the front window's queue along.
- `togglePanel()` / `applyLevel()` / `positionUnderStatusItem()` / `windowDidMove` — the panel **always** opens
  under the icon (`togglePanel` resets `detached`); only a real mouse drag (`windowDidMove` checks
  `NSEvent.pressedMouseButtons`) detaches it for that session. No panel frame is persisted. Opening clears a
  stale query (unless a page is showing) and focuses the field.
- `stopPanelSearch()` — cancels the debounce and active search on hide; drops interrupted loading pages, keeps completed results. Playback cancels pending debounce.
- `hotkeyPressed()` — plays a copied link if `hotkeyPlaysClipboard`, else toggles the panel.
- `startClipboardWatch()` / `checkClipboard()` — 1.5s changeCount poll; `VideoLinks.classify` decides: `.video` →
  `recordLink` (adds, then `probeLink` fills in the row), `.maybe` → probe first, add only a single video (a link
  already listed just moves up), `.other` → ignored (never fetched).
- `appMenu()` / `showDotMenu(_:)` (drops down from the ••• button) — YouTube History / YouTube Playlists / Pin Panel / Tile Windows (2+ players; `tileWindows` → `WindowManager.tile` on the panel's screen) / Close All Players / Clear Recent Links… / Open Downloads Folder / Media Tool Updates… /
  Preferences / Quit. `updateYtDlp()` is a legacy selector wrapper for whole-app update help.
- `setupMainMenu()` — App menu (Preferences ⌘, · Duplicate Player ⌘D · Quit) + Edit menu (⌘X/C/V/A).
- `duplicateFrontPlayer()` — ⌘D replays the frontmost player's `sourceURL` into a fresh window.
- `registerLoginItem()` (only registers when not already enabled) / `toggleLoginItem()` — `SMAppService`.
- `installHotkeyHandler()` / `applyHotkey()` — Carbon global hotkey.

## Shortcuts
⌥⌘Y open/toggle panel (or play clipboard link, if enabled) · ⌘D duplicate frontmost player ·
⌘, Preferences · ⌘Q quit · standard ⌘X/C/V/A in the field. In the panel's field: Return search/play (empty = copied
link) · ↑/↓ pick a row · Esc clear → back → hide. In a player: space play/pause · ←/→ ±5s · ↑/↓ volume ±10% ·
⌘←/⌘→ previous/next in Up Next · double-click swap size.

## September 2026 reliability cleanup

`DownloadJob.didProbeMP3` distinguishes an unknown bitrate from an unattempted probe. `DownloadManager.launch` probes once, then uses quality 0 (best VBR) when no source rate is available. Canceling while the probe is pending prevents a download. `test.sh` verifies these paths without network or user media.

### Distribution (3.17)
`Dependencies.json` pins versions, URLs and hashes. `scripts/build.sh` invokes `watch_helpers.py` to build/stage universal helpers, preserve notices/sources, sign helpers before the app and verify dependency paths and receipts. `Tests/bundled.py <Contents/Helpers> --live` checks relocated real helpers under a clean HOME/PATH; `Tests/panel.py` covers the guide and search with isolated preferences. No production app installation or personal cookies are needed.

### Now Playing adapter build (3.19)
`Dependencies.json` "sources" pins the mediaremote-adapter commit. `watch_helpers.fetch_source` gets it with
`git fetch --depth 1 <url> <commit>` (git verifies objects against the commit) into `build/watch-vendor/mediaremote-adapter-<commit>.tar`
(reuse checks its embedded commit id). `prepare_now_playing` builds a universal, macOS 13 `MediaRemoteAdapter.framework` with one clang
call (upstream's CMake source list and flags; no cmake) into its own cache (`build/watch-vendor/nowplaying`, own receipt), so it never
invalidates the FFmpeg payload (`helper_inputs` leaves "sources" out of that fingerprint). `stage_now_playing` copies the framework to
`Contents/Frameworks` (symlinks kept, signed before the app), the script to `Contents/Resources/NowPlaying`, the license and source
archive to `ThirdParty`, and records hashes under `nowPlaying` in `MediaTools.json`; `validate_helpers` checks them, the binary
(`inspect_binary(own_id:)`) and the signature. `Tests/bundled.py` runs the relocated adapter's read-only `get` under system perl.

### Automatic builds (3.19)
`.github/workflows/build.yml` runs on GitHub's `macos-15` (Apple Silicon) for pushes to `main` and `claude/**`: type-check the app
and `./check.sh` first (fast feedback), then `scripts/watch_helpers.py` with `build/watch-vendor` cached (saved straight after
preparing, so a later failure keeps the FFmpeg build), `./package.sh` (universal DMG), `Tests/bundled.py` and
`verify_watch_package.py --canonical`. When those pass on a `claude/*` branch (or a manual run) it replaces the `v<version>-preview`
pre-release with the DMG (notes: `docs/releases/v<version>-preview.md` + commit + SHA-256); pre-releases never become "latest".
`Tests/panel.py` runs afterwards as an informational GUI check; snapshots are uploaded as an artifact.

### Standalone project (3.18)
Sources and tests are at the repository root. `scripts/watch_build.py` handles this app only; framework/target settings are in `scripts/app.json`. `watch_helpers.py` and installer verification resolve files relative to this repo. No sibling checkout or shared suite scripts are used. MIT applies to Watch code; third-party licenses remain separate. Legacy URL schemes and preference keys are retained for compatibility.

## 3.26 — ★, menu-bar ticker, volume, full-screen resize
- `Sources/NowPlaying.swift` `AppVolume.favouriteApps/favouriteReadScript/favouriteWriteScript` — Apple Music's `favorited` (fallback `loved`) of the current track; fixed text, `run script` inside `try`.
- `Sources/ArtworkWindow.swift` — `MusicAppControl.favourite/setFavourite`; `ArtworkWindowController.refreshFavourite/toggleFavourite/beginVolumeDrag/dragVolume/resizeArtwork`; `ArtworkControlsView.favourite` (★), `setFavourite`, `volumeOpen`, `pointerMoved(at:)`, `collapseVolume`, `endVolumeInteraction`, `layoutParts(animated:)` (the slider stays at zero width beside the speaker while tucked away).
- `Sources/ArtworkStyle.swift` — `ControlRow.favourite`, `controlRow(favourite:)` (the speaker at the right edge — no slider in the row —, ★ left of shuffle, dropped with the remaining time), `fullScreen(artwork:in:scale:)` (+ `chrome`), `fullScreenScaleRange`, `resizedScale`.
- `Sources/PlayerZones.swift` — `VolumeGesture` (relative drag, slop, span), `VolumeHover.zone`, `VolumePopup.frame` (where the pop-up panel sits above the speaker).
- `Sources/ThinSlider.swift` — `ThinSlider.relative/vertical`, `VolumePopupView` (the pop-up panel), `DragButton` (click vs a drag along `dragAxis`; `GlyphButton` is one), used by the music window's speaker and `PlayerControlBar.muteButton`.
- `Sources/Marquee.swift` (pure, tested) / `Sources/MenuBarTicker.swift` — the ticker; `AppDelegate.refreshTicker/tickerSettingChanged`, `Prefs.showTicker`, `SettingsController.tickerChanged`.
- `scripts/watch-update.sh` — the Mac-side updater (Current build or `--stable`; `--dry-run`, `--force`; run on demand, no schedule).
- `Sources/main.swift` `PlayerSurfaceView.dragIsResize/onResizeDrag` — a drag resizes the picture in full screen instead of moving the window.
