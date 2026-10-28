// ============================================================================
// Watch — "plays any video" menu-bar player  (v3, reworked from the YouTube-only mini-player)
// ----------------------------------------------------------------------------
// Click the menu-bar icon (or ⌥⌘Y) for a small control panel with one field: type to search YouTube,
// or paste any video link (YouTube, live streams, or anything yt-dlp can resolve) and press Return.
// Below it: Recent Links (copied and played videos, with resume bars), downloads, and the videos
// open in your browser tabs. Drop a link or file onto the menu-bar icon to play it; copy a video
// link and press the hotkey to play it immediately; download any video or its audio.
// Everything plays natively in AVKit: yt-dlp resolves the stream, YouTube's split HD video+audio
// is bridged into an HLS playlist, live streams use their HLS manifest. The YouTube IFrame embed
// is only a fallback for when yt-dlp can't resolve a link.
// Standalone native macOS app; built with swiftc and locally ad-hoc signed.
// ============================================================================

import Cocoa
import WebKit
import Carbon
import ServiceManagement
import AVKit
import AVFoundation

// ----------------------------------------------------------------------------
// MARK: - Settings
// ----------------------------------------------------------------------------
enum Prefs {
    static let d = UserDefaults.standard
    static var hotkeyKeyCode: UInt32 { get { UInt32((d.object(forKey: "hotkeyKeyCode") as? Int) ?? Int(kVK_ANSI_Y)) } set { d.set(Int(newValue), forKey: "hotkeyKeyCode") } }
    static var hotkeyCarbon: UInt32 { get { UInt32((d.object(forKey: "hotkeyCarbon") as? Int) ?? Int(cmdKey | optionKey)) } set { d.set(Int(newValue), forKey: "hotkeyCarbon") } }
    static var hotkeyDisplay: String { get { d.string(forKey: "hotkeyDisplay") ?? "⌥⌘Y" } set { d.set(newValue, forKey: "hotkeyDisplay") } }
    static var detached: Bool { get { d.bool(forKey: "detached") } set { d.set(newValue, forKey: "detached") } }
    static var pinned: Bool { get { d.bool(forKey: "pinned") } set { d.set(newValue, forKey: "pinned") } }
    static var downloadDir: String { get { d.string(forKey: "downloadDir") ?? (NSHomeDirectory() + "/Downloads") } set { d.set(newValue, forKey: "downloadDir") } }
    static var askDownloadDir: Bool { get { d.bool(forKey: "askDownloadDir") } set { d.set(newValue, forKey: "askDownloadDir") } }
    static var autoUpdate: Bool { get { d.object(forKey: "autoUpdate") as? Bool ?? false } set { d.set(newValue, forKey: "autoUpdate") } }
    static var hotkeyPlaysClipboard: Bool { get { d.object(forKey: "hotkeyPlaysClipboard") as? Bool ?? true } set { d.set(newValue, forKey: "hotkeyPlaysClipboard") } }
    static var launchAtLogin: Bool { get { d.object(forKey: "launchAtLogin") as? Bool ?? true } set { d.set(newValue, forKey: "launchAtLogin") } }
    static var hasSeenWelcome: Bool { get { d.bool(forKey: "hasSeenWelcome") } set { d.set(newValue, forKey: "hasSeenWelcome") } }
    static var showBrowserTabs: Bool { get { d.object(forKey: "showBrowserTabs") as? Bool ?? true } set { d.set(newValue, forKey: "showBrowserTabs") } }
    static var showFavourites: Bool { get { d.bool(forKey: "showFavourites") } set { d.set(newValue, forKey: "showFavourites") } }  // the panel's list tab
    // The panel's Now Playing row (what other apps are playing, with its artwork — NowPlaying.swift).
    static var showNowPlaying: Bool { get { d.object(forKey: "showNowPlaying") as? Bool ?? true } set { d.set(newValue, forKey: "showNowPlaying") } }
    // Full-screen artwork backdrop: a gradient of the artwork's colours (default) or black.
    static var artworkColourBackground: Bool { get { d.object(forKey: "artworkColourBackground") as? Bool ?? true } set { d.set(newValue, forKey: "artworkColourBackground") } }
    // Playback modes. Each player window keeps its own (its "…" menu toggles them); these are what a NEW
    // window starts with, i.e. the last choice made anywhere.
    static var autoplay: Bool { get { d.object(forKey: "autoplay") as? Bool ?? true } set { d.set(newValue, forKey: "autoplay") } }
    static var repeatMode: String { get { d.string(forKey: "repeatMode") ?? "off" } set { d.set(newValue, forKey: "repeatMode") } }  // off | all | one
    static var shuffle: Bool { get { d.bool(forKey: "shuffle") } set { d.set(newValue, forKey: "shuffle") } }
    // YouTube sign-in (History / Playlists read the browser's YouTube cookies).
    static var cookieSource: String { get { d.string(forKey: "cookieSource") ?? "chrome" } set { d.set(newValue, forKey: "cookieSource") } } // auto | safari | chrome
    static var youtubeAccount: String { get { d.string(forKey: "youtubeAccount") ?? "" } set { d.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "youtubeAccount") } }
    // "Signed in" = Watch may read the browser's YouTube session. Sign Out just turns this off (the browser stays
    // signed in).
    static var youtubeConnected: Bool { get { d.object(forKey: "youtubeConnected") as? Bool ?? false } set { d.set(newValue, forKey: "youtubeConnected") } }
    static var cookieBrowserName: String { cookieSource == "safari" ? "Safari" : (cookieSource == "chrome" ? "Chrome" : "Safari or Chrome") }
    static var browserProfile: String { get { d.string(forKey: "browserProfile") ?? "Default" } set { d.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "browserProfile") } }
}

func carbonModifiers(from f: NSEvent.ModifierFlags) -> UInt32 {
    var m: UInt32 = 0
    if f.contains(.command) { m |= UInt32(cmdKey) }
    if f.contains(.option)  { m |= UInt32(optionKey) }
    if f.contains(.control) { m |= UInt32(controlKey) }
    if f.contains(.shift)   { m |= UInt32(shiftKey) }
    return m
}
func keyName(_ keyCode: UInt16, _ chars: String?) -> String {
    let map: [UInt16: String] = [49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑"]
    if let n = map[keyCode] { return n }
    if let c = chars, !c.isEmpty, c != " " { return c.uppercased() }
    return "Key\(keyCode)"
}
func shortcutDisplay(_ f: NSEvent.ModifierFlags, _ keyCode: UInt16, _ chars: String?) -> String {
    var s = ""
    if f.contains(.control) { s += "⌃" }; if f.contains(.option) { s += "⌥" }
    if f.contains(.shift) { s += "⇧" }; if f.contains(.command) { s += "⌘" }
    return s + keyName(keyCode, chars)
}
func sym(_ name: String) -> NSImage { NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage() }
func makeGlassContentView() -> NSVisualEffectView {
    let v = NSVisualEffectView()
    v.material = .sidebar
    v.blendingMode = .behindWindow
    v.state = .active
    v.appearance = NSAppearance(named: .vibrantDark)
    return v
}

// parseYouTube / parseSeconds / looksLikeURL / isLocalMedia live in Links.swift (compiled by the tests too).

// ----------------------------------------------------------------------------
// MARK: - yt-dlp (launched directly with an argument array — no shell, no quoting; see GOTCHAS)
// ----------------------------------------------------------------------------
enum YtDlp {
    static var path: String? { MediaTools.bundled.executable("yt-dlp")?.path }
    static func process(_ args: [String]) -> Process? { MediaTools.bundled.process(args) }
    // Run to completion off-main; completes on main with stdout, or nil on launch failure / non-zero exit.
    static func capture(_ args: [String], completion: @escaping (Data?) -> Void) {
        DispatchQueue.global().async {
            var out: Data? = nil
            if let p = process(args) {
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
                do {
                    try p.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    if p.terminationStatus == 0, !data.isEmpty { out = data }
                } catch {}
            }
            DispatchQueue.main.async { completion(out) }
        }
    }
    // Bundled helpers are immutable. Replace Watch to update the tested helper set.
}
// A running yt-dlp call its caller can abandon (a newer search, Back). Cancelling stops the process.
final class YtDlpTask {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() {
        lock.lock(); cancelled = true; let p = process; lock.unlock()
        if p?.isRunning == true { p?.terminate() }
    }
    fileprivate func launch(_ p: Process) throws -> Bool {   // cancellation and launch share the lock
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        process = p
        try p.run()
        return true
    }
}
extension YtDlp {
    static let timedOutError = "yt-dlp timed out"
    static let notFoundError = "Watch’s bundled media tools are missing or incomplete. Replace Watch with a fresh copy."
    // Like capture, but also reports yt-dlp's last ERROR line so browse screens can say why they failed.
    // `timeout` stops a call that hangs (the error is then `timedOutError`); the returned task cancels it.
    @discardableResult
    static func captureWithError(_ args: [String], timeout: TimeInterval? = nil, completion: @escaping (Data?, String) -> Void) -> YtDlpTask {
        let task = YtDlpTask()
        DispatchQueue.global().async {
            var out: Data? = nil, errText = ""
            if let p = process(args) {
                let pipe = Pipe(), errPipe = Pipe()
                p.standardOutput = pipe; p.standardError = errPipe
                let lock = NSLock(); var errData = Data(), timedOut = false
                errPipe.fileHandleForReading.readabilityHandler = { h in   // drained live so a chatty stderr can't block stdout
                    let chunk = h.availableData
                    guard !chunk.isEmpty else { h.readabilityHandler = nil; return }
                    lock.lock(); errData.append(chunk); lock.unlock()
                }
                do {
                    guard try task.launch(p) else { throw CocoaError(.userCancelled) }
                    if let t = timeout {
                        DispatchQueue.global().asyncAfter(deadline: .now() + t) {
                            guard p.isRunning else { return }
                            lock.lock(); timedOut = true; lock.unlock()
                            p.terminate()
                        }
                    }
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    lock.lock(); let e = String(decoding: errData, as: UTF8.self); let late = timedOut; lock.unlock()
                    errText = e.split(separator: "\n").last(where: { $0.hasPrefix("ERROR") }).map(String.init) ?? ""
                    if late { errText = timedOutError }
                    else if p.terminationStatus == 0, !data.isEmpty { out = data }
                    else if errText.isEmpty { errText = task.isCancelled ? "Cancelled" : "yt-dlp exited with \(p.terminationStatus)" }
                } catch {
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    errText = task.isCancelled ? "Cancelled" : error.localizedDescription
                }
            } else { errText = notFoundError }
            DispatchQueue.main.async { completion(out, errText) }
        }
        return task
    }
}

// ----------------------------------------------------------------------------
// MARK: - YouTube browsing (search · history · playlists) — adapted from Tube
// History and playlists read the signed-in browser's YouTube cookies (`--cookies-from-browser`); the account,
// browser and profile are Preferences ▸ YouTube. Everything here is flat-playlist metadata only; playback
// goes through the normal play() pipeline.
// ----------------------------------------------------------------------------
struct YTVideo { let url: String; let title: String; let thumbnail: String?; let channel: String; let views: Int?; let duration: Double?; var isLive = false }
struct YTPlaylist { let url: String; let title: String; let count: Int?; let thumbnail: String? }
struct YTFormat { let label: String; let selector: String }

enum YouTube {
    static let searchLimit = 18          // results per page; "Show More Results" asks for another page
    static let maxSearchResults = 90
    static let searchTimeout: TimeInterval = 25
    private static func int(_ v: Any?) -> Int? { (v as? Int) ?? (v as? Double).map { Int($0) } ?? (v as? String).flatMap { Int($0) } }
    private static func dbl(_ v: Any?) -> Double? { (v as? Double) ?? (v as? Int).map { Double($0) } }
    private static func thumb(_ d: [String: Any]) -> String? {
        let arr = (d["thumbnails"] as? [[String: Any]]) ?? []
        return arr.max(by: { (int($0["width"]) ?? 0) < (int($1["width"]) ?? 0) })?["url"] as? String ?? d["thumbnail"] as? String
    }
    static func video(_ d: [String: Any]) -> YTVideo? {
        let id = d["id"] as? String ?? ""
        let url = (d["webpage_url"] as? String) ?? (d["url"] as? String) ?? (id.isEmpty ? "" : "https://www.youtube.com/watch?v=\(id)")
        guard !url.isEmpty else { return nil }
        return YTVideo(url: url, title: d["title"] as? String ?? url, thumbnail: thumb(d) ?? VideoLinks.thumbnail(url),
                       channel: ((d["channel"] as? String) ?? (d["uploader"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                       views: int(d["view_count"]), duration: dbl(d["duration"]),
                       isLive: (d["live_status"] as? String) == "is_live")
    }
    static func playlist(_ d: [String: Any]) -> YTPlaylist? {
        let id = d["id"] as? String ?? ""
        let url = (d["url"] as? String) ?? (d["webpage_url"] as? String) ?? (id.isEmpty ? "" : "https://www.youtube.com/playlist?list=\(id)")
        guard !url.isEmpty else { return nil }
        return YTPlaylist(url: url, title: d["title"] as? String ?? "Playlist", count: int(d["playlist_count"]), thumbnail: thumb(d))
    }
    static func isPlaylistLink(_ s: String) -> Bool { VideoLinks.isYouTubePlaylist(s) }
    // YouTube's `authuser` picks which signed-in Google account a feed URL belongs to.
    static func accountURL(_ raw: String) -> String {
        let account = Prefs.youtubeAccount
        guard !account.isEmpty, var c = URLComponents(string: raw) else { return raw }
        c.queryItems = (c.queryItems ?? []).filter { $0.name != "authuser" } + [URLQueryItem(name: "authuser", value: account)]
        return c.url?.absoluteString ?? raw
    }
    static func cookieSources() -> [String] {
        switch Prefs.cookieSource { case "safari": return ["safari"]; case "chrome": return ["chrome"]; default: return ["safari", "chrome"] }
    }
    static func cookieArgs(_ browser: String) -> [String] {
        let profile = Prefs.browserProfile
        return ["--cookies-from-browser", profile.isEmpty || browser == "safari" ? browser : "\(browser):\(profile)"]
    }
    @discardableResult
    static func loadJSON(_ args: [String], timeout: TimeInterval? = nil, completion: @escaping ([String: Any]?, String) -> Void) -> YtDlpTask {
        YtDlp.captureWithError(["--dump-single-json", "--flat-playlist", "--no-warnings"] + args, timeout: timeout) { data, err in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            completion(j, j == nil && err.isEmpty ? "yt-dlp returned unreadable output" : err)
        }
    }
    // Signed-in pages: try each configured browser's cookies in turn.
    static func loadSignedIn(_ args: [String], completion: @escaping ([String: Any]?, String) -> Void) {
        var sources = cookieSources()
        func next(_ lastErr: String) {
            guard !sources.isEmpty else { completion(nil, lastErr); return }
            loadJSON(cookieArgs(sources.removeFirst()) + args, timeout: 45) { j, err in j != nil ? completion(j, "") : next(err) }
        }
        next("No browser cookies available")
    }
    static func videos(_ j: [String: Any]) -> [YTVideo] {
        if let e = j["entries"] as? [[String: Any]] { return e.compactMap(video) }
        return video(j).map { [$0] } ?? []
    }
    // `limit` grows by a page each time "Show More Results" asks; yt-dlp re-reads from the top (cheap: flat).
    @discardableResult
    static func search(_ q: String, limit: Int = searchLimit, completion: @escaping ([YTVideo]?, String) -> Void) -> YtDlpTask {
        loadJSON(["ytsearch\(limit):\(q)"], timeout: searchTimeout) { j, e in completion(j.map(videos), e) }
    }
    static func history(completion: @escaping ([YTVideo]?, String) -> Void) {
        loadSignedIn(["--playlist-end", "50", accountURL("https://www.youtube.com/feed/history")]) { j, e in completion(j.map(videos), e) }
    }
    static func playlists(completion: @escaping ([YTPlaylist]?, String) -> Void) {
        loadSignedIn([accountURL("https://www.youtube.com/feed/playlists")]) { j, e in
            completion(j.map { ($0["entries"] as? [[String: Any]] ?? []).compactMap(playlist) }, e)
        }
    }
    static func playlistVideos(_ url: String, completion: @escaping ([YTVideo]?, String) -> Void) {
        guard Prefs.youtubeConnected else { loadJSON(["--playlist-end", "80", url]) { j, e in completion(j.map(videos), e) }; return }
        loadSignedIn(["--playlist-end", "80", url]) { j, e in completion(j.map(videos), e) }
    }
    // Same list, plus the playlist's own title — what a player window's Up Next is built from.
    static func playlist(_ url: String, completion: @escaping (String?, [YTVideo]) -> Void) {
        playlistJSON(url) { j in completion(j?["title"] as? String, j.map(videos) ?? []) }
    }
    private static func playlistJSON(_ url: String, completion: @escaping ([String: Any]?) -> Void) {
        let args = ["--playlist-end", "100", url]
        guard Prefs.youtubeConnected else { loadJSON(args) { j, _ in completion(j) }; return }
        loadSignedIn(args) { j, _ in completion(j) }
    }
    // Quick sign-in probe for Preferences: can we read the history feed with the configured cookies?
    static func checkSignIn(completion: @escaping (Bool, String) -> Void) {
        loadSignedIn(["--playlist-end", "1", accountURL("https://www.youtube.com/feed/history")]) { j, e in completion(j != nil, e) }
    }
    // Exact formats for the Advanced download submenu. Video-only formats get the best audio merged in.
    static func formats(_ url: String, completion: @escaping ([YTFormat]) -> Void) {
        YtDlp.captureWithError(["-J", "--no-playlist", "--no-warnings", url]) { data, _ in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let fs = (j?["formats"] as? [[String: Any]] ?? []).reversed().compactMap { f -> YTFormat? in
                guard let id = f["format_id"] as? String, (f["protocol"] as? String ?? "").hasPrefix("http") else { return nil }
                let v = f["vcodec"] as? String ?? "none", a = f["acodec"] as? String ?? "none"
                guard v != "none" || a != "none" else { return nil }    // storyboards
                let res = v == "none" ? "audio" : (int(f["height"]).map { "\($0)p" } ?? "video")
                let size = int(f["filesize"]) ?? int(f["filesize_approx"])
                let parts = [res, f["ext"] as? String ?? "", v == "none" ? a : v, size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? ""]
                return YTFormat(label: parts.filter { !$0.isEmpty }.joined(separator: " · "),
                                selector: v != "none" && a == "none" ? "\(id)+ba" : id)
            }
            completion(fs)
        }
    }
}
func formatDuration(_ s: Double?) -> String {
    guard let s = s, s > 0 else { return "" }
    let t = Int(s), h = t / 3600, m = (t % 3600) / 60, sec = t % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}
func formatViews(_ n: Int?) -> String {
    guard let n = n else { return "" }
    if n >= 1_000_000 { return String(format: "%.1fM views", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK views", Double(n) / 1_000) }
    return "\(n) views"
}

func resolveTitle(_ link: String, completion: @escaping (String?) -> Void) {
    YtDlp.capture(["--get-title", "--no-playlist", "--no-warnings", link]) { data in
        let t = data.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        completion((t?.isEmpty == false) ? t : nil)
    }
}
// Title, thumbnail, duration and live flag for a Recent Links row; nil when yt-dlp finds nothing to play there.
// `-I 1` stops a channel or artist page from making yt-dlp walk every video on it (`isList` reports one).
func probeLink(_ link: String, completion: @escaping (LinkInfo?) -> Void) {
    YtDlp.captureWithError(["-J", "--flat-playlist", "--no-playlist", "-I", "1", "--no-warnings", link], timeout: 40) { data, _ in
        let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let info = j.map(LinkInfo.init(json:))
        completion(info?.title == nil ? nil : info)
    }
}

// ----------------------------------------------------------------------------
// MARK: - Up Next — the list Next/Previous walk through
// ----------------------------------------------------------------------------
// Every player window has one (built on demand, see PlayerWindowController.ensureQueue): the panel list a
// video was started from (a playlist, search results, History), what YouTube would roll into next for a
// video opened on its own, or the other media files sitting next to a local file. Autoplay / Repeat /
// Shuffle all act on this list.
struct QueueItem: Equatable { let url: String; let title: String? }
enum RepeatMode: String { case off, all, one }

struct PlayQueue {
    enum Kind { case list, recommended, folder }
    let kind: Kind
    let name: String                  // shown as the Up Next heading: "History", a playlist's title, a folder…
    private(set) var items: [QueueItem]
    private(set) var order: [Int]     // indices into items, in play order — identity unless shuffled
    private(set) var pos = 0          // where we are in `order`
    private(set) var shuffled = false

    init(kind: Kind, name: String, items: [QueueItem], startAt: Int = 0, shuffled: Bool = false) {
        self.kind = kind; self.name = name; self.items = items
        self.order = Array(items.indices)
        self.pos = items.isEmpty ? 0 : min(max(0, startAt), items.count - 1)
        if shuffled { setShuffle(true) }
    }
    var currentIndex: Int { order.indices.contains(pos) ? order[pos] : -1 }
    var current: QueueItem? { items.indices.contains(currentIndex) ? items[currentIndex] : nil }
    private func target(_ delta: Int, wrap: Bool) -> Int? {
        guard !order.isEmpty else { return nil }
        let p = pos + delta
        if order.indices.contains(p) { return p }
        guard wrap, order.count > 1 else { return nil }
        return p < 0 ? order.count - 1 : 0
    }
    func peek(_ delta: Int, wrap: Bool) -> QueueItem? { target(delta, wrap: wrap).map { items[order[$0]] } }
    @discardableResult mutating func step(_ delta: Int, wrap: Bool) -> QueueItem? {
        guard let p = target(delta, wrap: wrap) else { return nil }
        pos = p
        return items[order[p]]
    }
    mutating func jump(toItem i: Int) -> QueueItem? {
        guard let p = order.firstIndex(of: i) else { return nil }
        pos = p
        return items[i]
    }
    // Shuffle randomizes everything around whatever is playing, which stays put and keeps playing; turning it
    // back off restores the real order at the same item. (Randomizing only what's "behind" the cursor would
    // strand the items above a list you joined in the middle — they'd never come up.)
    mutating func setShuffle(_ on: Bool) {
        let here = max(0, currentIndex)
        guard items.count > 1 else { shuffled = on; return }
        if on {
            order = [here] + items.indices.filter { $0 != here }.shuffled()
            pos = 0
        } else {
            order = Array(items.indices)
            pos = here
        }
        shuffled = on
    }
    // Recommendations arrive ~25 at a time; when they run out we append the next video's own.
    @discardableResult mutating func append(_ more: [QueueItem]) -> Int {
        let known = Set(items.map { $0.url })
        let fresh = more.filter { !known.contains($0.url) }
        guard !fresh.isEmpty else { return 0 }
        order += Array(items.count..<(items.count + fresh.count))
        items += fresh
        return fresh.count
    }

    // A local file's neighbours: the other media of the same kind in its folder, in Finder order.
    // Only what AVFoundation can actually open — a .webm sitting next door would just fail to play.
    static let videoExts: Set<String> = ["mp4", "m4v", "mov", "qt", "3gp", "3g2"]
    static let audioExts: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "aifc", "caf", "flac"]
    static func mediaKind(_ ext: String) -> Int? {
        let e = ext.lowercased()
        return videoExts.contains(e) ? 0 : (audioExts.contains(e) ? 1 : nil)
    }
    static func folder(for path: String, shuffled: Bool) -> PlayQueue? {
        let file = URL(fileURLWithPath: path.hasPrefix("file://") ? (URL(string: path)?.path ?? path) : path)
        guard let kind = mediaKind(file.pathExtension),
              let names = try? FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path) else { return nil }
        let dir = file.deletingLastPathComponent()
        let items = names.filter { mediaKind(($0 as NSString).pathExtension) == kind }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { QueueItem(url: dir.appendingPathComponent($0).path, title: ($0 as NSString).deletingPathExtension) }
        guard items.count > 1, let start = items.firstIndex(where: { $0.url == file.path }) else { return nil }
        return PlayQueue(kind: .folder, name: dir.lastPathComponent, items: items, startAt: start, shuffled: shuffled)
    }
}

// ----------------------------------------------------------------------------
// MARK: - YouTubeUpNext — "what would play next on youtube.com"
// ----------------------------------------------------------------------------
// yt-dlp can't list a video's recommendations, and the RD… "Mix" playlist only exists for music videos, so
// this reads the watch page's own `ytInitialData`: the autoplay pick first (exactly what the site would
// roll into), then the sidebar list behind it. If YouTube reshapes that JSON the list just comes back
// empty — Next then has nowhere to go, and every other kind of Up Next list is unaffected.
enum YouTubeUpNext {
    static func load(id: String, completion: @escaping ([QueueItem]) -> Void) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { completion([]); return }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
                   forHTTPHeaderField: "User-Agent")
        r.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        r.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")     // skips the EU consent interstitial
        URLSession.shared.dataTask(with: r) { data, _, _ in
            let items = data.map(parse) ?? []
            DispatchQueue.main.async { completion(items) }
        }.resume()
    }
    static func parse(_ page: Data) -> [QueueItem] {
        guard let root = ytInitialData(page) else { return [] }
        let watchNext = dig(root["contents"], "twoColumnWatchNextResults") as? [String: Any]
        var ids: [String] = [], titles: [String: String] = [:]
        collect(watchNext?["secondaryResults"] ?? root, &ids, &titles)
        // The video the site itself would play next goes first.
        if let sets = dig(watchNext?["autoplay"], "autoplay", "sets") as? [[String: Any]],
           let vid = dig(sets.first?["autoplayVideo"], "watchEndpoint", "videoId") as? String {
            ids.removeAll { $0 == vid }
            ids.insert(vid, at: 0)
        }
        return ids.map { QueueItem(url: "https://www.youtube.com/watch?v=\($0)", title: titles[$0]) }
    }
    // Handles today's `lockupViewModel` entries and the older `compactVideoRenderer` ones.
    private static func collect(_ node: Any?, _ ids: inout [String], _ titles: inout [String: String]) {
        if let arr = node as? [Any] { for v in arr { collect(v, &ids, &titles) }; return }
        guard let d = node as? [String: Any] else { return }
        if let id = d["contentId"] as? String, (d["contentType"] as? String)?.hasSuffix("VIDEO") == true {
            keep(id, text(dig(d["metadata"], "lockupMetadataViewModel", "title")), &ids, &titles)
        } else if let id = d["videoId"] as? String, let t = text(d["title"]) {
            keep(id, t, &ids, &titles)
        }
        for v in d.values { collect(v, &ids, &titles) }
    }
    private static func keep(_ id: String, _ title: String?, _ ids: inout [String], _ titles: inout [String: String]) {
        guard id.count > 5 else { return }
        if titles[id] == nil { titles[id] = title }
        if !ids.contains(id) { ids.append(id) }
    }
    private static func dig(_ node: Any?, _ keys: String...) -> Any? {
        keys.reduce(node) { ($0 as? [String: Any])?[$1] }
    }
    private static func text(_ node: Any?) -> String? {
        if let s = node as? String { return s }
        guard let d = node as? [String: Any] else { return nil }
        if let s = (d["content"] ?? d["simpleText"]) as? String { return s }
        if let runs = d["runs"] as? [[String: Any]] { return runs.compactMap { $0["text"] as? String }.joined() }
        return nil
    }
    // `var ytInitialData = {…};` — find the marker, then take the balanced object that follows it.
    private static func ytInitialData(_ page: Data) -> [String: Any]? {
        for marker in ["var ytInitialData", "ytInitialData\"] ="] {
            guard let m = page.range(of: Data(marker.utf8)),
                  let open = page[m.upperBound...].firstIndex(of: UInt8(ascii: "{")) else { continue }
            var depth = 0, inString = false, escaped = false, i = open
            while i < page.endIndex {
                let c = page[i]
                if escaped { escaped = false }
                else if inString { if c == 0x5C { escaped = true } else if c == 0x22 { inString = false } }
                else if c == 0x22 { inString = true }
                else if c == 0x7B { depth += 1 }
                else if c == 0x7D {
                    depth -= 1
                    if depth == 0 { return (try? JSONSerialization.jsonObject(with: page[open...i])) as? [String: Any] }
                }
                i += 1
            }
        }
        return nil
    }
}

// ----------------------------------------------------------------------------
// MARK: - Stream resolution: link → ordered list of native AVPlayer plans
// ----------------------------------------------------------------------------
struct StreamRef {
    let url: URL, proto: String, ext: String
    let vcodec: String?, acodec: String?
    let width: Int?, height: Int?, bitrate: Int?
    let headers: [String: String]
    init?(_ f: [String: Any], urlKey: String = "url", headers fallbackHeaders: Any? = nil) {
        guard let s = f[urlKey] as? String, let u = URL(string: s) else { return nil }
        url = u
        proto = f["protocol"] as? String ?? ""; ext = f["ext"] as? String ?? ""
        vcodec = f["vcodec"] as? String; acodec = f["acodec"] as? String
        width = f["width"] as? Int; height = f["height"] as? Int
        bitrate = (f["tbr"] as? Double).map { Int($0 * 1000) }
        let all = (f["http_headers"] as? [String: String]) ?? (fallbackHeaders as? [String: String]) ?? [:]
        headers = all.filter { ["User-Agent", "Referer", "Origin"].contains($0.key) }
    }
    var isHLS: Bool { proto.hasPrefix("m3u8") }
    var isVideo: Bool { vcodec != nil && vcodec != "none" }
    // Header injection for AVURLAsset (widely used key; applies to playlist + segment requests).
    var assetOptions: [String: Any] { headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": headers] }
}
enum StreamPlan {
    case single(StreamRef)                              // one muxed URL: progressive file or HLS playlist
    case split(video: StreamRef, audio: StreamRef)      // separate video + audio → DashHLSBridge
}
struct ResolvedStream { let title: String?; let isLive: Bool; let plans: [StreamPlan]; var thumbnail: String? = nil; var duration: Double? = nil }

// Can AVPlayer open this yt-dlp format on its own, with sound? (No VP9/AV1: no hardware decode on most Macs.)
func avPlayableMuxed(_ f: [String: Any]) -> Bool {
    let proto = f["protocol"] as? String ?? "", ext = f["ext"] as? String ?? ""
    let v = f["vcodec"] as? String, a = f["acodec"] as? String
    guard v != "none", a != "none", f["url"] is String else { return false }
    if let v = v, v.hasPrefix("vp") || v.hasPrefix("av01") { return false }
    return proto.hasPrefix("m3u8") || (proto.hasPrefix("http") && ["mp4", "m4v", "mov"].contains(ext))
}

// One yt-dlp call (`-j`) gives the title, live flag and every format, so we build a primary plan plus
// fallbacks without re-running it. Completes on main; nil = yt-dlp missing/failed (caller falls back to web).
func resolveStream(_ link: String, completion: @escaping (ResolvedStream?) -> Void) {
    let fmt = parseYouTube(link) != nil
        // YouTube: H.264 HD video + AAC audio (bridged to HLS); live/other → best HLS; last resort muxed mp4.
        ? "bv*[vcodec^=avc1][height<=1080][protocol=https]+ba[ext=m4a][protocol=https]/b[protocol^=m3u8]/b[ext=mp4]/bv*+ba/b"
        : "b[protocol^=m3u8]/b[ext=mp4]/bv*[vcodec^=avc1]+ba[ext=m4a]/bv*[protocol^=m3u8]+ba[protocol^=m3u8]/b/bv*+ba"
    YtDlp.capture(["-j", "--no-playlist", "--no-warnings", "-f", fmt, link]) { data in
        guard let data = data,
              let firstLine = String(data: data, encoding: .utf8)?.split(separator: "\n").first,
              let d = (try? JSONSerialization.jsonObject(with: Data(firstLine.utf8))) as? [String: Any] else { completion(nil); return }
        let formats = (d["formats"] as? [[String: Any]]) ?? []
        let isLive = (d["is_live"] as? Bool) == true
        var plans: [StreamPlan] = []
        // Live: the master HLS manifest carries every quality + audio, so AVPlayer adapts on its own.
        if isLive {
            if let m = d["manifest_url"] as? String, let u = URL(string: m), m.contains("m3u8") || m.contains("manifest") {
                var f = d; f["url"] = u.absoluteString; f["protocol"] = "m3u8_native"
                if let s = StreamRef(f) { plans.append(.single(s)) }
            } else if let f = formats.first(where: { ($0["manifest_url"] as? String)?.contains("m3u8") == true }),
                      let s = StreamRef(f, urlKey: "manifest_url", headers: d["http_headers"]) {
                plans.append(.single(s))
            }
        }
        if let req = d["requested_formats"] as? [[String: Any]], req.count == 2,
           let a = StreamRef(req[0]), let b = StreamRef(req[1]) {
            plans.append(a.isVideo ? .split(video: a, audio: b) : .split(video: b, audio: a))
        } else if let s = StreamRef(d) {
            plans.append(.single(s))
        }
        // Safety net: the best muxed format AVPlayer can play by itself (e.g. YouTube's 360p "18").
        let taken = Set(plans.compactMap { if case .single(let s) = $0 { return s.url } else { return nil } })
        if let best = formats.filter(avPlayableMuxed).max(by: { ($0["height"] as? Int ?? 0) < ($1["height"] as? Int ?? 0) }),
           let s = StreamRef(best), !taken.contains(s.url) {
            plans.append(.single(s))
        }
        let info = LinkInfo(json: d)   // also fills in the video's Recent Links row (WindowManager.onInfo)
        completion(ResolvedStream(title: d["title"] as? String, isLive: isLive, plans: plans, thumbnail: info.thumbnail, duration: info.duration))
    }
}

// ----------------------------------------------------------------------------
// MARK: - DashHLSBridge — play split video+audio natively
// ----------------------------------------------------------------------------
// YouTube serves HD as separate fragmented-MP4 video and audio files. AVFoundation walks every fragment of
// a remote fMP4 before it will play (≈45 s for a 20-min 1080p file), so instead we read each file's `sidx`
// index and describe its fragments to AVPlayer as an HLS playlist with byte ranges. AVPlayer then starts in
// a couple of seconds, seeks instantly, and every segment fetch is a small bounded range request.
// Split HLS (video playlist + audio playlist) just gets a master playlist that points at both.
final class DashHLSBridge: NSObject, AVAssetResourceLoaderDelegate {
    static let scheme = "glasskit-hls"
    private let queue = DispatchQueue(label: "watch.hlsbridge")
    private var playlists: [String: Data] = [:]

    struct Index { let initLength: Int; let segments: [(offset: Int, length: Int, duration: Double)] }

    // Completes on main with a ready-to-play asset (the bridge must be retained as long as the asset), or nil.
    static func make(video: StreamRef, audio: StreamRef, completion: @escaping (DashHLSBridge?, AVURLAsset?) -> Void) {
        let base = "\(scheme)://p"
        func finish(_ videoURI: String, _ audioURI: String, _ extra: [String: Data]) {
            let b = DashHLSBridge()
            let codecs = [video.vcodec, audio.acodec].compactMap { $0 }.filter { $0 != "none" }.joined(separator: ",")
            var inf = "#EXT-X-STREAM-INF:BANDWIDTH=\((video.bitrate ?? 4_000_000) + (audio.bitrate ?? 128_000)),AUDIO=\"a\""
            if !codecs.isEmpty { inf += ",CODECS=\"\(codecs)\"" }
            if let w = video.width, let h = video.height { inf += ",RESOLUTION=\(w)x\(h)" }
            let master = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-INDEPENDENT-SEGMENTS\n"
                + "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a\",NAME=\"Audio\",DEFAULT=YES,AUTOSELECT=YES,URI=\"\(audioURI)\"\n"
                + "\(inf)\n\(videoURI)\n"
            b.playlists = extra.merging(["/master.m3u8": Data(master.utf8)]) { $1 }
            let asset = AVURLAsset(url: URL(string: "\(base)/master.m3u8")!, options: video.assetOptions)
            asset.resourceLoader.setDelegate(b, queue: b.queue)
            completion(b, asset)
        }
        if video.isHLS && audio.isHLS {
            DispatchQueue.main.async { finish(video.url.absoluteString, audio.url.absoluteString, [:]) }
            return
        }
        guard !video.isHLS, !audio.isHLS else { DispatchQueue.main.async { completion(nil, nil) }; return }
        let g = DispatchGroup(); var vi: Index?, ai: Index?
        g.enter(); fetchIndex(video) { vi = $0; g.leave() }
        g.enter(); fetchIndex(audio) { ai = $0; g.leave() }
        g.notify(queue: .main) {
            guard let vi = vi, let ai = ai else { completion(nil, nil); return }
            finish("\(base)/video.m3u8", "\(base)/audio.m3u8",
                   ["/video.m3u8": mediaPlaylist(video, vi), "/audio.m3u8": mediaPlaylist(audio, ai)])
        }
    }

    private static func fetchIndex(_ s: StreamRef, completion: @escaping (Index?) -> Void) {
        func get(_ length: Int, _ done: @escaping (Data?) -> Void) {
            var r = URLRequest(url: s.url, timeoutInterval: 15)
            r.setValue("bytes=0-\(length - 1)", forHTTPHeaderField: "Range")
            s.headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
            URLSession.shared.dataTask(with: r) { d, resp, _ in
                let ok = ((resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) }) ?? false
                done(ok ? d : nil)
            }.resume()
        }
        get(65536) { d in
            guard let d = d else { completion(nil); return }
            if let idx = parse(d) { completion(idx); return }
            // On very long videos the sidx runs past the first 64 KB — fetch exactly as much as it needs.
            guard let sidx = boxes(d).first(where: { $0.type == "sidx" }), sidx.offset + sidx.size > d.count,
                  sidx.offset + sidx.size < 8 << 20 else { completion(nil); return }
            get(sidx.offset + sidx.size) { d2 in completion(d2.flatMap(parse)) }
        }
    }
    private static func u32(_ d: Data, _ o: Int) -> Int {
        guard o >= 0, o + 4 <= d.count else { return 0 }
        return d[d.startIndex + o ..< d.startIndex + o + 4].reduce(0) { $0 << 8 | Int($1) }
    }
    private static func boxes(_ d: Data) -> [(type: String, offset: Int, size: Int)] {
        var out: [(type: String, offset: Int, size: Int)] = []; var o = 0
        while o + 8 <= d.count {
            let size = u32(d, o)
            guard size >= 8 else { break }
            let type = String(bytes: d[d.startIndex + o + 4 ..< d.startIndex + o + 8], encoding: .ascii) ?? ""
            out.append((type, o, size)); o += size
        }
        return out
    }
    private static func parse(_ d: Data) -> Index? {
        let all = boxes(d)
        guard let moov = all.first(where: { $0.type == "moov" }),
              let sidx = all.first(where: { $0.type == "sidx" }), sidx.offset + sidx.size <= d.count else { return nil }
        var p = sidx.offset + 8
        let version = Int(d[d.startIndex + p]); p += 4          // version + flags
        p += 4                                                   // reference_ID
        let timescale = Double(u32(d, p)); p += 4
        guard timescale > 0 else { return nil }
        let firstOffset: Int
        if version == 0 { p += 4; firstOffset = u32(d, p); p += 4 }
        else { p += 8; firstOffset = u32(d, p) << 32 | u32(d, p + 4); p += 8 }
        p += 2                                                   // reserved
        let count = u32(d, p - 2) & 0xFFFF; p += 2
        guard p + count * 12 <= sidx.offset + sidx.size else { return nil }
        var offset = sidx.offset + sidx.size + firstOffset
        var segments: [(offset: Int, length: Int, duration: Double)] = []
        for _ in 0..<count {
            let ref = u32(d, p), duration = u32(d, p + 4); p += 12
            guard ref >> 31 == 0 else { return nil }             // hierarchical sidx — not used by YouTube
            let length = ref & 0x7FFF_FFFF
            segments.append((offset, length, Double(duration) / timescale)); offset += length
        }
        return segments.isEmpty ? nil : Index(initLength: moov.offset + moov.size, segments: segments)
    }
    private static func mediaPlaylist(_ s: StreamRef, _ idx: Index) -> Data {
        let target = Int((idx.segments.map { $0.duration }.max() ?? 5).rounded(.up))
        let url = s.url.absoluteString
        var m = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:\(target)\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-INDEPENDENT-SEGMENTS\n"
        m += "#EXT-X-MAP:URI=\"\(url)\",BYTERANGE=\"\(idx.initLength)@0\"\n"
        for seg in idx.segments {
            m += String(format: "#EXTINF:%.3f,\n", seg.duration) + "#EXT-X-BYTERANGE:\(seg.length)@\(seg.offset)\n\(url)\n"
        }
        return Data((m + "#EXT-X-ENDLIST\n").utf8)
    }
    func resourceLoader(_ rl: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource req: AVAssetResourceLoadingRequest) -> Bool {
        guard let path = req.request.url?.path, let data = playlists[path] else { return false }
        req.contentInformationRequest?.contentType = "public.m3u-playlist"
        req.contentInformationRequest?.contentLength = Int64(data.count)
        req.contentInformationRequest?.isByteRangeAccessSupported = false
        req.dataRequest?.respond(with: data)
        req.finishLoading()
        return true
    }
}

// ============================================================================
// MARK: - Downloads (in-app yt-dlp, progress shown in the panel — no Terminal)
// ============================================================================
// Queue implementation: Downloads.swift.

// ============================================================================
// MARK: - HotkeyRecorderView
// ============================================================================
final class HotkeyRecorderView: NSButton {
    var onCapture: ((UInt32, UInt32, String) -> Void)?
    private var recording = false
    override init(frame: NSRect) { super.init(frame: frame); commonInit() }
    required init?(coder: NSCoder) { fatalError() }
    private func commonInit() { bezelStyle = .rounded; setButtonType(.momentaryPushIn); target = self; action = #selector(begin); title = Prefs.hotkeyDisplay }
    @objc func begin() { recording = true; title = "Press shortcut…"; window?.makeFirstResponder(self) }
    override var acceptsFirstResponder: Bool { true }
    override func resignFirstResponder() -> Bool { if recording { recording = false; title = Prefs.hotkeyDisplay }; return true }
    override func keyDown(with e: NSEvent) {
        guard recording else { super.keyDown(with: e); return }
        if e.keyCode == 53 { recording = false; title = Prefs.hotkeyDisplay; window?.makeFirstResponder(nil); return }
        let f = e.modifierFlags
        guard f.contains(.command) || f.contains(.option) || f.contains(.control) else { NSSound.beep(); return }
        let disp = shortcutDisplay(f, e.keyCode, e.charactersIgnoringModifiers)
        recording = false; title = disp; window?.makeFirstResponder(nil)
        onCapture?(UInt32(e.keyCode), carbonModifiers(from: f), disp)
    }
}

// ============================================================================
// MARK: - SettingsController (Preferences)
// ============================================================================
final class SettingsController: NSObject, NSTextFieldDelegate {
    let window: NSWindow
    weak var app: AppDelegate?
    var recorder: HotkeyRecorderView!
    private var loginCheck: NSButton!
    private var askDirCheck: NSButton!
    private var clipboardHotkeyCheck: NSButton!
    private var browserTabsCheck: NSButton!
    private var nowPlayingCheck: NSButton!
    private var dirField: NSTextField!
    private var updateButton: NSButton!
    private var updateLabel: NSTextField!
    private var cookiePopup: NSPopUpButton!
    private var accountField: NSTextField!
    private var profileField: NSTextField!
    private var signInLabel: NSTextField!
    private var accessLabel: NSTextField!
    private var ytStatus: NSTextField!
    private var signInButton: NSButton!
    private var signOutButton: NSButton!

    init(app: AppDelegate) {
        self.app = app
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Watch Preferences"; window.isReleasedWhenClosed = false
        super.init()
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshYouTube), name: .watchYouTubeAccountChanged, object: nil)
    }
    @objc func refreshYouTube() {
        let on = Prefs.youtubeConnected
        ytStatus.stringValue = on ? "Signed in — using your YouTube session from \(Prefs.cookieBrowserName)" : "Not signed in"
        ytStatus.textColor = on ? .systemGreen : .secondaryLabelColor
        signInButton.title = on ? "Sign In Again…" : "Sign In…"
        signOutButton.isEnabled = on
        cookiePopup.selectItem(at: ["auto", "safari", "chrome"].firstIndex(of: Prefs.cookieSource) ?? 2)
        accountField.stringValue = Prefs.youtubeAccount; profileField.stringValue = Prefs.browserProfile
    }
    func show() {
        loginCheck.state = currentLogin() ? .on : .off; dirField.stringValue = Prefs.downloadDir
        refreshYouTube()
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func section(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s); l.font = .boldSystemFont(ofSize: 12); return l
    }
    private func note(_ s: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s); l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = 400; return l
    }
    private func currentLogin() -> Bool { Prefs.launchAtLogin }
    private func label(_ s: String) -> NSTextField { let t = NSTextField(labelWithString: s); t.alignment = .right; t.widthAnchor.constraint(equalToConstant: 120).isActive = true; return t }
    private func row(_ t: String, _ c: NSView) -> NSStackView { let r = NSStackView(views: [label(t), c]); r.spacing = 10; r.alignment = .firstBaseline; return r }
    private func buildUI() {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
        ])
        recorder = HotkeyRecorderView(frame: NSRect(x: 0, y: 0, width: 150, height: 24))
        recorder.onCapture = { [weak self] kc, carbon, disp in
            Prefs.hotkeyKeyCode = kc; Prefs.hotkeyCarbon = carbon; Prefs.hotkeyDisplay = disp
            self?.app?.applyHotkey(keyCode: kc, carbonModifiers: carbon)
        }
        stack.addArrangedSubview(section("General"))
        stack.addArrangedSubview(row("Open hotkey:", recorder))

        clipboardHotkeyCheck = NSButton(checkboxWithTitle: "Hotkey plays a copied video link instead of toggling the panel", target: self, action: #selector(clipboardHotkeyChanged))
        clipboardHotkeyCheck.state = Prefs.hotkeyPlaysClipboard ? .on : .off
        stack.addArrangedSubview(clipboardHotkeyCheck)

        browserTabsCheck = NSButton(checkboxWithTitle: "Show videos open in browser tabs (Safari, Chrome, Brave, Edge, Arc)", target: self, action: #selector(browserTabsChanged))
        browserTabsCheck.state = Prefs.showBrowserTabs ? .on : .off
        stack.addArrangedSubview(browserTabsCheck)
        let access = NSButton(title: "Allow Browser Access…", target: self, action: #selector(allowBrowserAccess)); access.bezelStyle = .rounded
        accessLabel = note("macOS asks once per running browser to let Watch see its video tabs.")
        let accessRow = NSStackView(views: [access, accessLabel]); accessRow.spacing = 8; accessRow.alignment = .centerY
        stack.addArrangedSubview(accessRow)

        nowPlayingCheck = NSButton(checkboxWithTitle: "Show what's playing in other apps (Music, Spotify, browsers…) with its artwork", target: self, action: #selector(nowPlayingChanged))
        nowPlayingCheck.state = Prefs.showNowPlaying ? .on : .off
        stack.addArrangedSubview(nowPlayingCheck)

        dirField = NSTextField(string: Prefs.downloadDir); dirField.isEditable = false
        dirField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseDir)); choose.bezelStyle = .rounded
        let dirRow = NSStackView(views: [label("Download to:"), dirField, choose]); dirRow.spacing = 8; dirRow.alignment = .firstBaseline
        stack.addArrangedSubview(dirRow)
        askDirCheck = NSButton(checkboxWithTitle: "Ask where to save each download", target: self, action: #selector(askDirChanged))
        askDirCheck.state = Prefs.askDownloadDir ? .on : .off
        stack.addArrangedSubview(askDirCheck)

        loginCheck = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(loginChanged))
        loginCheck.state = currentLogin() ? .on : .off
        stack.addArrangedSubview(loginCheck)
        updateButton = NSButton(title: "Media Tool Updates…", target: self, action: #selector(updateNow)); updateButton.bezelStyle = .rounded
        updateLabel = NSTextField(labelWithString: "Media tools are included. Install a newer Watch to update them.")
        updateLabel.font = .systemFont(ofSize: 11); updateLabel.textColor = .secondaryLabelColor
        let updRow = NSStackView(views: [updateButton, updateLabel]); updRow.spacing = 8; updRow.alignment = .firstBaseline
        stack.addArrangedSubview(updRow)

        // YouTube sign-in — History and Playlists (••• menu) use this browser's signed-in YouTube session.
        stack.setCustomSpacing(20, after: updRow)
        stack.addArrangedSubview(section("YouTube Account"))
        ytStatus = NSTextField(labelWithString: ""); ytStatus.font = .systemFont(ofSize: 12, weight: .medium)
        stack.addArrangedSubview(row("Status:", ytStatus))
        signInButton = NSButton(title: "Sign In…", target: self, action: #selector(openSignIn)); signInButton.bezelStyle = .rounded
        signOutButton = NSButton(title: "Sign Out", target: self, action: #selector(signOut)); signOutButton.bezelStyle = .rounded
        let check = NSButton(title: "Check", target: self, action: #selector(checkSignIn)); check.bezelStyle = .rounded
        let spacer = NSView(); spacer.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let acctButtons = NSStackView(views: [spacer, signInButton, signOutButton, check]); acctButtons.spacing = 8
        stack.addArrangedSubview(acctButtons)
        cookiePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        cookiePopup.addItems(withTitles: ["Auto: Safari, then Chrome", "Safari", "Chrome"])
        cookiePopup.target = self; cookiePopup.action = #selector(cookieChanged)
        stack.addArrangedSubview(row("Signed in via:", cookiePopup))
        accountField = NSTextField(string: Prefs.youtubeAccount)
        accountField.placeholderString = "Optional: account email (if signed into several)"
        accountField.delegate = self; accountField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        stack.addArrangedSubview(row("Account:", accountField))
        profileField = NSTextField(string: Prefs.browserProfile)
        profileField.placeholderString = "Chrome profile: Default, Profile 2, …"
        profileField.delegate = self; profileField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        stack.addArrangedSubview(row("Browser profile:", profileField))
        signInLabel = note("Watch never sees your password — it uses the YouTube sign-in from that browser for History and Playlists. Sign Out only disconnects Watch; your browser stays signed in.")
        let signRow = NSStackView(views: [label(""), signInLabel]); signRow.spacing = 10
        stack.addArrangedSubview(signRow)

        stack.setCustomSpacing(20, after: signRow)
        let guide = NSButton(title: "Setup Guide…", target: self, action: #selector(openGuide)); guide.bezelStyle = .rounded
        let guideRow = NSStackView(views: [guide, note("Start watching, connect YouTube, and check the included media tools.")])
        guideRow.spacing = 8; guideRow.alignment = .centerY
        stack.addArrangedSubview(guideRow)
    }
    @objc private func openGuide() { app?.openWelcome() }
    @objc private func cookieChanged() { Prefs.cookieSource = ["auto", "safari", "chrome"][max(0, cookiePopup.indexOfSelectedItem)]; refreshYouTube() }
    func controlTextDidChange(_ n: Notification) {
        guard let f = n.object as? NSTextField else { return }
        if f === accountField { Prefs.youtubeAccount = f.stringValue }
        if f === profileField { Prefs.browserProfile = f.stringValue }
    }
    @objc private func openSignIn() { app?.openYouTubeSignIn() }
    @objc private func signOut() {
        Prefs.youtubeConnected = false
        NotificationCenter.default.post(name: .watchYouTubeAccountChanged, object: nil)
    }
    @objc private func checkSignIn() {
        ytStatus.stringValue = "Checking…"; ytStatus.textColor = .secondaryLabelColor
        YouTube.checkSignIn { [weak self] ok, err in
            guard let self = self else { return }
            if ok {
                Prefs.youtubeConnected = true
                NotificationCenter.default.post(name: .watchYouTubeAccountChanged, object: nil)
            } else {
                self.ytStatus.stringValue = "Couldn't read YouTube from \(Prefs.cookieBrowserName) — try Sign In…"
                self.ytStatus.textColor = .systemOrange
                self.signInLabel.stringValue = String(err.replacingOccurrences(of: "ERROR: ", with: "").prefix(160))
            }
        }
    }
    @objc private func allowBrowserAccess() {
        app?.mediaMonitor.requestAccessForRunningBrowsers { [weak self] asked in
            self?.accessLabel.stringValue = asked == 0 ? "No running browser is waiting for access." : "Asked \(asked) browser(s)."
        }
    }
    @objc private func chooseDir() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.directoryURL = URL(fileURLWithPath: Prefs.downloadDir)
        if p.runModal() == .OK, let u = p.url { Prefs.downloadDir = u.path; dirField.stringValue = u.path }
    }
    @objc private func askDirChanged() { Prefs.askDownloadDir = (askDirCheck.state == .on) }
    @objc private func clipboardHotkeyChanged() { Prefs.hotkeyPlaysClipboard = (clipboardHotkeyCheck.state == .on) }
    @objc private func browserTabsChanged() { Prefs.showBrowserTabs = (browserTabsCheck.state == .on); app?.mediaSettingsChanged() }
    @objc private func nowPlayingChanged() { Prefs.showNowPlaying = (nowPlayingCheck.state == .on); app?.nowPlayingSettingsChanged() }
    @objc private func loginChanged() { app?.toggleLoginItem(); loginCheck.state = currentLogin() ? .on : .off }
    @objc private func updateNow() { showMediaToolUpdateHelp() }
}

extension Notification.Name { static let watchYouTubeAccountChanged = Notification.Name("watchYouTubeAccountChanged") }

// MARK: - YouTube connection assistant
final class YouTubeSignInController: NSObject {
    let window: NSWindow
    private let stack = NSStackView()
    private let width: CGFloat = 470
    private var browserPicker: NSSegmentedControl!
    private var profileRow: NSView!
    private var profileField: NSTextField!
    private var accountField: NSTextField!
    private var openButton: NSButton!
    private var chromeHelp: NSView!
    private var safariHelp: NSView!
    private var connectButton: NSButton!
    private var result: NSTextField!
    private var doneRow: NSView!
    private static let browsers = [("Chrome", "com.google.Chrome", "chrome"), ("Safari", "com.apple.Safari", "safari")]

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Sign In to YouTube"; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 530, height: 360)
        super.init()
        build()
    }
    func show() {
        let current = Prefs.cookieSource == "safari" ? 1 : 0
        browserPicker.selectedSegment = isInstalled(current) ? current : (isInstalled(1 - current) ? 1 - current : current)
        profileField.stringValue = Prefs.browserProfile; accountField.stringValue = Prefs.youtubeAccount
        result.stringValue = ""; doneRow.isHidden = true
        browserChanged()
        window.center(); window.makeKeyAndOrderFront(nil); window.orderFrontRegardless(); NSApp.activate(ignoringOtherApps: true)
    }
    private func isInstalled(_ i: Int) -> Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.browsers[i].1) != nil }
    private var browser: (name: String, id: String, key: String) { let b = Self.browsers[max(0, browserPicker.selectedSegment)]; return (b.0, b.1, b.2) }

    private func text(_ s: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: s)
        t.font = .systemFont(ofSize: size, weight: weight); t.textColor = color; t.isSelectable = true
        t.preferredMaxLayoutWidth = width
        return t
    }
    private func step(_ n: Int, _ title: String) {
        if let last = stack.arrangedSubviews.last { stack.setCustomSpacing(22, after: last) }
        stack.addArrangedSubview(text("\(n). \(title)", size: 14, weight: .semibold))
    }
    private func column(_ views: [NSView]) -> NSStackView {
        let v = NSStackView(views: views); v.orientation = .vertical; v.alignment = .leading; v.spacing = 8; return v
    }

    private func build() {
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor, constant: 30),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor, constant: 24),
        ])
        window.contentView!.addSubview(scroll)

        stack.addArrangedSubview(text("Sign in to YouTube", size: 20, weight: .bold))
        stack.addArrangedSubview(text("This shows your YouTube History and Playlists in Watch. Watch never asks for your Google password — it uses the YouTube sign-in that's already in your web browser.", color: .secondaryLabelColor))

        step(1, "Which browser do you use for YouTube?")
        browserPicker = NSSegmentedControl(labels: Self.browsers.map { $0.0 }, trackingMode: .selectOne, target: self, action: #selector(browserChanged))
        for i in Self.browsers.indices where !isInstalled(i) {
            browserPicker.setLabel("\(Self.browsers[i].0) (not installed)", forSegment: i); browserPicker.setEnabled(false, forSegment: i)
        }
        stack.addArrangedSubview(browserPicker)
        profileField = NSTextField(string: Prefs.browserProfile); profileField.placeholderString = "Default"
        profileField.widthAnchor.constraint(equalToConstant: 160).isActive = true
        let pl = NSTextField(labelWithString: "Chrome profile:")
        let profileLine = NSStackView(views: [pl, profileField]); profileLine.spacing = 8; profileLine.alignment = .firstBaseline
        profileRow = column([profileLine, text("Most people can leave this as “Default”. Using several Chrome profiles? In that profile open chrome://version and copy the last part of “Profile Path” (for example Profile 2).", size: 11, color: .secondaryLabelColor)])
        stack.addArrangedSubview(profileRow)

        step(2, "Sign in to YouTube in that browser")
        stack.addArrangedSubview(text("Click the button, sign in with your Google account, and come back here. Already signed in to YouTube there? Skip to step 3.", color: .secondaryLabelColor))
        openButton = NSButton(title: "Open YouTube Sign-In", target: self, action: #selector(openSignInPage)); openButton.bezelStyle = .rounded
        stack.addArrangedSubview(openButton)

        step(3, "Let Watch read that sign-in")
        chromeHelp = column([text("When you click Connect below, macOS asks whether “yt-dlp” may use your “Chrome Safe Storage” keychain item. Approve access only if you want Watch to read that browser session. “Always Allow” remembers permission; a one-time approval may ask again.", color: .secondaryLabelColor)])
        let fda = NSButton(title: "Open Full Disk Access Settings", target: self, action: #selector(openFullDiskAccess)); fda.bezelStyle = .rounded
        safariHelp = column([
            text("Safari keeps its sign-in locked away, so Watch needs Full Disk Access:\n• Click the button below.\n• Turn on Watch in the list. If it isn't listed, click +, choose Applications ▸ Watch, and click Open.\n• If macOS asks to quit and reopen Watch, click “Quit & Reopen”, then come back via Preferences ▸ YouTube Account ▸ Sign In….", color: .secondaryLabelColor),
            fda])
        stack.addArrangedSubview(chromeHelp)
        stack.addArrangedSubview(safariHelp)

        step(4, "Connect")
        accountField = NSTextField(string: Prefs.youtubeAccount); accountField.placeholderString = "Optional — only if you're signed into several"
        accountField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        let al = NSTextField(labelWithString: "Account email:")
        let acct = NSStackView(views: [al, accountField]); acct.spacing = 8; acct.alignment = .firstBaseline
        stack.addArrangedSubview(acct)
        connectButton = NSButton(title: "Connect", target: self, action: #selector(connect)); connectButton.bezelStyle = .rounded
        connectButton.keyEquivalent = "\r"
        stack.addArrangedSubview(connectButton)
        result = text("", weight: .medium)
        stack.addArrangedSubview(result)
        let history = NSButton(title: "Show My History", target: self, action: #selector(showHistory)); history.bezelStyle = .rounded
        let close = NSButton(title: "Done", target: self, action: #selector(closeWindow)); close.bezelStyle = .rounded
        let dr = NSStackView(views: [history, close]); dr.spacing = 8
        doneRow = dr; doneRow.isHidden = true
        stack.addArrangedSubview(dr)
        stack.addArrangedSubview(text("You can sign out, or switch browser or account, any time in Watch ▸ Preferences ▸ YouTube Account.", size: 11, color: .tertiaryLabelColor))
    }

    @objc private func browserChanged() {
        let chrome = browser.key == "chrome"
        profileRow.isHidden = !chrome; chromeHelp.isHidden = !chrome; safariHelp.isHidden = chrome
        openButton.title = "Open YouTube Sign-In in \(browser.name)"
    }
    // Opens Google's YouTube sign-in in the chosen browser (only if installed — never names a missing app).
    @objc private func openSignInPage() {
        guard let u = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/"),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.id) else { return }
        NSWorkspace.shared.open([u], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
    @objc private func openFullDiskAccess() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(u) }
    }
    @objc private func connect() {
        Prefs.cookieSource = browser.key
        Prefs.browserProfile = profileField.stringValue.isEmpty ? "Default" : profileField.stringValue
        Prefs.youtubeAccount = accountField.stringValue
        connectButton.isEnabled = false; doneRow.isHidden = true
        result.textColor = .secondaryLabelColor; result.stringValue = "Connecting… (answer any macOS password prompt)"
        YouTube.checkSignIn { [weak self] ok, err in
            guard let self = self else { return }
            self.connectButton.isEnabled = true
            if ok {
                Prefs.youtubeConnected = true
                self.result.textColor = .systemGreen
                self.result.stringValue = "✓ Signed in. Your History and Playlists are in the ••• menu of Watch's panel."
                self.doneRow.isHidden = false
            } else {
                let why = err.replacingOccurrences(of: "ERROR: ", with: "")
                let hint = self.browser.key == "safari"
                    ? "Check that Watch is on under Full Disk Access (step 3) and that you're signed in to YouTube in Safari."
                    : "Check that you're signed in to YouTube in Chrome (step 2) and that you approved Keychain access. If you use several Chrome profiles, check the profile name."
                self.result.textColor = .systemOrange
                self.result.stringValue = "Couldn't read your YouTube sign-in from \(self.browser.name). \(hint)\n\n\(why.prefix(200))"
            }
            NotificationCenter.default.post(name: .watchYouTubeAccountChanged, object: nil)
        }
    }
    @objc private func showHistory() { window.close(); (NSApp.delegate as? AppDelegate)?.showHistory() }
    @objc private func closeWindow() { window.close() }
}

// Clipboard video-link history (B5): ClipboardLink / ClipboardLinkStore live in Links.swift.

// ============================================================================
// MARK: - MediaMonitor (B3) — videos open in browser tabs.
// Polls only while the control panel is open; off-main, cancellable. Never triggers a system prompt on
// its own: only browsers that are RUNNING are touched (AppleScript naming an app that isn't installed pops a
// "Where is …?" chooser), and only once Automation access is already granted. Browsers still awaiting
// access are reported so the panel can offer a single, user-initiated "Allow" button.
// ============================================================================
struct MediaItem { let app: String; let title: String; let url: String?; let isPlaying: Bool }
struct Browser { let name: String; let bundleID: String; let chromium: Bool }

// Automation (TCC) status for sending Apple Events to a running app. ask=false never shows UI.
func automationPermission(_ bundleID: String, ask: Bool) -> OSStatus {
    let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
    return AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kCoreEventClass), AEEventID(kAEGetData), ask)
}
let errAEWouldRequireUserConsent: OSStatus = -1744

final class MediaMonitor {
    static let browsers = [
        Browser(name: "Safari", bundleID: "com.apple.Safari", chromium: false),
        Browser(name: "Google Chrome", bundleID: "com.google.Chrome", chromium: true),
        Browser(name: "Brave Browser", bundleID: "com.brave.Browser", chromium: true),
        Browser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", chromium: true),
        Browser(name: "Arc", bundleID: "company.thebrowser.Browser", chromium: true),
    ]
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "watch.mediamonitor")
    var onUpdate: (([MediaItem], [Browser]) -> Void)?     // (items, running browsers awaiting Automation access)
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.8)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }
    func stop() { timer?.cancel(); timer = nil; running = false }

    // Preferences ▸ "Allow Browser Access…": prompts only running browsers that haven't decided yet.
    func requestAccessForRunningBrowsers(completion: @escaping (Int) -> Void) {
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        let candidates = Self.browsers.filter { runningIDs.contains($0.bundleID) }
        queue.async { [weak self] in
            let waiting = candidates.filter { automationPermission($0.bundleID, ask: false) == errAEWouldRequireUserConsent }
            waiting.forEach { _ = automationPermission($0.bundleID, ask: true) }
            self?.poll(force: true)
            DispatchQueue.main.async { completion(waiting.count) }
        }
    }

    private func poll(force: Bool = false) {
        guard running || force else { return }
        guard Prefs.showBrowserTabs else { DispatchQueue.main.async { self.onUpdate?([], []) }; return }
        let runningIDs = Set(DispatchQueue.main.sync { NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier } })
        var items: [MediaItem] = [], waiting: [Browser] = []
        for b in Self.browsers where runningIDs.contains(b.bundleID) {
            let status = automationPermission(b.bundleID, ask: false)
            if status == noErr { items += Self.browserTabs(b) }
            else if status == errAEWouldRequireUserConsent { waiting.append(b) }
            // denied → stay silent; the user can re-enable in System Settings ▸ Privacy ▸ Automation
        }
        DispatchQueue.main.async { self.onUpdate?(items, waiting) }
    }

    // Needs "Allow JavaScript from Apple Events" enabled in the browser's Develop/View menu.
    // Without it the JS probe throws and the tab is silently skipped (best-effort, by design).
    private static func browserTabs(_ b: Browser) -> [MediaItem] {
        let jsCall = b.chromium ? "execute javascript jsSrc in t" : "do JavaScript jsSrc in t"
        let script = """
        set jsSrc to "(function(){var v=document.querySelector('video,audio');if(!v)return 'none';return v.paused?'paused':'playing';})();"
        tell application id "\(b.bundleID)"
            set out to ""
            try
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to ""
                        set nm to ""
                        set st to "none"
                        try
                            set u to URL of t
                        end try
                        try
                            set nm to name of t
                        end try
                        try
                            set st to \(jsCall)
                        end try
                        if st is "playing" or st is "paused" then
                            set out to out & u & "|||" & nm & "|||" & st & "@@@"
                        end if
                    end repeat
                end repeat
            end try
            return out
        end tell
        """
        var err: NSDictionary?
        guard let r = NSAppleScript(source: script)?.executeAndReturnError(&err), err == nil else { return [] }
        let raw = r.stringValue ?? ""
        guard !raw.isEmpty else { return [] }
        return raw.components(separatedBy: "@@@").filter { !$0.isEmpty }.compactMap { rec -> MediaItem? in
            let parts = rec.components(separatedBy: "|||")
            guard parts.count == 3, !parts[0].isEmpty else { return nil }
            return MediaItem(app: b.name, title: parts[1].isEmpty ? parts[0] : parts[1], url: parts[0], isPlaying: parts[2] == "playing")
        }
    }
}

// ============================================================================
// MARK: - PlayerWindowController (B2) — a single video player window
// ============================================================================
final class PlayerWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let sharedProcessPool = WKProcessPool()   // reuse instead of cold-spawning a web view per player
    static let standardSize = NSSize(width: 440, height: 247)   // 16:9 — every player stays this size
    static let barInset: CGFloat = 16                            // playback bar ↔ window sides (keeps off the corner resize)

    let window: NSWindow
    private var webView: WKWebView?
    private var videoView: PlayerVideoView?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var bridge: DashHLSBridge?               // must outlive the asset it serves playlists for
    private var statusObservation: NSKeyValueObservation?
    var sourceURL: String = ""
    var mediaTitle: String?
    var isLocalFile = false
    var isLive = false
    var dotButton: NSButton!
    private let surface = PlayerSurfaceView()
    private let controls = PlayerControlBar()
    private var hideControlsWork: DispatchWorkItem?
    private var previousSize: NSSize?                // the size before the most recent resize — double-click returns here
    private var resizeStartSize: NSSize?
    private let loadingView = NSView()
    private let spinner = NSProgressIndicator()
    private let loadingLabel = NSTextField(labelWithString: "Loading…")
    weak var manager: WindowManager?
    var isPinned = false
    // Every load() bumps the token; async results carrying an older token are dropped, so a replaced or
    // closed window never gets hijacked by a slow yt-dlp/bridge/embed callback.
    private var loadToken = 0
    private var pendingPlans: [StreamPlan] = []
    private var youtubeID: String?
    private var youtubeStart = 0
    private var listID: String?                      // `list=` from the link that opened this video
    private var triedWatchFallback = false
    private var endObserver: NSObjectProtocol?
    // Resume where this video was left off (PlaybackPositions). An explicit `t=` wins over the saved spot.
    // `positionKey` belongs to the AVPlayer actually playing — startLoad of the next video leaves it alone,
    // so the outgoing video is saved under its own key when playAsset/ensureWebView tears it down.
    private var resumeAt: Double = 0
    private var positionKey: String?
    private var positionReady = false                // no saves until the start/resume seek has landed
    private var lastPositionSave = Date.distantPast
    private var startSeconds: Int { youtubeStart > 0 ? youtubeStart : Int(resumeAt) }
    // The playlist whose place this window keeps (PlaylistProgress): a playlist link's `list=`, or a YouTube
    // video link's. `playlistStart` is set when opening the playlist carried on past its first video; it belongs
    // to that one load (`token`), so a quick Next or a web fallback can't show it on a different video.
    private var playlistID: String?
    private var playlistStart: (index: Int, count: Int, token: Int)?
    private var info: LinkInfo?                      // what yt-dlp said about this video — Add to Favourites keeps it
    // "Resumed at 12:34 · Start Over": says where playback picked up, for a few seconds, and undoes it.
    private let resumeChip = FadingButton(title: "", target: nil, action: nil)
    private var resumeChipAction: (() -> Void)?
    private var hideChipWork: DispatchWorkItem?
    // Up Next + the playback modes acting on it. The modes start from the last choice made anywhere
    // (Prefs) and are then this window's own; the queue is built on demand — see ensureQueue.
    private(set) var queue: PlayQueue?
    private var queueLoading = false
    private var queueWaiters: [() -> Void] = []
    private var queueTried = false                   // don't re-fetch a list that came back empty on every tick
    private var queueToken = 0                       // a new video here drops an in-flight list
    var autoplay = Prefs.autoplay
    var repeatMode = RepeatMode(rawValue: Prefs.repeatMode) ?? .off
    var shuffle = Prefs.shuffle

    init(manager: WindowManager) {
        self.manager = manager
        let size = Self.standardSize
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        setup(size: size)
    }
    private func setup(size: NSSize) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.minSize = NSSize(width: 68, height: 38)   // ~1.6x cursor-arrow height, still 16:9
        window.delegate = self

        // The whole content view is a drop target: dropping a link/file onto this window REPLACES
        // what it's playing (instead of opening a new window). The web/AV views sitting on top have
        // their own drag types unregistered (see ensureWebView / playAsset) so the drop falls to here.
        let drop = PlayerDropView(frame: NSRect(origin: .zero, size: size))
        drop.onDrop = { [weak self] s in self?.load(s) }
        window.contentView = drop

        // Loading state: spinner + title while yt-dlp resolves and AVPlayer buffers.
        loadingView.frame = drop.bounds; loadingView.autoresizingMask = [.width, .height]
        spinner.style = .spinning; spinner.appearance = NSAppearance(named: .darkAqua)
        spinner.frame = NSRect(x: (size.width - 32) / 2, y: size.height / 2 - 6, width: 32, height: 32)
        spinner.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        loadingLabel.font = .systemFont(ofSize: 11); loadingLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        loadingLabel.alignment = .center; loadingLabel.lineBreakMode = .byTruncatingTail
        loadingLabel.frame = NSRect(x: 24, y: size.height / 2 - 30, width: size.width - 48, height: 16)
        loadingLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        loadingView.addSubview(spinner); loadingView.addSubview(loadingLabel)
        drop.addSubview(loadingView)

        // Z-order (bottom → top): video/web view, loading, surface (drag · click zones · hover), controls, "…".
        surface.frame = drop.bounds; surface.autoresizingMask = [.width, .height]
        surface.onMultiClick = { [weak self] point, clicks in self?.multiClick(at: point, clicks: clicks) }
        surface.onHover = { [weak self] inside in
            self?.fadeDot(visible: inside)
            inside ? self?.showControls() : self?.hideControls()
        }
        surface.onRightClick = { [weak self] e in
            guard let self = self else { return }
            NSMenu.popUpContextMenu(self.playerMenu(), with: e, for: self.surface)
        }
        surface.onClick = { [weak self] down, up in
            guard let self = self else { return }
            if let wv = self.webView { self.window.makeFirstResponder(wv); wv.mouseDown(with: down); wv.mouseUp(with: up); return }
            let at = self.surface.convert(down.locationInWindow, from: nil)
            if self.player != nil, PlayerZone.at(at, in: self.surface.bounds.size) == .playPause { self.togglePlay(); self.showControls() }
        }
        surface.onScroll = { [weak self] e in self?.webView?.scrollWheel(with: e) }
        surface.onKey = { [weak self] e in self?.handleKey(e) ?? false }
        drop.addSubview(surface)

        resumeChip.isBordered = false; resumeChip.wantsLayer = true
        resumeChip.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        resumeChip.layer?.cornerRadius = 10
        resumeChip.alphaValue = 0
        resumeChip.target = self; resumeChip.action = #selector(resumeChipClicked)
        resumeChip.autoresizingMask = [.maxXMargin, .minYMargin]
        drop.addSubview(resumeChip)

        // Inset well clear of the window's corner and bottom-edge resize areas.
        controls.frame = NSRect(x: Self.barInset, y: 6, width: size.width - 2 * Self.barInset, height: 20)
        controls.autoresizingMask = [.width, .maxYMargin]
        controls.alphaValue = 0
        controls.onPlayPause = { [weak self] in self?.togglePlay() }
        controls.onSkip = { [weak self] s in self?.skip(s); self?.showControls() }
        controls.onMute = { [weak self] in self?.player?.isMuted.toggle(); self?.refreshControls() }
        controls.onSeek = { [weak self] f in self?.seek(toFraction: f) }
        drop.addSubview(controls)

        let dot = FadingButton(title: "", image: sym("ellipsis.circle.fill"), target: self, action: #selector(showMenu))
        dot.alphaValue = 0
        dot.isBordered = false; dot.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        dot.imageScaling = .scaleProportionallyDown; dot.toolTip = "Menu"
        dot.frame = NSRect(x: size.width - 20, y: size.height - 20, width: 16, height: 16)
        dot.autoresizingMask = [.minXMargin, .minYMargin]
        drop.addSubview(dot)
        dotButton = dot
        window.makeFirstResponder(surface)
    }
    // The "…" button shows only while the cursor is over the window.
    private func fadeDot(visible: Bool) {
        let target: CGFloat = visible ? 1 : 0
        guard dotButton.alphaValue != target else { return }
        NSAnimationContext.runAnimationGroup { $0.duration = visible ? 0.15 : 0.25; dotButton.animator().alphaValue = target }
    }
    private func showLoading(_ text: String) { loadingLabel.stringValue = text; loadingView.isHidden = false; spinner.startAnimation(nil) }
    private func hideLoading() { loadingView.isHidden = true; spinner.stopAnimation(nil) }

    // MARK: loading — the single entry point for new windows AND drop-to-replace, so the two never drift.
    // `queue` is the Up Next list this video came from (a playlist page, search results, History); without
    // one the window builds its own when Next is first needed (see ensureQueue). Stepping through Up Next
    // goes to startLoad instead, which keeps the list.
    func load(_ raw: String, queue: PlayQueue? = nil) {
        queueToken += 1
        queueLoading = false; queueWaiters = []; queueTried = queue != nil
        self.queue = queue
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = URLComponents(string: input)?.queryItems?.first { $0.name == "list" }?.value ?? ""
        playlistID = queue == nil && !list.isEmpty && (YouTube.isPlaylistLink(input) || parseYouTube(input) != nil) ? list : nil
        playlistStart = nil
        // A playlist link plays the playlist: read it flat first, then play the video it was left on.
        if queue == nil, YouTube.isPlaylistLink(input) { loadPlaylist(input); return }
        startLoad(input, title: queue?.current?.url == input ? queue?.current?.title : nil)
    }
    // A playlist link (…/playlist?list=…, or the search bar's "play this playlist"): one flat yt-dlp read
    // gives the whole list, so the first video starts quickly and the rest becomes Up Next. (Handing the
    // playlist URL straight to resolveStream made yt-dlp resolve every entry before anything played.)
    private func loadPlaylist(_ url: String) {
        loadToken += 1
        sourceURL = url; isLocalFile = false; mediaTitle = nil; isLive = false
        if !window.isVisible { window.makeKeyAndOrderFront(nil) }
        showLoading("Loading playlist…")
        let token = queueToken
        YouTube.playlist(url) { [weak self] name, vs in
            guard let self = self, token == self.queueToken else { return }
            guard !vs.isEmpty else { self.playlistID = nil; self.startLoad(url); return }   // unreadable → let the normal pipeline try
            if let n = name { self.manager?.onInfo?(url, LinkInfo(title: n, thumbnail: vs.first?.thumbnail)) }
            self.startPlaylist(name: name, items: vs.map { QueueItem(url: $0.url, title: $0.title) })
        }
    }
    // The playlist becomes Up Next and plays from the video it was left on — the next one if that was finished
    // (PlaylistProgress.startIndex); the start chip then says so.
    private func startPlaylist(name: String?, items: [QueueItem]) {
        queueTried = true
        let start = PlaylistProgress.startIndex(keys: items.map { VideoLinks.key($0.url) },
                                                saved: playlistID.flatMap { PlaylistProgress.shared.video(for: $0) },
                                                finished: { WatchedVideos.shared.isWatched($0) && PlaybackPositions.shared.position(for: $0) == nil })
        queue = PlayQueue(kind: .list, name: name ?? "Playlist", items: items, startAt: start, shuffled: shuffle)
        guard let item = queue?.current else { return }
        startLoad(item.url, title: item.title)
        if start > 0 { playlistStart = (start, items.count, loadToken) }
    }
    private func startLoad(_ raw: String, title: String? = nil) {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let fileURL: URL? = input.hasPrefix("file://") ? URL(string: input)
            : (FileManager.default.fileExists(atPath: input) ? URL(fileURLWithPath: input) : nil)
        guard fileURL != nil || looksLikeURL(input) else { NSSound.beep(); return }
        loadToken += 1
        let token = loadToken
        pendingPlans = []; youtubeID = nil; youtubeStart = 0; listID = nil; triedWatchFallback = false
        mediaTitle = title; isLive = false; resumeAt = 0; info = nil
        hideResumeChip()
        if let t = title { window.title = t }
        // Only a window that isn't on screen yet gets raised: autoplaying the next video mustn't yank
        // a player in front of whatever the user is doing.
        if !window.isVisible { window.makeKeyAndOrderFront(nil) }

        if let u = fileURL {
            sourceURL = input; isLocalFile = true
            mediaTitle = u.lastPathComponent; window.title = u.lastPathComponent
            showLoading(u.lastPathComponent)
            resumeAt = PlaybackPositions.shared.position(for: PlaybackPositions.key(source: input, youtubeID: nil)) ?? 0
            playAsset(AVURLAsset(url: u), token: token)
            return
        }
        isLocalFile = false
        if let yt = parseYouTube(input) {
            sourceURL = "https://www.youtube.com/watch?v=\(yt.id)"; youtubeID = yt.id; youtubeStart = yt.start
            listID = URLComponents(string: input)?.queryItems?.first { $0.name == "list" }?.value
        } else {
            sourceURL = input
        }
        if youtubeStart == 0 {
            resumeAt = PlaybackPositions.shared.position(for: PlaybackPositions.key(source: sourceURL, youtubeID: youtubeID)) ?? 0
        }
        recordPlaylistSpot()
        showLoading(title ?? "Loading…")
        var settled = false
        resolveStream(sourceURL) { [weak self] res in
            guard let self = self, token == self.loadToken, !settled else { return }
            settled = true
            guard let res = res, !res.plans.isEmpty else { self.fallbackToWeb(token); return }
            self.isLive = res.isLive
            if let t = res.title {
                self.mediaTitle = t; self.window.title = t; self.loadingLabel.stringValue = t
                let info = LinkInfo(title: t, thumbnail: res.thumbnail, duration: res.duration, isLive: res.isLive)
                self.info = info
                self.manager?.onInfo?(self.sourceURL, info)
            }
            self.pendingPlans = res.plans
            self.tryNextPlan(token)
        }
        // yt-dlp can hang on a bad network; don't leave the user staring at a spinner.
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self = self, token == self.loadToken, !settled else { return }
            settled = true; self.fallbackToWeb(token)
        }
    }
    private func tryNextPlan(_ token: Int) {
        guard token == loadToken else { return }
        guard !pendingPlans.isEmpty else { fallbackToWeb(token); return }
        switch pendingPlans.removeFirst() {
        case .single(let s):
            playAsset(AVURLAsset(url: s.url, options: s.assetOptions), token: token)
        case .split(let v, let a):
            DashHLSBridge.make(video: v, audio: a) { [weak self] bridge, asset in
                guard let self = self, token == self.loadToken else { return }
                guard let bridge = bridge, let asset = asset else { self.tryNextPlan(token); return }
                self.playAsset(asset, bridge: bridge, token: token)
            }
        }
    }
    // Nothing native worked (yt-dlp missing, outdated, or the site isn't supported): YouTube → IFrame embed,
    // anything else → the page itself.
    private func fallbackToWeb(_ token: Int) {
        guard token == loadToken else { return }
        if let id = youtubeID { loadYouTubeEmbed(id: id, start: startSeconds) }
        else if let u = URL(string: sourceURL) { ensureWebView().load(URLRequest(url: u)) }
    }
    private func playAsset(_ asset: AVURLAsset, bridge: DashHLSBridge? = nil, token: Int) {
        teardownWebView(); teardownAVPlayer()
        self.bridge = bridge
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        // A bare AVPlayerLayer, NOT AVPlayerView: AVPlayerView's built-in controls pin the view to ≥130pt tall,
        // which stops the window shrinking and letterboxes the video (see GOTCHAS).
        let vv = PlayerVideoView(frame: window.contentView!.bounds)
        vv.playerLayer.player = p
        vv.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(vv, positioned: .below, relativeTo: loadingView)
        videoView = vv
        player = p
        positionKey = isLive ? nil : PlaybackPositions.key(source: sourceURL, youtubeID: youtubeID)
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if Date().timeIntervalSince(self.lastPositionSave) >= 5 { self.savePosition() }
            self.prefetchUpNext()
            guard self.controls.alphaValue > 0 else { return }
            self.refreshControls()
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self = self, token == self.loadToken else { return }
            self.itemDidEnd()
        }
        window.makeFirstResponder(surface)
        let start = youtubeStart > 0 ? Double(youtubeStart) : resumeAt
        let resumed = youtubeStart == 0 && resumeAt > 0      // a saved position, not a link's own t=
        var becameReady = false
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self, token == self.loadToken, item === self.player?.currentItem else { return }
                switch item.status {
                case .readyToPlay where !becameReady:
                    becameReady = true
                    self.hideLoading()
                    if start > 0 && !self.isLive, let p = self.player {
                        // Within ±0.5 s like skips: a default seek snaps to a keyframe, which in a local file can be
                        // many seconds before the spot (a 40 s clip resumed "at 0:20" landed on 0:16.7).
                        p.seek(to: CMTime(seconds: start, preferredTimescale: 600),
                               toleranceBefore: Self.skipTolerance, toleranceAfter: Self.skipTolerance) { [weak self] _ in
                            DispatchQueue.main.async {
                                guard let self = self, token == self.loadToken, p === self.player else { return }
                                self.positionReady = true
                                self.showStartChip(resumedAt: resumed ? start : nil)
                            }
                        }
                    } else { self.positionReady = true; self.showStartChip(resumedAt: nil) }
                case .failed where !becameReady:
                    self.tryNextPlan(token)          // e.g. bridge/segment trouble → next plan (muxed), then web
                default: break
                }
            }
        }
        p.play()
        manager?.beginPlaybackActivity()
    }

    // YouTube IFrame Player API on a youtube.com origin under a desktop-Safari UA (see GOTCHAS: error 153).
    // Only reached when yt-dlp can't resolve the video; embed errors fall through to the full watch page.
    private func loadYouTubeEmbed(id: String, start: Int) {
        let wv = ensureWebView()
        let html = """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
        #p{position:fixed;inset:0;width:100%;height:100%}</style></head>
        <body><div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var reported=false;
        function send(m){try{window.webkit.messageHandlers.yt.postMessage(m);}catch(e){}}
        function gkWhere(){var p=window.gkPlayer;if(p&&p.getCurrentTime)send('time:\(id):'+p.getCurrentTime()+':'+p.getDuration());}
        setInterval(function(){if(window.gkPlayer&&gkPlayer.getPlayerState&&gkPlayer.getPlayerState()===1)gkWhere();},5000);
        function onYouTubeIframeAPIReady(){
          window.gkPlayer=new YT.Player('p',{videoId:'\(id)',
            playerVars:{autoplay:1,playsinline:1,rel:0,modestbranding:1,fs:1,start:\(start),origin:'https://www.youtube.com'},
            events:{
              'onReady':function(e){e.target.playVideo();},
              'onError':function(e){send('error:'+e.data);},
              'onStateChange':function(e){if(e.data===1||e.data===3){reported=true;send('playing');}
                                          else if(e.data===2){gkWhere();}
                                          else if(e.data===0){send('ended:\(id)');}}
            }});
        }
        setTimeout(function(){if(!reported)send('timeout');},8000);
        </script></body></html>
        """
        wv.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "yt" else { return }
        let body = (message.body as? String) ?? ""
        if body == "playing" { hideLoading(); return }
        // The embed saves its place as well: "time:<id>:<seconds>:<duration>" every 5 s while playing and on pause.
        // The id travels with it, so a late message from a replaced embed can't land on the next video.
        if body.hasPrefix("time:") {
            let parts = body.split(separator: ":", maxSplits: 3).map(String.init)
            guard parts.count == 4, let t = Double(parts[2]), let d = Double(parts[3]) else { return }
            let key = PlaybackPositions.key(source: "", youtubeID: parts[1]), duration = d > 0 ? d : nil
            PlaybackPositions.shared.save(t, duration: duration, for: key)
            if WatchedVideos.shared.noteProgress(t, duration: duration, for: key) { NotificationCenter.default.post(name: .watchLibraryChanged, object: nil) }
            return
        }
        // The embed fallback ends its video too — Autoplay / Repeat One work there as well.
        if body.hasPrefix("ended") {
            if let id = body.split(separator: ":").dropFirst().first { markWatched(PlaybackPositions.key(source: "", youtubeID: String(id))) }
            if repeatMode == .one { webView?.evaluateJavaScript("gkPlayer.seekTo(0,true);gkPlayer.playVideo()") }
            else if autoplay || repeatMode == .all { advance(1, auto: true) }
            return
        }
        if body == "timeout" || body.hasPrefix("error") { loadWatchPageFallback() }
    }
    private func loadWatchPageFallback() {
        guard let id = youtubeID, !triedWatchFallback else { return }
        triedWatchFallback = true
        var s = "https://www.youtube.com/watch?v=\(id)"
        if startSeconds > 0 { s += "&t=\(startSeconds)s" }
        if let u = URL(string: s) { ensureWebView().load(URLRequest(url: u)) }
    }
    private func ensureWebView() -> WKWebView {
        teardownAVPlayer()
        if let wv = webView { return wv }
        let cfg = WKWebViewConfiguration()
        cfg.processPool = Self.sharedProcessPool
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.preferences.isElementFullscreenEnabled = true
        cfg.userContentController.add(self, name: "yt")   // YouTube IFrame API → userContentController(_:didReceive:)
        let wv = WKWebView(frame: window.contentView!.bounds, configuration: cfg)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.uiDelegate = self
        // YouTube serves a broken/blocked player to WKWebView's default user-agent; a normal desktop
        // Safari UA gets the real player.
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        wv.setValue(false, forKey: "drawsBackground")
        wv.unregisterDraggedTypes()   // let drops fall through to the window's PlayerDropView (replace-in-place)
        window.contentView!.addSubview(wv, positioned: .below, relativeTo: loadingView)
        webView = wv
        return wv
    }
    private func teardownWebView() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "yt")
        webView?.removeFromSuperview(); webView = nil
    }
    private func teardownAVPlayer() {
        savePosition(); positionKey = nil; positionReady = false; skipTarget = nil
        statusObservation = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
        if let t = timeObserver { player?.removeTimeObserver(t); timeObserver = nil }
        hideControlsWork?.cancel(); controls.alphaValue = 0
        player?.pause(); videoView?.removeFromSuperview(); videoView = nil; player = nil; bridge = nil
    }

    // Remember where this video is (every 5s while playing, on pause, and when it's torn down or the app quits).
    // Near the start or end, PlaybackPositions forgets it instead.
    func savePosition() {
        guard positionReady, let key = positionKey, let p = player, let item = p.currentItem else { return }
        let d = item.duration, t = p.currentTime().seconds, duration = d.isNumeric && d.seconds > 0 ? d.seconds : nil
        PlaybackPositions.shared.save(t, duration: duration, for: key)
        if WatchedVideos.shared.noteProgress(t, duration: duration, for: key) { NotificationCenter.default.post(name: .watchLibraryChanged, object: nil) }
        lastPositionSave = Date()
    }
    private func markWatched(_ key: String) {
        guard !WatchedVideos.shared.isWatched(key) else { return }
        WatchedVideos.shared.mark(key)
        NotificationCenter.default.post(name: .watchLibraryChanged, object: nil)
    }
    // Remember which video of the window's playlist this is — only while the list being walked is that playlist
    // (not the recommendations an unreadable list falls back to).
    private func recordPlaylistSpot() {
        guard let list = playlistID, let id = youtubeID, queue == nil || queue?.kind == .list else { return }
        PlaylistProgress.shared.set(PlaybackPositions.key(source: sourceURL, youtubeID: id), for: list)
    }

    // MARK: the start chip — top-left, for a few seconds after playback starts somewhere other than the beginning:
    // a playlist that carried on past its first video ("Playlist: 8 of 20 at 3:10 · Start from the Top"), else a video
    // that resumed ("Resumed at 12:34 · Start Over"). Clicking it undoes that. Too-small windows skip it.
    private func showStartChip(resumedAt seconds: Double?) {
        if let (index, count, token) = playlistStart, token == loadToken {
            playlistStart = nil
            let at = seconds.map { " at \(formatDuration($0))" } ?? ""
            showResumeChip("Playlist: \(index + 1) of \(count)\(at)", "Start from the Top") { [weak self] in
                guard let self = self, let item = self.queue?.jump(toItem: 0) else { return }
                self.startLoad(item.url, title: item.title)
            }
        } else if let s = seconds {
            showResumeChip("Resumed at \(formatDuration(s))", "Start Over") { [weak self] in
                guard let p = self?.player else { return }
                self?.skipTarget = nil
                p.seek(to: .zero); p.play(); self?.refreshControls()
            }
        }
    }
    private func showResumeChip(_ text: String, _ undo: String, action: @escaping () -> Void) {
        let size = window.contentView?.bounds.size ?? Self.standardSize
        let white = NSColor.white
        let title = NSMutableAttributedString(string: text + "  ·  ", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: white.withAlphaComponent(0.85)])
        title.append(NSAttributedString(string: undo, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: white]))
        let w = ceil(title.size().width) + 20
        guard size.width >= w + 60, size.height >= 90 else { return }
        resumeChip.attributedTitle = title
        resumeChip.toolTip = undo
        resumeChip.frame = NSRect(x: 10, y: size.height - 30, width: w, height: 20)
        resumeChipAction = action
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; resumeChip.animator().alphaValue = 1 }
        hideChipWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideResumeChip(animated: true) }
        hideChipWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }
    private func hideResumeChip(animated: Bool = false) {
        hideChipWork?.cancel(); hideChipWork = nil; resumeChipAction = nil
        guard resumeChip.alphaValue > 0 else { return }
        if animated { NSAnimationContext.runAnimationGroup { $0.duration = 0.3; resumeChip.animator().alphaValue = 0 } }
        else { resumeChip.alphaValue = 0 }
    }
    @objc private func resumeChipClicked() {
        let action = resumeChipAction
        hideResumeChip(animated: true)
        action?()
    }

    // MARK: playback controls — tiny bar at the bottom, shown on hover, auto-hidden while playing
    private func refreshControls() {
        guard let p = player, let item = p.currentItem else { return }
        let dur = item.duration
        let live = isLive || !(dur.isNumeric && dur.seconds > 0)
        controls.update(playing: p.timeControlStatus != .paused, muted: p.isMuted,
                        current: p.currentTime().seconds, duration: live ? nil : dur.seconds)
    }
    private func togglePlay() {
        guard let p = player else { return }
        if p.timeControlStatus != .paused { p.pause(); savePosition() }
        else {
            if let d = p.currentItem?.duration, d.isNumeric, p.currentTime().seconds >= d.seconds - 0.25 { p.seek(to: .zero) }
            p.play()
        }
        refreshControls()
    }
    private func seek(toFraction f: Double) {
        guard let p = player, let d = p.currentItem?.duration, d.isNumeric, d.seconds > 0 else { return }
        skipTarget = nil
        p.seek(to: CMTime(seconds: f * d.seconds, preferredTimescale: 600))
        scheduleControlsHide()
    }
    // Rapid skips (a quick run of clicks, the ⟲/⟳ buttons, a held arrow key) stack on the last target instead of
    // re-reading currentTime while the previous seek is still in flight. A default-tolerance seek snaps to a
    // keyframe, which can be seconds away, so skips allow only half a second either side.
    private var skipTarget: Double?
    private static let skipTolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
    private func skip(_ seconds: Double) {
        guard let p = player else { return }
        var t = max(0, (skipTarget ?? p.currentTime().seconds) + seconds)
        if let d = p.currentItem?.duration, d.isNumeric, d.seconds > 0 { t = min(t, d.seconds) }
        skipTarget = t
        p.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: Self.skipTolerance, toleranceAfter: Self.skipTolerance) { [weak self] _ in
            DispatchQueue.main.async { if self?.skipTarget == t { self?.skipTarget = nil } }
        }
    }
    // Second and later clicks of a quick run, by zone (PlayerZone): the left/right thirds below the top skip 10 s per
    // click, the top third and bottom middle resize on the double-click, the centre ignores it (its first click
    // already played/paused). Web fallback: the page has its own controls, so a double-click anywhere resizes.
    private func multiClick(at point: NSPoint, clicks: Int) {
        guard player != nil else { if clicks == 2 { toggleSavedSize() }; return }
        switch PlayerZone.at(point, in: surface.bounds.size) {
        case .skipBack:    skip(-10); showControls()
        case .skipForward: skip(10); showControls()
        case .resize:      if clicks == 2 { toggleSavedSize() }
        case .playPause:   break
        }
    }
    private func handleKey(_ e: NSEvent) -> Bool {
        if e.modifierFlags.contains(.command) {      // ⌘←/⌘→ step through Up Next (same as the menu)
            switch e.keyCode {
            case 123: previousItem()
            case 124: nextItem()
            default:  return false
            }
            return true
        }
        guard player != nil else { return false }
        switch e.keyCode {
        case 49:  togglePlay(); showControls()       // space
        case 123: skip(-5); showControls()           // ←
        case 124: skip(5); showControls()            // →
        default:  return false
        }
        return true
    }
    private func showControls() {
        guard player != nil, loadingView.isHidden else { return }
        refreshControls()
        if controls.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; controls.animator().alphaValue = 1 }
        }
        scheduleControlsHide()
    }
    private func scheduleControlsHide() {
        hideControlsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.autoHideControls() }
        hideControlsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
    // Stays up while paused or while the cursor rests on the bar; otherwise fades out.
    private func autoHideControls() {
        guard let cv = window.contentView else { return }
        let m = cv.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if controls.isScrubbing || (cv.bounds.contains(m) && (player?.timeControlStatus == .paused || controls.frame.contains(m))) {
            scheduleControlsHide(); return
        }
        hideControls()
    }
    private func hideControls() {
        guard !controls.isScrubbing else { return }
        hideControlsWork?.cancel()
        guard controls.alphaValue > 0 else { return }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; controls.animator().alphaValue = 0 }
    }

    // MARK: Up Next — Next/Previous, and what happens when a video ends
    // This window can have an Up Next list as long as there's somewhere to look for one.
    private var canQueue: Bool { isLocalFile || youtubeID != nil }
    // Build the list if this window doesn't have one yet: the playlist a `list=` link carried, what
    // YouTube would play next after a lone video, or the folder a local file sits in. `done` runs either
    // way — callers check `queue` themselves.
    private func ensureQueue(_ done: @escaping () -> Void) {
        if queue != nil { done(); return }
        if queueLoading { queueWaiters.append(done); return }
        if isLocalFile {
            queueTried = true
            queue = PlayQueue.folder(for: sourceURL, shuffled: shuffle)
            done(); return
        }
        guard let id = youtubeID else { queueTried = true; done(); return }
        queueLoading = true; queueWaiters.append(done)
        let token = queueToken, here = QueueItem(url: sourceURL, title: mediaTitle)
        guard let list = listID else { loadRecommended(id: id, here: here, token: token); return }
        YouTube.playlist("https://www.youtube.com/playlist?list=\(list)") { [weak self] name, vs in
            guard let self = self else { return }
            let items = vs.map { QueueItem(url: $0.url, title: $0.title) }
            // Unreadable list (a `RD…` mix, or a private one we have no cookies for) → recommendations instead.
            guard !items.isEmpty else { self.loadRecommended(id: id, here: here, token: token); return }
            let start = items.firstIndex { parseYouTube($0.url)?.id == id } ?? 0
            self.finishQueue(PlayQueue(kind: .list, name: name ?? "Playlist", items: items,
                                       startAt: start, shuffled: self.shuffle), token: token)
        }
    }
    private func loadRecommended(id: String, here: QueueItem, token: Int) {
        YouTubeUpNext.load(id: id) { [weak self] items in
            guard let self = self else { return }
            self.finishQueue(items.isEmpty ? nil : PlayQueue(kind: .recommended, name: "YouTube Recommended",
                                                             items: [here] + items, shuffled: self.shuffle), token: token)
        }
    }
    private func finishQueue(_ q: PlayQueue?, token: Int) {
        guard token == queueToken else { return }       // a different video is in this window now
        queueLoading = false; queueTried = true
        if let q = q { queue = q }
        let waiting = queueWaiters; queueWaiters = []
        waiting.forEach { $0() }
    }
    // With autoplay on, have the list ready before the video ends — but only in its last minute, so
    // opening five players at once doesn't fire five page fetches.
    private func prefetchUpNext() {
        guard queue == nil, !queueTried, !queueLoading, canQueue, autoplay || repeatMode != .off else { return }
        guard let p = player, let d = p.currentItem?.duration, d.isNumeric, d.seconds > 0,
              d.seconds - p.currentTime().seconds < 60 else { return }
        ensureQueue {}
    }
    // Step through Up Next. `auto` = the video ended by itself, so stay quiet when there's nowhere to go.
    private func advance(_ delta: Int, auto: Bool = false) {
        if queue == nil, canQueue, !auto { showLoading("Up Next…") }
        ensureQueue { [weak self] in
            guard let self = self else { return }
            if let item = self.queue?.step(delta, wrap: self.repeatMode == .all) {
                self.startLoad(item.url, title: item.title); return
            }
            // Recommendations ran out: ask YouTube what comes after the video playing now.
            if delta > 0, self.queue?.kind == .recommended, let id = parseYouTube(self.sourceURL)?.id {
                let token = self.queueToken
                YouTubeUpNext.load(id: id) { [weak self] more in
                    guard let self = self, token == self.queueToken else { return }
                    if (self.queue?.append(more) ?? 0) > 0, let item = self.queue?.step(delta, wrap: false) {
                        self.startLoad(item.url, title: item.title)
                    } else { self.deadEnd(auto) }
                }
                return
            }
            self.deadEnd(auto)
        }
    }
    private func deadEnd(_ auto: Bool) {
        if player?.currentItem?.status == .readyToPlay { hideLoading() }
        if !auto { NSSound.beep() }
    }
    // Repeat One loops here; otherwise Autoplay (or Repeat All, which implies playing on) moves along.
    private func itemDidEnd() {
        if let k = positionKey { markWatched(k) }
        if repeatMode == .one { player?.seek(to: .zero); player?.play(); refreshControls(); return }
        guard autoplay || repeatMode == .all else { refreshControls(); return }
        advance(1, auto: true)
    }
    @objc func nextItem() { advance(1) }
    @objc func previousItem() { advance(-1) }
    // Previous / Next / the list itself. With no list yet (a lone video), opening the menu starts
    // fetching one, so a second look at it shows what's coming.
    private func addUpNext(_ m: NSMenu) {
        let wrap = repeatMode == .all
        let prev = addItem(m, "Previous", #selector(previousItem), key: NSLeftArrowFunctionKey)
        let ahead = queue?.peek(1, wrap: wrap)
        let next = addItem(m, ahead?.title.map { "Next: " + Self.shorten($0) } ?? "Next", #selector(nextItem), key: NSRightArrowFunctionKey)
        guard let q = queue else {
            prev.isEnabled = false; next.isEnabled = canQueue
            if canQueue { ensureQueue {} }
            return
        }
        prev.isEnabled = q.peek(-1, wrap: wrap) != nil
        next.isEnabled = ahead != nil || q.kind == .recommended      // recommendations top themselves up
        let up = NSMenuItem(title: "Up Next", action: nil, keyEquivalent: "")
        up.submenu = queueMenu(q)
        m.addItem(up)
    }
    // The list in play order (so Shuffle is visible), current item checked, click to jump to any of it.
    private func queueMenu(_ q: PlayQueue) -> NSMenu {
        let sm = NSMenu()
        let watched = WatchedVideos.shared.keys()
        let head = NSMenuItem(title: q.name, action: nil, keyEquivalent: "")
        head.isEnabled = false
        sm.addItem(head); sm.addItem(.separator())
        for i in q.order.prefix(60) {
            let item = q.items[i]
            let it = NSMenuItem(title: Self.shorten(item.title ?? item.url), action: #selector(queueItemChosen(_:)), keyEquivalent: "")
            it.target = self; it.tag = i
            it.state = i == q.currentIndex ? .on : .off
            if watched.contains(VideoLinks.key(item.url)) {     // watched: dimmed, like the panel's ✓ rows
                it.attributedTitle = NSAttributedString(string: it.title, attributes: [.foregroundColor: NSColor.secondaryLabelColor])
                it.toolTip = "Watched"
            }
            sm.addItem(it)
        }
        return sm
    }
    private func addPlaybackModes(_ m: NSMenu) {
        let auto = addItem(m, "Autoplay", #selector(toggleAutoplay))
        auto.state = autoplay ? .on : .off
        auto.toolTip = "When a video ends, play the next thing in Up Next."
        let all = addItem(m, "Repeat All", #selector(toggleRepeatAll))
        all.state = repeatMode == .all ? .on : .off
        all.toolTip = "Play the whole Up Next list on a loop."
        let one = addItem(m, "Repeat One", #selector(toggleRepeatOne))
        one.state = repeatMode == .one ? .on : .off
        one.toolTip = "Replay this video when it ends."
        let shuf = addItem(m, "Shuffle", #selector(toggleShuffle))
        shuf.state = shuffle ? .on : .off
        shuf.toolTip = "Play Up Next in a random order."
    }
    private static func shorten(_ s: String, _ max: Int = 46) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }
    @objc func queueItemChosen(_ sender: NSMenuItem) {
        guard let item = queue?.jump(toItem: sender.tag) else { return }
        startLoad(item.url, title: item.title)
    }
    @objc func toggleAutoplay() { autoplay.toggle(); Prefs.autoplay = autoplay }
    @objc func toggleRepeatAll() { setRepeat(repeatMode == .all ? .off : .all) }
    @objc func toggleRepeatOne() { setRepeat(repeatMode == .one ? .off : .one) }
    private func setRepeat(_ m: RepeatMode) { repeatMode = m; Prefs.repeatMode = m.rawValue }
    @objc func toggleShuffle() {
        shuffle.toggle(); Prefs.shuffle = shuffle
        queue?.setShuffle(shuffle)
    }

    // MARK: double-click — back to the size the window had before its latest resize. Every manual resize
    // updates that size, and a double-click itself counts as a resize, so repeated double-clicks toggle.
    func windowWillStartLiveResize(_ n: Notification) { resizeStartSize = window.frame.size }
    func windowDidEndLiveResize(_ n: Notification) {
        if let start = resizeStartSize, start != window.frame.size { previousSize = start }
        resizeStartSize = nil
    }
    private func toggleSavedSize() {
        let current = window.frame
        let target = previousSize ?? window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.standardSize)).size
        previousSize = current.size
        guard target != current.size else { return }
        var f = NSRect(x: current.minX, y: current.maxY - target.height, width: target.width, height: target.height)
        if let vis = (window.screen ?? NSScreen.main)?.visibleFrame {
            f.origin.x = min(max(f.minX, vis.minX), vis.maxX - f.width)
            f.origin.y = min(max(f.minY, vis.minY), vis.maxY - f.height)
        }
        window.setFrame(f, display: true, animate: true)
    }
    // A double-click that lands on the (invisible) title bar zooms instead — route it to the same toggle.
    func windowShouldZoom(_ w: NSWindow, toFrame newFrame: NSRect) -> Bool { toggleSavedSize(); return false }

    func webView(_ wv: WKWebView, didFinish navigation: WKNavigation!) { hideLoading() }
    // Embed page failed to load at the network level → try the full watch page once.
    func webView(_ wv: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loadWatchPageFallback() }
    func webView(_ wv: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loadWatchPageFallback() }

    func webView(_ wv: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = navigationAction.request.url { wv.load(URLRequest(url: u)) }
        return nil
    }

    // MARK: menus
    @discardableResult
    private func addItem(_ m: NSMenu, _ t: String, _ a: Selector, key: Int? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: t, action: a, keyEquivalent: key.flatMap { UnicodeScalar($0).map { String(Character($0)) } } ?? "")
        if key != nil { it.keyEquivalentModifierMask = .command }
        it.target = self; m.addItem(it)
        return it
    }
    @objc func showMenu() {
        playerMenu().popUp(positioning: nil, at: NSPoint(x: dotButton.frame.minX - 150, y: dotButton.frame.minY - 4), in: window.contentView)
    }
    private func playerMenu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        addItem(m, "Close", #selector(closeSelf))
        addItem(m, isPinned ? "Unpin" : "Pin (Always on Top)", #selector(togglePin))
        if (manager?.players.count ?? 0) > 1 { addItem(m, "Tile Windows", #selector(tileWindows)) }
        if !sourceURL.isEmpty, !YouTube.isPlaylistLink(sourceURL) {
            addItem(m, Favourites.shared.contains(sourceURL) ? "Remove from Favourites" : "Add to Favourites", #selector(toggleFavourite))
        }
        m.addItem(.separator())
        addUpNext(m)
        m.addItem(.separator())
        addPlaybackModes(m)
        if !isLocalFile {
            m.addItem(.separator())
            if isLive { addItem(m, "Record Live Stream", #selector(downloadVideo)) }
            else {
                func sub(_ title: String, _ items: [(String, DownloadKind)]) {
                    let it = NSMenuItem(title: title, action: nil, keyEquivalent: ""), sm = NSMenu()
                    for (t, k) in items {
                        let x = NSMenuItem(title: t, action: #selector(downloadKindChosen(_:)), keyEquivalent: "")
                        x.target = self; x.representedObject = DownloadRequest(sourceURL, mediaTitle, k); sm.addItem(x)
                    }
                    it.submenu = sm; m.addItem(it)
                }
                sub("Download Video", [("Original (Source Format)", .originalVideo), ("MP4 (Highest Quality)", .mp4Best)])
                sub("Download Audio", [("Original Audio", .originalAudio), ("MP3 (Source Bit Rate)", .mp3)])
            }
            m.addItem(.separator())
            addItem(m, "Copy Link", #selector(copyLink))
            addItem(m, "Open in Browser", #selector(openInBrowser))
        }
        return m
    }
    @objc func tileWindows() { manager?.tile(on: window.screen) }
    // A grid slot from Tile Windows. It counts as a resize, so a double-click afterwards returns to the old size.
    func moveToTile(_ f: NSRect) {
        if f.size != window.frame.size { previousSize = window.frame.size }
        window.animator().setFrame(f, display: true)
    }
    @objc func downloadVideo() { manager?.onDownload?(sourceURL, mediaTitle, .video) }
    @objc func downloadKindChosen(_ item: NSMenuItem) {
        guard let r = item.representedObject as? DownloadRequest else { return }
        manager?.onDownload?(r.link, r.title, r.kind)
    }
    @objc func togglePin() {
        isPinned.toggle()
        window.level = isPinned ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1) : .floating
    }
    @objc func toggleFavourite() {
        guard !sourceURL.isEmpty else { return }
        if Favourites.shared.contains(sourceURL) { Favourites.shared.remove(sourceURL) }
        else { Favourites.shared.add(sourceURL, info: info ?? LinkInfo(title: mediaTitle)) }
        NotificationCenter.default.post(name: .watchLibraryChanged, object: nil)
    }
    @objc func copyLink() {
        guard !sourceURL.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(sourceURL, forType: .string)
    }
    @objc func openInBrowser() { if let u = URL(string: sourceURL) { NSWorkspace.shared.open(u) } }
    @objc func closeSelf() { window.close() }
    func windowDidMove(_ n: Notification) { manager?.rememberFrame(window.frame) }
    func windowDidResize(_ n: Notification) { manager?.rememberFrame(window.frame) }
    func windowWillClose(_ n: Notification) {
        manager?.rememberFrame(window.frame)
        loadToken += 1; queueToken += 1; queueWaiters = []
        teardownAVPlayer(); teardownWebView()
        manager?.removed(self)
    }
}

// ============================================================================
// MARK: - WindowManager (B2) — owns every open player window; tiles/anchors them.
// ============================================================================
final class WindowManager {
    private(set) var players: [PlayerWindowController] = []
    private var activityToken: NSObjectProtocol?
    var onInfo: ((String, LinkInfo) -> Void)?                    // (sourceURL, what yt-dlp resolved: title, thumbnail, …)
    var onDownload: ((String, String?, DownloadKind) -> Void)?   // (sourceURL, title, kind)

    // `replacing` = the control panel's frame when the video takes the panel's place (see AppDelegate.play).
    @discardableResult
    func open(_ input: String, anchor: NSStatusItem, queue: PlayQueue? = nil, replacing: NSRect? = nil) -> PlayerWindowController {
        let pc = PlayerWindowController(manager: self)
        if let f = replacing { take(f, for: pc.window) } else { place(pc.window, anchor: anchor) }
        players.append(pc)
        pc.load(input, queue: queue)
        NSApp.activate(ignoringOtherApps: true)
        return pc
    }
    func removed(_ pc: PlayerWindowController) {
        players.removeAll { $0 === pc }
        if players.isEmpty { endPlaybackActivity() }
    }
    func closeAll() { players.forEach { $0.window.close() } }

    // Tile Windows: every visible player goes into one grid filling `screen` (the one the command came from).
    // Windows keep their reading order (top row left to right, …), so re-tiling respects a window dragged elsewhere.
    func tile(on screen: NSScreen?) {
        let tiled = players.filter { $0.window.isVisible && !$0.window.isMiniaturized && !$0.window.styleMask.contains(.fullScreen) }
        guard tiled.count > 1, let vis = (screen ?? tiled.last.flatMap { Self.screen(for: $0.window.frame) })?.visibleFrame else { return }
        let (cols, slots) = Tiling.grid(count: tiled.count, in: vis)
        let order = Tiling.readingOrder(tiled.map { $0.window.frame }, columns: cols)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            for (slot, i) in order.enumerated() { tiled[i].moveToTile(slots[slot]) }
        }
    }

    // The last player window's frame (position + size) is remembered across windows and launches.
    // Saved whenever a player moves, resizes, or closes (PlayerWindowController delegate callbacks).
    private static let frameKey = "lastPlayerFrame"
    func rememberFrame(_ f: NSRect) {
        guard f.width >= 60, f.height >= 34 else { return }
        UserDefaults.standard.set(NSStringFromRect(f), forKey: Self.frameKey)
    }
    private func rememberedFrame() -> NSRect? {
        guard let s = UserDefaults.standard.string(forKey: Self.frameKey) else { return nil }
        let r = NSRectFromString(s)
        return (r.width >= 60 && r.height >= 34) ? r : nil
    }

    // New window: first one opens at the remembered frame (or under the menu-bar icon the very first
    // time); further ones take the remembered SIZE and sit beside an existing player without overlap.
    // Existing windows are never moved.
    private func place(_ window: NSWindow, anchor: NSStatusItem) {
        let saved = rememberedFrame()
        let size = saved?.size ?? window.frameRect(forContentRect: NSRect(origin: .zero, size: PlayerWindowController.standardSize)).size
        if players.isEmpty {
            if let f = saved, let vis = Self.screen(for: f)?.visibleFrame { window.setFrame(Self.clamp(f, to: vis), display: true) }
            else { window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true); positionUnderStatusItem(window, anchor: anchor) }
            return
        }
        let gap: CGFloat = 12
        let others = players.map { $0.window.frame }
        for prev in others.reversed() {
            guard let vis = Self.screen(for: prev)?.visibleFrame else { continue }
            let candidates = [
                NSRect(x: prev.maxX + gap, y: prev.maxY - size.height, width: size.width, height: size.height),   // right
                NSRect(x: prev.minX - gap - size.width, y: prev.maxY - size.height, width: size.width, height: size.height), // left
                NSRect(x: prev.minX, y: prev.minY - gap - size.height, width: size.width, height: size.height),   // below
                NSRect(x: prev.minX, y: prev.maxY + gap, width: size.width, height: size.height),                 // above
            ]
            if let f = candidates.first(where: { c in vis.contains(c) && !others.contains(where: { $0.intersects(c) }) }) {
                window.setFrame(f, display: true); return
            }
        }
        // No free spot beside any window — cascade off the most recent one.
        let last = others.last!
        let vis = Self.screen(for: last)?.visibleFrame ?? last
        window.setFrame(Self.clamp(NSRect(x: last.minX + 28, y: last.maxY - 28 - size.height, width: size.width, height: size.height), to: vis), display: true)
    }
    // Sit where the panel was: the usual player size (remembered, else standard), centred on the panel's top edge.
    private func take(_ panel: NSRect, for window: NSWindow) {
        let size = rememberedFrame()?.size ?? window.frameRect(forContentRect: NSRect(origin: .zero, size: PlayerWindowController.standardSize)).size
        window.setFrame(Self.frame(replacing: panel, size: size), display: true)
    }
    // Shared with the artwork window: centred on the panel's top edge, kept on screen.
    static func frame(replacing panel: NSRect, size: NSSize) -> NSRect {
        let f = NSRect(x: panel.midX - size.width / 2, y: panel.maxY - size.height, width: size.width, height: size.height)
        guard let vis = screen(for: panel)?.visibleFrame else { return f }
        return clamp(f, to: vis)
    }
    // Just under the menu-bar icon, kept inside its screen horizontally.
    static func frame(under anchor: NSStatusItem, size: NSSize) -> NSRect? {
        guard let b = anchor.button, let bw = b.window else { return nil }
        let on = bw.convertToScreen(b.convert(b.bounds, to: nil))
        var f = NSRect(x: on.midX - size.width / 2, y: on.minY - size.height - 4, width: size.width, height: size.height)
        if let vis = bw.screen?.visibleFrame { f.origin.x = min(max(f.origin.x, vis.minX + 8), vis.maxX - f.width - 8) }
        return f
    }
    static func screen(for f: NSRect) -> NSScreen? {
        func overlap(_ s: NSScreen) -> CGFloat { let i = s.visibleFrame.intersection(f); return i.isNull ? 0 : i.width * i.height }
        guard let best = NSScreen.screens.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 else { return NSScreen.main }
        return best
    }
    static func clamp(_ f: NSRect, to vis: NSRect) -> NSRect {
        var r = f
        r.size.width = min(r.width, vis.width); r.size.height = min(r.height, vis.height)
        r.origin.x = min(max(r.minX, vis.minX), vis.maxX - r.width)
        r.origin.y = min(max(r.minY, vis.minY), vis.maxY - r.height)
        return r
    }
    private func positionUnderStatusItem(_ window: NSWindow, anchor: NSStatusItem) {
        guard let f = Self.frame(under: anchor, size: window.frame.size) else { return }
        window.setFrame(f, display: true)
    }
    // Disables App Nap while any player is open, so a visible-but-unfocused video isn't throttled.
    func beginPlaybackActivity() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Watch video playback")
    }
    func endPlaybackActivity() {
        if let t = activityToken { ProcessInfo.processInfo.endActivity(t); activityToken = nil }
    }
}

// ============================================================================
// MARK: - DragReceiverView (B4) — overlay on the status-item button for drag-and-drop
// ============================================================================
final class DragReceiverView: NSView {
    var onDrop: ((String) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL, .URL, .string]) }
    required init?(coder: NSCoder) { fatalError() }
    // Forward ordinary clicks to the button underneath so the icon still opens the panel.
    override func mouseDown(with event: NSEvent) { nextResponder?.mouseDown(with: event) }
    override func mouseUp(with event: NSEvent) { nextResponder?.mouseUp(with: event) }
    override func rightMouseUp(with event: NSEvent) { nextResponder?.rightMouseUp(with: event) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let u = urls.first {
            onDrop?(u.isFileURL ? u.path : u.absoluteString); return true
        }
        if let s = pb.string(forType: .string), !s.isEmpty { onDrop?(s); return true }
        return false
    }
}

// ============================================================================
// MARK: - Player window views
// ============================================================================
// Hosts an AVPlayerLayer as its backing layer. No Auto Layout inside, so the window can shrink freely.
final class PlayerVideoView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override func makeBackingLayer() -> CALayer {
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        return playerLayer
    }
}

// Transparent layer over the video: drag anywhere moves the window, hover reveals the controls. A click that
// doesn't turn into a drag goes to `onClick`; the rest of a quick run of clicks goes to `onMultiClick` with its
// location and count (2 = double-click) — what either does depends on the zone (PlayerZone).
final class PlayerSurfaceView: NSView {
    var onMultiClick: ((NSPoint, Int) -> Void)?
    var onHover: ((Bool) -> Void)?
    var onClick: ((NSEvent, NSEvent) -> Void)?
    var onScroll: ((NSEvent) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onKey: ((NSEvent) -> Bool)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { false }   // we move it ourselves, and keep title-bar clicks here
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with e: NSEvent) { onHover?(true) }
    override func mouseMoved(with e: NSEvent) { onHover?(true) }
    override func mouseExited(with e: NSEvent) { onHover?(false) }
    override func scrollWheel(with e: NSEvent) { onScroll?(e) }
    override func rightMouseDown(with e: NSEvent) { onRightClick?(e) }
    override func keyDown(with e: NSEvent) { if onKey?(e) != true { super.keyDown(with: e) } }
    override func mouseDown(with e: NSEvent) {
        guard let win = window else { return }
        if e.clickCount >= 2 { onMultiClick?(convert(e.locationInWindow, from: nil), e.clickCount); return }
        let startMouse = NSEvent.mouseLocation, startOrigin = win.frame.origin
        var dragging = false
        while let next = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { if !dragging { onClick?(e, next) }; return }
            let now = NSEvent.mouseLocation
            let dx = now.x - startMouse.x, dy = now.y - startMouse.y
            if !dragging && hypot(dx, dy) < 3 { continue }
            dragging = true
            win.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
        }
    }
}

// A button that can't be clicked while faded out.
final class FadingButton: NSButton {
    override func hitTest(_ point: NSPoint) -> NSView? { alphaValue < 0.05 ? nil : super.hitTest(point) }
}

// The playback bar: ⟲10 · play/pause · ⟳10 · scrubber · time · mute. Parts drop out as the window narrows
// (the skip buttons first, then the time, then mute).
final class PlayerControlBar: NSView {
    var onPlayPause: (() -> Void)?
    var onSkip: ((Double) -> Void)?
    var onMute: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    private(set) var isScrubbing = false
    private let backButton = NSButton(title: "", image: NSImage(), target: nil, action: nil)
    private let playButton = NSButton(title: "", image: NSImage(), target: nil, action: nil)
    private let forwardButton = NSButton(title: "", image: NSImage(), target: nil, action: nil)
    private let muteButton = NSButton(title: "", image: NSImage(), target: nil, action: nil)
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let timeLabel = NSTextField(labelWithString: "")
    private var isLiveStream = false
    private var longClock = false                    // an hour or more: "1:02:03 / 1:23:45" needs a wider label
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
    private static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        layer?.cornerRadius = 5
        for (b, a) in [(backButton, #selector(backTapped)), (playButton, #selector(playTapped)),
                       (forwardButton, #selector(forwardTapped)), (muteButton, #selector(muteTapped))] {
            b.isBordered = false; b.imageScaling = .scaleProportionallyDown
            b.contentTintColor = NSColor.white.withAlphaComponent(0.9)
            b.target = self; b.action = a
            addSubview(b)
        }
        backButton.image = sym("gobackward.10").withSymbolConfiguration(Self.symbolConfig); backButton.toolTip = "Back 10 seconds"
        forwardButton.image = sym("goforward.10").withSymbolConfiguration(Self.symbolConfig); forwardButton.toolTip = "Forward 10 seconds"
        slider.controlSize = .small; slider.isContinuous = true
        slider.target = self; slider.action = #selector(sliderMoved)
        addSubview(slider)
        timeLabel.font = Self.timeFont
        timeLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        timeLabel.alignment = .right
        addSubview(timeLabel)
        setIcons(playing: false, muted: false)
        layoutParts()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { alphaValue < 0.05 ? nil : super.hitTest(point) }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); layoutParts() }

    private func layoutParts() {
        let h = bounds.height, btn: CGFloat = 16, gap: CGFloat = 4, pad: CGFloat = 5, labelH: CGFloat = 12, y = (h - btn) / 2
        let skips = bounds.width >= 150
        backButton.isHidden = !skips; forwardButton.isHidden = !skips
        var x = pad
        for b in [backButton, playButton, forwardButton] where !b.isHidden {
            b.frame = NSRect(x: x, y: y, width: btn, height: btn); x += btn + gap
        }
        var right = bounds.width - pad
        muteButton.isHidden = bounds.width < 100
        if !muteButton.isHidden { muteButton.frame = NSRect(x: right - btn, y: y, width: btn, height: btn); right -= btn + gap }
        let left = x + 2
        if isLiveStream {
            slider.isHidden = true
            timeLabel.isHidden = false; timeLabel.alignment = .left; timeLabel.stringValue = "LIVE"
            timeLabel.frame = NSRect(x: left, y: (h - labelH) / 2, width: max(0, right - left), height: labelH)
            return
        }
        slider.isHidden = false; timeLabel.alignment = .right
        timeLabel.isHidden = bounds.width < 210
        if !timeLabel.isHidden {
            let w = Self.clockWidth(long: longClock)
            timeLabel.frame = NSRect(x: right - w, y: (h - labelH) / 2, width: w, height: labelH); right -= w + gap
        }
        slider.frame = NSRect(x: left, y: 0, width: max(0, right - left), height: h)
    }
    private static func clockWidth(long: Bool) -> CGFloat {
        let sample = long ? "0:00:00 / 0:00:00" : "00:00 / 00:00"
        return ceil((sample as NSString).size(withAttributes: [.font: timeFont]).width) + 4
    }
    private var iconState = (playing: false, muted: false)
    private func setIcons(playing: Bool, muted: Bool) {
        iconState = (playing, muted)
        playButton.image = sym(playing ? "pause.fill" : "play.fill").withSymbolConfiguration(Self.symbolConfig)
        muteButton.image = sym(muted ? "speaker.slash.fill" : "speaker.wave.2.fill").withSymbolConfiguration(Self.symbolConfig)
    }
    func update(playing: Bool, muted: Bool, current: Double, duration: Double?) {
        if playing != iconState.playing || muted != iconState.muted { setIcons(playing: playing, muted: muted) }
        let live = duration == nil, long = (duration ?? 0) >= 3600
        if live != isLiveStream || long != longClock { isLiveStream = live; longClock = long; layoutParts() }
        guard let d = duration, current.isFinite else { return }
        if !isScrubbing { slider.doubleValue = min(1, max(0, current / d)) }
        timeLabel.stringValue = "\(Self.clock(current)) / \(Self.clock(d))"
    }
    private static func clock(_ s: Double) -> String {
        let t = Int(max(0, s)), hrs = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return hrs > 0 ? String(format: "%d:%02d:%02d", hrs, m, sec) : String(format: "%d:%02d", m, sec)
    }
    @objc private func playTapped() { onPlayPause?() }
    @objc private func backTapped() { onSkip?(-10) }
    @objc private func forwardTapped() { onSkip?(10) }
    @objc private func muteTapped() { onMute?() }
    @objc private func sliderMoved() {
        isScrubbing = NSApp.currentEvent?.type != .leftMouseUp   // continuous slider: last action arrives on mouse-up
        onSeek?(slider.doubleValue)
    }
}

// ============================================================================
// MARK: - PlayerDropView — a player window's content view; accepts dropped links/files to
// REPLACE what that window is playing. The views above it don't register drag types, so the
// drop falls through to here.
// ============================================================================
final class PlayerDropView: NSView {
    var onDrop: ((String) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL, .URL, .string]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let u = urls.first {
            onDrop?(u.isFileURL ? u.path : u.absoluteString); return true
        }
        if let s = pb.string(forType: .string), !s.isEmpty { onDrop?(s); return true }
        return false
    }
}

// ============================================================================
// MARK: - Browse rows (search results · history · playlists) — compact, click to play/open
// ============================================================================
final class ThumbView: NSImageView {
    private static var cache: [String: NSImage] = [:]     // main-thread only
    private var wanted: String?
    func load(_ s: String?) {
        wanted = s
        image = sym("play.rectangle")
        guard let s = s, let url = URL(string: s) else { return }
        if let img = Self.cache[s] { image = img; return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async { Self.cache[s] = img; if self.wanted == s { self.image = img } }
        }.resume()
    }
    func show(_ img: NSImage) { wanted = nil; image = img }   // an in-memory picture (Now Playing artwork)
}

// One row style for every list in the panel: thumbnail · title · details line · optional accessory button.
// `compact` (Recent Links) is one title line with a small thumbnail — links don't need a big picture.
// `favourite` puts a ★ before the details line and `watched` a ✓ (plus a dimmed thumbnail). `progress` draws a resume
// bar along the thumbnail's bottom edge. `image` shows an in-memory picture instead of loading `thumb`; `square` makes the
// thumbnail 24×24 (album artwork, in the Now Playing row). `isHighlighted` is the keyboard selection
// (↑/↓ from the search field); `onMenu` supplies the right-click menu.
final class BrowseRowView: NSView {
    var onClick: (() -> Void)?
    var onMenu: (() -> NSMenu?)?
    var isHighlighted = false { didSet { updateBackground() } }
    private var hovering = false

    init(thumb: String?, title: String, meta: String, accessory: NSView?, compact: Bool = false,
         favourite: Bool = false, watched: Bool = false, progress: Double? = nil, image: NSImage? = nil, square: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        let t = ThumbView()
        if let img = image { t.show(img) } else { t.load(thumb) }
        t.imageScaling = .scaleProportionallyUpOrDown
        t.wantsLayer = true; t.layer?.cornerRadius = 4; t.layer?.masksToBounds = true
        t.contentTintColor = .tertiaryLabelColor
        let titleField: NSTextField
        if compact {
            titleField = NSTextField(labelWithString: title)
        } else {
            titleField = NSTextField(wrappingLabelWithString: title); titleField.maximumNumberOfLines = 2
        }
        titleField.font = .systemFont(ofSize: 12, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let metaField = NSTextField(labelWithString: meta)
        metaField.font = .systemFont(ofSize: 10.5); metaField.textColor = .secondaryLabelColor; metaField.lineBreakMode = .byTruncatingTail
        metaField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var metaLine: NSView = metaField
        var marks: [NSView] = []
        for (on, symbol, tint, tip) in [(favourite, "star.fill", NSColor.systemYellow, "Favourite"),
                                        (watched, "checkmark.circle.fill", NSColor.secondaryLabelColor, "Watched")] where on {
            let mark = NSImageView(image: sym(symbol))
            mark.symbolConfiguration = .init(pointSize: 8, weight: .semibold); mark.contentTintColor = tint
            mark.toolTip = tip
            marks.append(mark)
        }
        if !marks.isEmpty {
            let line = NSStackView(views: marks + [metaField]); line.spacing = 3; line.alignment = .centerY
            line.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            metaLine = line
        }
        if watched { t.alphaValue = 0.5 }
        let texts = NSStackView(views: [titleField, metaLine]); texts.orientation = .vertical; texts.alignment = .leading; texts.spacing = 2
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        texts.setHuggingPriority(.defaultLow, for: .horizontal)
        var views: [NSView] = [t, texts]
        if let a = accessory { views.append(a) }
        // .fill: the text column takes the free width, so the accessory sits at the trailing edge even beside a short title.
        let h = NSStackView(views: views); h.spacing = 8; h.alignment = .centerY; h.distribution = .fill
        h.translatesAutoresizingMaskIntoConstraints = false
        addSubview(h)
        let (w, ht, inset): (CGFloat, CGFloat, CGFloat) = square ? (24, 24, 3) : compact ? (32, 18, 3) : (80, 45, 4)
        NSLayoutConstraint.activate([
            t.widthAnchor.constraint(equalToConstant: w), t.heightAnchor.constraint(equalToConstant: ht),
            h.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), h.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            h.topAnchor.constraint(equalTo: topAnchor, constant: inset), h.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
        if let f = progress, f > 0 {
            let track = NSView(), bar = NSView()
            for v in [track, bar] { v.wantsLayer = true; v.translatesAutoresizingMaskIntoConstraints = false; t.addSubview(v) }
            track.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
            bar.layer?.backgroundColor = NSColor.systemRed.cgColor
            NSLayoutConstraint.activate([
                track.leadingAnchor.constraint(equalTo: t.leadingAnchor), track.trailingAnchor.constraint(equalTo: t.trailingAnchor),
                track.bottomAnchor.constraint(equalTo: t.bottomAnchor), track.heightAnchor.constraint(equalToConstant: compact ? 2 : 3),
                bar.leadingAnchor.constraint(equalTo: t.leadingAnchor), bar.bottomAnchor.constraint(equalTo: t.bottomAnchor),
                bar.heightAnchor.constraint(equalTo: track.heightAnchor),
                bar.widthAnchor.constraint(equalTo: t.widthAnchor, multiplier: CGFloat(min(1, max(0.03, f)))),
            ])
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }
    private func updateBackground() {
        layer?.backgroundColor = isHighlighted ? NSColor.controlAccentColor.withAlphaComponent(0.32).cgColor
            : hovering ? NSColor.white.withAlphaComponent(0.08).cgColor : nil
    }
    override func mouseEntered(with e: NSEvent) { hovering = true; updateBackground() }
    override func mouseExited(with e: NSEvent) { hovering = false; updateBackground() }
    override func mouseUp(with e: NSEvent) { if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() } }
    override func mouseDown(with e: NSEvent) {}   // keep the click here instead of dragging the panel
    override func menu(for event: NSEvent) -> NSMenu? { onMenu?() }
}

// A panel "page" pushed over the main view: History, Playlists, search results, a playlist's videos.
enum MessageAction { case none, signIn, retry, updateAndRetry }   // the button under a message page
// One YouTube search's results so far: `requested` is how many were asked for, `more` whether YouTube had that many.
struct SearchPage { var videos: [YTVideo]; var requested: Int; var more: Bool }
enum BrowsePage {
    case loading(String, note: String = "Loading…")
    case videos(String, [YTVideo])
    case results(String, SearchPage)                  // a YouTube search: (query, results)
    case playlists([YTPlaylist])
    case message(String, String, action: MessageAction)
    var title: String {
        switch self {
        case .loading(let t, _), .videos(let t, _), .message(let t, _, _): return t
        case .results(let q, _): return "“\(q)”"
        case .playlists: return "Playlists"
        }
    }
}
// A page plus how to load it again (Try Again). The fetch returns the yt-dlp task when it can be cancelled.
typealias BrowseFetch = (@escaping (BrowsePage) -> Void) -> YtDlpTask?
struct BrowseEntry { var page: BrowsePage; let fetch: BrowseFetch? }

// A menu item that runs a closure (row context menus).
final class ClosureMenuItem: NSMenuItem {
    private var handler: (() -> Void)?
    convenience init(_ title: String, handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self; self.handler = handler
    }
    @objc private func fire() { handler?() }
}

// ============================================================================
// MARK: - App Delegate (the control panel)
// ============================================================================
// Carries a download choice through an NSMenuItem.
final class DownloadRequest: NSObject {
    let link: String, title: String?, kind: DownloadKind
    init(_ link: String, _ title: String?, _ kind: DownloadKind) { self.link = link; self.title = title; self.kind = kind }
}
// "Advanced Formats" submenu: fetched once, the first time it opens.
final class FormatsMenu: NSMenu {
    var link = "", videoTitle: String?, loaded = false
}
// A button that runs a closure (rows build these per item).
final class FlippedView: NSView { override var isFlipped: Bool { true } }   // scroll documents that start at the top

final class ClosureButton: NSButton {
    var handler: ((NSButton) -> Void)?
    convenience init(symbol: String, tip: String, handler: @escaping (NSButton) -> Void) {
        self.init(title: "", image: sym(symbol), target: nil, action: nil)
        isBordered = false; contentTintColor = .secondaryLabelColor; toolTip = tip
        target = self; action = #selector(fire); self.handler = handler
        widthAnchor.constraint(equalToConstant: 20).isActive = true
    }
    @objc private func fire() { handler?(self) }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    var statusItem: NSStatusItem!
    var dropdown: NSWindow!
    var hotKeyRef: EventHotKeyRef?
    var settingsController: SettingsController?
    var welcomeController: WelcomeController?
    var signInController: YouTubeSignInController?
    var suppressMoveSave = false
    var dragView: DragReceiverView?
    var pendingURLPlays: [String] = []

    let windowManager = WindowManager()
    let mediaMonitor = MediaMonitor()
    let downloads = DownloadManager()
    var mediaItems: [MediaItem] = []
    var browsersAwaitingAccess: [Browser] = []
    // Now Playing: what another app is playing (NowPlaying.swift) — the list's first row; its artwork opens in
    // `artworkWindow`, which then follows the music. The adapter runs only while the panel or that window shows.
    let nowPlaying = NowPlayingMonitor()
    var nowPlayingInfo: NowPlayingInfo?
    var nowPlayingImage: NSImage?               // decoded once per artwork change
    var nowPlayingRow: NSStackView!
    var artworkWindow: ArtworkWindowController?
    var lastClipboardChangeCount = NSPasteboard.general.changeCount
    var clipboardTimer: Timer?

    // The one field: search YouTube, or paste a link to play it. Typing filters Recent Links; ↑/↓ + Return
    // pick a row (`highlighted`); Esc clears, goes back, then hides the panel.
    var searchField: NSSearchField!
    var pasteDownloadButton: NSButton!
    var highlighted: Int?
    var mediaHeader: NSView!
    var mediaSection: NSStackView!
    var mainScroll: NSScrollView!
    // Browse pages (search results · History · Playlists) slide over the main view; Back pops.
    var browseView: NSView!
    var browseScroll: NSScrollView!
    var browseList: NSStackView!
    var browseTitle: NSTextField!
    var browseAction: NSButton!
    var browseStack: [BrowseEntry] = []
    var browseToken = 0
    var browseTask: YtDlpTask?                  // the page's running yt-dlp call; a newer page or Back cancels it
    var searchCache = SearchCache<SearchPage>()
    let liveSearch = LiveSearch()
    var activeSearchQuery: String?
    var downloadsHeader: NSView!
    var downloadsSection: NSStackView!
    var clipSection: NSStackView!
    var clipTitle: NSTextField!                 // "Matching Links" while the field filters; the tabs otherwise
    var listTabs: NSStackView!                  // Recent Links | ★ Favourites (Prefs.showFavourites)
    var recentTab: NSButton!
    var favouritesTab: NSButton!
    var statusLabel: NSTextField!

    // Short: the field and the newest links; everything else scrolls. The first video takes the panel's place
    // (see play).
    let panelW: CGFloat = 320, panelH: CGFloat = 250
    let headerH: CGFloat = 40, fieldH: CGFloat = 34   // header, then the pinned field row; pages fill the rest
    let links = ClipboardLinkStore.shared
    let favourites = Favourites.shared

    func applicationWillFinishLaunching(_ n: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.removeObject(forKey: "watchFrame")   // legacy: panel no longer restores a detached frame
        Prefs.detached = false
        setupStatusItem()
        setupPanel()
        setupMainMenu()
        installHotkeyHandler()
        applyHotkey(keyCode: Prefs.hotkeyKeyCode, carbonModifiers: Prefs.hotkeyCarbon)
        registerLoginItem()
        favourites.importPins(from: links)          // once: 3.12's Recent Links pins become favourites
        startClipboardWatch()
        mediaMonitor.onUpdate = { [weak self] items, waiting in
            self?.mediaItems = items; self?.browsersAwaitingAccess = waiting; self?.rebuildMediaSection()
        }
        nowPlaying.onUpdate = { [weak self] info in self?.nowPlayingChanged(info) }
        windowManager.onInfo = { [weak self] url, info in
            self?.links.update(url, with: info); self?.favourites.update(url, with: info); self?.rebuildClipSection()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .watchLibraryChanged, object: nil)
        windowManager.onDownload = { [weak self] url, title, kind in self?.startDownload(url, title: title, kind: kind) }
        downloads.onChange = { [weak self] in self?.rebuildDownloadsSection() }
        downloads.onFinish = { [weak self] job in
            switch job.state {
            case .done:   self?.flash("Downloaded ✓")
            case .failed: self?.flash("Download failed")
            default: break
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(appResignedActive),
                                               name: NSApplication.didResignActiveNotification, object: nil)
        let queued = pendingURLPlays
        pendingURLPlays.removeAll()
        queued.forEach { play($0) }
        // First launch only: the setup guide (reopen any time from Preferences ▸ Setup Guide…).
        if !Prefs.hasSeenWelcome { Prefs.hasSeenWelcome = true; openWelcome() }
    }
    func applicationWillTerminate(_ n: Notification) {
        liveSearch.cancel(); browseTask?.cancel()
        windowManager.players.forEach { $0.savePosition() }
        downloads.stopAll()
        nowPlaying.stopAll()
    }
    @objc func handleURLEvent(_ e: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let raw = e.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let comps = URLComponents(string: raw),
              comps.scheme == "glasskit-watch",
              comps.host == "play",
              let videoURL = comps.queryItems?.first(where: { $0.name == "url" })?.value,
              !videoURL.isEmpty else { return }
        if statusItem == nil { pendingURLPlays.append(videoURL) }
        else { play(videoURL) }
    }
    @objc func appResignedActive() {
        if dropdown.isVisible && !Prefs.pinned && !Prefs.detached { stopPanelSearch(); dropdown.orderOut(nil); stopPanelMonitors() }
    }

    // MARK: status item + drag-and-drop (B4)
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: "Watch")
            b.action = #selector(statusClicked); b.target = self
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            let drag = DragReceiverView(frame: b.bounds)
            drag.autoresizingMask = [.width, .height]
            drag.onDrop = { [weak self] s in self?.play(s) }
            b.addSubview(drag)
            dragView = drag
        }
    }
    @objc func statusClicked() {
        if let e = NSApp.currentEvent, e.type == .rightMouseUp {
            statusItem.menu = appMenu(); statusItem.button?.performClick(nil); statusItem.menu = nil
        } else { togglePanel() }
    }

    // MARK: control panel window
    func setupPanel() {
        dropdown = NSWindow(contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        dropdown.titleVisibility = .hidden
        dropdown.titlebarAppearsTransparent = true
        dropdown.standardWindowButton(.closeButton)?.isHidden = true
        dropdown.standardWindowButton(.miniaturizeButton)?.isHidden = true
        dropdown.standardWindowButton(.zoomButton)?.isHidden = true
        dropdown.isMovableByWindowBackground = true
        dropdown.level = .floating
        dropdown.collectionBehavior = [.moveToActiveSpace]
        dropdown.minSize = NSSize(width: 260, height: 200)
        dropdown.hidesOnDeactivate = false
        dropdown.isReleasedWhenClosed = false
        dropdown.delegate = self
        dropdown.contentView = makeGlassContentView()
        let content = dropdown.contentView!

        let header = NSView(frame: NSRect(x: 0, y: panelH - headerH, width: panelW, height: headerH))
        header.autoresizingMask = [.width, .minYMargin]
        let mini = NSButton(title: "", image: sym("menubar.arrow.up.rectangle"), target: self, action: #selector(minimizeToMenuBar))
        mini.isBordered = false; mini.contentTintColor = .secondaryLabelColor; mini.frame = NSRect(x: 12, y: 9, width: 24, height: 22)
        mini.toolTip = "Hide the panel (Esc)"; header.addSubview(mini)
        statusLabel = NSTextField(labelWithString: "Watch")
        statusLabel.alignment = .center; statusLabel.font = .systemFont(ofSize: 11); statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 40, y: 11, width: panelW - 110, height: 16); statusLabel.autoresizingMask = [.width]
        header.addSubview(statusLabel)
        let dots = NSButton(title: "", image: sym("ellipsis.circle"), target: self, action: #selector(showDotMenu(_:)))
        dots.isBordered = false; dots.contentTintColor = .secondaryLabelColor
        dots.frame = NSRect(x: panelW - 32, y: 9, width: 24, height: 22); dots.autoresizingMask = [.minXMargin]
        dots.toolTip = "Menu"; header.addSubview(dots)

        // The field row: pinned under the header, so it stays put while search results are showing.
        let fieldRow = NSView(frame: NSRect(x: 0, y: panelH - headerH - fieldH, width: panelW, height: fieldH))
        fieldRow.autoresizingMask = [.width, .minYMargin]
        searchField = NSSearchField(string: "")
        searchField.placeholderString = "Search YouTube or paste a link"
        searchField.sendsWholeSearchString = true
        searchField.cell?.sendsActionOnEndEditing = false
        searchField.delegate = self                  // Return / ↑ / ↓ / Esc: control(_:textView:doCommandBy:)
        searchField.target = self; searchField.action = #selector(searchFieldAction(_:))
        searchField.toolTip = "Type to search YouTube. Return searches now or plays a link — with the field empty, the copied link. ↑/↓ pick a row."
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pasteDownloadButton = NSButton(title: "", image: sym("arrow.down.circle"), target: self, action: #selector(showPasteDownloadMenu))
        pasteDownloadButton.isBordered = false; pasteDownloadButton.contentTintColor = .secondaryLabelColor
        pasteDownloadButton.toolTip = "Download this link (or the copied link)"
        pasteDownloadButton.widthAnchor.constraint(equalToConstant: 20).isActive = true
        let fieldStack = NSStackView(views: [searchField, pasteDownloadButton]); fieldStack.spacing = 6
        fieldStack.translatesAutoresizingMaskIntoConstraints = false
        fieldRow.addSubview(fieldStack)
        NSLayoutConstraint.activate([
            fieldStack.leadingAnchor.constraint(equalTo: fieldRow.leadingAnchor, constant: 14),
            fieldStack.trailingAnchor.constraint(equalTo: fieldRow.trailingAnchor, constant: -12),
            fieldStack.centerYAnchor.constraint(equalTo: fieldRow.centerYAnchor),
        ])
        rebuildSearchMenu()

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH - headerH - fieldH))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let outer = NSStackView(); outer.orientation = .vertical; outer.alignment = .leading; outer.spacing = 14
        outer.translatesAutoresizingMaskIntoConstraints = false
        // The document is a flipped view pinned to the clip view at zero, with the padding inside it. With the
        // stack itself as the (unflipped) document and offset constraints, content taller than the short panel
        // was scrolled to the document's origin — a blank band on top, text flush left (see GOTCHAS).
        let doc = FlippedView(); doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(outer)
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            outer.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 14),
            outer.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -14),
            outer.topAnchor.constraint(equalTo: doc.topAnchor, constant: 6),
            outer.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -10),
        ])

        // Now Playing — another app's media with its artwork; hidden unless something is playing (rebuildNowPlayingRow).
        nowPlayingRow = NSStackView(); nowPlayingRow.orientation = .vertical; nowPlayingRow.alignment = .leading
        nowPlayingRow.isHidden = true
        outer.addArrangedSubview(nowPlayingRow)
        nowPlayingRow.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        outer.setCustomSpacing(8, after: nowPlayingRow)

        // Both library tabs list every stored item inside the existing compact scroll area.
        clipTitle = sectionLabel("Matching Links")
        recentTab = listTab("Recent Links", symbol: nil, tip: "Video links you've copied or played", #selector(showRecentList))
        favouritesTab = listTab("Favourites", symbol: "star.fill", tip: "Videos you've added to Favourites", #selector(showFavouritesList))
        listTabs = NSStackView(views: [recentTab, favouritesTab]); listTabs.spacing = 12
        let clipHeader = NSStackView(views: [listTabs, clipTitle, NSView()]); clipHeader.spacing = 6
        outer.addArrangedSubview(clipHeader)
        clipHeader.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        outer.setCustomSpacing(4, after: clipHeader)
        clipSection = NSStackView(); clipSection.orientation = .vertical; clipSection.alignment = .leading; clipSection.spacing = 2
        outer.addArrangedSubview(clipSection)
        clipSection.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true

        // Downloads (hidden until there is one)
        downloadsHeader = sectionLabel("Downloads")
        outer.addArrangedSubview(downloadsHeader)
        downloadsSection = NSStackView(); downloadsSection.orientation = .vertical; downloadsSection.alignment = .leading; downloadsSection.spacing = 4
        outer.addArrangedSubview(downloadsSection)
        rebuildDownloadsSection()

        // Open media (B3) — the whole section is hidden unless a browser tab has a video
        let mh = NSStackView(views: [sectionLabel("Open in Browser Tabs"), NSView(), openAllButton()])
        mh.spacing = 6
        mediaHeader = mh
        outer.addArrangedSubview(mh)
        mediaSection = NSStackView(); mediaSection.orientation = .vertical; mediaSection.alignment = .leading; mediaSection.spacing = 4
        outer.addArrangedSubview(mediaSection)
        rebuildMediaSection()

        mainScroll = scroll
        content.addSubview(scroll)
        setupBrowseView(in: content)
        content.addSubview(fieldRow)
        content.addSubview(header)
        rebuildClipSection()
    }
    private func setupBrowseView(in content: NSView) {
        let barH: CGFloat = 30
        let v = NSView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH - headerH - fieldH))
        v.autoresizingMask = [.width, .height]; v.isHidden = true
        let bar = NSView(frame: NSRect(x: 0, y: v.bounds.height - barH, width: panelW, height: barH))
        bar.autoresizingMask = [.width, .minYMargin]
        let back = NSButton(title: "", image: sym("chevron.left"), target: self, action: #selector(browseBack))
        back.isBordered = false; back.contentTintColor = .secondaryLabelColor; back.toolTip = "Back (Esc)"
        back.frame = NSRect(x: 10, y: 5, width: 22, height: 20); bar.addSubview(back)
        browseTitle = NSTextField(labelWithString: "")
        browseTitle.font = .boldSystemFont(ofSize: 12); browseTitle.lineBreakMode = .byTruncatingTail
        browseTitle.frame = NSRect(x: 36, y: 7, width: panelW - 72, height: 16); browseTitle.autoresizingMask = [.width]
        bar.addSubview(browseTitle)
        browseAction = NSButton(title: "", image: sym("arrow.down.circle"), target: self, action: #selector(downloadAllPlaylists))
        browseAction.isBordered = false; browseAction.contentTintColor = .secondaryLabelColor; browseAction.toolTip = "Download all playlists"
        browseAction.frame = NSRect(x: panelW - 32, y: 5, width: 22, height: 20); browseAction.autoresizingMask = [.minXMargin]
        bar.addSubview(browseAction)
        v.addSubview(bar)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: panelW, height: v.bounds.height - barH))
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let list = NSStackView(); list.orientation = .vertical; list.alignment = .leading; list.spacing = 2
        list.translatesAutoresizingMaskIntoConstraints = false
        // Same flipped-document arrangement as the main list (see GOTCHAS: blank band in a short scroll panel);
        // it also keeps the scroll position put when "Show More Results" appends rows.
        let doc = FlippedView(); doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(list)
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            list.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 8),
            list.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -8),
            list.topAnchor.constraint(equalTo: doc.topAnchor, constant: 2),
            list.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -8),
        ])
        v.addSubview(scroll)
        content.addSubview(v)
        browseView = v; browseScroll = scroll; browseList = list
    }
    private func sectionLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s.uppercased())
        l.font = .boldSystemFont(ofSize: 10); l.textColor = .tertiaryLabelColor
        return l
    }
    // A list tab styled like a section label; the selected one is brighter (updateListTabs).
    private func listTab(_ s: String, symbol: String?, tip: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: s.uppercased(), target: self, action: action)
        b.isBordered = false; b.toolTip = tip
        if let name = symbol {
            b.image = sym(name).withSymbolConfiguration(.init(pointSize: 8, weight: .bold)); b.imagePosition = .imageLeading
        }
        return b
    }
    private func updateListTabs() {
        for (b, on) in [(recentTab!, !Prefs.showFavourites), (favouritesTab!, Prefs.showFavourites)] {
            let color: NSColor = on ? .labelColor : .tertiaryLabelColor
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [.font: NSFont.boldSystemFont(ofSize: 10), .foregroundColor: color])
            b.contentTintColor = on && b === favouritesTab ? .systemYellow : color
        }
    }
    @objc func showRecentList() { selectList(favourites: false) }
    @objc func showFavouritesList() { selectList(favourites: true) }
    private func selectList(favourites on: Bool) {
        guard Prefs.showFavourites != on else { return }
        Prefs.showFavourites = on
        highlighted = nil
        rebuildClipSection()
        mainScroll.contentView.scroll(to: .zero)
        mainScroll.reflectScrolledClipView(mainScroll.contentView)
    }
    private func hint(_ s: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: 12); l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = panelW - 40
        return l
    }
    private func openAllButton() -> NSButton {
        let b = NSButton(title: "Open All", target: self, action: #selector(openAllMedia))
        b.bezelStyle = .rounded; b.controlSize = .small
        return b
    }
    // Shown only while some browser tab has a video; otherwise the section (header included) disappears.
    // Granting browser access lives in Preferences ▸ "Allow Browser Access…".
    func rebuildMediaSection() {
        mediaSection.subviews.forEach { $0.removeFromSuperview() }
        let show = Prefs.showBrowserTabs && !mediaItems.isEmpty
        mediaHeader.isHidden = !show; mediaSection.isHidden = !show
        guard show else { return }
        let grouped = Dictionary(grouping: mediaItems, by: { $0.app })
        for app in grouped.keys.sorted() {
            let appLabel = NSTextField(labelWithString: app)
            appLabel.font = .boldSystemFont(ofSize: 11); appLabel.textColor = .secondaryLabelColor
            mediaSection.addArrangedSubview(appLabel)
            for item in grouped[app] ?? [] {
                let b = NSButton(title: (item.isPlaying ? "▶︎ " : "⏸ ") + item.title, target: self, action: #selector(mediaRowClicked(_:)))
                b.bezelStyle = .inline; b.alignment = .left; b.lineBreakMode = .byTruncatingTail
                b.widthAnchor.constraint(equalToConstant: panelW - 40).isActive = true
                b.toolTip = item.url
                mediaSection.addArrangedSubview(b)
            }
        }
    }
    // The Recent Links or Favourites tab — or, while the field has text, the favourites and links matching it
    // (favourites first) under a line saying what Return will do. Rows: thumbnail (with a resume bar), title,
    // ★/✓ marks, "site · resume/duration · when".
    func rebuildClipSection() {
        rebuildNowPlayingRow()                      // hidden while the field filters
        let keep = highlighted
        clipSection.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtering = !query.isEmpty, favs = favourites.all()
        clipTitle.isHidden = !filtering; listTabs.isHidden = filtering
        updateListTabs()
        let marks = LibraryMarks(favourites: Set(favs.map { VideoLinks.key($0.url) }), watched: WatchedVideos.shared.keys())
        var rows: [BrowseRowView] = []
        if filtering {
            clipSection.addArrangedSubview(returnHint(for: query))
            let matchedFavs = favourites.matching(query)
            let recent = links.matching(query).filter { !marks.favourites.contains(VideoLinks.key($0.url)) }
            rows = matchedFavs.prefix(40).map { favouriteRow($0, in: favs, marks) } + recent.prefix(max(0, 40 - matchedFavs.count)).map { linkRow($0, marks) }
        } else if Prefs.showFavourites {
            if favs.isEmpty { clipSection.addArrangedSubview(hint("Right-click a video ▸ Add to Favourites, or use a player's … menu.")) }
            rows = favs.map { favouriteRow($0, in: favs, marks) }
        } else {
            let all = links.all()
            if all.isEmpty { clipSection.addArrangedSubview(hint("Copy a video link to see it here.")) }
            rows = all.map { linkRow($0, marks) }
        }
        for row in rows {
            clipSection.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: clipSection.widthAnchor).isActive = true
        }
        highlighted = nil
        if browseView.isHidden, let k = keep, k < rows.count { setHighlight(k) }
    }
    // The list's first row while another app plays something: artwork, title, "Artist · App · Paused" (album in the
    // tooltip). Click opens the artwork — or, without one, brings that app forward; right-click adds Copy / Save /
    // Search YouTube. Never part of ↑/↓ (navRows reads clipSection only).
    func rebuildNowPlayingRow() {
        nowPlayingRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let filtering = !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard Prefs.showNowPlaying, !filtering, let info = nowPlayingInfo else { nowPlayingRow.isHidden = true; return }
        nowPlayingRow.isHidden = false
        let parts: [String?] = [info.artist, ArtworkActions.appName(info.appBundleID), info.isPlaying ? nil : "Paused"]
        let meta = parts.compactMap { $0 }.joined(separator: " · ")
        let picture = nowPlayingImage ?? ArtworkActions.appIcon(info.appBundleID) ?? sym("music.note")
        var open: NSView?
        if info.artwork != nil {
            open = ClosureButton(symbol: "arrow.up.left.and.arrow.down.right", tip: "Open Artwork") { [weak self] _ in self?.openArtwork() }
        }
        let row = BrowseRowView(thumb: nil, title: info.title, meta: meta, accessory: open, compact: true, image: picture, square: true)
        let tip: [String?] = [info.title, info.artist, info.album]
        row.toolTip = tip.compactMap { $0 }.joined(separator: " — ")
        row.onClick = { [weak self] in
            if info.artwork == nil { ArtworkActions.showApp(info) } else { self?.openArtwork() }
        }
        row.onMenu = { [weak self] in
            let m = NSMenu()
            ArtworkActions.menuItems(info, open: { self?.openArtwork() }, fullScreen: { self?.openArtwork(fullScreen: true) },
                                     search: { self?.searchYouTube(for: $0) }).forEach(m.addItem)
            return m
        }
        nowPlayingRow.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: nowPlayingRow.widthAnchor).isActive = true
    }
    func nowPlayingChanged(_ info: NowPlayingInfo?) {
        if info?.artwork != nowPlayingInfo?.artwork { nowPlayingImage = info?.artwork.flatMap { NSImage(data: $0) } }
        nowPlayingInfo = info
        rebuildNowPlayingRow()
        if artworkWindow?.window.isVisible == true { artworkWindow?.show(info) }
    }
    // The artwork window takes the panel's spot and the panel hides, as with the first video; it then follows the music.
    // `fullScreen` (the row's Open Full Screen) goes straight on to macOS full screen.
    func openArtwork(fullScreen: Bool = false) {
        guard let info = nowPlayingInfo, info.artwork != nil else { return }
        let viewer = artworkWindow ?? makeArtworkWindow()
        nowPlaying.want(.viewer, true)              // before the panel lets go, so the adapter keeps running
        let panelShown = dropdown.isVisible && dropdown.isOnActiveSpace
        viewer.present(info, replacing: panelShown && !viewer.window.isVisible ? dropdown.frame : nil, anchor: statusItem)
        if panelShown { stopPanelSearch(); dropdown.orderOut(nil); stopPanelMonitors() }
        if fullScreen && !viewer.inFullScreen { viewer.toggleFullScreen() }
    }
    private func makeArtworkWindow() -> ArtworkWindowController {
        let viewer = ArtworkWindowController()
        viewer.onClose = { [weak self] in self?.nowPlaying.want(.viewer, false) }
        viewer.onSearch = { [weak self] q in self?.searchYouTube(for: q) }
        artworkWindow = viewer
        return viewer
    }
    // "Search YouTube for …" from the Now Playing row or the artwork window: results open in the panel.
    func searchYouTube(for query: String) {
        presentPanel()
        searchField.stringValue = query
        search(query)
    }
    func nowPlayingSettingsChanged() {
        if !Prefs.showNowPlaying { artworkWindow?.close() }   // its onClose releases the adapter
        nowPlaying.want(.panel, Prefs.showNowPlaying && dropdown.isVisible)
        rebuildNowPlayingRow()
    }
    // Which videos get a ★ / ✓ — read once per redraw.
    struct LibraryMarks {
        var favourites: Set<String>, watched: Set<String>
        static func current() -> LibraryMarks {
            LibraryMarks(favourites: Set(Favourites.shared.all().map { VideoLinks.key($0.url) }), watched: WatchedVideos.shared.keys())
        }
    }
    private func returnHint(for query: String) -> NSTextField {
        let text: String
        switch OmniboxInput.parse(query) {
        case .play:            text = "Return plays this link."
        case .playlist:        text = "Return lists this playlist."
        case .search(let q):   text = "Searching YouTube for “\(q)”… Return searches now."
        case .empty:           text = ""
        }
        let l = hint(text); l.font = .systemFont(ofSize: 11); l.textColor = .tertiaryLabelColor
        return l
    }
    private static let relativeDate: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; f.dateTimeStyle = .named; return f
    }()
    private func linkRow(_ it: ClipboardLink, _ marks: LibraryMarks) -> BrowseRowView {
        let url = it.url, info = LinkInfo(title: it.title, thumbnail: it.thumbnail, duration: it.duration, isLive: it.isLive)
        let row = compactRow(url, info, date: it.date, marks)
        row.onClick = { [weak self] in self?.play(url) }
        row.onMenu = { [weak self] in self?.linkMenu(url, title: it.title, removable: true, info: info) }
        return row
    }
    // A favourite video plays with the Favourites list as its Up Next, from that row on. A favourite playlist
    // link opens as a playlist (and stays out of that list: handed to yt-dlp as one "video" it would resolve
    // every entry first).
    private func favouriteRow(_ f: FavouriteVideo, in all: [FavouriteVideo], _ marks: LibraryMarks) -> BrowseRowView {
        let url = f.url, info = LinkInfo(title: f.title, thumbnail: f.thumbnail, duration: f.duration, isLive: f.isLive)
        let row = compactRow(url, info, date: nil, marks)
        let videos = all.filter { !YouTube.isPlaylistLink($0.url) }
        row.onClick = { [weak self] in
            guard let start = videos.firstIndex(where: { $0.url == url }) else { self?.play(url); return }
            self?.play(url, queue: PlayQueue(kind: .list, name: "Favourites", items: videos.map { QueueItem(url: $0.url, title: $0.title) },
                                             startAt: start, shuffled: Prefs.shuffle))
        }
        row.onMenu = { [weak self, weak row] in self?.linkMenu(url, title: f.title, removable: false, info: info, play: row?.onClick) }
        return row
    }
    // The compact row both tabs use: "site · LIVE / resume / duration · when" (no date for favourites).
    private func compactRow(_ url: String, _ info: LinkInfo, date: Date?, _ marks: LibraryMarks) -> BrowseRowView {
        let key = VideoLinks.key(url)
        let resume = PlaybackPositions.shared.position(for: key)
        var meta = [VideoLinks.site(url)]
        if info.isLive == true { meta.append("LIVE") }
        else if let p = resume { meta.append(info.duration.map { "\(formatDuration(p)) / \(formatDuration($0))" } ?? "Resume \(formatDuration(p))") }
        else if let d = info.duration { meta.append(formatDuration(d)) }
        if let d = date { meta.append(Self.relativeDate.localizedString(for: d, relativeTo: Date())) }
        var progress: Double?
        if let p = resume, let d = info.duration, d > 0, info.isLive != true { progress = p / d }
        let bare = url.replacingOccurrences(of: #"^https?://(www\.)?"#, with: "", options: .regularExpression)
        // YouTube's small 16:9 still beats the full-size one yt-dlp reports; other sites use theirs.
        let row = BrowseRowView(thumb: VideoLinks.thumbnail(url) ?? info.thumbnail, title: info.title ?? bare,
                                meta: meta.filter { !$0.isEmpty }.joined(separator: " · "), accessory: rowButtons(url, title: info.title),
                                compact: true, favourite: marks.favourites.contains(key), watched: marks.watched.contains(key), progress: progress)
        row.toolTip = url
        return row
    }
    // A row's trailing buttons: ↗ opens the video's page in the browser (a YouTube video where you left off),
    // ⬇ downloads. Local files get only ⬇.
    func rowButtons(_ url: String, title: String?) -> NSView {
        let dl = ClosureButton(symbol: "arrow.down.circle", tip: "Download") { [weak self] b in
            self?.popDownloadMenu(for: url, title: title, from: b)
        }
        guard VideoLinks.webURL(url) != nil else { return dl }
        let site = VideoLinks.site(url)
        let open = ClosureButton(symbol: "arrow.up.right.square", tip: site == "YouTube" ? "Open in YouTube" : "Open on \(site)") { _ in
            let resume = PlaybackPositions.shared.position(for: VideoLinks.key(url))
            if let page = VideoLinks.webURL(url, resumeAt: resume) { NSWorkspace.shared.open(page) }
        }
        let s = NSStackView(views: [open, dl]); s.spacing = 4
        return s
    }
    func rebuildDownloadsSection() {
        downloadsSection.subviews.forEach { $0.removeFromSuperview() }
        let jobs = downloads.jobs
        downloadsHeader.isHidden = jobs.isEmpty
        downloadsSection.isHidden = jobs.isEmpty
        statusItem?.button?.image = NSImage(systemSymbolName: downloads.hasRunning ? "arrow.down.circle" : "play.rectangle", accessibilityDescription: "Watch")
        for job in jobs.prefix(8) {
            let kind = job.kind.label
            let status: String
            switch job.state {
            case .queued:  status = "Queued"
            case .running where job.converting: status = "Converting…"
            case .running: status = job.part > 1 && job.kind != .playlist && !job.kind.isAudio ? "\(Int(job.percent))% (audio)" : "\(Int(job.percent))%"
            case .done:    status = "✓"
            case .failed:  status = "⚠︎ Failed"
            case .stopped: status = "Stopped"
            }
            let b = NSButton(title: "\(status) · \(kind) · \(job.title)", target: self, action: #selector(downloadRowClicked(_:)))
            b.bezelStyle = .inline; b.alignment = .left; b.lineBreakMode = .byTruncatingTail
            b.widthAnchor.constraint(equalToConstant: panelW - 66).isActive = true
            b.identifier = NSUserInterfaceItemIdentifier(job.id.uuidString)
            b.toolTip = job.state == .done ? "Show in Finder" : (job.error ?? job.url)
            let x = NSButton(title: "", image: sym(job.state == .running ? "stop.circle" : "xmark.circle"), target: self, action: #selector(downloadRowDismiss(_:)))
            x.isBordered = false; x.contentTintColor = .secondaryLabelColor
            x.identifier = b.identifier
            x.toolTip = job.state == .running ? "Stop" : "Remove from list"
            let row = NSStackView(views: [b, x]); row.spacing = 4
            downloadsSection.addArrangedSubview(row)
        }
    }
    private func job(for sender: NSButton) -> DownloadJob? { downloads.jobs.first { $0.id.uuidString == sender.identifier?.rawValue } }
    @objc func downloadRowClicked(_ sender: NSButton) {
        guard let job = job(for: sender) else { return }
        switch job.state {
        case .done:
            if let p = job.filePath, FileManager.default.fileExists(atPath: p) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
            else { NSWorkspace.shared.open(URL(fileURLWithPath: job.dir)) }
        case .failed: flash(job.error ?? "Download failed")
        default: NSWorkspace.shared.open(URL(fileURLWithPath: job.dir))
        }
    }
    @objc func downloadRowDismiss(_ sender: NSButton) {
        guard let job = job(for: sender) else { return }
        if job.state == .running { downloads.stop(job) } else { downloads.remove(job) }
    }
    func startDownload(_ url: String, title: String?, kind: DownloadKind) {
        guard let dir = downloadFolder(for: title) else { return }
        downloads.start(url: url, title: title, kind: kind, dir: dir)
        flash(kind == .playlist ? "Downloading playlist…" : kind.isAudio ? "Downloading audio…" : "Downloading video…")
    }
    // The Preferences folder, or — with "Ask where to save each download" on — a folder picked now (nil = cancelled).
    func downloadFolder(for title: String?) -> String? {
        guard Prefs.askDownloadDir else { return Prefs.downloadDir }
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.canCreateDirectories = true; p.prompt = "Download Here"
        p.message = title.map { "Choose where to save “\($0)”" } ?? "Choose where to save this download"
        p.directoryURL = URL(fileURLWithPath: Prefs.downloadDir)
        NSApp.activate(ignoringOtherApps: true)
        return p.runModal() == .OK ? p.url?.path : nil
    }
    // ⬇ next to the field: the field's link if it holds one, else the copied link.
    @objc func showPasteDownloadMenu() {
        var typed: String?
        switch OmniboxInput.parse(searchField.stringValue) {
        case .play(let u), .playlist(let u): typed = looksLikeURL(u) ? u : nil
        default: break
        }
        let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let link = typed ?? (looksLikeURL(clip) ? clip : nil) else { flash("Paste or copy a video link first"); return }
        popDownloadMenu(for: link, title: links.link(for: link)?.title, from: pasteDownloadButton)
    }
    // One download menu for the field and every row (⬇ buttons, right-click ▸ Download): quick picks +
    // lazily-loaded exact formats.
    func downloadMenu(for link: String, title: String?) -> NSMenu {
        let m = NSMenu()
        func add(_ t: String, _ k: DownloadKind, _ menu: NSMenu) {
            let it = NSMenuItem(title: t, action: #selector(downloadChosen(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = DownloadRequest(link, title, k); menu.addItem(it)
        }
        func header(_ t: String) { let h = NSMenuItem(title: t, action: nil, keyEquivalent: ""); h.isEnabled = false; m.addItem(h) }
        header("Video")
        add("Original (Source Format)", .originalVideo, m)
        add("MP4 (Highest Quality)", .mp4Best, m)
        m.addItem(.separator())
        header("Audio")
        add("Original Audio", .originalAudio, m)
        add("MP3 (Source Bit Rate)", .mp3, m)
        if YouTube.isPlaylistLink(link) { m.addItem(.separator()); add("Whole Playlist (MP4)", .playlist, m) }
        m.addItem(.separator())
        let more = NSMenuItem(title: "More", action: nil, keyEquivalent: ""), moreMenu = NSMenu()
        add("Compatible MP4 (H.264, ≤1080p)", .video, moreMenu)
        add("1080p", .videoUpTo(1080), moreMenu); add("720p", .videoUpTo(720), moreMenu); add("480p", .videoUpTo(480), moreMenu)
        moreMenu.addItem(.separator())
        add("Audio (M4A)", .audio, moreMenu)
        more.submenu = moreMenu; m.addItem(more)
        let adv = NSMenuItem(title: "Advanced Formats", action: nil, keyEquivalent: "")
        let sub = FormatsMenu(); sub.link = link; sub.videoTitle = title; sub.delegate = self
        sub.addItem(NSMenuItem(title: "Loading…", action: nil, keyEquivalent: ""))
        adv.submenu = sub; m.addItem(adv)
        return m
    }
    func popDownloadMenu(for link: String, title: String?, from button: NSView) {
        downloadMenu(for: link, title: title).popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }
    func menuWillOpen(_ menu: NSMenu) {
        guard let fm = menu as? FormatsMenu, !fm.loaded else { return }
        fm.loaded = true
        YouTube.formats(fm.link) { [weak self, weak fm] formats in
            guard let self = self, let fm = fm else { return }
            fm.removeAllItems()
            if formats.isEmpty { fm.addItem(NSMenuItem(title: "No formats found", action: nil, keyEquivalent: "")) }
            for f in formats.prefix(40) {
                let it = NSMenuItem(title: f.label, action: #selector(self.downloadChosen(_:)), keyEquivalent: "")
                it.target = self; it.representedObject = DownloadRequest(fm.link, fm.videoTitle, .exact(f.selector, f.label))
                fm.addItem(it)
            }
        }
    }
    @objc func downloadChosen(_ item: NSMenuItem) {
        guard let r = item.representedObject as? DownloadRequest else { return }
        if [.play(r.link), .playlist(r.link)].contains(OmniboxInput.parse(searchField.stringValue)) {
            searchField.stringValue = ""; rebuildClipSection()
        }
        startDownload(r.link, title: r.title, kind: r.kind)
    }
    // Right-click on a Recent Links / Favourites row or a search result. `play` overrides the plain Play (a result
    // keeps its page as the player's Up Next). Add to Favourites keeps `info` (title, thumbnail, duration) with it;
    // Mark as Watched / Unwatched also forgets the resume point, so the video starts from the top either way.
    func linkMenu(_ url: String, title: String?, removable: Bool, info: LinkInfo? = nil, play playAction: (() -> Void)? = nil) -> NSMenu {
        let m = NSMenu()
        m.addItem(ClosureMenuItem("Play") { [weak self] in if let p = playAction { p() } else { self?.play(url) } })
        let dl = NSMenuItem(title: "Download", action: nil, keyEquivalent: "")
        dl.submenu = downloadMenu(for: url, title: title); m.addItem(dl)
        m.addItem(.separator())
        m.addItem(ClosureMenuItem("Copy Link") { [weak self] in
            let pb = NSPasteboard.general
            pb.clearContents(); pb.setString(url, forType: .string)
            self?.lastClipboardChangeCount = pb.changeCount   // copying from the list isn't a newly copied link
        })
        if looksLikeURL(url), let u = URL(string: url) { m.addItem(ClosureMenuItem("Open in Browser") { NSWorkspace.shared.open(u) }) }
        m.addItem(.separator())
        let favourite = favourites.contains(url)
        m.addItem(ClosureMenuItem(favourite ? "Remove from Favourites" : "Add to Favourites") { [weak self] in
            self?.setFavourite(url, !favourite, info: info)
        })
        if !YouTube.isPlaylistLink(url) {
            let key = VideoLinks.key(url), seen = WatchedVideos.shared.isWatched(key)
            m.addItem(ClosureMenuItem(seen ? "Mark as Unwatched" : "Mark as Watched") { [weak self] in
                if seen { WatchedVideos.shared.unmark(key) } else { WatchedVideos.shared.mark(key) }
                PlaybackPositions.shared.clear(key)
                self?.libraryChanged()
            })
        }
        if removable {
            m.addItem(ClosureMenuItem("Remove from Recent Links") { [weak self] in self?.links.remove(url); self?.rebuildClipSection() })
        }
        return m
    }
    func setFavourite(_ url: String, _ on: Bool, info: LinkInfo?) {
        if on { favourites.add(url, info: info) } else { favourites.remove(url) }
        flash(on ? "Added to Favourites" : "Removed from Favourites")
        libraryChanged()
    }
    // A watched mark or favourite changed (here or in a player): redraw what shows them. A hidden panel redraws
    // when it opens.
    @objc func libraryChanged() {
        guard dropdown.isVisible else { return }
        rebuildClipSection()
        if !browseStack.isEmpty { renderBrowse(keepScroll: true) }
    }
    @objc func clearRecentLinks() {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Clear Recent Links?"
        a.informativeText = "This removes every link from the list. Favourites, watched marks, resume positions and downloaded files aren't affected."
        a.addButton(withTitle: "Clear"); a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        links.clear()
        rebuildClipSection()
    }

    // MARK: the field — Return, ↑/↓ and Esc arrive through control(_:textView:doCommandBy:)
    // Return: a link plays, a playlist link is listed, anything else searches YouTube; an empty field plays the
    // copied link (what the old Play button did).
    func submitField() {
        liveSearch.cancel()
        switch OmniboxInput.parse(searchField.stringValue) {
        case .empty:            playClipboard()
        case .play(let s):      searchField.stringValue = ""; rebuildClipSection(); play(s)
        case .playlist(let s):  openPlaylist(s, title: "Playlist", root: true)
        case .search(let q):    search(q)
        }
    }
    // The field's own action only fires for its ✕ button (Return is handled in doCommandBy).
    @objc func searchFieldAction(_ sender: NSSearchField) {
        if sender.stringValue.isEmpty { fieldTextChanged() }
    }
    func controlTextDidChange(_ n: Notification) {
        guard (n.object as? NSSearchField) === searchField else { return }
        fieldTextChanged(composing: (searchField.currentEditor() as? NSTextView)?.hasMarkedText() == true)
    }
    func fieldTextChanged(composing: Bool = false) {
        // Invalidate immediately, not after the debounce: an older response may arrive while typing.
        liveSearch.cancel()
        browseToken += 1
        browseTask?.cancel(); browseTask = nil
        activeSearchQuery = nil
        browseStack.removeAll()
        highlighted = nil
        renderBrowse()
        rebuildClipSection()
        mainScroll.contentView.scroll(to: .zero)
        mainScroll.reflectScrolledClipView(mainScroll.contentView)
        liveSearch.update(searchField.stringValue, composing: composing) { [weak self] query in
            self?.search(query, remember: false)
        }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        guard control === searchField else { return false }
        if textView.hasMarkedText() { return false }
        switch sel {
        case #selector(NSResponder.moveDown(_:)):   moveHighlight(1); return true
        case #selector(NSResponder.moveUp(_:)):     moveHighlight(-1); return true
        case #selector(NSResponder.insertNewline(_:)):
            let rows = navRows()
            if let i = highlighted, i < rows.count { liveSearch.cancel(); rows[i].onClick?() } else { submitField() }
            return true
        case #selector(NSResponder.cancelOperation(_:)): escapePressed(); return true
        default: return false
        }
    }
    // The rows ↑/↓ walk: search results / History / a playlist when a page is showing, else Recent Links.
    private func navRows() -> [BrowseRowView] {
        (browseView.isHidden ? clipSection : browseList).arrangedSubviews.compactMap { $0 as? BrowseRowView }
    }
    private func moveHighlight(_ delta: Int) {
        let rows = navRows()
        guard !rows.isEmpty else { return }
        liveSearch.cancel()   // choosing a local match must not be interrupted by the pending search
        let next = (highlighted ?? -1) + delta
        setHighlight(next < 0 ? nil : min(next, rows.count - 1))
    }
    private func setHighlight(_ i: Int?) {
        let rows = navRows()
        for (n, r) in rows.enumerated() { r.isHighlighted = n == i }
        highlighted = i
        if let i = i, i < rows.count { rows[i].scrollToVisible(rows[i].bounds.insetBy(dx: 0, dy: -6)) }
    }
    // Esc: clear the field, else leave the page, else hide the panel.
    private func escapePressed() {
        setHighlight(nil)
        if !searchField.stringValue.isEmpty { searchField.stringValue = ""; fieldTextChanged() }
        else if !browseStack.isEmpty { browseBack() }
        else { minimizeToMenuBar() }
    }
    // The magnifier's menu: recent searches (pick one to search again) and Clear. Our own store, not the
    // field's recents, so a pasted link is never remembered.
    func rebuildSearchMenu() {
        let m = NSMenu(title: "Recent Searches")
        let recents = RecentSearches.shared.all
        let head = NSMenuItem(title: recents.isEmpty ? "No Recent Searches" : "Recent Searches", action: nil, keyEquivalent: "")
        head.isEnabled = false; m.addItem(head)
        for q in recents {
            let it = NSMenuItem(title: q, action: #selector(recentSearchChosen(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = q; m.addItem(it)
        }
        if !recents.isEmpty {
            m.addItem(.separator())
            let clear = NSMenuItem(title: "Clear Recent Searches", action: #selector(clearRecentSearches), keyEquivalent: "")
            clear.target = self; m.addItem(clear)
        }
        searchField.searchMenuTemplate = m
    }
    @objc func recentSearchChosen(_ item: NSMenuItem) {
        guard let q = item.representedObject as? String else { return }
        searchField.stringValue = q
        search(q)
    }
    @objc func clearRecentSearches() { RecentSearches.shared.clear(); rebuildSearchMenu() }

    // MARK: YouTube browse pages (search · History · Playlists)
    func search(_ q: String, remember: Bool = true) {
        liveSearch.cancel()
        if remember { RecentSearches.shared.add(q); rebuildSearchMenu() }
        if activeSearchQuery == q, let page = browseStack.last?.page {
            switch page {
            case .loading, .results: return   // Return during live search must not restart it.
            default: break                   // Explicit Return retries a failed search.
            }
        }
        let cached = searchCache.value(for: q).map { BrowsePage.results(q, $0) }
        openPage("“\(q)”", root: true, initial: cached, note: "Searching YouTube…", searchFetch(q, limit: YouTube.searchLimit))
        activeSearchQuery = q
    }
    // One boundary for live service calls; the isolated UI harness substitutes delayed fixture results.
    func performSearch(_ query: String, limit: Int, completion: @escaping ([YTVideo]?, String) -> Void) -> YtDlpTask {
        YouTube.search(query, limit: limit, completion: completion)
    }
    private func searchFetch(_ q: String, limit: Int) -> BrowseFetch {
        return { [weak self] done in
            guard let self = self else { return nil }
            let token = self.browseToken
            return self.performSearch(q, limit: limit) { [weak self] vs, e in
                guard let self = self, token == self.browseToken else { return }
                guard let vs = vs else {
                    done(.message("“\(q)”", Self.failureText("Search failed.", e), action: Self.failureAction(e))); return
                }
                let page = SearchPage(videos: vs, requested: limit, more: vs.count >= limit && limit < YouTube.maxSearchResults)
                self.searchCache.store(page, for: q)
                done(.results(q, page))
            }
        }
    }
    // "Show More Results": ask for one more page; yt-dlp re-reads from the top, so only new videos are appended.
    @objc func loadMoreResults(_ sender: NSButton) {
        guard let top = browseStack.last, case .results(let q, let shown) = top.page else { return }
        sender.isEnabled = false; sender.title = "Loading…"
        let limit = min(shown.requested + YouTube.searchLimit, YouTube.maxSearchResults)
        browseTask?.cancel()
        let token = browseToken, depth = browseStack.count
        browseTask = performSearch(q, limit: limit) { [weak self] vs, e in
            guard let self = self, token == self.browseToken, self.browseStack.count == depth else { return }
            self.browseTask = nil
            guard let vs = vs else {
                sender.isEnabled = true; sender.title = "Show More Results"
                self.flash(e == YtDlp.timedOutError ? "YouTube didn't answer in time" : "Couldn't load more results")
                return
            }
            let seen = Set(shown.videos.map(\.url))
            let page = SearchPage(videos: shown.videos + vs.filter { !seen.contains($0.url) }, requested: limit,
                                  more: vs.count >= limit && limit < YouTube.maxSearchResults)
            self.searchCache.store(page, for: q)
            self.browseStack[depth - 1].page = .results(q, page)
            self.renderBrowse(keepScroll: true)
        }
    }
    private static func failureText(_ lead: String, _ e: String) -> String {
        if e == YtDlp.timedOutError { return "YouTube didn't answer in time. Check your connection, then try again." }
        if e == YtDlp.notFoundError { return "Watch’s included media tools could not be found. Replace Watch with a fresh copy from your sender, then open Setup Guide to check the tools." }
        let fix = SearchFailure.suggestsUpdate(e) ? " YouTube may have changed — ask your sender for an updated Watch installer." : ""
        return "\(lead)\(fix)\n\n\(e)"
    }
    private static func failureAction(_ e: String) -> MessageAction {
        e == YtDlp.notFoundError ? .none : (SearchFailure.suggestsUpdate(e) ? .updateAndRetry : .retry)
    }
    @objc func showHistory() {
        presentPanel()
        guard Prefs.youtubeConnected else { showSignedOut("History"); return }
        openPage("History", root: true) { done in
            YouTube.history { vs, e in done(vs.map { .videos("History", $0) } ?? .message("History", Self.signInHelp("history", e), action: .signIn)) }
            return nil
        }
    }
    @objc func showPlaylists() {
        presentPanel()
        guard Prefs.youtubeConnected else { showSignedOut("Playlists"); return }
        openPage("Playlists", root: true) { done in
            YouTube.playlists { ps, e in done(ps.map { .playlists($0) } ?? .message("Playlists", Self.signInHelp("playlists", e), action: .signIn)) }
            return nil
        }
    }
    private func showSignedOut(_ title: String) {
        browseTask?.cancel(); browseTask = nil
        browseToken += 1
        browseStack = [BrowseEntry(page: .message(title, "Sign in to YouTube to see your \(title.lowercased()) here. Watch uses the sign-in from your browser — the assistant walks you through it.", action: .signIn), fetch: nil)]
        renderBrowse()
    }
    // "YouTube Account…" on sign-in pages: the assistant when signed out, Preferences otherwise.
    @objc func youtubeAccountButton() { Prefs.youtubeConnected ? openSettings() : openYouTubeSignIn() }
    private func openPlaylist(_ url: String, title: String, root: Bool) {
        openPage(title, root: root) { done in
            YouTube.playlistVideos(url) { vs, e in
                done(vs.map { .videos(title, $0) } ?? .message(title, Self.failureText("Couldn't load this playlist.", e), action: Self.failureAction(e)))
            }
            return nil
        }
    }
    private static func signInHelp(_ what: String, _ err: String) -> String {
        let browser = Prefs.cookieSource == "safari" ? "Safari" : (Prefs.cookieSource == "chrome" ? "Chrome" : "Safari or Chrome")
        return "Couldn't read your YouTube \(what). Make sure you're signed in to YouTube in \(browser) — see Preferences ▸ YouTube Account.\n\n\(err)"
    }
    func presentPanel() { if !(dropdown.isVisible && dropdown.isOnActiveSpace) { togglePanel() } }
    // Push a page that shows a spinner until `fetch` delivers its content (`initial`, e.g. cached results, shows
    // at once instead). A newer page or Back cancels the running fetch and drops its late result.
    private func openPage(_ title: String, root: Bool, initial: BrowsePage? = nil, note: String = "Loading…", _ fetch: @escaping BrowseFetch) {
        liveSearch.cancel()
        activeSearchQuery = nil
        browseTask?.cancel(); browseTask = nil
        if root { browseStack = [] }
        browseStack.append(BrowseEntry(page: initial ?? .loading(title, note: note), fetch: fetch))
        browseToken += 1
        renderBrowse()
        if initial == nil { runFetch(fetch) }
    }
    private func runFetch(_ fetch: BrowseFetch) {
        let token = browseToken, depth = browseStack.count
        browseTask = fetch { [weak self] page in
            guard let self = self, token == self.browseToken, self.browseStack.count == depth else { return }
            self.browseStack[depth - 1].page = page
            self.browseTask = nil
            self.renderBrowse()
        }
    }
    // Try Again on a failed page: run its fetch again in place.
    @objc func reloadPage() {
        guard let top = browseStack.last, let fetch = top.fetch else { return }
        browseTask?.cancel(); browseTask = nil
        browseToken += 1
        browseStack[browseStack.count - 1].page = .loading(top.page.title, note: "Trying again…")
        renderBrowse()
        runFetch(fetch)
    }
    @objc func updateAndReloadPage() { showMediaToolUpdateHelp() }
    @objc func browseBack() {
        liveSearch.cancel()
        activeSearchQuery = nil
        browseTask?.cancel(); browseTask = nil
        browseToken += 1
        if !browseStack.isEmpty { browseStack.removeLast() }
        // Back home: the query that led to the page would otherwise filter Recent Links.
        if browseStack.isEmpty, !searchField.stringValue.isEmpty { searchField.stringValue = ""; rebuildClipSection() }
        renderBrowse()
    }
    private func renderBrowse(keepScroll: Bool = false) {
        highlighted = nil
        guard let page = browseStack.last?.page else {
            browseView.isHidden = true; mainScroll.isHidden = false; return
        }
        let offset = browseScroll.contentView.bounds.origin
        mainScroll.isHidden = true; browseView.isHidden = false
        browseTitle.stringValue = page.title
        browseAction.isHidden = true
        browseList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        func add(_ v: NSView, fill: Bool = true) {
            browseList.addArrangedSubview(v)
            if fill { v.widthAnchor.constraint(equalTo: browseList.widthAnchor).isActive = true }
        }
        // Video rows; the page itself becomes the player's Up Next list, from whichever row was clicked.
        let marks = LibraryMarks.current()
        func addVideos(_ vs: [YTVideo], queueName name: String) {
            let items = vs.map { QueueItem(url: $0.url, title: $0.title) }
            for (i, v) in vs.enumerated() {
                let meta = [v.channel, v.isLive ? "LIVE" : formatViews(v.views), formatDuration(v.duration)].filter { !$0.isEmpty }.joined(separator: " · ")
                var progress: Double?
                let key = VideoLinks.key(v.url)
                if let p = PlaybackPositions.shared.position(for: key), let d = v.duration, d > 0 { progress = p / d }
                let row = BrowseRowView(thumb: v.thumbnail, title: v.title, meta: meta, accessory: rowButtons(v.url, title: v.title),
                                        favourite: marks.favourites.contains(key), watched: marks.watched.contains(key), progress: progress)
                row.toolTip = v.url
                row.onClick = { [weak self] in
                    self?.play(v.url, queue: PlayQueue(kind: .list, name: name, items: items, startAt: i, shuffled: Prefs.shuffle))
                }
                let info = LinkInfo(title: v.title, thumbnail: v.thumbnail, duration: v.duration, isLive: v.isLive)
                row.onMenu = { [weak self, weak row] in self?.linkMenu(v.url, title: v.title, removable: false, info: info, play: row?.onClick) }
                add(row)
            }
        }
        switch page {
        case .loading(_, let note):
            let sp = NSProgressIndicator(); sp.style = .spinning; sp.controlSize = .small; sp.startAnimation(nil)
            let row = NSStackView(views: [sp, hint(note)]); row.spacing = 8
            row.edgeInsets = NSEdgeInsets(top: 10, left: 6, bottom: 0, right: 0)
            add(row, fill: false)
        case .message(_, let text, let action):
            let l = hint(text); l.preferredMaxLayoutWidth = browseList.bounds.width > 0 ? browseList.bounds.width - 12 : panelW - 40
            let wrap = NSStackView(views: [l]); wrap.orientation = .vertical; wrap.alignment = .leading; wrap.spacing = 10
            wrap.edgeInsets = NSEdgeInsets(top: 10, left: 6, bottom: 0, right: 6)
            let button: NSButton?
            switch action {
            case .none:           button = nil
            case .signIn:         button = NSButton(title: Prefs.youtubeConnected ? "YouTube Account…" : "Sign In to YouTube…", target: self, action: #selector(youtubeAccountButton))
            case .retry:          button = NSButton(title: "Try Again", target: self, action: #selector(reloadPage))
            case .updateAndRetry: button = NSButton(title: "How to Update Watch…", target: self, action: #selector(updateAndReloadPage))
            }
            if let b = button { b.bezelStyle = .rounded; wrap.addArrangedSubview(b) }
            add(wrap)
        case .videos(let name, let vs):
            if vs.isEmpty { add(hint("No videos found."), fill: false) }
            addVideos(vs, queueName: name)
        case .results(let q, let results):
            if results.videos.isEmpty { add(hint("No videos found for “\(q)”."), fill: false) }
            addVideos(results.videos, queueName: "“\(q)”")
            if results.more {
                let more = NSButton(title: "Show More Results", target: self, action: #selector(loadMoreResults(_:)))
                more.bezelStyle = .rounded; more.controlSize = .small
                let wrap = NSStackView(views: [more]); wrap.edgeInsets = NSEdgeInsets(top: 6, left: 4, bottom: 4, right: 0)
                add(wrap, fill: false)
            }
        case .playlists(let ps):
            browseAction.isHidden = ps.isEmpty
            if ps.isEmpty { add(hint("No playlists found."), fill: false) }
            for p in ps {
                let dl = ClosureButton(symbol: "arrow.down.circle", tip: "Download playlist") { [weak self] _ in
                    self?.startDownload(p.url, title: p.title, kind: .playlist)
                }
                let row = BrowseRowView(thumb: p.thumbnail, title: p.title, meta: p.count.map { "\($0) videos" } ?? "Playlist", accessory: dl)
                row.onClick = { [weak self] in self?.openPlaylist(p.url, title: p.title, root: false) }
                add(row)
            }
        }
        browseList.layoutSubtreeIfNeeded()
        browseScroll.contentView.scroll(to: keepScroll ? offset : .zero)
        browseScroll.reflectScrolledClipView(browseScroll.contentView)
    }
    @objc func downloadAllPlaylists() {
        guard case .playlists(let ps)? = browseStack.last?.page else { return }
        guard let dir = downloadFolder(for: "\(ps.count) playlists") else { return }
        ps.forEach { downloads.start(url: $0.url, title: $0.title, kind: .playlist, dir: dir) }
        flash("Queued \(ps.count) playlists")
    }
    func mediaSettingsChanged() {
        if !Prefs.showBrowserTabs { mediaItems = []; browsersAwaitingAccess = [] }
        rebuildMediaSection()
    }
    @objc func mediaRowClicked(_ sender: NSButton) { if let u = sender.toolTip { play(u) } }
    @objc func openAllMedia() { mediaItems.compactMap { $0.url }.forEach { play($0) } }
    @objc func playClipboard() {
        guard let s = NSPasteboard.general.string(forType: .string), looksLikeURL(s) else { flash("Clipboard has no video link"); return }
        play(s)
    }

    func applyLevel() {
        if Prefs.pinned { dropdown.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1) }
        else if Prefs.detached { dropdown.level = .normal }
        else { dropdown.level = .floating }
    }
    @objc func togglePanel() {
        if dropdown.isVisible && dropdown.isOnActiveSpace { stopPanelSearch(); dropdown.orderOut(nil); stopPanelMonitors(); return }
        // Every open anchors under the menu-bar icon. A drag-off detaches only until the panel is hidden.
        Prefs.detached = false
        suppressMoveSave = true
        positionUnderStatusItem()
        suppressMoveSave = false
        applyLevel()
        if browseStack.isEmpty { searchField.stringValue = "" }   // a stale query shouldn't filter the list
        rebuildClipSection()
        if !browseStack.isEmpty { renderBrowse(keepScroll: true) }   // ★/✓ marks may have changed while hidden
        mainScroll.contentView.scroll(to: .zero); mainScroll.reflectScrolledClipView(mainScroll.contentView)
        dropdown.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        dropdown.makeFirstResponder(searchField)      // type to search or filter right away
        startPanelMonitors()
    }
    // Only while the panel shows: browser-tab polling and the Now Playing adapter.
    func startPanelMonitors() {
        mediaMonitor.start()
        if Prefs.showNowPlaying { nowPlaying.want(.panel, true) }
    }
    func stopPanelMonitors() { mediaMonitor.stop(); nowPlaying.want(.panel, false) }
    // Pressing the hotkey plays a copied video link directly; otherwise it toggles the panel.
    @objc func hotkeyPressed() {
        if Prefs.hotkeyPlaysClipboard, let s = NSPasteboard.general.string(forType: .string), looksLikeURL(s) { play(s); return }
        togglePanel()
    }
    func positionUnderStatusItem() {
        guard let b = statusItem.button, let bw = b.window else { return }
        let on = bw.convertToScreen(b.convert(b.bounds, to: nil))
        var f = dropdown.frame
        f.origin.x = on.midX - f.width / 2; f.origin.y = on.minY - f.height - 4
        if let vis = bw.screen?.visibleFrame { f.origin.x = min(max(f.origin.x, vis.minX + 8), vis.maxX - f.width - 8) }
        dropdown.setFrame(f, display: false)
    }
    func windowDidMove(_ n: Notification) {
        // Only a real user drag detaches — programmatic/system moves (screen changes, Space moves) don't.
        guard let w = n.object as? NSWindow, w === dropdown, !suppressMoveSave, NSEvent.pressedMouseButtons & 1 != 0 else { return }
        Prefs.detached = true; applyLevel()
    }
    func stopPanelSearch() {
        liveSearch.cancel()
        guard activeSearchQuery != nil, browseTask != nil else { return }
        browseToken += 1
        browseTask?.cancel(); browseTask = nil
        if case .loading? = browseStack.last?.page { browseStack.removeAll(); activeSearchQuery = nil }
        renderBrowse(keepScroll: true)
    }
    @objc func minimizeToMenuBar() { Prefs.detached = false; stopPanelSearch(); dropdown.orderOut(nil); stopPanelMonitors() }
    @objc func togglePin() { Prefs.pinned.toggle(); applyLevel() }

    // MARK: playback entry point — a window opens immediately and resolves its own stream (see PlayerWindowController.load)
    // `queue` is the list the video was picked from (search results, History, a playlist page); it becomes
    // that window's Up Next. Without one the player works out its own — see PlayerWindowController.ensureQueue.
    func play(_ raw: String, queue: PlayQueue? = nil) {
        liveSearch.cancel()
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let local = isLocalMedia(input)
        guard local || looksLikeURL(input) else { flash("Not a recognizable video link"); return }
        // The first video turns the panel into the player: it opens on the panel's spot and the panel hides
        // (the menu-bar icon brings it back). With players already open, new ones tile beside them.
        let panelShown = dropdown.isVisible && dropdown.isOnActiveSpace
        let takeOver = panelShown && windowManager.players.isEmpty
        let pc = windowManager.open(input, anchor: statusItem, queue: queue, replacing: takeOver ? dropdown.frame : nil)
        if takeOver { stopPanelSearch(); dropdown.orderOut(nil); stopPanelMonitors() }
        if !local { recordLink(pc.sourceURL, probe: false) }   // the player reports title/thumbnail via onInfo
    }
    // Puts a video link on top of Recent Links. `probe` asks yt-dlp for its title, thumbnail and duration when
    // the list doesn't know them yet (a played video reports its own through WindowManager.onInfo).
    func recordLink(_ url: String, probe: Bool = true) {
        links.add(url)
        rebuildClipSection()
        guard probe, links.link(for: url)?.title == nil else { return }
        probeLink(url) { [weak self] info in
            guard let self = self, let info = info else { return }
            self.links.update(url, with: info); self.rebuildClipSection()
        }
    }
    func flash(_ s: String) {
        statusLabel.stringValue = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in if self?.statusLabel.stringValue == s { self?.statusLabel.stringValue = "Watch" } }
    }

    // MARK: B5 clipboard watcher (continuous, lightweight — just an int compare per tick)
    func startClipboardWatch() {
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.checkClipboard() }
    }
    func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = pb.changeCount
        guard let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), looksLikeURL(s) else { return }
        // Only video links. YouTube videos/playlists and media files go in right away; other video sites once
        // yt-dlp finds a single video there; anything else (docs, repos, articles) is never recorded or fetched.
        switch VideoLinks.classify(s) {
        case .video: recordLink(s)
        case .maybe:
            if links.link(for: s) != nil { recordLink(s); return }
            probeLink(s) { [weak self] info in
                guard let self = self, let info = info, !info.isList else { return }
                self.links.add(s); self.links.update(s, with: info); self.rebuildClipSection()
            }
        case .other: break
        }
    }

    // MARK: menus
    // Drops down from the ••• button itself (it used to pop at the panel's bottom-left corner).
    @objc func showDotMenu(_ sender: NSButton) { appMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender) }
    func appMenu() -> NSMenu {
        let m = NSMenu()
        func item(_ t: String, _ a: Selector, _ key: String = "", state: NSControl.StateValue? = nil, target: AnyObject? = nil) {
            let it = NSMenuItem(title: t, action: a, keyEquivalent: key); it.target = target ?? self
            if let s = state { it.state = s }
            m.addItem(it)
        }
        item("YouTube History", #selector(showHistory))
        item("YouTube Playlists", #selector(showPlaylists))
        m.addItem(.separator())
        item(Prefs.pinned ? "Unpin Panel" : "Pin Panel (Always on Top)", #selector(togglePin), state: Prefs.pinned ? .on : .off)
        if windowManager.players.count > 1 { item("Tile Windows", #selector(tileWindows)) }
        item("Close All Players", #selector(closeAllPlayers))
        item("Clear Recent Links…", #selector(clearRecentLinks))
        item("Open Downloads Folder", #selector(openDownloadsFolder))
        item("Media Tool Updates…", #selector(updateYtDlpMenu))
        m.addItem(.separator())
        item("Preferences…", #selector(openSettings), ",")
        item("Quit Watch", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        return m
    }
    @objc func closeAllPlayers() { windowManager.closeAll() }
    @objc func tileWindows() { windowManager.tile(on: dropdown.screen) }
    @objc func openDownloadsFolder() { NSWorkspace.shared.open(URL(fileURLWithPath: Prefs.downloadDir)) }
    @objc func updateYtDlpMenu() { updateYtDlp() }
    func updateYtDlp() { showMediaToolUpdateHelp() }

    // MARK: menu / hotkey / login
    func setupMainMenu() {
        let main = NSMenu()

        // App menu
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        let s = NSMenuItem(title: "Preferences…", action: #selector(openSettings), keyEquivalent: ","); s.target = self
        appMenu.addItem(s)
        let dup = NSMenuItem(title: "Duplicate Player", action: #selector(duplicateFrontPlayer), keyEquivalent: "d"); dup.target = self
        appMenu.addItem(dup)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Watch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu

        // Edit menu — without it, ⌘X/⌘C/⌘V/⌘A never reach the panel's link field. nil targets route
        // each standard action down the responder chain to whatever text field is focused.
        let editItem = NSMenuItem(); main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu

        NSApp.mainMenu = main
    }
    // ⌘D — duplicate the frontmost player window by replaying its source (and its Up Next list) into a fresh window.
    @objc func duplicateFrontPlayer() {
        guard let key = NSApp.keyWindow,
              let pc = windowManager.players.first(where: { $0.window === key }),
              !pc.sourceURL.isEmpty else { NSSound.beep(); return }
        play(pc.sourceURL, queue: pc.queue)
    }
    @objc func openYouTubeSignIn() { if signInController == nil { signInController = YouTubeSignInController() }; signInController?.show() }
    @objc func openWelcome() { if welcomeController == nil { welcomeController = WelcomeController() }; welcomeController?.show() }
    @objc func openSettings() { if settingsController == nil { settingsController = SettingsController(app: self) }; settingsController?.show() }
    // Only register when not already enabled — re-registering on every launch re-posts the
    // "Login Item Added" system notification.
    func registerLoginItem() {
        if #available(macOS 13.0, *), Prefs.launchAtLogin, SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
    }
    @objc func toggleLoginItem() {
        Prefs.launchAtLogin.toggle()
        if #available(macOS 13.0, *) { do { if Prefs.launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {} }
    }
    func installHotkeyHandler() {
        var et = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.hotkeyPressed() }
            return noErr
        }, 1, &et, nil, nil)
    }
    func applyHotkey(keyCode: UInt32, carbonModifiers: UInt32) {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        let id = EventHotKeyID(signature: OSType(0x57415443) /* 'WATC' */, id: 1)
        RegisterEventHotKey(keyCode, carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

// MARK: - Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
