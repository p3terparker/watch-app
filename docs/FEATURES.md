# Watch 3.26

Plays almost any video and downloads it. Hotkey **⌥⌘Y**.

## The panel

Click the menu-bar icon (or press the hotkey) and a small panel drops down under it, 320×250. Drag it away and it stays open until you hide it.

- **One field** at the top: *Search YouTube or paste a link*. It stays put while results show, and it's focused whenever the panel opens.
- **Typing searches YouTube** after a 350 ms pause. **Return** searches right away, plays a pasted link (with or without `https://`, or a local file path), or lists a playlist link. Return in an empty field plays whatever link you last copied. Links and paths never start playing just from typing.
- While you type, Favourites and Recent Links are filtered instantly ("Matching Links", favourites first) until the search results arrive. Editing cancels the old search, so a late answer can't replace the current one.
- **↑/↓ + Return** pick a row. **Esc** clears the field, then goes back, then hides the panel.
- The magnifier menu lists your recent searches (only ones you submitted, never links) and has **Clear Recent Searches**.
- **⬇** next to the field downloads the field's link, or the copied one.
- Below the field: download progress, and any videos open in your browser tabs with **Open All**. That section only shows up when a tab actually has a video.
- **•••** has History, Playlists, Tile Windows and Clear Recent Links.

### Search

- Results come as thumbnail rows: click to play, **↗** to open on YouTube, **⬇** for download options, **+** to add to Up Next, right-click for the full menu.
- Results have **YouTube | Podcasts | Music** tabs. The tab you pick stays selected for your next searches.
- **Show More Results** loads another page, up to 90.
- A search that hangs gives up after 25 seconds. A new search, or Back, stops the one still running. Results are cached for 10 minutes, so Back and repeat searches are instant.
- A failed search offers **Try Again**. When the error looks like YouTube changed under an old yt-dlp, there's also a button that explains how to update Watch.

## Recent links, favourites and watched marks

**Recent Links** are the video links you copy or play, newest first, up to 100, all in the same scrolling panel. Each row has a small thumbnail, the title, and site · duration · age. A video you stopped partway shows where you left off (12:34 / 45:10) and a red resume bar. Live streams say LIVE.

- Each video appears once, whatever link shape it came from (youtu.be, watch?v=, a `t=` link). Copying it again moves it to the top.
- Only video links are kept: YouTube videos and playlists, direct media files, and links from other sites once yt-dlp finds a single video there. Anything else you copy (docs, repos, articles) is ignored and never fetched.
- **↗** opens the video's page in your browser, at your resume point for YouTube. **⬇** downloads.
- Right-click: Play · Download ▸ · Copy Link · Open in Browser · Add to Favourites · Mark as Watched / Unwatched · Play Next · Play Later · Remove from Recent Links.
- **Clear Recent Links…** (in •••) asks first and leaves Favourites and watched marks alone.

**Favourites** is the second tab (Recent Links | ★ Favourites). Add a video from any row's right-click menu or a player's "…" menu. A yellow ★ marks favourites wherever they appear. Clicking one plays it with your favourites as Up Next. A favourite playlist opens as its playlist.

**Watched marks.** Once you've seen 90% of a video, reached its last 15 seconds, or played it to the end, it gets a ✓ and a dimmed thumbnail in Recent Links, Favourites, search results, History and playlist pages, and it's dimmed in Up Next. Right-click → Mark as Watched / Unwatched sets it by hand and also forgets the resume point.

**Playlists carry on** where you were. Open a playlist link again and it starts at the video you were on, or the next one if you'd finished it, with a "Playlist: 8 of 20 · Start from the Top" chip.

## YouTube sign-in (optional)

Search and most public videos work without it. Sign-in is under **Preferences ▸ YouTube Account**: a status line plus **Sign In… / Sign Out / Check**. Sign In… walks you through it (pick a browser, sign in there, allow access, Connect). You can also set the browser (Auto / Safari / Chrome), an account email and the Chrome profile. It unlocks **History** and **Playlists**, and videos that ask you to sign in. Sign Out only disconnects Watch.

## Playing videos

A player window opens right away with a spinner while yt-dlp finds the stream. Everything plays in AVKit.

- **YouTube up to 1080p60.** The separate H.264 video and AAC audio files are stitched into an in-memory HLS playlist (using byte ranges from each file's `sidx` index), so playback starts in about 2 seconds and seeking is instant.
- **Quality follows the window.** YouTube's lower H.264 renditions (360/480/720p) go into the same playlist, and the player caps the picture at the window's size, so a small window plays 480p and a big one switches up to 1080p as you resize. The "…" menu shows what you're getting ("Playing at 720p").
- **Live streams** (YouTube Live, Twitch and so on) play from their HLS manifest and adapt their own quality.
- **Other sites** use their best HLS or MP4 stream. **Local files** (a path, or drag and drop) play directly.
- **When a stream fails**, Watch tries the next plan (another rendition, then 360p muxed). A YouTube video that still won't play shows why in the window, never YouTube's own page, with **Sign In… / Try Again / Open in Browser / Copy Details**. If YouTube asks Watch to prove it isn't a bot and an account is connected, Watch retries once with that sign-in. Slow answers show "Still loading…" for up to 60 seconds. Failures are logged to `~/Library/Logs/Watch/playback.log`. Other sites fall back to loading their page.
- **Resume.** Videos reopen where you left them (YouTube by video id, other sites, local files), within half a second. A "Resumed at 12:34 · Start Over" chip shows for a few seconds. A link with `t=` starts there instead, and a video you finished or barely started starts over.

## Player windows

- Windows are minimal: a "…" button at the top that only shows while the pointer is over the window, and a thin 20 pt control bar at the bottom on hover (⟲10 · play/pause · ⟳10 · scrubber · time · volume), set in from the corners so it doesn't fight the resize handles. Hover the speaker for a volume slider.
- **Drag anywhere** to move. The window can shrink to 68×38 without letterboxing.
- **Click zones.** Click the middle to play/pause. Double-click the left or right side (below the top third) to skip back or forward 10 seconds; keep clicking to skip further. Double-click the top third or the bottom middle to return to the window's size before its last resize (every manual resize updates it, so a second double-click toggles back).
- **Keys:** Space play/pause · ←/→ ±5 s · ↑/↓ volume · ⌘←/⌘→ previous/next in Up Next.
- The "…" menu (also on right-click) starts with **Close** and **Pin**, then Tile Windows (with 2+ players), Add to Favourites, Up Next, playback modes, downloads, and copy/open link.
- **Positions.** The first window reopens where the last one was. More windows open beside the existing ones (and the music window), never on top of them while there's room, otherwise they cascade. **Tile Windows** sorts all players into a grid that fills the screen, each as big as fits at 16:9, keeping their order.
- **The first video takes the panel's place** and the panel hides; click the menu-bar icon to bring it back.
- **Drop a link or file** on a player to replace what it's playing, or on the menu-bar icon to open a new one.
- App Nap is turned off while something plays.

## Music, podcasts and Now Playing

While Music, Spotify, Podcasts or another audio app plays (or is paused), the list starts with a **Now Playing** row: artwork, the title, and *artist · app*. Click it (or **⤢**) to open the artwork in a floating window.

- The window follows the music: the next track's artwork cross-fades in without taking focus. **Only music changes it.** A video, in a browser tab or a Watch player, never replaces the song.
- Hover anywhere for the caption and "…". Rest the pointer on the caption, or just above it, and one row of controls slides in: **⏮ ⏯ ⏭**, a timeline with elapsed and remaining time (drag to seek), **shuffle**, **repeat**, and the volume. In a small window, the elapsed time drops out first, then shuffle and repeat, then the volume slider, then the star.
- For Music and Spotify, shuffle, repeat and volume set **that app's own** settings (Music's repeat goes off → all → this song; Spotify's is on/off). macOS asks once, on your first click. Other music apps are controlled only while they hold the system's Now Playing slot, otherwise the buttons dim.
- **★ (Apple Music only):** the star next to shuffle favourites the playing song in Music itself. It happens in the background (Music doesn't come forward) and the star shows Music's real state, read when the controls appear and when the song changes. It is separate from Watch's own Favourites (right-click ▸ Add to Favourites). Spotify has no star: its scripting has no way to like a song.
- **Volume:** the slider is always hidden. Rest the pointer on the speaker and it slides out to its left (the speaker stays under the pointer); it tucks away shortly after the pointer leaves. Click the speaker to mute or unmute. Press and drag sideways on the speaker (or on the slider, anywhere along it) to change the volume from wherever it is now, as in Apple Music: the pointer doesn't have to be on the slider and the volume doesn't jump. Video windows work the same way.
- Watch only acts on another app when you click. It reads Now Playing information only while the panel or the artwork window is open (or while the menu-bar ticker is on).
- **Clicks:** a click anywhere plays or pauses (after about a third of a second, so a double-click doesn't also toggle). A quick double-click (within 0.3 s) opens the music in its app. A double-click near the far left or right edge skips 10 seconds. Space, ←/→ and F work too.
- Right-click or "…": **Copy · Save…** (the original image, named *Artist – Album*) · **Open in Preview** · **Search YouTube for this song** · **Show ‹App›**. Esc closes.
- **Full screen** (**F**, **⌃⌘F**, or the menu): the artwork sits over a gradient of its own colours, or black (…▸ Full-Screen Background). The title, "…" and pointer fade after a couple of idle seconds. **Click and drag** anywhere to resize the picture: drag away from its centre to grow it, towards the centre to shrink it (from a quarter of the usual size up to filling the screen). As it nears the full height the caption and controls slide down and fade, and when it fills the screen from top to bottom they're gone; make it smaller and they come back. The size is remembered. A plain click still plays or pauses.
- Turn the row off with **Preferences ▸ Show what's playing in other apps**.
- **Menu-bar ticker** (**Preferences ▸ Show the playing song and artist in the menu bar**, off by default): one small line, "Song – Artist", next to Watch's icon so you can glance at what's playing. Text that fits stands still; longer text rests, then scrolls leftwards like iTunes's display, in a window up to 150 pt wide. Paused songs show dimmed and still, as does everything with Reduce Motion on. It disappears when nothing is playing, and clicking it does what the icon does. While it is on, Watch reads Now Playing in the background all the time.

**Podcasts.** Search Apple's podcast directory from the Podcasts tab (no account). Pick a show, or paste an Apple Podcasts show link or a feed, to see its episodes newest first, with date, length, a resume bar and ✓. Episodes play in the music window, resume where you left off, and get a ✓ when finished (right-click to Mark as Played). **+** adds one to Up Next, **↗** opens it in Apple Podcasts, **⬇** downloads it. Pasted episode links work the same and show up in Recent Links.

**Your Music library.** The Music tab searches songs in the Music app (names, artists, albums). Click one to play it in Music, or **+** to add it to Up Next. Watch only looks while Music is open and you've allowed it; otherwise the tab offers **Open Music** or **Allow…**.

## Up Next

Every player window has a list it can walk through with **Previous (⌘←)** and **Next (⌘→)** in the "…" menu, which also shows **Next: ‹title›** and the whole list under **Up Next ▸** (click a row to jump). Where the list comes from:

- the page you clicked the video from (search results, History, a playlist, Favourites);
- the playlist a `list=` link carries;
- for a lone video, what youtube.com itself would play next (its autoplay pick, then the sidebar recommendations, topped up as you go);
- for a local file, the other media files in its folder.

Under it are **Autoplay** (on by default), **Repeat All**, **Repeat One** and **Shuffle**. They're per window, and a new window starts with your last choice. Pasting a playlist link plays it straight away.

**The shared queue.** The music window has a list that drops down under it (the **≡** button, **⌥⌘U**, or its menu). It shows **Now Playing**, **Playing Next**, the rest, **Then: Continue in Music/Spotify**, and a collapsed **History**.

- Add with **Play Next** / **Play Later** from any row's right-click menu, or its **+** button (⌥-click = Play Next); **⌥Return** in the field; several files or links dropped on the menu-bar icon (or one with ⌥); drops on the list itself; or `glasskit-watch://queue?url=…`.
- It mixes YouTube and other sites (they open in a video window beside the music window when their turn comes), audio files and direct audio links (played by Watch in the music window, with their own tags and artwork), podcast episodes, and Spotify songs and episodes (played by the Spotify app; Spotify albums and playlists just open in Spotify).
- If Music or Spotify is playing when you add something, Watch waits for the current song to end, pauses that app, plays your items, and when the list runs out the app carries on with its own queue. (Apple doesn't let other apps see Music's queue.) macOS asks once for Watch to control that app.
- Drag rows to reorder, ⌫ removes, double-click or Return plays a row, **Clear** removes what you added. If you pick something else in Music or Spotify yourself, Watch lets go and the list shows **Resume**.
- The queue is kept when you close the music window or quit: the list offers **Up Next from before ▸ Resume**.

**Video windows** can show their own list too: **⌥⌘U** or **Show Up Next List** in the "…" menu. It's that window's list (playlist, search results, folder or YouTube's next videos); drag to reorder, ⌫ removes, double-click plays, and you can drop videos, files or links on it to play them next in that window.

## Downloads

⬇ is on every player window (and its "…" menu), beside the field, and on every search, History and playlist row.

- **Video:** **Original** (the source file type and codecs, untouched, e.g. WebM/VP9/Opus) or **MP4 (Highest Quality)** (top resolution, e.g. 4K; kept as is when it's H.264 or HEVC, otherwise converted to HEVC on the Mac's hardware encoder at the source bit rate so QuickTime can play it).
- **Audio:** **Original Audio** (no re-encode) or **MP3 (Source Bit Rate)** (the source's bit rate, rounded up to a valid MP3 rate).
- **More ▸** has compatible H.264 MP4 (≤1080p), 1080/720/480p caps, M4A, and an **Advanced Formats** list of exact yt-dlp formats. Whole playlists go into their own folder, and the Playlists page has **Download All**.
- Up to 3 downloads run at once; the rest wait as **Queued**. Rows show **Converting…** while FFmpeg re-encodes. Live streams can be **recorded**; Stop finalizes the file.
- Progress is in the panel's **Downloads** list; click a finished row to reveal it in Finder. Files go to the folder set in Preferences (default `~/Downloads`), or, with **Ask where to save each download** on, to a folder you pick each time.

## Around macOS

- **Media keys and Control Center.** Whatever Watch plays (a video window, or a song, file or podcast in the music window) shows in Now Playing with its picture, and the media keys, AirPods and headphone buttons play/pause, skip and scrub it. When only Music or Spotify is playing, the keys stay theirs.
- **Music pauses for your videos.** If Music or Spotify is playing when you start something in Watch, Watch pauses it, and plays it again when you close Watch's videos. Both are on by default in Preferences ▸ General.
- **Finder ▸ Open With ▸ Watch.** A video plays in a window; audio files, folders or several files go to Up Next. Watch never makes itself the default app.
- **Hotkey** ⌥⌘Y opens the panel. If a video link is on your clipboard and **Clipboard plays on hotkey** is on (the default), it plays that link instead.
- **URL scheme.** `glasskit-watch://play?url=<percent-encoded link>` plays a link from any app or script; `glasskit-watch://queue?url=…` adds one to Up Next.
- **Browser tabs.** Watch lists videos playing in Safari, Chrome, Brave, Edge and Arc, using AppleScript and in-page JavaScript. It only talks to browsers that are running and have already allowed it. **Preferences ▸ Allow Browser Access…** asks macOS once per running browser, and detection can be switched off there. Each browser also needs "Allow JavaScript from Apple Events" (Develop or View menu).

## What's in the app

yt-dlp (with Python and EJS), FFmpeg, ffprobe and Deno are bundled, so there's no setup. They update when you replace Watch with a newer release. On first launch a short guide offers **Start Watching**, an optional YouTube connection, and a check of the bundled tools (rerun it under Preferences ▸ Setup Guide).

## Limits

- Browser-tab detection covers browsers only. Music, Spotify, TV, QuickTime and VLC rows were removed in 3.3 because they triggered Automation prompts. The Now Playing row shows what those apps play, with artwork, without Automation, but doesn't play it in Watch.
- Some sites block yt-dlp from certain networks (Vimeo sometimes returns a 403). Those fall back to loading the page.
- In-window YouTube caps at 1080p (H.264). 1440p and 4K are VP9 or AV1 only; download them instead.
- Up Next's recommendations aren't personalised. They're read from the public watch page, not your account, so if YouTube reshapes that page, Next has nothing to go to until Watch is updated. Lists you played from keep working.
- Now Playing relies on a workaround (the system's perl loading the bundled mediaremote-adapter) for the limit macOS 15.4 put on reading Now Playing information. If a later macOS closes it, the row stops appearing.
- Music library search only covers songs in your library, not the Apple Music catalogue, and lists the first 50 matches.
- Podcasts: paid (Apple Podcasts Subscriptions) and private feeds aren't playable. A show page lists the newest 200 episodes. Apple Podcasts' own library and listening history aren't read.
- Builds are ad hoc signed and not notarized (see the README for the first-launch steps).

## Changelog

- **3.26.** A ★ on the music window for Apple Music (favourites the song in the background), an optional one-line scrolling song name in the menu bar, a volume slider that stays hidden until you rest on the speaker (click to mute, drag from the speaker to change it), and a full-screen picture you can resize by dragging, with the caption sliding away when it fills the screen.
- **3.25.** Now Playing artwork window with its own controls, podcasts, Music library search, one Up Next queue under the music window (and a list in each video window), media keys and Control Center, Finder's Open With, YouTube always plays natively with a proper error card, quality that follows the window size, a volume slider in video windows, and windows that open beside each other. Builds 3.19 to 3.24 were development steps toward this and were never released on their own. See [the release notes](releases/v3.25.md).
- **3.18.** First release from this repository, under MIT, with its own build, test and package scripts.
- **3.17.** Self-contained installer: pinned universal yt-dlp, FFmpeg, ffprobe and Deno inside the app, a first-run guide, optional YouTube connection, bundled notices and sources. Tools update by replacing the app.
- **3.16.** Recent Links and Favourites list in full inside the same 320×250 panel. Live search: typing searches after 350 ms, Return searches at once without duplicating the request, edits cancel obsolete work.
- **3.15.** Watched marks, Favourites (replacing Recent Links pins), a "Resumed at…" chip, and playlists that carry on where you left off. Resume lands within half a second instead of snapping to a keyframe.
- **3.14.** Click zones on the player, a bigger playback bar with ⟲10 / ⟳10, skips that land where they should.
- **3.13.** Player menu starts with Close and Pin. Picture in Picture removed (players already float). Tile Windows added.
- **3.12.** Smaller thumbnails in Recent Links, pins, and ↗ Open in YouTube on every row.
- **3.11.** Search and paste merged into one field. Recent Links redesigned as thumbnail rows, one per video, and only video links are kept. Sturdier search: Show More, a 25 s timeout, a 10-minute cache, Try Again.
- **3.10.** Every video resumes where you left it. A shorter panel, and the first video takes the panel's place.
- **3.9.** MP3 downloads probe the source bit rate once.
- **3.8.** Up Next for player windows: Previous/Next and Autoplay, Repeat All, Repeat One and Shuffle.
- **3.7.1.** Tube retired; its settings were copied into Watch.
- **3.7.** Download choices reworked into Video (Original / MP4 highest quality) and Audio (Original / MP3). Ask where to save each download. New app icon.
- **3.6.** Tube's features folded in: YouTube search, History and Playlists in the panel, sign-in under Preferences, more download formats and a queue, a welcome guide.
- **3.5.** The panel always opens under the menu-bar icon. Player windows remember their position and size.
- **3.4.** Tiny players (down to 68×38) on a bare AVPlayerLayer with a custom hover bar.
- **3.3.** No more surprise permission popups from browser detection. Every link plays natively in AVKit, with an instant window. In-app downloads and live recording.
- **3.2.** `glasskit-watch://play` URL scheme.
- **3.1.** More reliable YouTube playback, ⌘V into the field, ⌘D to duplicate a player, drop-to-replace.
- **3.0.** Rebuilt from a YouTube-only mini player into an any-video player with a control panel, multiple tiled windows, drag and drop, and link history.
- **2.x and 1.x.** A menu-bar mini player that mirrored your browser's current video, and before that a tabbed in-window YouTube browser.
