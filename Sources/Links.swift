import Foundation

// Links: URL helpers, which copied links count as videos, and the Recent Links store. Foundation only, so
// test.sh can compile it without AppKit.

// Parse a YouTube URL → (videoID, startSeconds). Handles watch?v=, youtu.be/, shorts/, embed/.
func parseYouTube(_ s: String) -> (id: String, start: Int)? {
    guard let c = URLComponents(string: s) else { return nil }
    let host = c.host ?? ""
    var id = ""
    if host.contains("youtu.be") { id = String(c.path.dropFirst()) }
    else if host.contains("youtube.com") {
        if c.path == "/watch" { id = c.queryItems?.first(where: { $0.name == "v" })?.value ?? "" }
        else if c.path.hasPrefix("/shorts/") { id = String(c.path.dropFirst("/shorts/".count)) }
        else if c.path.hasPrefix("/embed/") { id = String(c.path.dropFirst("/embed/".count)) }
        else if c.path.hasPrefix("/live/") { id = String(c.path.dropFirst("/live/".count)) }
    }
    id = id.components(separatedBy: "/").first ?? id
    id = id.components(separatedBy: "?").first ?? id
    guard !id.isEmpty else { return nil }
    var start = 0
    if let t = c.queryItems?.first(where: { $0.name == "t" || $0.name == "start" })?.value { start = parseSeconds(t) }
    return (id, start)
}
func parseSeconds(_ t: String) -> Int {
    if let n = Int(t) { return n }
    var total = 0, num = 0
    for ch in t {
        if let d = ch.wholeNumberValue, ch.isNumber { num = num * 10 + d }
        else { switch ch { case "h": total += num * 3600; case "m": total += num * 60; case "s": total += num; default: break }; num = 0 }
    }
    return total + num
}
func looksLikeURL(_ s: String) -> Bool {
    guard let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = u.scheme else { return false }
    return scheme.hasPrefix("http")
}
func isLocalMedia(_ s: String) -> Bool { s.hasPrefix("file://") || FileManager.default.fileExists(atPath: s) }

// ----------------------------------------------------------------------------
// MARK: - Which links are videos
// ----------------------------------------------------------------------------
enum LinkKind { case video, maybe, other }

enum VideoLinks {
    // Sites where a link is often, but not always, a video: a copied link from one of these is kept only once
    // yt-dlp finds a video in it. (A channel or home page on these sites isn't a video.)
    static let videoSites = [
        "vimeo.com", "twitch.tv", "tiktok.com", "soundcloud.com", "dailymotion.com", "dai.ly", "streamable.com",
        "kick.com", "rumble.com", "loom.com", "archive.org", "bilibili.com", "nicovideo.jp", "bandcamp.com",
        "x.com", "twitter.com", "reddit.com", "redd.it", "instagram.com", "facebook.com", "fb.watch",
        "bsky.app", "threads.net",
    ]
    // Whether the Spotify app is there to play copied Spotify songs/episodes (AppDelegate sets it at launch).
    static var spotifyInstalled = false
    static let mediaExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv", "avi", "ts", "m3u8", "mpd",
                                               "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"]

    // What the clipboard watcher does with a copied link: `.video` is kept straight away (a YouTube video or
    // playlist, or a media file), `.maybe` only if yt-dlp finds a video in it, `.other` is ignored.
    static func classify(_ s: String) -> LinkKind {
        let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeURL(text), let u = URL(string: text), let host = u.host?.lowercased(), !host.isEmpty else { return .other }
        if parseYouTube(text) != nil || isYouTubePlaylist(text) { return .video }
        if host.contains("youtube.com") || host.contains("youtu.be") { return .other }   // channel, home, feed pages
        if host == "open.spotify.com" { return spotifyInstalled && SpotifyLink.uri(text) != nil ? .video : .other }   // songs/episodes
        if mediaExtensions.contains(u.pathExtension.lowercased()) { return .video }
        return isVideoSite(host) ? .maybe : .other
    }
    static func isVideoSite(_ host: String) -> Bool {
        let h = host.lowercased()
        return h.contains("youtube.com") || h.contains("youtu.be") || videoSites.contains { h == $0 || h.hasSuffix("." + $0) }
    }
    static func isYouTubePlaylist(_ s: String) -> Bool {
        guard let c = URLComponents(string: s), (c.host ?? "").contains("youtube.com") else { return false }
        return c.path == "/playlist" || (c.path != "/watch" && c.queryItems?.contains { $0.name == "list" } == true)
    }
    // One key per video, whatever the link looks like — the same key resume positions use.
    static func key(_ url: String) -> String { PlaybackPositions.key(source: url, youtubeID: parseYouTube(url)?.id) }
    static func thumbnail(_ url: String) -> String? { parseYouTube(url).map { "https://i.ytimg.com/vi/\($0.id)/mqdefault.jpg" } }
    // The page a row's ↗ button opens in the browser: the link itself, and for a YouTube video with a resume
    // position, that link starting there (`t=`, replacing any time it already carried). nil for local files.
    static func webURL(_ url: String, resumeAt seconds: Double? = nil) -> URL? {
        guard looksLikeURL(url), var c = URLComponents(string: url) else { return nil }
        if let s = seconds, s >= 1, parseYouTube(url) != nil, !(c.path.hasPrefix("/shorts/")) {
            var q = (c.queryItems ?? []).filter { $0.name != "t" && $0.name != "start" }
            q.append(URLQueryItem(name: "t", value: "\(Int(s))s"))
            c.queryItems = q
        }
        return c.url
    }
    // "YouTube", "vimeo.com", "File" — the first part of a row's details line.
    static func site(_ url: String) -> String {
        if url.hasPrefix("/") || url.hasPrefix("file://") { return "File" }
        guard let host = URL(string: url)?.host?.lowercased() else { return "" }
        if host.contains("youtube.com") || host.contains("youtu.be") { return "YouTube" }
        if host == "open.spotify.com" { return "Spotify" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

// What yt-dlp says about a link (`-J`, or the data a player resolved). Every field may be missing.
struct LinkInfo: Equatable {
    var title: String?
    var thumbnail: String?
    var duration: Double?
    var isLive: Bool?
    var isList = false          // a playlist, channel or multi-video post rather than one video (not stored)

    init(title: String? = nil, thumbnail: String? = nil, duration: Double? = nil, isLive: Bool? = nil) {
        self.title = title; self.thumbnail = thumbnail; self.duration = duration; self.isLive = isLive
    }
    // A video's JSON, or a playlist's (whose own thumbnail may be missing — then its first entry's).
    init(json d: [String: Any]) {
        func num(_ v: Any?) -> Double? { (v as? Double) ?? (v as? Int).map(Double.init) }
        func thumb(_ d: [String: Any]) -> String? {
            if let t = d["thumbnail"] as? String { return t }
            let all = (d["thumbnails"] as? [[String: Any]]) ?? []
            return all.max { (num($0["width"]) ?? 0) < (num($1["width"]) ?? 0) }?["url"] as? String ?? all.last?["url"] as? String
        }
        let title = (d["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title?.isEmpty == false ? title : nil
        thumbnail = thumb(d) ?? ((d["entries"] as? [[String: Any]])?.first.flatMap(thumb))
        duration = num(d["duration"]).flatMap { $0 > 0 ? $0 : nil }
        if let live = d["is_live"] as? Bool { isLive = live }
        else if let status = d["live_status"] as? String { isLive = status == "is_live" }
        isList = (d["_type"] as? String) == "playlist"
    }
}

// ----------------------------------------------------------------------------
// MARK: - Recent Links — copied and played video links, newest first
// ----------------------------------------------------------------------------
// One JSON array in UserDefaults (`watchClipboardLinks`, unchanged since 3.0; entries from before 3.11 simply
// have no thumbnail/duration yet). Each video appears once: adding it again moves it to the top. Pinned links
// (3.12, right-click ▸ Pin) are listed above the rest, never pushed out by the cap, and survive Clear.
struct ClipboardLink: Codable, Equatable {
    var url: String
    var title: String?
    var date: Date
    var thumbnail: String?
    var duration: Double?
    var isLive: Bool?
    var pinned: Bool?
    var isPinned: Bool { pinned == true }
}

struct ClipboardLinkStore {
    static let shared = ClipboardLinkStore(defaults: .standard)
    static let limit = 100                     // unpinned links kept; pinned ones don't count
    let defaults: UserDefaults
    private let storeKey = "watchClipboardLinks"

    // Older versions could store one video under two link shapes; they're shown once (their details merged)
    // without rewriting what's stored. Pinned links come first; each group keeps its newest-first order.
    func all() -> [ClipboardLink] {
        var order: [String] = [], merged: [String: ClipboardLink] = [:]
        for item in stored() {
            let k = VideoLinks.key(item.url)
            guard var m = merged[k] else { order.append(k); merged[k] = item; continue }
            m.title = m.title ?? item.title; m.thumbnail = m.thumbnail ?? item.thumbnail
            m.duration = m.duration ?? item.duration; m.isLive = m.isLive ?? item.isLive
            if item.isPinned { m.pinned = true }
            merged[k] = m
        }
        let list = order.compactMap { merged[$0] }
        return list.filter(\.isPinned) + list.filter { !$0.isPinned }
    }
    func link(for url: String) -> ClipboardLink? {
        let k = VideoLinks.key(url)
        return all().first { VideoLinks.key($0.url) == k }
    }
    // Puts `url` on top, dated `date`, carrying over whatever is already known about that video.
    func add(_ url: String, date: Date = Date()) {
        let k = VideoLinks.key(url)
        var items = stored()
        let old = items.filter { VideoLinks.key($0.url) == k }
        items.removeAll { VideoLinks.key($0.url) == k }
        items.insert(ClipboardLink(url: url, title: old.lazy.compactMap({ $0.title }).first, date: date,
                                   thumbnail: old.lazy.compactMap({ $0.thumbnail }).first,
                                   duration: old.lazy.compactMap({ $0.duration }).first,
                                   isLive: old.lazy.compactMap({ $0.isLive }).first,
                                   pinned: old.contains(where: \.isPinned) ? true : nil), at: 0)
        save(Self.capped(items))
    }
    // Pins or unpins a video. Pinning one that isn't listed (a search result) adds it, with what's known.
    func setPinned(_ url: String, _ on: Bool, info: LinkInfo? = nil) {
        let k = VideoLinks.key(url)
        if on && !stored().contains(where: { VideoLinks.key($0.url) == k }) {
            add(url)
            if let info = info { update(url, with: info) }
        }
        var items = stored(), changed = false
        for i in items.indices where VideoLinks.key(items[i].url) == k && items[i].isPinned != on {
            items[i].pinned = on ? true : nil; changed = true
        }
        if changed { save(Self.capped(items)) }
    }
    // Fills in what's known; nil fields leave the stored value alone. Only videos already in the list change.
    func update(_ url: String, with info: LinkInfo) {
        let k = VideoLinks.key(url)
        var items = stored(), changed = false
        for i in items.indices where VideoLinks.key(items[i].url) == k {
            if let t = info.title, !t.isEmpty { items[i].title = t }
            if let t = info.thumbnail { items[i].thumbnail = t }
            if let d = info.duration { items[i].duration = d }
            if let l = info.isLive { items[i].isLive = l }
            changed = true
        }
        if changed { save(items) }
    }
    func remove(_ url: String) {
        let k = VideoLinks.key(url)
        var items = stored()
        let before = items.count
        items.removeAll { VideoLinks.key($0.url) == k }
        if items.count != before { save(items) }
    }
    // Removes every unpinned link.
    func clear() {
        let pinned = stored().filter(\.isPinned)
        if pinned.isEmpty { defaults.removeObject(forKey: storeKey) } else { save(pinned) }
    }
    // Every word must appear in the title, the link or its site (case and accents ignored).
    func matching(_ query: String) -> [ClipboardLink] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return all() }
        return all().filter { link in
            let haystack = [link.title ?? "", link.url, VideoLinks.site(link.url)].joined(separator: " ")
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    // Every pinned link plus the newest `limit` unpinned ones, order unchanged.
    private static func capped(_ items: [ClipboardLink]) -> [ClipboardLink] {
        var unpinned = 0
        return items.filter { $0.isPinned || { unpinned += 1; return unpinned <= limit }() }
    }
    private func stored() -> [ClipboardLink] {
        guard let data = defaults.data(forKey: storeKey),
              let items = try? JSONDecoder().decode([ClipboardLink].self, from: data) else { return [] }
        return items
    }
    private func save(_ items: [ClipboardLink]) {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: storeKey) }
    }
}
