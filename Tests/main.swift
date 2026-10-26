import Foundation

// Substitute only the external process boundary; exercise the production queue unchanged.
enum Prefs { static let downloadDir = NSTemporaryDirectory(); static let autoUpdate = false }
func resolveTitle(_ url: String, completion: @escaping (String?) -> Void) { completion(nil) }
enum YtDlp {
    static var calls = 0
    static var launched: [[String]] = []
    static var pending: ((Data?) -> Void)?
    static func capture(_ args: [String], completion: @escaping (Data?) -> Void) {
        calls += 1; pending = completion
    }
    static func update(completion: @escaping (Bool) -> Void) { completion(true) }
    static func process(_ args: [String]) -> Process? { launched.append(args); return nil }
    static func reset() { calls = 0; launched = []; pending = nil }
    static func finish(_ data: Data?) { let callback = pending; pending = nil; callback?(data) }
}
var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }; checks += 1
}
for (response, quality) in [(nil, "0"), ("{}", "0"), ("not JSON", "0"), ("{\"abr\":0}", "0"), ("{\"abr\":129}", "160K")] as [(String?, String)] {
    YtDlp.reset()
    let queue = DownloadManager()
    queue.start(url: "https://example.invalid/audio", title: "Fixture", kind: .mp3)
    expect(YtDlp.calls == 1, "one initial probe expected")
    YtDlp.finish(response.map { Data($0.utf8) })
    expect(YtDlp.calls == 1, "unknown/invalid bitrate must not start another probe")
    expect(YtDlp.launched.count == 1, "download should proceed after the probe")
    let args = YtDlp.launched[0]
    let index = args.firstIndex(of: "--audio-quality")!
    expect(args[index + 1] == quality, "wrong MP3 quality fallback")
    expect(queue.jobs[0].state == .failed, "missing tool should visibly fail the job")
}
YtDlp.reset()
let canceled = DownloadManager()
canceled.start(url: "https://example.invalid/audio", title: "Fixture", kind: .mp3)
canceled.stop(canceled.jobs[0])
YtDlp.finish(nil)
expect(YtDlp.launched.isEmpty, "canceling during probe must prevent download")
expect(canceled.jobs[0].state == .stopped, "canceled job state changed")
// Resume positions: an isolated defaults suite, never the user's.
let suite = "glasskit-watch-tests-\(ProcessInfo.processInfo.processIdentifier)"
let positionDefaults = UserDefaults(suiteName: suite)!
defer { positionDefaults.removePersistentDomain(forName: suite) }
let positions = PlaybackPositions(defaults: positionDefaults)
expect(PlaybackPositions.key(source: "https://youtu.be/abc", youtubeID: "abc") == "yt:abc", "YouTube key uses the id")
expect(PlaybackPositions.key(source: "file:///tmp/a%20b.mp4", youtubeID: nil) == "/tmp/a b.mp4", "file URL key is its path")
expect(PlaybackPositions.key(source: "/tmp/x/../a b.mp4", youtubeID: nil) == "/tmp/a b.mp4", "path key is standardized")
positions.save(120, duration: 600, for: "yt:abc")
expect(positions.position(for: "yt:abc") == 120, "position saved")
positions.save(2, duration: 600, for: "yt:abc")
expect(positions.position(for: "yt:abc") == nil, "the first seconds forget the video")
positions.save(120, duration: 600, for: "yt:abc")
positions.save(590, duration: 600, for: "yt:abc")
expect(positions.position(for: "yt:abc") == nil, "finishing forgets the video")
positions.save(300, duration: nil, for: "live-or-unknown")
expect(positions.position(for: "live-or-unknown") == 300, "unknown duration still saves")
for i in 0..<(PlaybackPositions.limit + 5) { positions.save(60, duration: nil, for: "k\(i)") }
expect(positions.position(for: "k0") == nil && positions.position(for: "k\(PlaybackPositions.limit + 4)") == 60, "oldest entries pruned")
// Which copied links count as videos.
expect(VideoLinks.classify("https://youtu.be/dQw4w9WgXcQ?si=x") == .video, "YouTube short link is a video")
expect(VideoLinks.classify("https://www.youtube.com/playlist?list=PL123") == .video, "YouTube playlist is kept")
expect(VideoLinks.classify("https://www.youtube.com/@LofiGirl") == .other, "a YouTube channel page isn't a video link")
expect(VideoLinks.classify("https://cdn.example.com/a/movie.MP4?token=1") == .video, "media file extension counts")
expect(VideoLinks.classify("https://vimeo.com/123456") == .maybe, "other video sites need yt-dlp's say-so")
expect(VideoLinks.classify("https://x.com/user/status/1") == .maybe, "posts may carry a video")
expect(VideoLinks.classify("https://github.com/yt-dlp/yt-dlp") == .other, "a repo isn't a video link")
expect(VideoLinks.classify("https://notvimeo.com/1") == .other, "host suffix match needs a dot boundary")
expect(VideoLinks.classify("lofi beats") == .other, "text isn't a link")
expect(VideoLinks.key("https://youtu.be/abc?si=1") == VideoLinks.key("https://www.youtube.com/watch?v=abc&t=10"), "one key per YouTube video")
expect(VideoLinks.thumbnail("https://youtu.be/abc") == "https://i.ytimg.com/vi/abc/mqdefault.jpg", "YouTube thumbnail from the id")
expect(VideoLinks.site("https://www.vimeo.com/1") == "vimeo.com" && VideoLinks.site("https://youtu.be/a") == "YouTube", "site label")

// What yt-dlp's JSON says about a link.
let videoInfo = LinkInfo(json: ["title": " T ", "thumbnail": "u", "duration": 12, "live_status": "is_live"])
expect(videoInfo.title == "T" && videoInfo.thumbnail == "u" && videoInfo.duration == 12 && videoInfo.isLive == true && !videoInfo.isList, "video info")
let listInfo = LinkInfo(json: ["_type": "playlist", "title": "P", "entries": [["thumbnails": [["url": "a", "width": 120], ["url": "b", "width": 480]]]]])
expect(listInfo.isList && listInfo.thumbnail == "b" && listInfo.duration == nil, "playlist info falls back to its first entry's thumbnail")
expect(LinkInfo(json: ["title": "", "duration": 0, "is_live": false]).title == nil, "empty title is no title")

// Recent Links: an isolated defaults suite, never the user's.
let linkSuite = "glasskit-watch-links-\(ProcessInfo.processInfo.processIdentifier)"
let linkDefaults = UserDefaults(suiteName: linkSuite)!
defer { linkDefaults.removePersistentDomain(forName: linkSuite) }
let store = ClipboardLinkStore(defaults: linkDefaults)
let d1 = Date(timeIntervalSinceReferenceDate: 1_000), d2 = Date(timeIntervalSinceReferenceDate: 2_000)
store.add("https://youtu.be/abc?si=1", date: d1)
store.update("https://www.youtube.com/watch?v=abc", with: LinkInfo(title: "Lofi Beats Café", thumbnail: "th", duration: 100))
expect(store.all().first?.title == "Lofi Beats Café", "update matches by video, not link text")
store.add("https://www.youtube.com/watch?v=abc&t=5", date: d2)
expect(store.all().count == 1, "the same video is listed once")
expect(store.all()[0].url == "https://www.youtube.com/watch?v=abc&t=5" && store.all()[0].date == d2, "re-adding moves it up with the newest link")
expect(store.all()[0].title == "Lofi Beats Café" && store.all()[0].thumbnail == "th" && store.all()[0].duration == 100, "re-adding keeps what's known")
store.add("https://vimeo.com/1")
expect(store.all().map(\.url) == ["https://vimeo.com/1", "https://www.youtube.com/watch?v=abc&t=5"], "newest first")
expect(store.matching("cafe LOFI").count == 1, "matching ignores case, accents and word order")
expect(store.matching("vimeo").first?.url == "https://vimeo.com/1", "matching looks at the link too")
expect(store.matching("nothing here").isEmpty, "no match")
store.remove("https://youtu.be/abc")
expect(store.all().map(\.url) == ["https://vimeo.com/1"], "remove goes by video")
store.clear()
expect(store.all().isEmpty, "clear empties the list")
// Entries written before 3.11 (no thumbnail/duration), including one video stored twice.
let legacy = #"[{"url":"https://youtu.be/x","date":700000000},{"url":"https://www.youtube.com/watch?v=x","title":"Old","date":600000000},{"url":"https://vimeo.com/2","title":"V","date":500000000}]"#
linkDefaults.set(Data(legacy.utf8), forKey: "watchClipboardLinks")
expect(store.all().count == 2 && store.all()[0].title == "Old" && store.all()[0].url == "https://youtu.be/x", "legacy entries decode; duplicates shown once, merged")
expect(linkDefaults.data(forKey: "watchClipboardLinks") == Data(legacy.utf8), "showing the list never rewrites what's stored")
store.clear()
for i in 0..<(ClipboardLinkStore.limit + 5) { store.add("https://vimeo.com/\(i)") }
expect(store.all().count == ClipboardLinkStore.limit && store.all()[0].url == "https://vimeo.com/\(ClipboardLinkStore.limit + 4)", "list capped, newest kept")

// Pinned links: listed first, kept past the cap and through Clear, carried over when copied again.
store.clear()
store.add("https://vimeo.com/old"); store.add("https://youtu.be/p1"); store.add("https://vimeo.com/new")
store.setPinned("https://www.youtube.com/watch?v=p1", true)
expect(store.all().map(\.url) == ["https://youtu.be/p1", "https://vimeo.com/new", "https://vimeo.com/old"], "pinned first, by video")
expect(store.all()[0].isPinned && !store.all()[1].isPinned, "only that one is pinned")
store.add("https://youtu.be/p1?t=9")
expect(store.all()[0].isPinned && store.all().count == 3, "copying a pinned video again keeps it pinned")
store.add("https://vimeo.com/newest")
expect(store.all().map(\.url).prefix(2) == ["https://youtu.be/p1?t=9", "https://vimeo.com/newest"], "newer unpinned links stay below the pin")
for i in 0..<(ClipboardLinkStore.limit + 5) { store.add("https://vimeo.com/fill\(i)") }
expect(store.all().count == ClipboardLinkStore.limit + 1 && store.all()[0].isPinned, "the cap never drops a pinned link")
store.clear()
expect(store.all().map(\.url) == ["https://youtu.be/p1?t=9"], "Clear keeps pinned links")
store.setPinned("https://youtu.be/p1", false)
expect(store.all().count == 1 && !store.all()[0].isPinned, "unpin")
store.setPinned("https://www.youtube.com/watch?v=r1", true, info: LinkInfo(title: "Result", duration: 60))
expect(store.all()[0].url == "https://www.youtube.com/watch?v=r1" && store.all()[0].isPinned && store.all()[0].title == "Result", "pinning an unlisted video adds it")
store.setPinned("https://vimeo.com/ghost", false)
expect(!store.all().contains { $0.url == "https://vimeo.com/ghost" }, "unpinning an unlisted link adds nothing")
store.remove("https://youtu.be/r1")
expect(!store.all().contains { $0.url.contains("r1") }, "a pinned link can still be removed")
let pinnedLegacy = #"[{"url":"https://youtu.be/y","date":700000000},{"url":"https://www.youtube.com/watch?v=y","date":600000000,"pinned":true}]"#
linkDefaults.set(Data(pinnedLegacy.utf8), forKey: "watchClipboardLinks")
expect(store.all().count == 1 && store.all()[0].isPinned, "a pin on either stored shape pins the video")
store.clear()

// The ↗ button: the link itself, a YouTube video at its resume point.
expect(VideoLinks.webURL("https://youtu.be/abc")?.absoluteString == "https://youtu.be/abc", "plain link")
expect(VideoLinks.webURL("https://www.youtube.com/watch?v=abc&t=5", resumeAt: 83.9)?.absoluteString == "https://www.youtube.com/watch?v=abc&t=83s", "resume replaces t")
expect(VideoLinks.webURL("https://vimeo.com/1", resumeAt: 30)?.absoluteString == "https://vimeo.com/1", "other sites unchanged")
expect(VideoLinks.webURL("https://youtu.be/abc", resumeAt: 0.4)?.absoluteString == "https://youtu.be/abc", "no resume under a second")
expect(VideoLinks.webURL("/Users/x/v.mp4") == nil && VideoLinks.webURL("file:///x.mp4") == nil, "files have no web page")

// The field: what Return does with its text.
let noFiles: (String) -> Bool = { _ in false }
expect(OmniboxInput.parse("   ", fileExists: noFiles) == .empty, "blank")
expect(OmniboxInput.parse("lofi hip hop", fileExists: noFiles) == .search("lofi hip hop"), "text searches")
expect(OmniboxInput.parse("  https://example.com/v  ", fileExists: noFiles) == .play("https://example.com/v"), "a link plays")
expect(OmniboxInput.parse("youtu.be/abc", fileExists: noFiles) == .play("https://youtu.be/abc"), "link without a scheme")
expect(OmniboxInput.parse("www.youtube.com/watch?v=abc", fileExists: noFiles) == .play("https://www.youtube.com/watch?v=abc"), "www link")
expect(OmniboxInput.parse("vimeo.com/123", fileExists: noFiles) == .play("https://vimeo.com/123"), "video site link")
expect(OmniboxInput.parse("https://www.youtube.com/playlist?list=PL1", fileExists: noFiles) == .playlist("https://www.youtube.com/playlist?list=PL1"), "playlist is listed")
expect(OmniboxInput.parse("youtube.com/playlist?list=PL1", fileExists: noFiles) == .playlist("https://youtube.com/playlist?list=PL1"), "schemeless playlist")
for text in ["mr.beast", "node.js", "3.14", "a.b/c"] { expect(OmniboxInput.parse(text, fileExists: noFiles) == .search(text), "\(text) stays a search") }
expect(OmniboxInput.parse("/tmp/x.mp4", fileExists: { $0 == "/tmp/x.mp4" }) == .play("/tmp/x.mp4"), "an existing file plays")
expect(OmniboxInput.parse("/tmp/x.mp4", fileExists: noFiles) == .search("/tmp/x.mp4"), "a missing path is just text")
expect(OmniboxInput.parse("file:///tmp/x.mp4", fileExists: noFiles) == .play("file:///tmp/x.mp4"), "file URL plays")

// Recent searches: queries only, newest first, no case duplicates, capped.
let searchSuite = "glasskit-watch-searches-\(ProcessInfo.processInfo.processIdentifier)"
let searchDefaults = UserDefaults(suiteName: searchSuite)!
defer { searchDefaults.removePersistentDomain(forName: searchSuite) }
let recents = RecentSearches(defaults: searchDefaults)
recents.add("lofi"); recents.add("jazz"); recents.add("LOFI ")
expect(recents.all == ["LOFI", "jazz"], "dedupe ignoring case, newest first")
for link in ["https://youtu.be/x", "youtu.be/x", "   "] { recents.add(link) }
expect(recents.all == ["LOFI", "jazz"], "links and blanks aren't remembered")
for i in 0..<12 { recents.add("q\(i)") }
expect(recents.all.count == RecentSearches.limit && recents.all.first == "q11", "capped")
recents.clear()
expect(recents.all.isEmpty, "clear")

// Which failures an update of yt-dlp usually fixes.
expect(SearchFailure.suggestsUpdate("ERROR: [youtube] abc: Unable to extract initial data"), "extractor breakage")
expect(SearchFailure.suggestsUpdate("ERROR: unable to download video data: HTTP Error 403: Forbidden"), "403")
expect(!SearchFailure.suggestsUpdate("yt-dlp timed out"), "timeouts aren't a version problem")
expect(!SearchFailure.suggestsUpdate("ERROR: [youtube:search] Unable to download API page: <urlopen error [Errno 8] nodename nor servname provided>"), "offline isn't either")

// Result cache: keyed by normalized query, entries expire.
var cache = SearchCache<Int>(lifetime: 600)
let t0 = Date(timeIntervalSinceReferenceDate: 10_000)
cache.store(1, for: "Lofi ", now: t0)
expect(cache.value(for: "lofi", now: t0.addingTimeInterval(10)) == 1, "cache hit")
expect(cache.value(for: "lofi", now: t0.addingTimeInterval(601)) == nil, "cache entries expire")
// Tile Windows: a 16:9 grid that fills the screen without overlap, in reading order of where windows sat.
let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
for n in 1...9 {
    let (cols, tiles) = Tiling.grid(count: n, in: screen)
    expect(tiles.count == n && cols >= 1 && cols <= n, "one tile per window")
    for (i, t) in tiles.enumerated() {
        expect(screen.insetBy(dx: 12, dy: 12).contains(t), "tile \(i) of \(n) stays inside the margins")
        expect(abs(t.width / t.height - 16.0 / 9.0) < 0.01, "tiles stay 16:9")
        for u in tiles[(i + 1)...] { expect(!t.intersects(u), "tiles never overlap") }
    }
}
let four = Tiling.grid(count: 4, in: screen)
expect(four.columns == 2, "four windows make a 2x2 grid")
let three = Tiling.grid(count: 3, in: screen)
expect(three.columns == 2 && abs(three.frames[2].midX - screen.midX) <= 1, "a short last row is centred")
expect(three.frames[0].minY > three.frames[2].minY && three.frames[0].minX < three.frames[1].minX, "rows fill left to right from the top")
expect(Tiling.grid(count: 5, in: screen).frames.allSatisfy { $0.width >= 400 }, "five windows are still usable")
expect(Tiling.grid(count: 0, in: screen).frames.isEmpty, "no windows, no tiles")
let scattered = [CGRect(x: 900, y: 600, width: 400, height: 225),   // top right
                 CGRect(x: 50, y: 100, width: 400, height: 225),    // bottom left
                 CGRect(x: 60, y: 610, width: 400, height: 225),    // top left (a little higher than top right)
                 CGRect(x: 800, y: 90, width: 400, height: 225)]    // bottom right
expect(Tiling.readingOrder(scattered, columns: 2) == [2, 0, 1, 3], "top row left to right, then the next row")
expect(Tiling.readingOrder(scattered, columns: 1) == [2, 0, 1, 3], "one column: top to bottom")
// Player click zones: top third + bottom middle resize, centre plays/pauses, lower left/right thirds skip.
let player = CGSize(width: 440, height: 247)
func zone(_ x: CGFloat, _ yFromTop: CGFloat) -> PlayerZone { PlayerZone.at(CGPoint(x: x, y: player.height - yFromTop), in: player) }
for x in [0, 100, 220, 300, 439] as [CGFloat] { expect(zone(x, 10) == .resize, "top third resizes at x \(x)") }
expect(zone(220, 123) == .playPause, "centre plays/pauses")
expect(zone(20, 123) == .skipBack && zone(20, 240) == .skipBack, "left third below the top skips back")
expect(zone(420, 123) == .skipForward && zone(420, 240) == .skipForward, "right third below the top skips forward")
expect(zone(220, 240) == .resize, "bottom middle resizes")
expect(zone(146, 123) == .skipBack && zone(147, 123) == .playPause, "column edges split at a third of the width")
expect(zone(220, 82) == .resize && zone(220, 83) == .playPause, "row edges split at a third of the height")
expect(PlayerZone.at(CGPoint(x: 500, y: -5), in: player) == .skipForward, "points just outside clamp to the nearest zone")
expect(PlayerZone.at(.zero, in: .zero) == .resize, "an empty view has no play/skip zones")

// Library: watched marks, Favourites, playlist progress — an isolated defaults suite, never the user's.
let librarySuite = "glasskit-watch-library-\(ProcessInfo.processInfo.processIdentifier)"
let libraryDefaults = UserDefaults(suiteName: librarySuite)!
defer { libraryDefaults.removePersistentDomain(forName: librarySuite) }
expect(WatchedVideos.threshold(duration: 600) == 540, "long video: watched at 90%")
expect(WatchedVideos.threshold(duration: 60) == 45, "short video: watched in its last 15 s")
expect(WatchedVideos.threshold(duration: 20) == 10, "never before half-way")
expect(!WatchedVideos.isFinished(500, duration: nil) && !WatchedVideos.isFinished(.nan, duration: 600), "unknown duration or time isn't finished")
let watched = WatchedVideos(defaults: libraryDefaults)
expect(!watched.noteProgress(300, duration: 600, for: "yt:w1") && !watched.isWatched("yt:w1"), "half-way isn't watched")
expect(watched.noteProgress(545, duration: 600, for: "yt:w1") && watched.isWatched("yt:w1"), "90% marks it")
expect(!watched.noteProgress(590, duration: 600, for: "yt:w1"), "already watched: no second mark")
watched.mark("/tmp/a.mp4")
expect(watched.keys() == ["yt:w1", "/tmp/a.mp4"], "keys lists every mark")
watched.unmark("yt:w1")
expect(!watched.isWatched("yt:w1") && watched.isWatched("/tmp/a.mp4"), "unmark one")
for i in 0..<(WatchedVideos.limit + 3) { watched.mark("k\(i)", date: Date(timeIntervalSinceReferenceDate: Double(i + 10))) }
expect(watched.keys().count == WatchedVideos.limit && !watched.isWatched("k0") && !watched.isWatched("k3") && watched.isWatched("k4")
       && watched.isWatched("/tmp/a.mp4"), "oldest marks pruned")

let favs = Favourites(defaults: libraryDefaults)
favs.add("https://youtu.be/f1?si=x", info: LinkInfo(title: "First", duration: 90), date: d1)
favs.add("https://vimeo.com/7", date: d2)
expect(favs.all().map(\.url) == ["https://vimeo.com/7", "https://youtu.be/f1?si=x"], "newest favourite first")
expect(favs.contains("https://www.youtube.com/watch?v=f1&t=3"), "contains goes by video")
favs.add("https://www.youtube.com/watch?v=f1", info: LinkInfo(thumbnail: "th"))
expect(favs.all().count == 2 && favs.all()[1].url == "https://youtu.be/f1?si=x", "adding again doesn't duplicate or move it")
expect(favs.all()[1].title == "First" && favs.all()[1].thumbnail == "th", "adding again fills in details")
favs.update("https://youtu.be/f1", with: LinkInfo(title: "Renamed"))
expect(favs.all()[1].title == "Renamed" && favs.all()[1].duration == 90, "update fills, nil leaves alone")
expect(favs.matching("renamed").count == 1 && favs.matching("VIMEO").count == 1 && favs.matching("zzz").isEmpty, "matching")
favs.remove("https://www.youtube.com/watch?v=f1")
expect(favs.all().map(\.url) == ["https://vimeo.com/7"], "remove goes by video")

// 3.12 pins become favourites once, keep their order and details, and stop floating in Recent Links.
let pinStore = ClipboardLinkStore(defaults: libraryDefaults)
pinStore.add("https://youtu.be/p2", date: d1); pinStore.add("https://youtu.be/p3", date: d2); pinStore.add("https://vimeo.com/plain")
pinStore.update("https://youtu.be/p2", with: LinkInfo(title: "Pinned Two", duration: 42))
pinStore.setPinned("https://youtu.be/p2", true); pinStore.setPinned("https://youtu.be/p3", true)
let pinOrder = pinStore.all().filter(\.isPinned).map(\.url)
favs.importPins(from: pinStore)
expect(Array(favs.all().map(\.url).prefix(2)) == pinOrder, "pins imported in their listed order, on top")
expect(favs.all().first { $0.url == "https://youtu.be/p2" }?.title == "Pinned Two" && favs.all().first { $0.url == "https://youtu.be/p2" }?.added == d1, "details and date carried over")
expect(pinStore.all().count == 3 && !pinStore.all().contains(where: \.isPinned), "Recent Links keeps every link, unpinned")
expect(pinStore.all().first?.url == "https://vimeo.com/plain", "Recent Links is newest-first again")
pinStore.setPinned("https://vimeo.com/plain", true)
favs.importPins(from: pinStore)
expect(!favs.contains("https://vimeo.com/plain") && pinStore.all()[0].isPinned, "the import runs only once")

let lists = PlaylistProgress(defaults: libraryDefaults)
expect(lists.video(for: "PL1") == nil, "no progress yet")
lists.set("yt:b", for: "PL1")
expect(lists.video(for: "PL1") == "yt:b", "progress saved")
let playlistKeys = ["yt:a", "yt:b", "yt:c"]
expect(PlaylistProgress.startIndex(keys: playlistKeys, saved: nil, finished: { _ in false }) == 0, "new playlist starts at the top")
expect(PlaylistProgress.startIndex(keys: playlistKeys, saved: "yt:b", finished: { _ in false }) == 1, "carries on at the saved video")
expect(PlaylistProgress.startIndex(keys: playlistKeys, saved: "yt:b", finished: { $0 == "yt:b" }) == 2, "a finished video moves on to the next")
expect(PlaylistProgress.startIndex(keys: playlistKeys, saved: "yt:c", finished: { $0 == "yt:c" }) == 0, "finishing the last goes back to the top")
expect(PlaylistProgress.startIndex(keys: playlistKeys, saved: "yt:gone", finished: { _ in true }) == 0, "a video no longer listed starts at the top")
for i in 0..<(PlaylistProgress.limit + 2) { lists.set("yt:v", for: "L\(i)", date: Date(timeIntervalSinceReferenceDate: Double(i + 5_000))) }
expect(lists.video(for: "L0") == nil && lists.video(for: "L2") == nil && lists.video(for: "L3") == "yt:v"
       && lists.video(for: "PL1") == "yt:b", "oldest playlists pruned")
// Fake scheduler: force even superseded work to execute, testing the cancellation token too.
var scheduled: [DispatchWorkItem] = []
var queries: [String] = []
let live = LiveSearch { delay, work in
    expect(delay == 0.35, "live searches wait 350 ms")
    scheduled.append(work)
}
live.update("c") { queries.append($0) }
live.update("cats") { queries.append($0) }
expect(queries.isEmpty, "typing does not search synchronously")
scheduled.forEach { $0.perform() }; scheduled.removeAll()
expect(queries == ["cats"], "only the newest query searches")
for input in ["", "  ", "https://youtu.be/abc", "www.youtube.com/watch?v=abc", "https://youtube.com/playlist?list=PL1", "/tmp/not-yet-created.mp4", "~/Movies/", "file:///tmp/a.mp4"] {
    live.update("pending") { queries.append($0) }
    live.update(input) { queries.append($0) }
    scheduled.forEach { $0.perform() }; scheduled.removeAll()
    expect(queries == ["cats"], "clearing or link/path input cancels pending search: \(input)")
}
live.update("pending") { queries.append($0) }
live.update("日本", composing: true) { queries.append($0) }
scheduled.forEach { $0.perform() }; scheduled.removeAll()
expect(queries == ["cats"], "marked text does not search")
live.update("  日  ") { queries.append($0) }
scheduled.forEach { $0.perform() }; scheduled.removeAll()
expect(queries.last == "日", "committed one-character query searches, trimmed")
live.update("cancel") { queries.append($0) }
live.cancel()
scheduled.forEach { $0.perform() }
expect(!queries.contains("cancel"), "navigation or submit cancels scheduled work")
checkMediaTools()
print("Watch downloads + positions + links + search + tiling + zones + library: \(checks) checks passed")
