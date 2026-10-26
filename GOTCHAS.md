# Watch gotchas

## Watch

> **Live search must invalidate at the keystroke, not when the debounce fires** *(Watch · 2026-10-26)*
> A prior search can complete during the 350 ms pause and render results for text no longer in the field.
> `fieldTextChanged` immediately increments `browseToken`, cancels the task, and clears its page; both
> cache writes and rendering check that token. `LiveSearch` has a separate cancellation revision for queued
> debounce callbacks. Return cancels that timer and reuses an already running/completed query. Clear/Back/hide
> cancel it too, so a hidden or cleared panel cannot sprout a new search later. The isolated panel harness
> deliberately delivers cancelled responses to exercise this boundary. Process launch also shares the task
> cancellation lock: previously cancellation could fall between attaching a process and starting it, leaving
> that obsolete search running until its timeout.

> **"Skip 10 s" landed seconds away from where it should** *(Watch · 2026-09-28)*
> **Problem:** a skip back from 50 s landed at 41.7 s instead of 40 s; skips felt random.
> **Cause:** `AVPlayer.seek(to:)` uses the default (infinite) tolerance and snaps to a keyframe; x264 GOPs are often
> 8+ s apart.
> **Fix:** `seek(to:toleranceBefore:toleranceAfter:)` with a small tolerance (0.5 s) for skips. Also stack rapid skips
> on the last *target* — `currentTime()` still reports the old time while a seek is in flight.
> **Same bug in the resume seek (3.15):** a 40 s x264 clip saved at 0:20 resumed at 0:16.7 (keyframes every 16.7 s) while
> the new "Resumed at 0:20" chip claimed otherwise. The start/resume seek in `playAsset` now uses the same ±0.5 s
> tolerance. Any `seek(to:)` whose target the user sees needs an explicit tolerance.

> **"Unable to type-check this expression in reasonable time" on simple CGRect code** *(Watch · 2026-09-27)*
> **Problem:** a Foundation-only helper file (`Tiling.swift`) using `rect.midX` / `insetBy` failed to compile with the
> type-checker timeout error on short sort closures; SourceKit also said `CGRect` has no `insetBy`.
> **Cause:** `import Foundation` exposes the `CGRect` struct but not CoreGraphics' Swift overlay (`midX`, `insetBy`, …),
> so the solver failed to resolve those members and reported it as a timeout.
> **Fix:** add `import CoreGraphics` to any non-AppKit source file that does rect geometry.

> **YouTube embed errors 153 / 152 / "15x"** *(Watch · 2026-06-22)*
> **Problem:** YouTube embeds throw "video player configuration error" / refuse to play.
> **Cause (153):** loading `/embed/<id>` as a **top-level document** — YouTube rejects it.
> **Fix:** host the player in an `<iframe>` on a **`youtube.com` origin** via
> `loadHTMLString(…, baseURL: https://www.youtube.com/)`, built with the **IFrame Player API** under a
> desktop-Safari UA. Some videos/networks still throw 15x (YouTube flagging the session — reproducible in
> plain Safari, not a Watch bug); Watch **auto-falls back to a yt-dlp-resolved direct stream in AVPlayer**.

> **Unfocused player window stutters during playback** *(Watch · 2026-06-22)*
> **Cause:** macOS **App Nap** throttles a background/unfocused app.
> **Fix:** hold a `ProcessInfo.beginActivity(options:[.userInitiated,.idleSystemSleepDisabled], reason:)`
> token while something is actively playing; release it on stop.

> **"Where is Brave Browser?" choosers + Automation prompts on opening the panel** *(Watch · 2026-09-12)*
> **Problem:** opening Watch's panel popped app-chooser dialogs and "Watch wants to control Music/Spotify/…"
> prompts for apps Jacob doesn't use.
> **Cause:** `NSAppleScript` compiles `tell application "Brave Browser"` even when the body starts with
> `if not running` — an **uninstalled** app name pops the "Choose Application" sheet (evidence: the
> `OSAStandardAdditions ChooseApplication Bounds` key in Watch's defaults), and any installed target triggers
> the Automation consent prompt on first send.
> **Fix:** filter by `NSWorkspace.runningApplications` bundle ids first, address apps as
> `tell application id "<bundle id>"`, and gate every script on
> `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: false)` (`noErr` = granted, `-1744` = would
> prompt). Only a user-initiated button calls it with `true`. Dropped probes whose results were never usable.

> **Blank band at the top of a short scroll panel, content flush left** *(Watch · 2026-09-25)*
> **Problem:** after shortening the control panel, its content sat ~60 pt down with empty space above it and
> lost its 14 pt left inset; the bottom rows were cut off.
> **Cause:** the `NSStackView` was the scroll view's `documentView` directly, positioned by offset
> constraints (`leading +14`, `top +10`) to the clip view. Harmless while the content fit (520 pt panel);
> once it was taller than the clip view, the unflipped document was scrolled to its own origin, which the
> offsets had shifted.
> **Fix:** make the document a **flipped** `NSView` pinned to the clip view at **zero** (leading/trailing/top),
> put the stack inside it with the padding and a bottom constraint, and scroll to `.zero` when showing.

> **AVPlayer takes ~45 s to start a remote YouTube DASH file** *(Watch · 2026-09-12)*
> **Problem:** composing YouTube's separate 1080p video + m4a audio URLs in an `AVMutableComposition` played
> fine, but `loadTracks` took 40–45 s.
> **Cause:** YouTube's DASH files are **fragmented MP4**; AVFoundation reads every `moof` of a remote fMP4
> before reporting tracks/duration — i.e. it streams the whole file first.
> **Fix:** don't hand AVFoundation the files — read each file's `sidx` (first 64 KB), emit an HLS VOD playlist
> with `EXT-X-MAP` + `EXT-X-BYTERANGE` segments pointing at the real URL, plus a master playlist with an audio
> group; serve the playlists from memory via an `AVAssetResourceLoaderDelegate` custom scheme. Starts in ~2 s,
> seeks instantly (`DashHLSBridge`). Live streams: use the format's `manifest_url` (newer yt-dlp no longer puts
> it top-level).

> **Everything YouTube 403s after ~20 MB (playback and yt-dlp's own downloads)** *(Watch · 2026-09-12)*
> **Problem:** stream URLs worked for the first chunks, then `HTTP 403`; `yt-dlp` downloads failed too.
> **Cause:** a **stale yt-dlp** (2026.06.09, >90 days) — YouTube changed client requirements.
> **Historical fix:** `brew upgrade yt-dlp` (2026.08.19). Current Watch bundles its tools; replace the app to update them. The former menu / Preferences
> / optional before each download). When YouTube playback or downloads suddenly fail, update yt-dlp first.

> **Player window won't shrink below ~130 pt tall; black bars appear instead** *(Watch · 2026-09-17)*
> **Problem:** with `minSize` lowered to 68×38, dragging the player smaller shrank the width but the height
> stopped, so the 16:9 video letterboxed inside a too-tall window.
> **Cause:** `AVPlayerView` with `controlsStyle = .floating` adds ~430 internal Auto Layout constraints once
> media loads, pinning the view to ≥130–141 pt tall (`fittingSize` 473×141). The window's `minSize` doesn't
> override that. `.none` has no such constraints (`fittingSize` 0×0).
> **Fix:** drop `AVPlayerView`. Render through a view whose backing layer is an `AVPlayerLayer`
> (`PlayerVideoView`), draw custom controls with frame-based layout, and do PiP with
> `AVPictureInPictureController(playerLayer:)`. Check it headlessly: put the window offscreen at `alphaValue = 0`,
> let media load, then print `contentView.fittingSize`. Any height above 0 means something is setting a floor.

> **Menu-bar panel reopens near the bottom of the screen instead of under its icon** *(Watch · 2026-09-17)*
> **Problem:** Watch's control panel kept opening at the bottom-left of the screen.
> **Cause:** `windowDidMove` flagged the panel `detached` and persisted its frame on *any* move, not only user
> drags, and `togglePanel` restored that frame. A non-user move saved `{{51, 0}, …}` (y = 0 = screen bottom).
> **Fix:** always anchor under the status item on open, and treat a move as a detach only while the mouse button
> is down (`NSEvent.pressedMouseButtons & 1 != 0`). Don't persist tray-panel frames. Check stale state with
> `defaults read <bundle-id>`.

> **Panel's ••• menu pops up at the bottom of the panel** *(Watch · 2026-09-17)*
> **Problem:** the ••• menu opened at the panel's bottom-left corner, far from the button.
> **Cause:** `menu.popUp(positioning:at:in:)` took `NSPoint(0,0)` in the panel's content view. That view isn't
> flipped, so (0,0) is its bottom-left.
> **Fix:** pop the menu in the button's own coordinates, at `NSPoint(x: 0, y: button.bounds.height + 4)`
> (`NSButton` is flipped, so this lands just below the button).

> **First-launch window never shows up** *(Watch · 2026-09-17)*
> **Problem:** the Welcome window got created on first launch, but the user never saw it.
> **Cause:** an `LSUIElement` app launched in the background can be refused activation
> (`NSApp.activate(ignoringOtherApps:)` doesn't force it on macOS 14+). `makeKeyAndOrderFront` then orders the
> window front only within the inactive app, which leaves it behind the frontmost app's windows.
> **Fix:** call `window.orderFrontRegardless()` as well, for windows the user has to see unprompted.

> **"MP4, highest quality" 4K downloads won't play in QuickTime** *(Watch · 2026-09-17)*
> **Problem:** picking the top resolution and merging to `.mp4` gives a file QuickTime/Finder preview can't play.
> **Cause:** YouTube serves 1440p/4K only as VP9 (even the `ext=mp4` m3u8 variants, e.g. format 628) or 10-bit
> AV1 HDR; macOS has no VP9 file playback and AV1 decode only on M3+. The mp4 container is valid, the codec isn't.
> **Fix:** probe with `yt-dlp -j` first; if the chosen video codec isn't H.264/HEVC, merge to mkv and
> `--recode-video mp4 --postprocessor-args "VideoConvertor:-c:v hevc_videotoolbox -b:v <src vbr>k -tag:v hvc1 -c:a copy"`.
> (`--recode-video` skips files already in mp4, so the merge must not target mp4.) Prefer SDR (`-S hdr:sdr`).

> **"Play what YouTube would play next" can't come from yt-dlp** *(Watch · 2026-09-19)*
> **Problem:** building an autoplay/Up Next queue for a single video. yt-dlp has no "related videos" output, and
> the obvious stand-in — the auto-generated mix, `watch?v=<id>&list=RD<id>` — **only exists for music videos**.
> `yt-dlp --flat-playlist -J` on a mix returns 25+ entries for a music video and **0** for anything else (it
> silently falls back to the single video), so a queue built on it works right up until you try it on a talk.
> **Cause:** mixes are a YouTube Music feature; ordinary videos only have the watch page's own autoplay target
> and sidebar recommendations.
> **Fix:** fetch the watch page (desktop-Safari UA, `Cookie: SOCS=CAI` to skip the EU consent interstitial) and
> read `var ytInitialData`: `…twoColumnWatchNextResults.autoplay.autoplay.sets[0].autoplayVideo.watchEndpoint.videoId`
> is exactly what the site would roll into, and `…secondaryResults` holds the rest. Today's entries are
> `lockupViewModel` (`contentId` + `metadata.lockupMetadataViewModel.title.content`), not the older
> `compactVideoRenderer` — walk the subtree for both shapes rather than a fixed path, and treat an empty result
> as "no recommendations" so a YouTube redesign degrades instead of breaking playback.

> **A menu key equivalent outranks the text field the user is typing in** *(Watch · 2026-09-19)*
> **Problem:** wiring ⌘←/⌘→ (previous/next) as `NSMenuItem` key equivalents on the **main menu** would steal
> them from every text field in the app — `performKeyEquivalent:` runs before `keyDown:`, so "move to start/end
> of line" in the panel's search/paste field would stop working.
> **Fix:** put the shortcut where it belongs to one window — the player's own `keyDown` path
> (`PlayerSurfaceView.onKey` → `handleKey`, checking `.command`) — and set `keyEquivalent` on the *pop-up* menu
> items for display only. (The alternative is `validateMenuItem` disabling the item whenever a field editor is
> first responder; a window-scoped handler is simpler.)

---

*(Add new entries above as they happen.)*

> **Retiring an app can silently sign out a sibling that reads its prefs** *(Watch/Tube · 2026-09-19)*
> **Problem:** Deleting Tube's `com.jacob.tube.plist` would have reset Watch's YouTube sign-in (account, cookie browser, profile).
> **Cause:** Watch 3.6 read unset keys from `UserDefaults(suiteName: "com.jacob.tube")` as a migration fallback, so Tube's prefs were live Watch state.
> **Fix:** Before trashing an app's prefs, `grep -rn 'suiteName: "com.jacob.<app>"'` across the suite; copy any borrowed keys into the reader's own domain (`defaults write`), then drop the fallback code.

> **Unknown metadata is still a completed probe** *(Watch · 2026-09-20)*
> **Problem:** the MP3 downloader used nil bitrate to mean both “not probed” and “probe returned no bitrate,” so the fallback could never run.
> **Fix:** track probe completion independently of the optional value; missing bitrate proceeds to quality 0. Test the actual queue with a fake process boundary, including cancel-before-callback.

> **An NSSearchField's ✕ button sends its action too — with an empty string** *(Watch · 2026-09-25)*
> **Problem:** Watch 3.11 merged search and paste into one `NSSearchField` where Return on an **empty** field plays
> the copied link. Wired to the field's action, clicking the field's ✕ (clear) button would have started a video.
> Separately, AppKit records every string the field sends as its action in its built-in recent searches, so
> pasted links would have ended up in the magnifier menu.
> **Cause:** with `sendsWholeSearchString`, the action fires on Return *and* on the cancel button (value `""`).
> **Fix:** handle Return, ↑/↓ and Esc in the delegate's `control(_:textView:doCommandBy:)` (return `true`, so the
> field never sends its action for Return); the action itself only refreshes the list after ✕. Turn off
> `sendsActionOnEndEditing`. Recent searches come from our own store (`RecentSearches`) rendered into
> `searchMenuTemplate` as plain items, so only real queries are ever remembered.

> **List rows narrower than the controls above them; accessory buttons drift left** *(Watch · 2026-09-25)*
> **Problem:** in the redesigned panel the Recent Links rows ended ~15 pt short of the field row, and a row with a
> short title had its ⬇ button right after the text instead of at the trailing edge.
> **Cause:** (1) with a mouse attached (or "Show scroll bars: Always"), `NSScrollView` uses **legacy scrollers**, which
> reserve their track width even when nothing scrolls unless `autohidesScrollers` is on. (2) A horizontal
> `NSStackView(views:)` defaults to `.gravityAreas` distribution, so its views cluster at the leading edge.
> **Fix:** `autohidesScrollers = true` on panel scroll views; rows use `distribution = .fill` with the text column's
> hugging priority low, so it takes the free width. Checked by rendering the panel offscreen
> (`layer.render(in:)` after `display()` — `cacheDisplay` skips layer-only properties like background colors).

---


## Watch 3.17 — bundled helper updates and local dependency masking

Never run yt-dlp `-U` or Homebrew updates against a bundled executable: mutating it invalidates the app signature. Watch updates helpers through whole-app replacement. Testing with a developer PATH can hide missing FFmpeg/Deno; use `MediaTools` and the clean-HOME relocated fixture in `Tests/bundled.py`. Pin helper/source hashes, reject non-system dylibs, sign child executables before the app, and validate the mounted DMG. Deno 2.9.8 has no `--license` option; extract supplied notice files from the pinned source archive instead.

The resizable first-run guide must update each wrapping label's `preferredMaxLayoutWidth` to the stack's current width. Keeping the initial fixed width makes short labels silently lose their second line at smaller sizes. `GuideStackView.layout` and the small-guide/last-action fixture cover this.
