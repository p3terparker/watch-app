import Foundation

// Up Next (Queue.swift) and the music-app hand-off (Handoff.swift): pure, no app or network.
func checkQueue() {
    func titles(_ q: PlayQueue) -> [String] { q.order.map { q.items[$0].title ?? "" } }
    let list = (1...5).map { QueueItem(url: "https://fixtures.invalid/v\($0)", title: "v\($0)") }

    // One list with a cursor; Play Next / Play Later go between Now Playing and the rest of the list.
    var q = PlayQueue(kind: .list, name: "Fixture", items: list, startAt: 1)
    expect(q.current?.title == "v2", "starts where asked")
    q.insert([QueueItem(url: "/tmp/a.mp3", title: "a")], .later)
    q.insert([QueueItem(url: "https://youtu.be/b", title: "b")], .later)
    q.insert([QueueItem(url: "https://youtu.be/n", title: "n")], .next)
    expect(titles(q) == ["v1", "v2", "n", "a", "b", "v3", "v4", "v5"],
           "Play Next first, Play Later after earlier additions, both before the list continues: \(titles(q))")
    let s = q.sections()
    expect(s.history.map(\.title) == ["v1"] && s.now?.title == "v2", "history and now")
    expect(s.playingNext.map(\.title) == ["n", "a", "b"] && s.continuing.map(\.title) == ["v3", "v4", "v5"], "Playing Next, then the list")
    expect(q.items.first { $0.title == "a" }?.source == .audio && q.items.first { $0.title == "b" }?.source == .web
           && q.items.allSatisfy { ["n", "a", "b"].contains($0.title ?? "") == $0.added }, "additions are marked, with their sources")
    expect(q.continues(autoplay: false, repeatMode: .off), "your additions play even with Autoplay off")
    q.step(1, wrap: false); q.step(1, wrap: false); q.step(1, wrap: false)
    expect(q.current?.title == "b" && !q.continues(autoplay: false, repeatMode: .off), "the list itself waits for Autoplay")
    expect(q.continues(autoplay: true, repeatMode: .off) && q.continues(autoplay: false, repeatMode: .all), "Autoplay or Repeat All carries on")
    expect(q.step(1, wrap: false)?.title == "v3", "after your additions the list continues")
    var empty = PlayQueue(kind: .list, name: "Up Next", items: [])
    empty.insert([QueueItem(url: "https://youtu.be/first", title: "first"), QueueItem(url: "https://youtu.be/second", title: "second")], .later)
    expect(titles(empty) == ["first", "second"] && empty.current?.title == "first", "an empty queue starts with the first addition")

    // Clear, remove, move.
    var c = PlayQueue(kind: .list, name: "C", items: list)
    c.insert([QueueItem(url: "x", title: "x"), QueueItem(url: "y", title: "y")], .later)
    c.clearAdded()
    expect(titles(c) == ["v1", "v2", "v3", "v4", "v5"] && c.current?.title == "v1", "Clear empties Playing Next; the list stays")
    var r = PlayQueue(kind: .list, name: "R", items: list, startAt: 2)
    let ids = r.items.map(\.id)
    r.remove(ids: [ids[0], ids[2], ids[4]])
    expect(titles(r) == ["v2", "v3", "v4"] && r.current?.title == "v3" && r.pos == 1, "removing never takes Now Playing; the cursor stays on it")
    var m = PlayQueue(kind: .list, name: "M", items: list)
    let v5 = m.items[4].id
    m.move(ids: [v5], to: 1)
    expect(titles(m) == ["v1", "v5", "v2", "v3", "v4"] && m.item(v5)?.added == true, "dragged right after Now Playing: yours, next")
    m.move(ids: [v5], to: 5)
    expect(titles(m) == ["v1", "v2", "v3", "v4", "v5"] && m.item(v5)?.added == false, "dragged back into the list: part of it again")
    var several = PlayQueue(kind: .list, name: "S", items: list)
    several.move(ids: [several.items[3].id, several.items[1].id], to: 5)
    expect(titles(several) == ["v1", "v3", "v5", "v2", "v4"], "several rows keep their play order when moved: \(titles(several))")
    several.move(ids: [several.items[0].id], to: 4)
    expect(titles(several) == ["v1", "v3", "v5", "v2", "v4"], "Now Playing can't be moved")
    var u = PlayQueue(kind: .list, name: "U", items: list)
    let first = u.items[0].id
    u.update(first) { $0.title = "Renamed"; $0.duration = 61; $0.id = UUID() }
    expect(u.current?.title == "Renamed" && u.current?.duration == 61 && u.current?.id == first, "details fill in; the id stays")

    // Shuffle keeps Now Playing and Playing Next in place; off restores the real order with additions where they were.
    var sh = PlayQueue(kind: .list, name: "Sh", items: list)
    sh.insert([QueueItem(url: "x", title: "x"), QueueItem(url: "y", title: "y")], .later)
    sh.setShuffle(true)
    expect(Array(titles(sh).prefix(3)) == ["v1", "x", "y"] && Set(titles(sh)) == Set(["v1", "x", "y", "v2", "v3", "v4", "v5"]) && sh.pos == 0,
           "shuffle keeps Now Playing and Playing Next in place")
    sh.setShuffle(false)
    expect(titles(sh) == ["v1", "x", "y", "v2", "v3", "v4", "v5"] && sh.current?.title == "v1", "unshuffle restores the real order")
    var t = PlayQueue(kind: .list, name: "T", items: list, shuffled: true)
    let playing = t.step(1, wrap: false)!
    t.insert([QueueItem(url: "z", title: "z")], .next)
    expect(t.peek(1, wrap: false)?.title == "z", "Play Next while shuffled plays next")
    t.setShuffle(false)
    expect(t.current?.id == playing.id && t.peek(1, wrap: false)?.title == "z", "and still right after it in the real order")

    // A lone video's list arriving after you added things: your additions go between the video and the list.
    var provisional = PlayQueue(kind: .list, name: "Up Next", items: [QueueItem(url: "https://youtu.be/lone", title: "lone")])
    provisional.insert([QueueItem(url: "/tmp/p1.mp3", title: "p1"), QueueItem(url: "https://youtu.be/p2", title: "p2")], .later)
    let context = PlayQueue(kind: .recommended, name: "YouTube Recommended",
                            items: ["lone", "r1", "r2"].map { (t: String) in QueueItem(url: "https://youtu.be/\(t)", title: t) })
    let merged = provisional.merged(into: context)
    expect(titles(merged) == ["lone", "p1", "p2", "r1", "r2"] && merged.kind == .recommended && merged.current?.title == "lone",
           "additions go between the video and the list that arrived later: \(titles(merged))")
    var early = provisional
    early.step(1, wrap: false)
    let mergedEarly = early.merged(into: context)
    expect(mergedEarly.current?.title == "p1" && titles(mergedEarly) == ["lone", "p1", "p2", "r1", "r2"], "…still playing what it was playing")
    var handing = provisional
    handing.handBack = "com.apple.Music"
    expect(handing.merged(into: context).handBack == "com.apple.Music", "the hand-back app carries over")

    let item = QueueItem(url: "spotify:track:6rqhFgbbKwnb9MLmUQDhG6", title: "S", added: true)
    let back = try! JSONDecoder().decode(QueueItem.self, from: try! JSONEncoder().encode(item))
    expect(back == item && back.source == .spotify && back.added, "queue items round-trip")

    // Where each item plays.
    expect(MediaSource.of("/Users/x/a.MP3") == .audio && MediaSource.of("/Users/x/a.mov") == .file
           && MediaSource.of("file:///x/a%20b.flac") == .audio, "local files: audio or video")
    expect(MediaSource.of("https://cdn.example.com/ep1.mp3?token=1") == .audio && MediaSource.of("https://youtu.be/abc") == .web, "links")
    expect(MediaSource.of("https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6") == .spotify && MediaSource.of("spotify:album:abc") == .spotify, "Spotify")
    expect(MediaSource.of("music:0123456789ABCDEF") == .music && MediaSource.music.isExternal && !MediaSource.audio.isExternal, "Music")

    // Spotify: only songs and episodes, only well-formed ids — they go into an AppleScript.
    expect(SpotifyLink.uri("https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6?si=abc") == "spotify:track:6rqhFgbbKwnb9MLmUQDhG6", "track link")
    expect(SpotifyLink.uri("https://open.spotify.com/intl-de/episode/4rOoJ6Egrf8K2IrywzwOMk") == "spotify:episode:4rOoJ6Egrf8K2IrywzwOMk",
           "episode link with a locale")
    expect(SpotifyLink.uri("spotify:track:6rqhFgbbKwnb9MLmUQDhG6") == "spotify:track:6rqhFgbbKwnb9MLmUQDhG6", "URI")
    expect(SpotifyLink.uri("https://open.spotify.com/album/1DFixLWuPkv3KT3TnV35m3") == nil
           && SpotifyLink.uri("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M") == nil, "albums and playlists aren't single items")
    expect(SpotifyLink.uri("spotify:track:abc\"; do shell script \"x") == nil && SpotifyLink.uri("https://open.spotify.com/track/short") == nil,
           "malformed ids rejected")
    expect(SpotifyLink.webURL("spotify:episode:4rOoJ6Egrf8K2IrywzwOMk") == "https://open.spotify.com/episode/4rOoJ6Egrf8K2IrywzwOMk", "page for a URI")
    expect(Handoff.spotifyPlayScript("https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6")
           == #"tell application id "com.spotify.client" to play track "spotify:track:6rqhFgbbKwnb9MLmUQDhG6""#, "play script")
    expect(Handoff.spotifyPlayScript("spotify:track:x\" & quit") == nil, "nothing unchecked reaches AppleScript")

    // What a music app's next report means while one of its songs is the queue's current item.
    let now = Date()
    func song(_ title: String, app: String = "com.apple.Music", elapsed: Double? = nil, at: Date? = nil, playing: Bool = true) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: "A", album: nil, bundleID: app, isPlaying: playing, duration: 200, elapsed: elapsed, elapsedAt: at, rate: 1)
    }
    func judge(_ ours: NowPlayingInfo, _ report: NowPlayingInfo?, fallback: Double? = nil, frontmost: Bool = false, running: Bool = true) -> Handoff.Event {
        Handoff.judge(song: ours, report: report, app: "com.apple.Music", now: now, fallback: fallback, frontmost: frontmost, running: running)
    }
    let near = song("Ours", elapsed: 198.5, at: now), early1 = song("Ours", elapsed: 60, at: now), theirs = song("Theirs")
    expect(judge(near, theirs, frontmost: true) == .finished, "a new song right at the end: ours finished")
    expect(judge(early1, theirs) == .skipped, "early, with Music in the background: a media-key skip")
    expect(judge(early1, theirs, frontmost: true) == .detached, "early, with Music in front: you picked something — Watch lets go")
    expect(judge(early1, song("Ours", playing: false), frontmost: true) == .none, "pausing the same song is nothing")
    expect(judge(early1, song("Theirs", app: "com.google.Chrome")) == .none, "another app's report is nothing")
    expect(judge(near, nil) == .finished, "stopping at the end: finished")
    expect(judge(early1, nil) == .none && judge(early1, nil, running: false) == .detached, "stopping early is nothing; quitting lets go")
    let unknown = song("Ours")
    expect(judge(unknown, theirs, fallback: 199, frontmost: true) == .finished && judge(unknown, theirs, fallback: 20) == .skipped,
           "without a position, Watch's own reckoning decides")
    expect(judge(song("Ours", elapsed: 190, at: now.addingTimeInterval(-9)), theirs, frontmost: true) == .finished,
           "the reported position runs on with the clock")

    // Spotify links in the field and in Recent Links.
    expect(OmniboxInput.parse("spotify:track:6rqhFgbbKwnb9MLmUQDhG6", fileExists: { _ in false }) == .play("spotify:track:6rqhFgbbKwnb9MLmUQDhG6")
           && OmniboxInput.parse("https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6", fileExists: { _ in false }) == .play("https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6"),
           "Spotify links and URIs play (never a YouTube search)")
    let spotifyTrack = "https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6"
    VideoLinks.spotifyInstalled = false
    expect(VideoLinks.classify(spotifyTrack) == .other, "without Spotify, a copied Spotify link isn't kept")
    VideoLinks.spotifyInstalled = true
    expect(VideoLinks.classify(spotifyTrack) == .video && VideoLinks.classify("https://open.spotify.com/album/1DFixLWuPkv3KT3TnV35m3") == .other,
           "with Spotify, copied songs and episodes are kept; albums aren't")
    VideoLinks.spotifyInstalled = false
    expect(VideoLinks.site(spotifyTrack) == "Spotify", "site label")

    expect(QueueRoute.pick(queueRunning: true, playingApp: "com.apple.Music") == .add, "a running queue takes additions")
    expect(QueueRoute.pick(queueRunning: false, playingApp: "com.spotify.client") == .slotIn("com.spotify.client"), "Spotify playing: slot in")
    expect(QueueRoute.pick(queueRunning: false, playingApp: "com.apple.podcasts") == .start && QueueRoute.pick(queueRunning: false, playingApp: nil) == .start,
           "otherwise a new queue")
}

// 3.24: what macOS's Now Playing shows of Watch's, pausing a music app while Watch plays, and Up Next after a relaunch.
func checkSystemPlayback() {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    func player(_ id: Int, _ playing: Bool, _ seconds: Double) -> OwnPlayback.PlayerState {
        OwnPlayback.PlayerState(id: id, playing: playing, lastPlayed: t0.addingTimeInterval(seconds))
    }
    expect(OwnPlayback.pick(queueItem: false, queuePlaying: false, players: [], musicPlaying: false) == .none, "nothing of Watch's")
    expect(OwnPlayback.pick(queueItem: true, queuePlaying: true, players: [player(1, true, 50)], musicPlaying: true) == .queue,
           "the queue's own item while it plays")
    expect(OwnPlayback.pick(queueItem: true, queuePlaying: false, players: [player(1, false, 10), player(2, true, 5)], musicPlaying: false) == .player(2),
           "a playing video window over a paused queue item")
    expect(OwnPlayback.pick(queueItem: false, queuePlaying: false, players: [player(1, true, 10), player(2, true, 30)], musicPlaying: false) == .player(2),
           "of two playing windows, the one that played last")
    expect(OwnPlayback.pick(queueItem: false, queuePlaying: false, players: [player(1, false, 10), player(2, false, 30)], musicPlaying: false) == .player(2),
           "paused: the last one keeps ⏯")
    expect(OwnPlayback.pick(queueItem: true, queuePlaying: false, players: [player(1, false, 30)], musicPlaying: true) == .none,
           "paused while Music plays: the keys are Music's")
    expect(OwnPlayback.pick(queueItem: true, queuePlaying: false, players: [player(1, false, 30)], musicPlaying: false) == .queue,
           "paused, nothing else: the queue's item keeps ⏯")

    expect(MusicPause.toPause(enabled: true, playingApp: "com.apple.Music", queueUsesApp: false) == "com.apple.Music", "pause Music")
    expect(MusicPause.toPause(enabled: true, playingApp: "com.spotify.client", queueUsesApp: false) == "com.spotify.client", "pause Spotify")
    expect(MusicPause.toPause(enabled: false, playingApp: "com.apple.Music", queueUsesApp: false) == nil, "the preference is off")
    expect(MusicPause.toPause(enabled: true, playingApp: "com.apple.Music", queueUsesApp: true) == nil, "Up Next is handing off with it already")
    expect(MusicPause.toPause(enabled: true, playingApp: "com.apple.Safari", queueUsesApp: false) == nil, "only Music and Spotify")
    expect(MusicPause.toPause(enabled: true, playingApp: nil, queueUsesApp: false) == nil, "nothing playing")
    expect(MusicPause.shouldResume(enabled: true, paused: "com.apple.Music", watchActive: false, appPlaying: false), "resume when Watch is done")
    expect(!MusicPause.shouldResume(enabled: true, paused: "com.apple.Music", watchActive: true, appPlaying: false), "not while Watch still plays")
    expect(!MusicPause.shouldResume(enabled: true, paused: "com.apple.Music", watchActive: false, appPlaying: true), "not if you resumed it yourself")
    expect(!MusicPause.shouldResume(enabled: false, paused: "com.apple.Music", watchActive: false, appPlaying: false), "not with the preference off")
    expect(!MusicPause.shouldResume(enabled: true, paused: nil, watchActive: false, appPlaying: false), "nothing was paused")

    // Snapshots: play order kept, the music app's mirror dropped, the cursor on the same item (or the next of Watch's).
    var q = PlayQueue(kind: .list, name: "Up Next", items: [QueueItem(url: QueueItem.musicPrefix, title: "Music's song", source: .music)])
    q.handBack = "com.apple.Music"
    q.insert([QueueItem(url: "/tmp/a.mp3", title: "a"), QueueItem(url: "https://youtu.be/b", title: "b")], .later)
    guard let s = q.snapshot else { expect(false, "a queue with Watch's items has a snapshot"); return }
    expect(s.items.map(\.title) == ["a", "b"] && s.current == 0 && s.handBack == "com.apple.Music" && s.items.allSatisfy(\.added),
           "the mirror goes; the cursor moves to Watch's first item: \(s)")
    q.step(1, wrap: false); q.step(1, wrap: false)
    expect(q.snapshot?.current == 1 && q.snapshot?.items.map(\.title) == ["a", "b"], "the cursor stays on what plays")
    let data = try? JSONEncoder().encode(s)
    let back = data.flatMap { try? JSONDecoder().decode(QueueSnapshot.self, from: $0) }
    expect(back == s, "a snapshot survives being saved")
    let restored = PlayQueue(snapshot: QueueSnapshot(name: "Up Next", items: s.items, current: 1, handBack: nil))
    expect(restored.current?.title == "b" && restored.sections().history.map(\.title) == ["a"] && restored.handBack == nil, "restored where it was")
    expect(PlayQueue(snapshot: QueueSnapshot(name: "X", items: s.items, current: 9, handBack: nil)).current?.title == "b", "a bad cursor is clamped")
    expect(PlayQueue(kind: .list, name: "Up Next", items: [QueueItem(url: "spotify:", source: .spotify)]).snapshot == nil, "only a mirror: nothing to keep")
    var shuffled = PlayQueue(kind: .list, name: "S", items: (1...6).map { QueueItem(url: "https://youtu.be/\($0)", title: "\($0)") }, shuffled: true)
    shuffled.step(1, wrap: false)
    let order = shuffled.order.map { shuffled.items[$0].title }
    expect(shuffled.snapshot?.items.map(\.title) == order && shuffled.snapshot?.current == 1, "a shuffled list is kept in the order it plays")
}
