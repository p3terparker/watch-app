import AppKit
import AVFoundation

// The universal queue under the music window (3.21): one app-wide Up Next mixing YouTube and other sites, local and
// direct audio, podcast episodes (3.22) and Spotify songs, and where its current item plays —
//   · Music/Spotify themselves (`.external`): the music window follows the app as always. Watch can't see or edit their
//     own queues, so it waits for the song to end (Handoff.judge), pauses the app — which has already moved on to its
//     own next song — and rewinds it, then plays the next item. When the list runs out it hands back (`handBack`).
//   · Watch's own audio player (`.native`), shown in the music window through the NowPlayingInfo it already renders;
//     podcast episodes resume where they were left and get their ✓ like videos (PlaybackPositions, WatchedVideos).
//   · a video window beside the music window (`.video`), run queue-driven: its end and its Next/Previous come here.
// Items you add go in with Play Next / Play Later (PlayQueue). Nothing is ever sent to Music/Spotify without a user's
// action behind it: adding to the queue, a click, or the queue moving on from one of their songs.
final class UniversalQueue: NSObject {
    static let ownID = Bundle.main.bundleIdentifier ?? "com.jacob.watch"
    static let musicID = "com.apple.Music"
    enum Engine: Equatable { case idle, external(String), native, video }

    private(set) var queue: PlayQueue? { didSet { if let s = queue?.snapshot { keep(s) } } }
    private(set) var engine: Engine = .idle
    // The last Up Next, kept across closing the music window and relaunching (3.24; UserDefaults `upNextQueue`) until it's
    // played to its end or replaced: the list offers to resume it.
    private(set) var saved: QueueSnapshot? = UniversalQueue.loadSaved()
    static let savedKey = "upNextQueue"
    private(set) var held = false                      // a music app took over: the queue waits for Resume
    private(set) var volume: Double = Prefs.playerVolume
    var isRunning: Bool { queue != nil }
    var showsOwnItem: Bool { engine == .native || engine == .video }   // the music window shows Watch's item, not the app's
    var ownInfo: NowPlayingInfo? { engine == .native ? nativeInfo : engine == .video ? videoInfo : nil }

    // Wiring (AppDelegate).
    var onChange: (() -> Void)?                        // the drop-down list, the music window
    var show: ((NowPlayingInfo?) -> Void)?             // Watch's own item into the music window; nil = back to the music app
    var openVideo: ((String, String?) -> PlayerWindowController?)?   // (link, title) → a video window beside the music window
    var showList: (() -> Void)?                        // the music window's Up Next list (a queue-driven video window's ⌥⌘U)
    var control = MusicAppControl()                    // Music/Spotify commands and Spotify's play-by-URI
    var frontmostApp: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    var appIsRunning: (String) -> Bool = { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    var resolveEpisode: (String, @escaping (PodcastEpisode?) -> Void) -> Void = { PodcastDirectory.episode($0, completion: $1) }

    private var token = 0                              // every start bumps it; late callbacks from a replaced item are dropped
    // Native audio.
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var nativeInfo: NowPlayingInfo?
    private var positionKey: String?                   // a podcast episode's resume key, once it's at its start position
    private var lastSave = Date.distantPast
    // Video.
    private weak var video: PlayerWindowController?
    private var videoTimer: Timer?
    private var videoInfo: NowPlayingInfo?
    // External: the song Watch follows in the app, and since when (Watch's own reckoning when the app gives no position).
    private var followed: NowPlayingInfo?
    private var followedSince: Date?
    private var awaiting: (title: String?, since: Date)?   // started a song there; its first report starts the following

    // MARK: adding and moving

    // Play Next / Play Later, routed by QueueRoute.pick (AppDelegate asks for Automation before a slot-in). `current` is the
    // music app's song when slotting in.
    func add(_ items: [QueueItem], _ placement: PlayQueue.Placement, route: QueueRoute, current: NowPlayingInfo?) {
        guard !items.isEmpty else { return }
        switch route {
        case .add:
            queue?.insert(items, placement)
            onChange?()
        case .slotIn(let app):
            var q = PlayQueue(kind: .list, name: "Up Next", items: [mirror(current, app: app)])
            q.handBack = app
            q.insert(items, .later)
            leave(for: nil)
            queue = q; held = false
            engine = .external(app)
            followed = current?.appBundleID == app ? current : nil
            followedSince = Date(); awaiting = nil
            if followed == nil { awaiting = (title: nil, since: Date()) }
            onChange?()
        case .start:
            var q = PlayQueue(kind: .list, name: "Up Next", items: [])
            q.insert(items, .later)
            q.handBack = q.current.flatMap { Self.app(for: $0) }   // begun with a song in Music/Spotify: it carries on after
            queue = q; held = false
            if let first = queue?.current { start(first) }
        }
    }
    // Right after what's playing, and play it now (a Spotify link, the list's Play Now).
    func playNow(_ items: [QueueItem]) {
        guard !items.isEmpty else { return }
        guard queue != nil else { add(items, .later, route: .start, current: nil); return }
        queue?.insert(items, .next)
        if let item = queue?.step(1, wrap: false) { start(item) }
    }
    func jump(to id: UUID) {
        guard let item = queue?.jump(to: id) else { return }
        start(item)
    }
    func remove(_ ids: Set<UUID>) { queue?.remove(ids: ids); onChange?() }
    func move(_ ids: [UUID], to position: Int) { queue?.move(ids: ids, to: position); onChange?() }
    func insert(_ items: [QueueItem], at position: Int) {
        guard queue != nil else { add(items, .later, route: .start, current: nil); return }
        queue?.insert(items, .at(position)); onChange?()
    }
    func clearAdded() { queue?.clearAdded(); onChange?() }
    func resume() { held = false; advance() }
    func update(_ id: UUID, title: String?, artwork: String?) {
        queue?.update(id) { item in
            if let t = title, !t.isEmpty { item.title = t }
            if let a = artwork { item.artwork = a }
        }
        onChange?()
    }

    // MARK: saved Up Next (3.24)

    private static func loadSaved() -> QueueSnapshot? {
        UserDefaults.standard.data(forKey: savedKey).flatMap { try? JSONDecoder().decode(QueueSnapshot.self, from: $0) }
    }
    private func keep(_ s: QueueSnapshot?) {
        saved = s
        if let s = s, let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.savedKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.savedKey) }
    }
    // The list's Resume for a saved Up Next: it plays again from the item it was on.
    func resumeSaved() {
        guard queue == nil, let s = saved else { return }
        queue = PlayQueue(snapshot: s)
        held = false
        if let item = queue?.current { start(item) }
    }
    // Watch is quitting: an episode remembers where it was.
    func quitting() { savePosition() }

    // MARK: stepping

    func advance() {
        if let next = queue?.step(1, wrap: false) { start(next) } else { finish() }
    }
    func previous() {
        guard let item = queue?.step(-1, wrap: false) else { NSSound.beep(); return }
        start(item)
    }
    private func start(_ item: QueueItem) {
        token += 1
        held = false
        leave(for: item)
        switch item.source {
        case .audio:          playNative(item)
        case .podcast:        playPodcast(item)
        case .spotify, .music: playExternal(item)
        case .web, .file:     playVideo(item)
        }
        onChange?()
    }
    // Stop whatever plays now, unless the next item plays in the same place (a video window is reused; the same app keeps
    // its own playback going).
    private func leave(for next: QueueItem?) {
        stopNative()
        videoTimer?.invalidate(); videoTimer = nil
        let nextIsVideo = next.map { $0.source == .web || $0.source == .file } ?? false
        if !nextIsVideo { closeVideo() }
        if case .external(let app) = engine, next.flatMap({ Self.app(for: $0) }) != app {
            control.perform(.command(.pause), bundleID: app) { _ in }
        }
        followed = nil; awaiting = nil
        engine = .idle
    }
    // The list ran out: hand back to the app whose own queue it slotted into.
    private func finish() {
        let back = queue?.handBack
        leave(for: nil)
        queue = nil; held = false
        keep(nil)                                          // played to its end: nothing to resume
        show?(nil)
        if let app = back, appIsRunning(app) { control.perform(.command(.play), bundleID: app) { _ in } }
        onChange?()
    }
    // The music window closed: the queue ends. A queued video keeps playing as an ordinary player; Music/Spotify resume
    // only if Watch had paused them and nothing of Watch's is still playing.
    func musicWindowClosed() {
        guard queue != nil else { return }
        let back = queue?.handBack
        let resume = engine == .native || engine == .idle
        stopNative()
        videoTimer?.invalidate(); videoTimer = nil
        detachVideo()
        queue = nil; engine = .idle; held = false; followed = nil; awaiting = nil
        if resume, let app = back, appIsRunning(app) { control.perform(.command(.play), bundleID: app) { _ in } }
        onChange?()
    }

    // MARK: Music / Spotify

    static func app(for item: QueueItem) -> String? {
        switch item.source {
        case .spotify: return SpotifyLink.bundleID
        case .music:   return musicID
        default:       return nil
        }
    }
    // "What the app is playing", the queue's first item when it slots in.
    private func mirror(_ info: NowPlayingInfo?, app: String) -> QueueItem {
        let url = app == SpotifyLink.bundleID ? "spotify:" : QueueItem.musicPrefix
        return QueueItem(url: url, title: info?.title ?? ArtworkActions.appName(app), subtitle: info?.artist, duration: info?.duration,
                         source: app == SpotifyLink.bundleID ? .spotify : .music)
    }
    private func playExternal(_ item: QueueItem) {
        guard let app = Self.app(for: item) else { advance(); return }
        engine = .external(app)
        show?(nil)                                           // the music window follows the app again
        // A Spotify song or a Music library song is started by its script; the mirror of "what the app was playing" just resumes.
        let script = Handoff.spotifyPlayScript(item.url) ?? MusicLibrary.persistentID(item.url).flatMap(MusicLibrary.playScript)
        awaiting = (title: script != nil ? item.title : nil, since: Date())
        let mine = token
        let done: (Bool) -> Void = { [weak self] ok in
            guard let self = self, self.token == mine, !ok else { return }
            NSSound.beep(); self.advance()                     // couldn't play it there: go on
        }
        if let script = script { control.playScript(script, app: app, completion: done) }
        else { control.perform(.command(.play), bundleID: app, completion: done) }   // the song it was on: carry on
    }
    // Every report from the music apps (adapter and broadcasts), while the queue's current item plays in one of them.
    func externalChanged(_ info: NowPlayingInfo?) {
        guard case .external(let app) = engine, !held else { return }
        if let wait = awaiting {
            guard let i = info, i.appBundleID == app else { return }
            // Spotify may still report the song it was on: wait for ours (by title, when known) or a few seconds.
            if let title = wait.title, i.title.caseInsensitiveCompare(title) != .orderedSame, Date().timeIntervalSince(wait.since) < 4 { return }
            awaiting = nil
            follow(i)
            return
        }
        guard let song = followed else { if let i = info, i.appBundleID == app { follow(i) }; return }
        let fallback = followedSince.map { Date().timeIntervalSince($0) }
        switch Handoff.judge(song: song, report: info, app: app, now: Date(), fallback: fallback,
                             frontmost: frontmostApp() == app, running: appIsRunning(app)) {
        case .none:
            if let i = info, i.appBundleID == app, i.itemKey == song.itemKey { followed = i }
        case .finished, .skipped:
            // The app has moved on to its own next song: hold that one for the hand-back, from its start.
            control.perform(.command(.pause), bundleID: app) { _ in }
            control.perform(.seek(0), bundleID: app) { _ in }
            followed = nil
            engine = .idle                                   // already paused: leaving it needs nothing more
            advance()
        case .detached:
            held = true; followed = nil; engine = .idle
            onChange?()
        }
    }
    private func follow(_ info: NowPlayingInfo) {
        followed = info; followedSince = Date()
        if let id = queue?.current?.id {
            queue?.update(id) { item in
                item.title = info.title; item.subtitle = info.artist
                if let d = info.duration { item.duration = d }
            }
        }
        onChange?()
    }

    // MARK: Watch's own audio

    // A podcast episode. An Apple Podcasts link is looked up first (its audio, title and picture; the item keeps the link
    // as its page); the music window says so meanwhile.
    private func playPodcast(_ item: QueueItem) {
        guard PodcastLinks.isEpisode(item.url) else { playNative(item); return }
        engine = .native
        nativeInfo = NowPlayingInfo(title: item.title ?? "Loading episode…", artist: item.subtitle, album: nil, bundleID: Self.ownID, isPlaying: false)
        show?(nativeInfo)
        let mine = token
        resolveEpisode(item.url) { [weak self] episode in
            guard let self = self, self.token == mine else { return }
            guard let found = episode else { NSSound.beep(); self.advance(); return }
            var resolved = found.queueItem()
            resolved.added = item.added
            if resolved.page == nil { resolved.page = item.url }
            self.queue?.update(item.id) { $0 = resolved }
            resolved.id = item.id
            self.playNative(resolved)
            self.onChange?()
        }
    }
    private func playNative(_ item: QueueItem) {
        let url: URL? = item.url.hasPrefix("/") ? URL(fileURLWithPath: item.url) : URL(string: item.url)
        guard let u = url else { advance(); return }
        let asset = AVURLAsset(url: u)
        let p = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        p.volume = Float(volume)
        player = p
        engine = .native
        let mine = token
        nativeInfo = NowPlayingInfo(title: item.title ?? u.deletingPathExtension().lastPathComponent, artist: item.subtitle, album: nil,
                                    bundleID: Self.ownID, isPlaying: true, artwork: Self.folderArtwork(u), artworkMIME: nil,
                                    duration: item.duration, elapsed: 0, elapsedAt: Date(), rate: 1)
        show?(nativeInfo)
        if item.source == .podcast, let art = item.artwork { loadArtwork(art, token: mine) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
            guard let self = self, self.token == mine else { return }
            if let key = self.positionKey {                  // an episode heard to the end: ✓, and next time from the top
                self.positionKey = nil
                PlaybackPositions.shared.clear(key)
                if !WatchedVideos.shared.isWatched(key) { WatchedVideos.shared.mark(key); Self.libraryChanged() }
            }
            self.advance()
        }
        // An episode resumes where it was left (within ±0.5 s, as videos do), once the item can seek.
        if item.source == .podcast, let current = p.currentItem {
            let key = item.resumeKey, start = PlaybackPositions.shared.position(for: key) ?? 0
            statusObservation = current.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
                DispatchQueue.main.async {
                    guard let self = self, self.token == mine, observed.status == .readyToPlay, self.statusObservation != nil else { return }
                    self.statusObservation = nil
                    guard start > 0 else { self.positionKey = key; return }
                    let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
                    p.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
                        DispatchQueue.main.async {
                            guard let self = self, self.token == mine else { return }
                            self.positionKey = key
                            self.refreshNative()
                        }
                    }
                }
            }
        }
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] _ in
            guard let self = self, self.token == mine else { return }
            self.refreshNative()
        }
        asset.loadValuesAsynchronously(forKeys: ["commonMetadata"]) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.token == mine else { return }
                self.applyMetadata(asset, to: item.id)
            }
        }
        p.play()
    }
    private func refreshNative() {
        guard let p = player, var info = nativeInfo else { return }
        let t = p.currentTime().seconds
        info.isPlaying = p.timeControlStatus != .paused
        info.elapsed = t.isFinite ? t : 0
        info.elapsedAt = Date()
        if let d = p.currentItem?.duration, d.isNumeric, d.seconds > 0 { info.duration = d.seconds }
        nativeInfo = info
        show?(info)
        if info.isPlaying, Date().timeIntervalSince(lastSave) >= 5 { savePosition() }
    }
    // Where an episode is (every 5 s while playing, when paused, and when it stops); its ✓ at 90% or the last 15 s.
    private func savePosition() {
        guard let key = positionKey, let p = player else { return }
        let t = p.currentTime().seconds, d = p.currentItem?.duration
        let duration = d.flatMap { $0.isNumeric && $0.seconds > 0 ? $0.seconds : nil } ?? nativeInfo?.duration
        PlaybackPositions.shared.save(t, duration: duration, for: key)
        if WatchedVideos.shared.noteProgress(t, duration: duration, for: key) { Self.libraryChanged() }
        lastSave = Date()
    }
    private static func libraryChanged() { NotificationCenter.default.post(name: .watchLibraryChanged, object: nil) }
    // An episode's picture (the file's own tags, read below, win when there are any).
    private func loadArtwork(_ link: String, token mine: Int) {
        guard let url = URL(string: link) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, !data.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self = self, self.token == mine, self.engine == .native, var info = self.nativeInfo, info.artwork == nil else { return }
                info.artwork = data
                self.nativeInfo = info
                self.show?(info)
            }
        }.resume()
    }
    // Title, artist, album and artwork from the file's own tags.
    private func applyMetadata(_ asset: AVAsset, to id: UUID) {
        let tags = asset.commonMetadata
        func text(_ key: AVMetadataKey) -> String? {
            AVMetadataItem.metadataItems(from: tags, withKey: key, keySpace: .common).first?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard var info = nativeInfo else { return }
        if let t = text(.commonKeyTitle) { info.title = t }
        info.artist = text(.commonKeyArtist) ?? info.artist
        info.album = text(.commonKeyAlbumName) ?? info.album
        if let art = AVMetadataItem.metadataItems(from: tags, withKey: AVMetadataKey.commonKeyArtwork, keySpace: .common).first?.dataValue {
            info.artwork = art
        }
        nativeInfo = info
        queue?.update(id) { $0.title = info.title; $0.subtitle = info.artist }
        show?(info)
        onChange?()
    }
    // A folder's cover picture, for files without their own.
    static func folderArtwork(_ url: URL) -> Data? {
        guard url.isFileURL else { return nil }
        let dir = url.deletingLastPathComponent()
        for name in ["cover.jpg", "Cover.jpg", "folder.jpg", "Folder.jpg", "front.jpg", "cover.png", "AlbumArt.jpg"] {
            if let data = try? Data(contentsOf: dir.appendingPathComponent(name)), !data.isEmpty { return data }
        }
        return nil
    }
    private func stopNative() {
        savePosition(); positionKey = nil; statusObservation = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
        if let t = timeObserver { player?.removeTimeObserver(t); timeObserver = nil }
        player?.pause(); player = nil; nativeInfo = nil
    }

    // MARK: videos

    private func playVideo(_ item: QueueItem) {
        engine = .video
        let mine = token
        let pc: PlayerWindowController
        if let existing = video { pc = existing; pc.load(item.url) }
        else {
            guard let opened = openVideo?(item.url, item.title) else { advance(); return }
            pc = opened
        }
        video = pc
        pc.onEnded = { [weak self] in
            guard let self = self, self.token == mine else { return }
            self.advance()
        }
        pc.onStep = { [weak self] delta in if delta > 0 { self?.advance() } else { self?.previous() } }
        pc.onShowList = { [weak self] in self?.showList?() }
        pc.onClosed = { [weak self] in
            guard let self = self, self.token == mine else { return }
            self.videoClosed()
        }
        videoInfo = NowPlayingInfo(title: item.title ?? VideoLinks.site(item.url), artist: VideoLinks.site(item.url), album: nil,
                                   bundleID: Self.ownID, isPlaying: true, duration: item.duration, elapsed: 0, elapsedAt: Date(), rate: 1)
        show?(videoInfo)
        loadThumbnail(item.artwork ?? VideoLinks.thumbnail(item.url), token: mine)
        videoTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshVideo() }
    }
    private func refreshVideo() {
        guard let pc = video, var info = videoInfo else { return }
        if let t = pc.mediaTitle, !t.isEmpty { info.title = t }
        info.isPlaying = pc.isPlaying
        info.elapsed = pc.playbackTime.isFinite ? pc.playbackTime : 0
        info.elapsedAt = Date()
        info.duration = pc.playbackDuration ?? info.duration
        videoInfo = info
        show?(info)
    }
    private func loadThumbnail(_ link: String?, token mine: Int) {
        guard let s = link, let url = URL(string: s) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, !data.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self = self, self.token == mine, self.engine == .video, var info = self.videoInfo else { return }
                info.artwork = data
                self.videoInfo = info
                self.show?(info)
            }
        }.resume()
    }
    // You closed the queue's video window: the queue waits (Resume plays on from the next item).
    private func videoClosed() {
        video = nil
        videoTimer?.invalidate(); videoTimer = nil
        engine = .idle; held = true
        onChange?()
    }
    private func closeVideo() {
        guard let pc = video else { return }
        detachVideo()
        pc.window.close()
    }
    private func detachVideo() {
        video?.onEnded = nil; video?.onStep = nil; video?.onClosed = nil; video?.onShowList = nil
        video = nil
    }

    // MARK: the music window's controls, for Watch's own item

    func command(_ request: NowPlayingRequest) {
        switch request {
        case .command(.next):     advance(); return
        case .command(.previous): previous(); return
        case .command(.play):     player?.play(); video?.setPaused(false)
        case .command(.pause):    player?.pause(); video?.setPaused(true); savePosition()
        case .seek(let t):
            player?.seek(to: CMTime(seconds: max(0, t), preferredTimescale: 600),
                         toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600))
            video?.seek(toSeconds: t)
        }
        if engine == .native { refreshNative() } else if engine == .video { refreshVideo() }
    }
    func setVolume(_ level: Double) {
        volume = min(1, max(0, level))
        player?.volume = Float(volume)
        video?.setPlaybackVolume(volume)
    }
    // Double-click: the item in its own place — a file in Finder, a page in the browser (where you are in it), Spotify.
    func openSource() {
        guard let item = queue?.current else { return }
        if item.source == .podcast {
            if let page = item.page.flatMap(URL.init(string:)) { NSWorkspace.shared.open(page) } else { NSSound.beep() }
        } else if item.url.hasPrefix("/") || item.url.hasPrefix("file://") {
            let path = item.url.hasPrefix("file://") ? (URL(string: item.url)?.path ?? item.url) : item.url
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else if let uri = SpotifyLink.uri(item.url), let u = URL(string: uri) {
            NSWorkspace.shared.open(u)
        } else {
            let at = engine == .native ? player?.currentTime().seconds : engine == .video ? video?.playbackTime : nil
            if let page = VideoLinks.webURL(item.url, resumeAt: at) { NSWorkspace.shared.open(page) }
        }
    }
}

// The music window's volume, commands and double-click for Watch's own items, in place of an app's (MusicAppControl):
// AppDelegate hands the window this while the queue shows one of Watch's own items. No shuffle/repeat (those are the
// apps' own) and no Apple Events.
final class OwnPlaybackControl: MusicAppControl {
    weak var queue: UniversalQueue?
    override func check(_ bundleID: String, completion: @escaping (AppVolumeAccess, Double?) -> Void) { completion(.granted, queue?.volume) }
    override func requestAccess(_ bundleID: String, completion: @escaping (AppVolumeAccess) -> Void) { completion(.granted) }
    override func set(_ bundleID: String, _ level: Double) { queue?.setVolume(level) }
    override func perform(_ request: NowPlayingRequest, bundleID: String, completion: @escaping (Bool) -> Void) {
        queue?.command(request); completion(true)
    }
    override func modes(_ bundleID: String, completion: @escaping (AppModes?) -> Void) { completion(nil) }
    override func setMode(_ script: String?, bundleID: String, completion: @escaping (Bool) -> Void) { completion(false) }
    override func reveal(_ bundleID: String) { queue?.openSource() }
    override func artwork(_ bundleID: String, completion: @escaping (Data?) -> Void) { completion(nil) }
}

// A Spotify link's title and picture from Spotify's public oEmbed endpoint (no account), for its row and queue entry.
enum SpotifyOEmbed {
    static func info(_ link: String, completion: @escaping (LinkInfo?) -> Void) {
        var c = URLComponents(string: "https://open.spotify.com/oembed")
        c?.queryItems = [URLQueryItem(name: "url", value: SpotifyLink.webURL(link))]
        guard let url = c?.url else { completion(nil); return }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 15)) { data, _, _ in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let info = j.map { LinkInfo(title: $0["title"] as? String, thumbnail: $0["thumbnail_url"] as? String) }
            DispatchQueue.main.async { completion(info?.title == nil ? nil : info) }
        }.resume()
    }
}
