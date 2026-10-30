import Foundation

// Main-thread debounce. The revision check also rejects callbacks already enqueued when cancelled.
final class LiveSearch {
    static let delay: TimeInterval = 0.35
    private var revision = 0
    private var pending: DispatchWorkItem?
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void

    init(schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = {
        DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1)
    }) { self.schedule = schedule }

    func cancel() {
        revision += 1
        pending?.cancel(); pending = nil
    }

    func update(_ raw: String, composing: Bool = false, search: @escaping (String) -> Void) {
        cancel()
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Partial local paths must not be sent to YouTube, even before the file exists.
        guard !composing, !text.hasPrefix("/"), !text.hasPrefix("~/"),
              case .search(let query) = OmniboxInput.parse(text) else { return }
        let token = revision
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, token == self.revision else { return }
            self.pending = nil
            search(query)
        }
        pending = work
        schedule(Self.delay, work)
    }
}

// The panel's single field: what its text means, the searches it remembers, and what a failed search means.
// Foundation only, so test.sh can compile it without AppKit.

enum OmniboxInput: Equatable {
    case empty
    case play(String)        // a link or a local media file
    case playlist(String)    // a YouTube playlist link: listed in the panel
    case search(String)      // anything else: a YouTube search

    static func parse(_ raw: String, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> OmniboxInput {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        if text.hasPrefix("file://") { return .play(text) }
        if text.hasPrefix("spotify:") { return .play(text) }     // a Spotify URI: played by the Spotify app (UpNext.swift)
        if text.hasPrefix("/") || text.hasPrefix("~/") {
            let path = (text as NSString).expandingTildeInPath
            if fileExists(path) { return .play(path) }
        }
        let link = looksLikeURL(text) ? text : schemeless(text)
        guard let url = link else { return .search(text) }
        return VideoLinks.isYouTubePlaylist(url) ? .playlist(url) : .play(url)
    }

    // "youtu.be/abc", "www.youtube.com/watch?v=…", "vimeo.com/123" → an https link. It has to look like a link to
    // a page: a real top-level domain and a path, a "www." host, or a known video site ("mr.beast", "node.js" and
    // "3.14" stay searches).
    static func schemeless(_ text: String) -> String? {
        guard !text.contains(where: { $0.isWhitespace }), !text.contains("://"),
              let url = URL(string: "https://" + text), let host = url.host?.lowercased(),
              url.user == nil, url.password == nil else { return nil }
        let tld = host.split(separator: ".").last.map(String.init) ?? ""
        guard host.contains("."), tld.count >= 2, tld.allSatisfy({ $0.isLetter }) else { return nil }
        let hasPath = !url.path.isEmpty && url.path != "/"
        guard hasPath || host.hasPrefix("www.") || VideoLinks.isVideoSite(host) else { return nil }
        return "https://" + text
    }
}

// The last few YouTube searches (magnifier menu). Links and file paths are never remembered.
struct RecentSearches {
    static let shared = RecentSearches(defaults: .standard)
    static let limit = 10
    let defaults: UserDefaults
    private let storeKey = "watchRecentSearches"

    var all: [String] { defaults.stringArray(forKey: storeKey) ?? [] }
    func add(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, OmniboxInput.parse(q, fileExists: { _ in false }) == .search(q) else { return }
        let rest = all.filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        defaults.set(Array(([q] + rest).prefix(Self.limit)), forKey: storeKey)
    }
    func clear() { defaults.removeObject(forKey: storeKey) }
}

enum SearchFailure {
    // yt-dlp's ways of saying YouTube changed under it — an update usually fixes these (see GOTCHAS: a stale
    // yt-dlp makes YouTube 403 everything).
    static func suggestsUpdate(_ error: String) -> Bool {
        let e = error.lowercased()
        return ["http error 403", "unable to extract", "failed to extract", "nsig", "player response",
                "please report this issue"].contains { e.contains($0) }
    }
}

// Recent results, so Back and repeating a search are instant. Entries expire after `lifetime` seconds.
struct SearchCache<Value> {
    let lifetime: TimeInterval
    private var entries: [String: (value: Value, at: Date)] = [:]
    init(lifetime: TimeInterval = 600) { self.lifetime = lifetime }

    static func key(_ query: String) -> String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    func value(for query: String, now: Date = Date()) -> Value? {
        guard let e = entries[Self.key(query)], now.timeIntervalSince(e.at) < lifetime else { return nil }
        return e.value
    }
    mutating func store(_ value: Value, for query: String, now: Date = Date()) {
        entries = entries.filter { now.timeIntervalSince($0.value.at) < lifetime }
        entries[Self.key(query)] = (value, now)
    }
}
