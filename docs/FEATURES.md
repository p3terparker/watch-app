# Watch — v3.19 · Beta *(reworked)*
**Plays almost any video, from anywhere — and downloads it.** Hotkey **⌥⌘Y**.

**Features**
- The dropdown is a **control panel** with **one field** at the top — *Search YouTube or paste a link* — that
  stays put while results show. **Typing searches YouTube after a 350 ms pause**; **Return** searches immediately, plays a pasted link (with or without `https://`, or a
  local file path), or lists a playlist link; Return in an **empty** field plays the copied link. **⬇** beside it
  downloads the field's link (or the copied one). **Typing filters Favourites and Recent Links instantly**
  ("Matching Links", favourites first, until the automatic search starts). Editing cancels the old request; late results cannot replace the current query. Links and paths still require Return; typing never auto-plays. **↑/↓ + Return** pick a row (Recent Links or results); **Esc** clears
  the field, then goes back, then hides the panel. The field is focused whenever the panel opens. The magnifier's
  menu lists **explicitly submitted recent searches** (never links or each typing pause) with **Clear Recent Searches**.
- **Now Playing — see the artwork of what's playing anywhere:** while Music, Spotify, Podcasts, a browser video or any
  other app is playing (or paused), the list starts with a **Now Playing** row — its artwork, the title and *artist ·
  app* (· **Paused**). Click it (or **⤢**) to **open the artwork** in a floating window like the players: it takes the
  panel's spot, starts at the artwork's own sharp size, drags and resizes freely, and **follows the music** — the next
  track's artwork cross‑fades in without ever taking focus. Hover for the caption and "…"; right‑click or "…" →
  **Copy · Save…** (the original image, named *Artist – Album*) **· Open in Preview · Search YouTube for this song ·
  Show ‹App›**; Esc closes. A row without artwork brings that app forward instead. **It never touches playback** — Watch
  only reads macOS's Now Playing information (no play/pause/skip, no permission prompts) and only while the panel or the
  artwork window is open. Hidden while you type, when nothing is playing, or with Preferences ▸ *Show what's playing in
  other apps* off.
- **Recent Links** — video links you copy or play, newest first: a **small thumbnail**, the title, and *site ·
  duration · how long ago*; a video you stopped part‑way shows where you left off (**12:34 / 45:10**) and a red
  **resume bar** on its thumbnail, a live stream shows LIVE. Each video appears **once**, whatever link shape it was copied as
  (youtu.be, watch?v=, `t=`…) — copying or playing it again moves it to the top. **↗ Open in YouTube** (or "Open on
  <site>") opens the video's page in your browser — a YouTube video at the point you left off — and **⬇** downloads;
  **right‑click** → Play · Download ▸ · Copy Link · Open in Browser · **Add to Favourites** · **Mark as Watched /
  Unwatched** · **Remove from Recent Links**. ••• → **Clear Recent Links…** (asks first) leaves Favourites and watched
  marks alone. **The full list (up to 100 recent links) is available immediately**: scroll inside the same
  320×250 panel, with no expand button. Favourites also start fully listed. **Only video links are captured:** YouTube videos/playlists and direct media files straight away; links
  from other video sites (Vimeo, Twitch, TikTok, SoundCloud, X, Reddit, Instagram, …) once yt‑dlp finds a single
  video there; everything else you copy (docs, repos, articles) is ignored and never fetched.
- **Favourites** — the list's second tab (**Recent Links | ★ Favourites**; the panel remembers which you used last).
  Add a video from any row's right‑click menu (Recent Links, search results, History, playlists) or from a player's
  "…" menu — **Add to Favourites** / **Remove from Favourites**. A yellow ★ marks favourites wherever they appear.
  Clicking one plays it with **your Favourites as Up Next**, so Autoplay/Shuffle/Repeat work through them. A
  favourite playlist link opens as its playlist. (Favourites replace 3.12's "Pin" for Recent Links: links you'd
  pinned were moved into Favourites.)
- **Watched videos are marked:** once you've seen 90% of a video (or reached its last 15 s, or it played to the end),
  a ✓ appears before its details and its thumbnail dims — in Recent Links, Favourites, search results, History and
  playlist pages — and it's dimmed in the player's **Up Next ▸** list. Right‑click → **Mark as Watched / Mark as
  Unwatched** sets it by hand (either one also forgets the resume point, so the video starts from the top).
- Below: live **download progress** and the videos currently open in your **browser tabs** (Safari + Chromium
  browsers, via AppleScript + in‑page JS) with **Open All** — that section only appears when a tab actually has a
  video. The panel is **short** (320×250); anything that doesn't fit scrolls.
- **YouTube browsing (from Tube):** search results, **History** and **Playlists** open as a page inside the panel
  under the field (‹ or Esc to go back) with thumbnail rows — click to play in Watch, ↗ to open it on YouTube, ⬇ for
  download options, right‑click for the row menu (incl. **Add to Favourites**); videos you've partly watched show their
  resume bar, watched ones a ✓, favourites a ★. History and Playlists
  live in the **••• menu** (and the icon's right‑click menu), not on the main page. Playlist rows open the
  playlist or ⬇ download it whole; the Playlists page has **Download All**.
- **Sturdier search:** **Show More Results** at the bottom asks YouTube for another page (up to 90); a search
  that hangs gives up after 25 s; a new search or Back **stops the one still running**; results are remembered for
  10 minutes, so Back and repeat searches are instant. A failed search offers **Try Again**, or **Update yt‑dlp &
  Try Again** when the error looks like YouTube changed under an old yt‑dlp.
- **YouTube sign‑in is in Preferences ▸ YouTube Account:** a status line plus **Sign In… / Sign Out / Check**. Sign In…
  opens a step‑by‑step assistant (pick browser → sign in there → allow access → Connect). Also here: the browser
  (Auto / Safari / Chrome), an optional account email, and the Chrome profile.
- **Native playback, no embed errors:** a player window opens instantly with a spinner, yt‑dlp resolves the
  stream, and everything plays in **AVKit** (tiny hover controls, seeking):
  - **YouTube up to 1080p60** — YouTube's separate H.264 video + AAC audio files are bridged into an in‑memory
    **HLS playlist** (byte ranges from each file's `sidx` index), so playback starts in ~2 s and seeks instantly.
  - **Live streams** (YouTube Live, Twitch, …) play from their **HLS manifest** with adaptive quality.
  - Other yt‑dlp sites use their best HLS/MP4 stream; local files (path or drag‑drop) play directly.
  - Fallback chain: next stream plan (e.g. 360p muxed) → YouTube IFrame embed → the page itself.
- **Downloads, in‑app:** ⬇ on any player window (or its "…" menu), next to the paste field, or on any search/
  History/playlist row. The menu is split into **Video** and **Audio**: **Original** video (the source file type
  and codecs, untouched — e.g. WebM/VP9/Opus), **MP4 (Highest Quality)** (top resolution, e.g. 4K; kept as‑is when
  it's H.264/HEVC, otherwise converted to HEVC on the Mac's hardware encoder at the source bit rate so it plays in
  QuickTime), **Original Audio** (source stream, no re‑encode) and **MP3 (Source Bit Rate)** (encoded at the
  source audio's bit rate, rounded up to a legal MP3 rate). **More ▸** keeps compatible H.264 MP4 (≤1080p), 1080/
  720/480p caps and M4A; whole playlists go into their own folder, plus an **Advanced Formats** list of exact
  yt‑dlp formats. Up to 3 run at once; the rest wait as **Queued**; live streams can be **recorded**
  (Stop finalizes the file). Progress shows in the panel's **Downloads** list — click a finished row to reveal
  it in Finder. Files go to the Preferences download folder (default `~/Downloads`), or — with **Preferences ▸
  Ask where to save each download** — to a folder you pick for each download.
- **Up Next — Next / Previous and playback modes (menu items, not on‑screen buttons):** every player window
  keeps a list it can walk with **Previous ⌘←** and **Next ⌘→** in the "…" (and right‑click) menu, which also
  shows what's coming (**Next: ‹title›**) and the whole list under **Up Next ▸** (click any row to jump; ✓ marks
  what's playing). Where the list comes from: whatever you clicked it from — **search results, History, a
  playlist** — the **playlist a `…&list=…` link carries**, **what youtube.com itself would play next** for a video
  opened on its own (its autoplay pick, then the sidebar recommendations, topped up as you go), or the **other
  media files in a local file's folder**. Four toggles sit under it: **Autoplay** (play the next thing when a video
  ends — on by default), **Repeat All** (loop the list), **Repeat One** (loop this video) and **Shuffle** (random
  order around whatever is playing, which keeps playing; turning it off restores the real order). They're per window, and a new window starts with your last choice.
  Pasting a **playlist link** now plays it straight away — the list is read flat first, so nothing waits for yt‑dlp
  to resolve every entry.
- **App icon is a play button** (red rounded square, white ▶); the menu‑bar icon is unchanged.
- **No surprise permission popups:** Watch only talks to browsers that are **running** and have already
  granted access; **Preferences ▸ Allow Browser Access…** asks macOS once per running browser. Browser‑tab detection can be turned off in Preferences. Terminal is no longer scripted.
- **Drag a video file or link onto the menu‑bar icon** to play it; drop one onto a player to **replace** it.
- **The first video takes the panel's place:** it opens right where the panel was (at the usual player size) and
  the panel hides — click the menu‑bar icon to bring it back. With a player already open, new videos open beside it.
- **Videos resume where you left off** — YouTube (by video, whatever the link looks like), other sites and local
  files — and a **"Resumed at 12:34 · Start Over"** chip says so for a few seconds (click it to play from the
  beginning). Resuming lands on the exact spot (within half a second). A link with `t=` starts there instead; a video
  you watched to the end (or barely started) starts over. The YouTube embed fallback saves its place too.
- **Playlists carry on where you were:** opening a playlist link again (pasted, from Recent Links or Favourites, or
  via the URL scheme) starts at the video you were on — or the next one, if you'd finished it — with a
  **"Playlist: 8 of 20 · Start from the Top"** chip to go back to the beginning.
- **The control panel always opens under the menu‑bar icon.** Dragging it off keeps it open until you hide it.
- **Player windows remember the last one's position and size** (across launches). The first window reopens
  where the last one was; more windows open **beside** the existing ones at that size, never overlapping, and
  existing windows stay put. **Tile Windows** (in a player's menu and the panel's ••• menu, whenever 2+ players are
  open) sorts them all into a grid that fills that screen — each as large as fits at 16:9, keeping their
  top‑to‑bottom, left‑to‑right order; double‑click a tiled window to get its old size back. App Nap is disabled
  while something plays.
- **Minimal player chrome:** only a "…" button at the top, and it appears only while the cursor is over the
  window. Its menu (also on **right‑click** anywhere on the video) starts with **Close** and **Pin**, then Tile
  Windows (2+ players), **Add to Favourites**, Up Next, playback modes, downloads, and copy/open link. A **20 pt control bar** (⟲10 ·
  play/pause · ⟳10 · scrubber · time · mute) fades in at the bottom on hover, set in from the edges so it never
  competes with the window's resize corners. **Drag anywhere** to move the window. **Click zones:** click the
  middle to play/pause; double‑click the left or right side (below the top third) to skip back/forward 10 s —
  keep clicking to skip further; double‑click the top third or the bottom middle to return to the size the window
  had before its last resize (every manual resize updates it, so double‑clicking again toggles back). The window shrinks to **68×38** without letterboxing. Space =
  play/pause, ←/→ = ±5 s, ⌘←/⌘→ = previous/next in Up Next.
- **Clipboard‑plays‑on‑hotkey** (Preferences toggle, default on).
- **URL scheme handoff:** `glasskit-watch://play?url=<percent-encoded-video-url>` plays a link from any app or script.

**Installation and included tools**
- A self-contained universal DMG includes yt-dlp (Python/EJS included), FFmpeg, ffprobe and Deno. No Homebrew, Python or Terminal setup. Requires macOS 13+; real Intel/older-system acceptance is still pending.
- First launch offers Start Watching, optional Connect YouTube and local helper checks. Media tools update by replacing Watch with a newer installer; helpers never self-modify the signed app.
- Browser-tab detection requires **"Allow JavaScript from Apple Events"** in that browser's Develop/View menu. Optional account connection may require Keychain or Full Disk Access approval.
- This personal preview is ad-hoc signed, not Apple-notarized. The installer guide describes the macOS Privacy & Security approval; a seamless public installer still needs Developer ID signing/notarization.

**Known limitations**
- Playable detection is scoped to browser tabs. Local‑app rows (Music, Spotify, TV, QuickTime, VLC) were removed in
  3.3 — they caused Automation prompts and couldn't be played anyway; 3.19's Now Playing row shows what those apps play
  (with artwork) without Automation, but doesn't play it in Watch.
- Now Playing relies on a workaround (system perl loading the bundled MediaRemote adapter) for macOS 15.4+'s
  restriction on reading Now Playing information. If a future macOS closes it, the row simply stops appearing.
- Some sites block yt‑dlp from certain networks (e.g. Vimeo 403) — those fall back to loading the page.
- In‑window YouTube quality caps at 1080p (H.264); 1440p/4K are VP9/AV1 only.
- Up Next's **recommendations aren't personalized** — they're read from the public watch page, not your signed‑in
  account (playlists and History still use your sign‑in). If YouTube reshapes that page, Next simply has nothing
  to go to until it's taught the new shape; lists you played from keep working.

**Changelog**
- **3.19** — **Now Playing artwork:** a Now Playing row for whatever another app is playing, opening its artwork in a
  floating window that follows the music (Copy · Save · Open in Preview · Search YouTube · Show ‹App›). Read-only
  macOS Now Playing access through the bundled, pinned mediaremote-adapter; no playback control, no prompts; runs only
  while the panel or artwork window shows. Preferences toggle.
- **3.18** — Standalone Watch App repository under MIT, with its own build/test/package commands and no sibling-project dependencies. Fully bundled installer retained; existing preferences and URL handlers remain compatible.
- **3.17** — **Self-contained installer:** pinned universal media tools, no system-tool fallback, no-Terminal first-run guide with local checks and recovery, optional YouTube connection, included notices/sources. Whole-app updates replace helper self-updates.
- **3.16** — **Full lists at the same size:** Recent Links and Favourites start fully listed and scroll inside the existing 320×250 panel; All/Less and automatic expansion resizing are removed. **Live search:** typing searches after 350 ms, Return searches immediately without duplicate requests, edits cancel obsolete work, and clear/Escape returns home. Links, local paths and unfinished input-method composition do not auto-search or play.
- **3.15** — **Watched marks:** videos you've finished (90%, the last 15 s, or played to the end) get a ✓ and a dimmed
  thumbnail in every list, and are dimmed in Up Next ▸; right‑click **Mark as Watched / Unwatched**. **Favourites:** a
  second tab beside Recent Links (**★ Favourites**), filled from any row's right‑click menu or a player's "…" menu;
  playing one queues the rest as Up Next. They replace Recent Links pins (existing pins moved over). **Playback
  location:** a **"Resumed at 12:34 · Start Over"** chip shows when a video picks up where you left it; resuming now
  lands on the exact second (it could snap several seconds early); **playlist links carry on at the video you were
  on**; the YouTube embed fallback saves its position.
- **3.14** — **Click zones:** click the middle of a video to play/pause; double‑click its left/right side to skip
  10 s (more clicks, more skips); double‑click the top third or bottom middle to resize. **Playback bar:** bigger (20 pt),
  inset away from the resize corners, with **⟲10 / ⟳10** buttons; hour‑long times no longer get cut off. Skips now
  land where they should (they used to snap to the nearest keyframe, sometimes seconds off).
- **3.13** — **Player menu tidied:** Close and Pin are the top two items; **Picture in Picture removed** (player
  windows already float). **Tile Windows** — with several players open, one click sorts them into a grid filling the
  screen (largest 16:9 size that fits, current order kept), from any player's menu or the panel's ••• menu.
- **3.12** — **Recent Links slimmed down:** thumbnails are now small (32×18, was 64×36). **Pin links** from the
  right‑click menu (Recent Links rows and search/History/playlist results): pinned links sit on top, skip the cap and
  survive Clear. **↗ Open in YouTube** beside every row's ⬇ (YouTube videos open at your resume point; other sites
  open their page).
- **3.11** — **One field instead of two:** search and paste merged into a single field pinned under the header
  (Return searches or plays; empty = the copied link; ↑/↓/Return/Esc keyboard control; recent searches in the
  magnifier menu). **Recent Links redesigned:** thumbnail rows with site, duration, age and a resume bar; one entry
  per video (link shapes merged); right‑click to remove, ••• → Clear Recent Links…; typing filters them. **Only
  video links are captured** — other copied URLs are no longer recorded or fetched with yt‑dlp. **Search:** Show
  More Results, a 25 s timeout, superseded searches stopped, 10‑minute result cache, Try Again / Update yt‑dlp &
  Try Again on failure. The hide button's icon is now a menu‑bar arrow.
- **3.10** — **Resume playback:** every video reopens where you left it (saved every few seconds, on pause, on
  close and on quit; finished videos start over; `t=` links still win). **Shorter panel:** same width, 250 pt tall
  instead of 520, with the two newest copied links; **All ▾** extends the panel downward to list the rest (the "Play Clipboard
  Link" button is gone — Play with an empty field does it). **The first video replaces the panel** instead of
  opening a separate window elsewhere.
- **3.9** — MP3 downloads probe source bitrate once. Missing/invalid probe results now use the existing best-VBR fallback instead of repeatedly probing. Download queue extracted for isolated regression checks, including cancellation during a probe.
- **3.8** — **Up Next.** Player windows gained **Previous ⌘← / Next ⌘→ / Up Next ▸** and **Autoplay · Repeat All ·
  Repeat One · Shuffle**, all in the "…" / right‑click menu. The list is the panel page a video was played from
  (search results, History, a playlist), the playlist a `list=` link carried, **what youtube.com would play next**
  for a lone video — read from the watch page's own autoplay pick and sidebar, since yt‑dlp can't list
  recommendations and `RD…` mixes only exist for music — or the folder a local file sits in. Autoplay is **on** by
  default. Pasting a playlist link now starts playing immediately (flat read first) instead of waiting for yt‑dlp
  to resolve the whole playlist.
- **3.7.1** — **Tube retired.** Watch no longer reads Tube's `com.jacob.tube` preferences as a fallback for YouTube
  sign‑in; those settings were copied into Watch's own preferences, and Tube was removed from the suite.
- **3.7** — **Download choices reworked:** the menu is split into **Video** (Original source format · MP4 highest
  quality, hardware‑converted to HEVC only when the top stream is VP9/AV1) and **Audio** (Original · MP3 at the
  source bit rate); older presets moved under **More ▸**. The player window's menu offers the same four. New
  **Preferences ▸ Ask where to save each download** (a folder picker per download; one for Download All).
  Rows show **Converting…** while ffmpeg re‑encodes. New **play‑button app icon** (included `AppIcon.icns`).
- **3.6** — **Tube's features folded into Watch, keeping the panel minimal:** a YouTube search bar above the
  paste bar; search results, **History** and **Playlists** (••• menu) open as in‑panel pages with thumbnail rows
  (click = play natively, ⬇ = download menu); playlist open / download / Download All. **YouTube sign‑in moved to
  Preferences** (cookie browser, account, profile, Sign In…, Check). The **browser‑tabs section disappears
  entirely** when nothing is open (its access button moved to Preferences). Download menu gains 1080/720/480p, MP3,
  whole‑playlist and Advanced Formats; downloads queue (max 3 concurrent). **Welcome / setup guide** on first
  launch (reopen: Preferences ▸ Setup Guide…): live yt‑dlp/ffmpeg check and a copy‑paste Homebrew walkthrough,
  so the DMG can go to friends. The DMG's Read Me now covers the Gatekeeper step and yt‑dlp. **YouTube
  sign‑in assistant** (Welcome step 4, Preferences ▸ Sign In…, or the History/Playlists pages when signed out):
  pick Chrome or Safari, open YouTube sign‑in there, get help with the Chrome keychain prompt or Safari's Full
  Disk Access, then Connect. Preferences shows a signed‑in status with **Sign In / Sign Out / Check**. Sign Out
  only disconnects Watch. The panel's **••• menu now drops down from the button** (it used to pop up at the
  panel's bottom corner), and the Welcome window is forced to the front on first launch. **Double‑click to resize
  returns to the previous size.** It used to go back to the size from the double-click before (often two resizes
  back); now every manual resize updates the size it returns to.
- **3.5** — The control panel **always opens under the menu‑bar icon** (it had been reopening at a stale
  "detached" frame near the bottom of the screen). Only a real mouse drag detaches it now. **Player windows
  remember the last window's position and size**, and new ones open beside the existing ones without
  rearranging them.
- **3.4** — **Tiny players:** the minimum size dropped from 256×144 to 68×38 (still 16:9, about 1.6× the
  cursor's height). AVPlayerView's built‑in controls forced the view to stay ≥130 pt tall, which blocked
  shrinking and letterboxed the video, so it's gone. Video now renders on a bare `AVPlayerLayer` with a custom
  14 pt hover bar at the bottom. Only the **"…"** button is left at the top, and it hides unless you're hovering
  (⬇ and ✕ moved into its menu, **Close** is at the top, and **Picture in Picture** joins them). **Right‑click**
  opens the same menu. **Drag anywhere** moves the window. **Double‑click** swaps to the size
  saved at the previous double‑click. AVKit's full‑screen button and volume slider are gone; there's a mute
  toggle instead.
- **3.3** — **Popups fixed:** browser‑tab detection no longer names apps that aren't installed (that popped
  "Where is Brave Browser?"‑style choosers) or probes Music/Spotify/TV/QuickTime/VLC (Automation prompts);
  it only reads running browsers that already granted access, with a one‑click "Show videos from…" button
  instead of automatic prompts, plus a Preferences toggle. Launch‑at‑login no longer re‑registers every launch.
  **Seamless playback:** every link now plays natively in AVKit — YouTube HD (≤1080p60) via a DASH→HLS bridge,
  live streams via their HLS manifest — with an instant window + spinner; the IFrame embed is only a fallback.
  **Downloads:** in‑app video (MP4) / audio (M4A) downloads and live recording with progress in the panel;
  yt‑dlp updates run in‑app. yt‑dlp is launched directly (argument array, no shell).
- **3.2** — Added `glasskit-watch://play?url=...` URL-scheme handling for Tube. Watch registers the scheme
  in `Info.plist`, receives `kAEGetURL`, and routes the decoded URL into the same `play(_:)` pipeline used
  by paste, clipboard, drag-and-drop, and media rows.
- **3.1** — **YouTube reliability:** the player is now built with YouTube's **IFrame Player API** under a
  desktop‑Safari user‑agent, and **auto‑falls back to a yt‑dlp‑resolved direct stream in AVPlayer** when the
  embed errors or stalls (some videos/networks still throw YouTube's 15x embed errors — the fallback makes it
  play anyway, ~360p). **⌘V** now pastes into the panel's link field (added the missing Edit menu); **⌘D**
  duplicates the front player window. **Multi‑window sizing fix:** extra players keep the small single‑window
  size in a non‑overlapping grid instead of stretching full‑screen. **Drop‑to‑replace:** dropping a link/file
  on a player window swaps its media in place (dropping on the menu‑bar icon still opens a new window).
- **3.0** — Full rework from a YouTube‑only mini‑player into an any‑video player: resolution pipeline
  (YouTube iframe / AVPlayer for everything else), a `WindowManager` with automatic tiling for multiple
  open players, the media‑monitor control panel (browser tabs + local‑app allowlist), drag‑and‑drop onto
  the menu‑bar icon, and clipboard link history + clipboard‑plays‑on‑hotkey. Verified live: panel
  open/anchor, local‑file → AVPlayer playback, multi‑window tiling, and real browser‑tab/local‑app
  detection. YouTube embed playback itself depends on YouTube not flagging the network/session — this is
  outside the app's control and unrelated to the code (confirmed by reproducing the same embed error in
  plain Safari on the same network).
- **2.0.1** — Fixed embed **error 153** (“video player configuration error”): the player is now hosted in
  an `<iframe>` on a youtube.com origin instead of loading `/embed/` as a top‑level page. Clean placeholder
  when no video is loaded; **Quit** in the icon menu is no longer greyed out.
- **2.0** — Rebuilt as a menu‑bar **mini‑player** that mirrors your browser’s current video.
- **1.x** — A tabbed in‑window YouTube browser (native window tabs, drag‑out, copy links, yt‑dlp).

---

