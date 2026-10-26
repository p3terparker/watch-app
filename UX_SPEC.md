# Watch 3.16: full recent list and live search

Requested 2026-10-22. Keep the existing compact panel and make its everyday actions immediate.

- Open at the existing 320×250 size. Recent Links and Favourites contain their full stored lists from the start, inside the existing scroll area. Remove All/Less and automatic expansion resizing. The field remains pinned; manual resizing continues to work. Reopening starts at the top of the list.
- Typing ordinary search text immediately filters local links, then searches YouTube after a 350 ms pause, including one-character queries. Replace the results for the previous query; keep focus in the field. Return bypasses the delay; it must not duplicate an already running/completed search for the same query.
- Cancel the pending debounce and invalidate the old request as soon as the text changes. Late completions cannot redraw the page or populate the cache. Clearing with the × button or Escape returns to the full list. Back, opening another page, hiding the panel, or playing a result cancels pending work.
- Links, playlist links and local paths require Return or an explicit click; typing/pasting them never starts playback, downloads or an automatic YouTube search. Wait for input-method composition to finish. Arrow-key selection of a local match cancels the pending automatic search so it is not replaced mid-selection. Existing Return-to-play, cached results, Show More, timeout and retry behavior remain available.
- Store only explicitly submitted searches in the recent-search menu, not each typing pause. Preserve bundle ID, preferences, link library and playback state.

Acceptance: deterministic debounce/cancellation checks; isolated AppKit fixtures with more rows than fit, last-row scrolling and constant window size; rapid edits with deliberately late results; clear/Back/hide cancellation; immediate Return without a duplicate; URLs, local paths and input composition; keyboard selection, empty/error/cache states. Build and verify a universal arm64/x86_64 DMG with setup instructions. Local signing is separate from notarization and Intel/older-macOS runtime acceptance.

## Watch 3.17: self-contained friend installer

- Ship universal, pinned yt-dlp (including Python and EJS), FFmpeg, ffprobe and Deno in `Contents/Helpers`. Resolve only those tools, pass explicit runtime/FFmpeg paths, ignore external yt-dlp configuration/plugins and disable remote component fetching. Never rely on Homebrew or a shell login environment.
- Build FFmpeg/LAME from verified source for both architectures with only Apple system dynamic libraries. Record source hashes, bundled executable hashes, notices and source archives. Sign helpers before the containing app and verify the final mounted image.
- Replace helper self-update with whole-app replacement instructions. Never mutate executables inside a signed application. Preserve preference keys, libraries, bundle ID and hotkey.
- First launch shows a scrollable native guide: Start Watching, optional browser-based YouTube connection, asynchronous local tool checks, recovery through app replacement, optional browser-tab permissions and notices. The installer has a short text guide. No Terminal setup steps.
- Public search does not need an account. Browser cookie access remains an explicit optional connection and may require Keychain/Full Disk Access approval. Do not package or test with personal cookies. Do not promise History/restricted-video access across upstream changes.
- Acceptance: isolated UI checks; helper path/environment and missing-tool tests; real tools from a relocated path with spaces and a clean HOME/PATH; generated local HTTP media download, MP3 conversion, video/audio merge, Deno execution; live public search; universal architecture/dependency/signature/receipt checks; read-only DMG validation. Developer ID notarization and real Intel/macOS 13 acceptance are separate remaining gates.
