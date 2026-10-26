import Foundation

// Library: which videos you've watched, your Favourites, and where each playlist was left off. Foundation
// only, so test.sh can compile it without AppKit. Videos are keyed like resume positions (`VideoLinks.key`):
// `yt:<id>` for YouTube, whatever the link looks like.

// Posted (by the app, not these stores) when a watched mark or a favourite changes, so the panel redraws.
extension Notification.Name { static let watchLibraryChanged = Notification.Name("watchLibraryChanged") }

// ----------------------------------------------------------------------------
// MARK: - Watched videos
// ----------------------------------------------------------------------------
// One UserDefaults dictionary (`watchedVideos`): video key → when it was marked. A video counts as watched once
// playback reaches `threshold` — 90% of it, or its last 15 s if that comes first, never before half-way — or
// plays to its end. Newest `limit` kept.
struct WatchedVideos {
    static let shared = WatchedVideos(defaults: .standard)
    static let limit = 2000
    let defaults: UserDefaults
    private let storeKey = "watchedVideos"

    static func threshold(duration d: Double) -> Double { max(d * 0.5, min(d * 0.9, d - PlaybackPositions.endMargin)) }
    static func isFinished(_ seconds: Double, duration: Double?) -> Bool {
        guard seconds.isFinite, let d = duration, d.isFinite, d > 0 else { return false }
        return seconds >= threshold(duration: d)
    }
    private var all: [String: Double] { defaults.dictionary(forKey: storeKey) as? [String: Double] ?? [:] }

    func isWatched(_ key: String) -> Bool { all[key] != nil }
    // Every watched key at once, for drawing a list.
    func keys() -> Set<String> { Set(all.keys) }
    // Called with every position save. True when this call marked the video.
    @discardableResult func noteProgress(_ seconds: Double, duration: Double?, for key: String) -> Bool {
        guard Self.isFinished(seconds, duration: duration), !isWatched(key) else { return false }
        mark(key); return true
    }
    func mark(_ key: String, date: Date = Date()) {
        var dict = all
        dict[key] = date.timeIntervalSinceReferenceDate
        if dict.count > Self.limit {
            dict.sorted { $0.value < $1.value }.prefix(dict.count - Self.limit).forEach { dict.removeValue(forKey: $0.key) }
        }
        defaults.set(dict, forKey: storeKey)
    }
    func unmark(_ key: String) {
        var dict = all
        guard dict.removeValue(forKey: key) != nil else { return }
        defaults.set(dict, forKey: storeKey)
    }
}

// ----------------------------------------------------------------------------
// MARK: - Favourites
// ----------------------------------------------------------------------------
// One JSON array in UserDefaults (`watchFavourites`), newest first, one entry per video, no cap. They replace
// the 3.12 Recent Links pins: `importPins` moves those over once.
struct FavouriteVideo: Codable, Equatable {
    var url: String
    var title: String?
    var thumbnail: String?
    var duration: Double?
    var isLive: Bool?
    var added: Date
}

struct Favourites {
    static let shared = Favourites(defaults: .standard)
    let defaults: UserDefaults
    private let storeKey = "watchFavourites"
    private let importedKey = "favouritesImportedPins"

    func all() -> [FavouriteVideo] {
        guard let data = defaults.data(forKey: storeKey),
              let items = try? JSONDecoder().decode([FavouriteVideo].self, from: data) else { return [] }
        return items
    }
    func contains(_ url: String) -> Bool { let k = VideoLinks.key(url); return all().contains { VideoLinks.key($0.url) == k } }
    // Adds on top. Already a favourite: stays where it is, with any new details filled in.
    func add(_ url: String, info: LinkInfo? = nil, date: Date = Date()) {
        guard !contains(url) else { if let i = info { update(url, with: i) }; return }
        var items = all()
        items.insert(FavouriteVideo(url: url, title: info?.title, thumbnail: info?.thumbnail, duration: info?.duration,
                                    isLive: info?.isLive, added: date), at: 0)
        save(items)
    }
    func remove(_ url: String) {
        let k = VideoLinks.key(url)
        var items = all()
        let before = items.count
        items.removeAll { VideoLinks.key($0.url) == k }
        if items.count != before { save(items) }
    }
    // Fills in what's known; nil fields leave the stored value alone.
    func update(_ url: String, with info: LinkInfo) {
        let k = VideoLinks.key(url)
        var items = all(), changed = false
        for i in items.indices where VideoLinks.key(items[i].url) == k {
            if let t = info.title, !t.isEmpty { items[i].title = t }
            if let t = info.thumbnail { items[i].thumbnail = t }
            if let d = info.duration { items[i].duration = d }
            if let l = info.isLive { items[i].isLive = l }
            changed = true
        }
        if changed { save(items) }
    }
    // Same rule as Recent Links: every word in the title, the link or its site (case and accents ignored).
    func matching(_ query: String) -> [FavouriteVideo] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return all() }
        return all().filter { f in
            let haystack = [f.title ?? "", f.url, VideoLinks.site(f.url)].joined(separator: " ")
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
    // Once: links pinned in Recent Links (3.12–3.14) become favourites, in their listed order, then lose the pin —
    // Recent Links goes back to plain newest-first. Nothing is removed from either list.
    func importPins(from links: ClipboardLinkStore) {
        guard !defaults.bool(forKey: importedKey) else { return }
        let pinned = links.all().filter(\.isPinned)
        for p in pinned.reversed() {
            add(p.url, info: LinkInfo(title: p.title, thumbnail: p.thumbnail, duration: p.duration, isLive: p.isLive), date: p.date)
        }
        pinned.forEach { links.setPinned($0.url, false) }
        defaults.set(true, forKey: importedKey)
    }
    private func save(_ items: [FavouriteVideo]) {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: storeKey) }
    }
}

// ----------------------------------------------------------------------------
// MARK: - Playlist progress
// ----------------------------------------------------------------------------
// Which video each playlist was on (`playlistProgress`: list id → video key + when), so opening the playlist
// link again carries on there. Newest `limit` kept.
struct PlaylistProgress {
    static let shared = PlaylistProgress(defaults: .standard)
    static let limit = 200
    let defaults: UserDefaults
    private let storeKey = "playlistProgress"
    private struct Entry: Codable { var video: String; var date: Date }

    private var all: [String: Entry] {
        guard let data = defaults.data(forKey: storeKey),
              let dict = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return dict
    }
    func video(for list: String) -> String? { all[list]?.video }
    func set(_ videoKey: String, for list: String, date: Date = Date()) {
        var dict = all
        guard dict[list]?.video != videoKey else { return }
        dict[list] = Entry(video: videoKey, date: date)
        if dict.count > Self.limit {
            dict.sorted { $0.value.date < $1.value.date }.prefix(dict.count - Self.limit).forEach { dict.removeValue(forKey: $0.key) }
        }
        if let data = try? JSONEncoder().encode(dict) { defaults.set(data, forKey: storeKey) }
    }
    // Where a playlist starts: the video it was on — or, when that one was finished (watched, no resume point
    // left), the one after it, and the top after the last. `keys` are the playlist's video keys in order.
    static func startIndex(keys: [String], saved: String?, finished: (String) -> Bool) -> Int {
        guard let s = saved, let i = keys.firstIndex(of: s) else { return 0 }
        guard finished(s) else { return i }
        return i + 1 < keys.count ? i + 1 : 0
    }
}
