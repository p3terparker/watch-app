import Foundation

// Up Next: the list a player plays through — each video window's own (the playlist, search page, Favourites, folder or
// YouTube's recommendations it came from) and the universal queue under the music window (UpNext.swift). One list with
// a cursor: what played, what's playing, then what's next. Items added with Play Next / Play Later are marked `added` and
// play before the list carries on ("Playing Next"). Foundation only, so test.sh covers it.

// Where an item plays. Everything but Spotify and Music plays in Watch.
enum MediaSource: String, Codable, Equatable {
    case web        // a page yt-dlp resolves: YouTube and other sites (a video window)
    case file       // a local video file (a video window)
    case audio      // a local audio file or a direct link to one (Watch's own player, shown in the music window)
    case spotify    // a Spotify song or episode, played by the Spotify app
    case music      // a song in the Music app, played by Music
    case podcast    // a podcast episode: its audio, played by Watch in the music window, resuming where it was left (3.22)

    static let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "aifc", "caf", "flac"]

    static func of(_ url: String) -> MediaSource {
        let s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if SpotifyLink.isSpotify(s) { return .spotify }
        if s.hasPrefix(QueueItem.musicPrefix) { return .music }
        if PodcastLinks.isEpisode(s) { return .podcast }       // an Apple Podcasts episode link: its audio is looked up
        if s.hasPrefix("/") || s.hasPrefix("file://") {
            let path = s.hasPrefix("file://") ? (URL(string: s)?.path ?? s) : s
            return audioExtensions.contains((path as NSString).pathExtension.lowercased()) ? .audio : .file
        }
        let ext = ((URL(string: s)?.path ?? "") as NSString).pathExtension.lowercased()
        return audioExtensions.contains(ext) && looksLikeURL(s) ? .audio : .web
    }
    // Played by another app (Music, Spotify) rather than Watch.
    var isExternal: Bool { self == .spotify || self == .music }
}

// Spotify links: a song or episode becomes the `spotify:track:…` / `spotify:episode:…` URI the app plays; albums,
// playlists, artists and shows are only opened in Spotify (expanding them needs the Web API).
enum SpotifyLink {
    static let bundleID = "com.spotify.client"
    // Any Spotify link or URI, playable or not.
    static func isSpotify(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("spotify:") || URLComponents(string: t)?.host?.lowercased() == "open.spotify.com"
    }
    // The URI for a song or episode; nil for anything else (or a malformed id).
    static func uri(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String]
        if t.hasPrefix("spotify:") {
            parts = t.split(separator: ":").dropFirst().map(String.init)
        } else {
            guard let c = URLComponents(string: t), c.host?.lowercased() == "open.spotify.com" else { return nil }
            parts = c.path.split(separator: "/").map(String.init)
            if parts.first?.hasPrefix("intl-") == true { parts.removeFirst() }      // open.spotify.com/intl-de/track/…
        }
        guard parts.count >= 2, ["track", "episode"].contains(parts[0]), isID(parts[1]) else { return nil }
        return "spotify:\(parts[0]):\(parts[1])"
    }
    static func isID(_ s: String) -> Bool { s.count == 22 && s.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) } }
    // The page for a URI (the row's ↗ and Copy Link); the link itself otherwise.
    static func webURL(_ s: String) -> String {
        guard let u = uri(s) else { return s }
        let parts = u.split(separator: ":")
        return "https://open.spotify.com/\(parts[1])/\(parts[2])"
    }
}

// A saved Up Next (PlayQueue.snapshot), kept in UserDefaults (`upNextQueue`) so it's there after a relaunch.
struct QueueSnapshot: Codable, Equatable {
    var name: String
    var items: [QueueItem]
    var current: Int
    var handBack: String?
}

struct QueueItem: Codable, Equatable, Identifiable {
    static let musicPrefix = "music:"     // a song in the Music app: "music:<persistent ID>", or "music:" for "what Music plays"
    var id = UUID()
    var url: String
    var title: String?
    var subtitle: String?                 // artist, channel or show
    var artwork: String?                  // picture URL
    var duration: Double?
    var source: MediaSource
    var added = false                     // put here with Play Next / Play Later, not by the list it came from
    var page: String?                     // where it lives when that isn't `url`: a podcast episode's Apple Podcasts page
    // Its resume position and ✓: a podcast episode's by its Apple Podcasts page when known (any link to it), else the link.
    var resumeKey: String { VideoLinks.key(source == .podcast ? page ?? url : url) }

    init(url: String, title: String? = nil, subtitle: String? = nil, artwork: String? = nil, duration: Double? = nil,
         source: MediaSource? = nil, added: Bool = false, page: String? = nil) {
        self.url = url; self.title = title; self.subtitle = subtitle; self.artwork = artwork; self.duration = duration
        self.source = source ?? .of(url); self.added = added; self.page = page
    }
}
enum RepeatMode: String { case off, all, one }

// What the drop-down list shows, top to bottom.
struct QueueSections: Equatable {
    var history: [QueueItem] = []         // what played, oldest first
    var now: QueueItem?
    var playingNext: [QueueItem] = []     // what you added, next in line
    var continuing: [QueueItem] = []      // the rest of the list
}

struct PlayQueue {
    enum Kind { case list, recommended, folder }
    // Where an addition goes: right after Now Playing, after your other additions, or at a spot in play order (a drop).
    enum Placement: Equatable { case next, later, at(Int) }
    let kind: Kind
    let name: String                  // shown as the Up Next heading: "History", a playlist's title, a folder…
    private(set) var items: [QueueItem]
    private(set) var order: [Int]     // indices into items, in play order — identity unless shuffled
    private(set) var pos = 0          // where we are in `order`
    private(set) var shuffled = false
    // The app whose own queue carries on when this list runs out (the universal queue slotted in while it played).
    var handBack: String?

    init(kind: Kind, name: String, items: [QueueItem], startAt: Int = 0, shuffled: Bool = false) {
        self.kind = kind; self.name = name; self.items = items
        self.order = Array(items.indices)
        self.pos = items.isEmpty ? 0 : min(max(0, startAt), items.count - 1)
        if shuffled { setShuffle(true) }
    }
    var currentIndex: Int { order.indices.contains(pos) ? order[pos] : -1 }
    var current: QueueItem? { items.indices.contains(currentIndex) ? items[currentIndex] : nil }
    var isEmpty: Bool { items.isEmpty }
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
    mutating func jump(to id: UUID) -> QueueItem? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        return jump(toItem: i)
    }
    func item(_ id: UUID) -> QueueItem? { items.first { $0.id == id } }
    // An item's place in play order.
    func position(of id: UUID) -> Int? { order.firstIndex { items[$0].id == id } }

    // How many of your additions are lined up right after Now Playing ("Playing Next").
    var addedAhead: Int {
        var n = 0
        while order.indices.contains(pos + 1 + n), items[order[pos + 1 + n]].added { n += 1 }
        return n
    }
    // When the current item ends: your additions always play on; the list itself only with Autoplay or Repeat All.
    func continues(autoplay: Bool, repeatMode: RepeatMode) -> Bool {
        autoplay || repeatMode == .all || (order.indices.contains(pos + 1) && items[order[pos + 1]].added)
    }

    // Play Next goes right after Now Playing, Play Later after the other additions; both are marked `added`. A drop at a
    // spot in play order (`at`, never before what's playing) counts as an addition when it lands in or right after
    // Playing Next. An empty list starts with the first item.
    mutating func insert(_ new: [QueueItem], _ placement: Placement) {
        guard !new.isEmpty else { return }
        let p: Int
        switch placement {
        case .next:      p = pos + 1
        case .later:     p = pos + 1 + addedAhead
        case .at(let i): p = min(max(i, pos + 1), order.count)
        }
        let added: Bool
        if case .at = placement { added = p <= pos + 1 + addedAhead } else { added = true }
        place(new.map { var item = $0; item.added = added; return item }, at: p)
    }
    // Into play order at `p` and into `items` right after the item it follows there, so turning shuffle off keeps it in
    // the same spot. Items keep their ids and flags.
    private mutating func place(_ new: [QueueItem], at p: Int) {
        guard !items.isEmpty else { items = new; order = Array(new.indices); pos = 0; return }
        let p = min(max(p, 0), order.count)
        let at = p == 0 ? 0 : order[p - 1] + 1
        order = order.map { $0 >= at ? $0 + new.count : $0 }
        items.insert(contentsOf: new, at: at)
        order.insert(contentsOf: Array(at..<(at + new.count)), at: p)
    }
    // Takes items out — never what's playing.
    mutating func remove(ids: Set<UUID>) {
        let playing = currentIndex
        let gone = Set(items.indices.filter { ids.contains(items[$0].id) && $0 != playing })
        guard !gone.isEmpty else { return }
        var newIndex = [Int](repeating: -1, count: items.count), n = 0
        for i in items.indices where !gone.contains(i) { newIndex[i] = n; n += 1 }
        items = items.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
        order = order.filter { !gone.contains($0) }.map { newIndex[$0] }
        pos = playing >= 0 ? (order.firstIndex(of: newIndex[playing]) ?? 0) : 0
    }
    // Moves upcoming items (in their play order) to play-order position `p`, counted before the move — as a list drop
    // gives it. Where they land decides whether they count as additions.
    mutating func move(ids: [UUID], to p: Int) {
        let wanted = Set(ids)
        let positions = order.indices.filter { $0 > pos && wanted.contains(items[order[$0]].id) }
        guard !positions.isEmpty else { return }
        let moving = positions.map { items[order[$0]] }
        let before = positions.filter { $0 < p }.count
        remove(ids: Set(moving.map(\.id)))
        insert(moving, .at(p - before))
    }
    // "Clear": every upcoming addition goes; the list stays.
    mutating func clearAdded() {
        remove(ids: Set(order.indices.filter { $0 > pos && items[order[$0]].added }.map { items[order[$0]].id }))
    }
    // Fills in what's learnt later (a title, artwork, length); the id never changes.
    mutating func update(_ id: UUID, _ change: (inout QueueItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        items[i].id = id
    }

    // Up Next as it stands, to restore after a relaunch (3.24): the items in play order and where it was; the mirror of
    // "what Music/Spotify was playing" isn't kept (it's the app's, not Watch's). nil when nothing of Watch's would remain.
    var snapshot: QueueSnapshot? {
        var kept: [QueueItem] = [], current = 0
        for (i, index) in order.enumerated() {
            let item = items[index]
            if item.url == QueueItem.musicPrefix || item.url == "spotify:" { continue }
            if i < pos { current += 1 }                          // what already played stays, before the cursor
            kept.append(item)
        }
        guard !kept.isEmpty else { return nil }
        return QueueSnapshot(name: name, items: kept, current: min(current, kept.count - 1), handBack: handBack)
    }
    init(snapshot s: QueueSnapshot) {
        self.init(kind: .list, name: s.name, items: s.items, startAt: min(max(0, s.current), max(0, s.items.count - 1)))
        handBack = s.handBack
    }

    // Shuffle randomizes everything around whatever is playing — which stays put and keeps playing — except Playing
    // Next, which stays right after it in your order; turning it back off restores the real order at the same item.
    // (Randomizing only what's "behind" the cursor would strand the items above a list you joined in the middle.)
    mutating func setShuffle(_ on: Bool) {
        let here = max(0, currentIndex)
        guard items.count > 1 else { shuffled = on; return }
        if on {
            let ahead = Array(order[(pos + 1)..<(pos + 1 + addedAhead)])
            let pinned = Set(ahead + [here])
            order = [here] + ahead + items.indices.filter { !pinned.contains($0) }.shuffled()
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
    // A list that arrives after you've already added things to a lone video (its playlist, recommendations or folder):
    // the list, with your additions right after its current item, still playing whatever this queue is playing now.
    func merged(into context: PlayQueue) -> PlayQueue {
        var result = context
        result.handBack = handBack ?? context.handBack
        let anchor = order.firstIndex { !items[$0].added } ?? 0
        let carried = order.indices.filter { $0 > anchor }.map { items[order[$0]] }
        if !carried.isEmpty, !result.items.isEmpty { result.place(carried, at: result.pos + 1) }
        else if result.items.isEmpty { result.place(Array(order.map { items[$0] }), at: 0) }
        if let playing = current, playing.added { _ = result.jump(to: playing.id) }
        return result
    }

    // History (the last `historyLimit` played), Now Playing, Playing Next, then the rest — for the drop-down list.
    func sections(historyLimit: Int = 50) -> QueueSections {
        guard !order.isEmpty else { return QueueSections() }
        let ahead = addedAhead
        var s = QueueSections()
        s.history = order[max(0, pos - historyLimit)..<pos].map { items[$0] }
        s.now = current
        s.playingNext = order[(pos + 1)..<(pos + 1 + ahead)].map { items[$0] }
        s.continuing = order[(pos + 1 + ahead)...].map { items[$0] }
        return s
    }

    // A local file's neighbours: the other media of the same kind in its folder, in Finder order.
    // Only what AVFoundation can actually open — a .webm sitting next door would just fail to play.
    static let videoExts: Set<String> = ["mp4", "m4v", "mov", "qt", "3gp", "3g2"]
    static let audioExts: Set<String> = MediaSource.audioExtensions
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
    // Every media file in a folder (Finder order), for a folder dropped on a queue.
    static func media(inFolder dir: URL) -> [QueueItem] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { mediaKind(($0 as NSString).pathExtension) != nil && !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { QueueItem(url: dir.appendingPathComponent($0).path, title: ($0 as NSString).deletingPathExtension) }
    }
}
