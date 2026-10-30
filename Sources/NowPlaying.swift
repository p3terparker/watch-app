import Foundation

// What another app is playing (Music, Spotify, a browser video…), from macOS's Now Playing info. Since macOS 15.4
// only Apple-signed processes may read it, so the bundled mediaremote-adapter runs inside /usr/bin/perl (see
// GOTCHAS). Watch reads with the adapter's `stream` command; it sends `send`/`seek` (NowPlayingRemote) only when you
// click the artwork window's controls, and never runs `test`, which registers a fake player.
struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String?
    var album: String?
    var bundleID: String
    var parentBundleID: String?
    var isPlaying: Bool
    var artwork: Data?
    var artworkMIME: String?
    // Timing (`stream --micros`): the position `elapsed` was reported at `elapsedAt`, moving at `rate` while playing.
    var duration: Double?
    var elapsed: Double?
    var elapsedAt: Date?
    var rate: Double?
    var mediaType: String?                          // what the app says it plays, when it says (e.g. "…Music")

    // Where playback is at `now`: the reported position plus the time since, at the playback rate (1 when an app
    // reports none while playing), never past the end. nil when the app reports no position.
    func position(at now: Date) -> Double? {
        guard let start = elapsed else { return nil }
        var p = start
        if isPlaying, let at = elapsedAt { p += max(0, now.timeIntervalSince(at)) * (rate.flatMap { $0 > 0 ? $0 : nil } ?? 1) }
        if let d = duration, d > 0 { p = min(p, d) }
        return max(0, p)
    }
    // "1:12", "1:02:03"; `remaining` prefixes a minus ("-2:51").
    static func clock(_ seconds: Double, remaining: Bool = false) -> String {
        let t = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down)), h = t / 3600, m = (t % 3600) / 60, s = t % 60
        let text = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        return remaining ? "-" + text : text
    }

    // The music window follows music only: a known music/audio app, or any other app that says it's playing audio.
    // Never a browser, a WebKit process (web pages, Watch's own web views) or Watch itself (`own`) — videos keep their
    // own windows, so a YouTube video never replaces the song.
    static let musicApps: Set<String> = [
        "com.apple.Music", "com.apple.iTunes", "com.spotify.client", "com.apple.podcasts", "com.tidal.desktop", "com.deezer.deezer-desktop",
        "com.amazon.music", "com.pandora.desktop", "tv.plex.plexamp", "com.cider.app", "sh.cider.electron", "com.swinsian.Swinsian",
        "com.coppertino.Vox", "app.doppler.Doppler", "com.audirvana.Audirvana-Studio", "com.audirvana.Audirvana-Origin"]
    static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.canary", "org.chromium.Chromium",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "org.mozilla.firefox", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "com.kagi.kagimacOS"]
    func isMusicSource(ignoring own: Set<String>) -> Bool {
        let ids = [bundleID, parentBundleID].compactMap { $0 }
        if ids.contains(where: { own.contains($0) || Self.browsers.contains($0) || $0.hasPrefix("com.apple.WebKit") }) { return false }
        if Self.musicApps.contains(appBundleID) { return true }
        let type = mediaType?.lowercased() ?? ""
        return type.contains("music") || type.contains("audio")
    }

    // A browser's media is reported by its web-content process; the parent is the app to name and bring forward.
    var appBundleID: String { parentBundleID ?? bundleID }
    // The same track whatever its play state or artwork — the artwork window cross-fades only when this changes.
    var itemKey: String { [appBundleID, title, artist ?? "", album ?? ""].joined(separator: "\u{1F}") }
    var youtubeQuery: String { ([title] + [artist].compactMap { $0 }).joined(separator: " ") }

    // From the adapter's MIME type, else the file's signature; nil when neither is known (save re-encodes as PNG).
    var artworkExtension: String? {
        switch artworkMIME?.lowercased() {
        case "image/jpeg"?, "image/jpg"?: return "jpg"
        case "image/png"?: return "png"
        case "image/gif"?: return "gif"
        case "image/heic"?, "image/heif"?: return "heic"
        case "image/webp"?: return "webp"
        case "image/tiff"?: return "tiff"
        default: return artwork.flatMap(Self.sniffExtension)
        }
    }
    static func sniffExtension(_ data: Data) -> String? {
        let b = Array(data.prefix(12))
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if b.starts(with: Array("GIF8".utf8)) { return "gif" }
        if b.count == 12, b.starts(with: Array("RIFF".utf8)), Array(b[8..<12]) == Array("WEBP".utf8) { return "webp" }
        if b.count == 12, Array(b[4..<8]) == Array("ftyp".utf8) { return "heic" }
        if b.starts(with: [0x49, 0x49, 0x2A, 0x00]) || b.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        return nil
    }

    // "Artist – Album.jpg" (or "Artist – Title" for a single without an album), safe as a file name.
    func suggestedFileName(extension ext: String) -> String {
        let parts = [artist, album ?? title].compactMap { $0 }.filter { !$0.isEmpty }
        return Self.safeFileName(parts.joined(separator: " – ")) + "." + ext
    }
    static func safeFileName(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) { out.append(" ") }
            else if scalar == "/" || scalar == ":" || scalar == "\\" { out.append("-") }
            else { out.unicodeScalars.append(scalar) }
        }
        let trim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))   // a leading dot hides the file
        out = String(out.trimmingCharacters(in: trim).prefix(120)).trimmingCharacters(in: trim)
        return out.isEmpty ? "Artwork" : out
    }
}

enum NowPlayingUpdate: Equatable {
    case nothing                 // nothing playing (or only Watch itself)
    case info(NowPlayingInfo)
    case invalid                 // not a full-state line; ignored
}

extension NowPlayingInfo {
    // One `stream --no-diff` line: {"type":"data","diff":false,"payload":{…}}. An empty payload means nothing is
    // playing. Media from `ignoring` (Watch's own bundle id) counts as nothing.
    static func parse(line: Data, ignoring: Set<String>) -> NowPlayingUpdate {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              object["type"] as? String == "data", object["diff"] as? Bool != true else { return .invalid }
        guard let payload = object["payload"] as? [String: Any] else { return .nothing }
        func text(_ key: String) -> String? {
            guard let s = payload[key] as? String else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        guard let title = text("title"), let bundle = text("bundleIdentifier") else { return .nothing }
        let parent = text("parentApplicationBundleIdentifier")
        if ignoring.contains(bundle) || parent.map({ ignoring.contains($0) }) == true { return .nothing }
        func number(_ key: String) -> Double? {
            switch payload[key] {
            case let d as Double: return d.isFinite ? d : nil
            case let i as Int: return Double(i)
            case let n as NSNumber: return n.doubleValue
            default: return nil
            }
        }
        let artwork = (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        return .info(NowPlayingInfo(title: title, artist: text("artist"), album: text("album"), bundleID: bundle,
                                    parentBundleID: parent, isPlaying: payload["playing"] as? Bool ?? false,
                                    artwork: artwork, artworkMIME: artwork == nil ? nil : text("artworkMimeType"),
                                    duration: number("durationMicros").map { $0 / 1_000_000 }.flatMap { $0 > 0 ? $0 : nil },
                                    elapsed: number("elapsedTimeMicros").map { $0 / 1_000_000 },
                                    elapsedAt: number("timestampEpochMicros").map { Date(timeIntervalSince1970: $0 / 1_000_000) },
                                    rate: number("playbackRate"), mediaType: text("mediaType")))
    }
}

// Music's and Spotify's own track-change broadcasts (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`,
// no permission needed): they keep the music window right while something else — a video — holds macOS's single
// "now playing" slot. They carry title, artist, album, state and length (Spotify also its position), never artwork.
extension NowPlayingInfo {
    static let broadcasts: [String: String] = ["com.apple.Music.playerInfo": "com.apple.Music",
                                                "com.spotify.client.PlaybackStateChanged": "com.spotify.client"]
    // nil for "Stopped" or a broadcast without a track name.
    static func broadcast(_ userInfo: [AnyHashable: Any], app: String, at now: Date = Date()) -> NowPlayingInfo? {
        func text(_ key: String) -> String? {
            guard let s = userInfo[key] as? String else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        func number(_ key: String) -> Double? {
            switch userInfo[key] { case let d as Double: return d; case let i as Int: return Double(i); case let n as NSNumber: return n.doubleValue; default: return nil }
        }
        let state = text("Player State") ?? ""
        guard state != "Stopped", let title = text("Name") else { return nil }
        let length = number("Total Time") ?? number("Duration")                  // milliseconds
        let position = number("Playback Position")                                // seconds (Spotify)
        return NowPlayingInfo(title: title, artist: text("Artist"), album: text("Album"), bundleID: app, isPlaying: state == "Playing",
                              duration: length.map { $0 / 1000 }.flatMap { $0 > 0 ? $0 : nil },
                              elapsed: position, elapsedAt: position == nil ? nil : now)
    }
    // A broadcast about the track already showing only updates its state (keeping the artwork and timing the richer
    // Now Playing report gave); a different track replaces it.
    static func merge(_ b: NowPlayingInfo, onto current: NowPlayingInfo?, at now: Date = Date()) -> NowPlayingInfo {
        guard var m = current, m.itemKey == b.itemKey else { return b }
        if b.elapsed != nil { m.elapsed = b.elapsed; m.elapsedAt = b.elapsedAt }
        else if m.isPlaying != b.isPlaying { m.elapsed = m.position(at: now); m.elapsedAt = now }   // the clock stops or starts here
        m.isPlaying = b.isPlaying
        if let d = b.duration { m.duration = d }
        return m
    }
}

// Pipe reads arrive in arbitrary chunks; one line with artwork is several hundred KB and spans many of them.
struct LineBuffer {
    static let limit = 32 << 20               // a runaway line is dropped rather than held forever
    private var pending = Data()
    mutating func append(_ chunk: Data) -> [Data] {
        var lines: [Data] = []
        var rest = chunk[...]
        while let newline = rest.firstIndex(of: 0x0A) {
            pending.append(rest[rest.startIndex..<newline])
            if !pending.isEmpty { lines.append(pending) }
            pending = Data()
            rest = rest[rest.index(after: newline)...]
        }
        pending.append(rest)
        if pending.count > Self.limit { pending = Data() }
        return lines
    }
}

// Where the build puts the adapter (scripts/watch_helpers.py): the framework in Contents/Frameworks, the perl
// entry script in Contents/Resources/NowPlaying. Optional — without it the feature is simply off.
struct NowPlayingAdapter {
    static let bundled = NowPlayingAdapter(contents: Bundle.main.bundleURL.appendingPathComponent("Contents"))
    static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    let script: URL
    let framework: URL
    init(contents: URL) {
        script = contents.appendingPathComponent("Resources/NowPlaying/mediaremote-adapter.pl")
        framework = contents.appendingPathComponent("Frameworks/MediaRemoteAdapter.framework")
    }
    var isAvailable: Bool {
        let fm = FileManager.default
        return fm.isReadableFile(atPath: script.path) && fm.fileExists(atPath: framework.appendingPathComponent("MediaRemoteAdapter").path)
            && fm.isExecutableFile(atPath: Self.perl.path)
    }
    // Full state on every line (no diff merging), times in microseconds; updates only come on track changes,
    // play/pause and seeks.
    var arguments: [String] { [script.path, framework.path, "stream", "--no-diff", "--debounce=150", "--micros"] }
    // One playback command or seek, from the artwork window's controls.
    func arguments(for request: NowPlayingRequest) -> [String] {
        switch request {
        case .command(let c): return [script.path, framework.path, "send", String(c.rawValue)]
        case .seek(let seconds): return [script.path, framework.path, "seek", String(Int64((max(0, seconds) * 1_000_000).rounded()))]
        }
    }
    // Nothing from the user's shell may reach perl or the adapter: no PERL5OPT/PERL5LIB, no DYLD_*, no adapter options.
    static func environment(_ inherited: [String: String]) -> [String: String] {
        var env = inherited.filter { key, _ in
            !(key.hasPrefix("PERL") || key.hasPrefix("DYLD_") || key.hasPrefix("MEDIAREMOTEADAPTER_") || key == "ADAPTER_TEST_MODE")
        }
        env["PATH"] = "/usr/bin:/bin"
        return env
    }
    func process(_ request: NowPlayingRequest? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) -> Process? {
        guard isAvailable else { return nil }
        let p = Process()
        p.executableURL = Self.perl
        p.arguments = request.map(arguments(for:)) ?? arguments
        p.environment = Self.environment(environment)
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice   // every stderr line is a non-fatal adapter message
        return p
    }
}

// The artwork window's controls. IDs are the adapter's (kMRAPlay = 0, kMRAPause = 1, kMRANextTrack = 4,
// kMRAPreviousTrack = 5); seeks are in seconds.
enum NowPlayingCommand: Int { case play = 0, pause = 1, next = 4, previous = 5 }
enum NowPlayingRequest: Equatable { case command(NowPlayingCommand), seek(Double) }

// Sends a request to whatever is playing — only ever from a click on the artwork window's controls. Each is one short
// adapter run with the same clean environment as the stream; one that hasn't finished after `timeout` is stopped.
final class NowPlayingRemote {
    private let timeout: TimeInterval
    private let launch: (NowPlayingRequest) -> Process?
    init(timeout: TimeInterval = 5, launch: @escaping (NowPlayingRequest) -> Process? = { NowPlayingAdapter.bundled.process($0) }) {
        self.timeout = timeout; self.launch = launch
    }
    @discardableResult
    func send(_ request: NowPlayingRequest) -> Process? {
        guard let p = launch(request) else { return nil }
        do { try p.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        return p
    }
}

// Music's and Spotify's own volume (`sound volume`, 0–100), for the artwork window's slider. Pure: the scripts address
// the app by bundle ID, never by name (GOTCHAS); the caller runs them only for a running app with Automation access.
enum AppVolume {
    static let supported: Set<String> = ["com.apple.Music", "com.spotify.client"]
    static func readScript(_ bundleID: String) -> String? {
        supported.contains(bundleID) ? "tell application id \"\(bundleID)\" to get sound volume" : nil
    }
    static func writeScript(_ bundleID: String, level: Double) -> String? {
        guard supported.contains(bundleID) else { return nil }
        return "tell application id \"\(bundleID)\" to set sound volume to \(percent(level))"
    }
    // Playback commands addressed to that app — so pausing the music window can't pause whatever else holds the
    // "now playing" slot (a video, say).
    static func commandScript(_ request: NowPlayingRequest, bundleID: String) -> String? {
        guard supported.contains(bundleID) else { return nil }
        let verb: String
        switch request {
        case .command(.play): verb = "play"
        case .command(.pause): verb = "pause"
        case .command(.next): verb = "next track"
        case .command(.previous): verb = "previous track"
        case .seek(let seconds): verb = "set player position to " + String(format: "%.2f", max(0, seconds.isFinite ? seconds : 0))
        }
        return "tell application id \"\(bundleID)\" to \(verb)"
    }
    // The current track's artwork: Music hands over the image itself, Spotify a URL to it.
    static func artworkScript(_ bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.Music": return "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
        case "com.spotify.client": return "tell application id \"com.spotify.client\" to get artwork url of current track"
        default: return nil
        }
    }
    // Double-clicking the music window: Music shows the playing song in its own window (Spotify just comes forward).
    static func revealScript(_ bundleID: String) -> String? {
        bundleID == "com.apple.Music" ? "tell application id \"com.apple.Music\" to reveal current track" : nil
    }

    // The app's own shuffle and repeat (the music window's 🔀 🔁) — never Watch's queue. Music has repeat-one; Spotify's
    // scripting only has repeat on/off. The read script answers {shuffle, repeat}: Music's repeat as "off"/"all"/"one",
    // Spotify's as a boolean (AppModes.parse).
    static func modesScript(_ bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.Music": return "tell application id \"com.apple.Music\" to get {shuffle enabled, (song repeat as string)}"
        case "com.spotify.client": return "tell application id \"com.spotify.client\" to get {shuffling, repeating}"
        default: return nil
        }
    }
    static func shuffleScript(_ bundleID: String, on: Bool) -> String? {
        switch bundleID {
        case "com.apple.Music": return "tell application id \"com.apple.Music\" to set shuffle enabled to \(on)"
        case "com.spotify.client": return "tell application id \"com.spotify.client\" to set shuffling to \(on)"
        default: return nil
        }
    }
    static func repeatScript(_ bundleID: String, _ mode: AppRepeat) -> String? {
        switch bundleID {
        case "com.apple.Music": return "tell application id \"com.apple.Music\" to set song repeat to \(mode.rawValue)"
        case "com.spotify.client": return "tell application id \"com.spotify.client\" to set repeating to \(mode != .off)"
        default: return nil
        }
    }

    // 3.26: the star on the music window's controls — Apple Music's own favourite flag on the current song (what its ☆ sets in
    // the library, not Watch's Favourites list). Spotify's scripting has no way to like a song, so only Music has one. Music
    // names the property `favorited`; older versions called it `loved`, so the script tries the new name first. The scripts
    // are fixed text: nothing of the song goes into them.
    static let favouriteApps: Set<String> = ["com.apple.Music"]
    static func favouriteReadScript(_ bundleID: String) -> String? {
        favouriteApps.contains(bundleID) ? favouriteScript(bundleID, "get favorited of current track", "get loved of current track") : nil
    }
    static func favouriteWriteScript(_ bundleID: String, on: Bool) -> String? {
        favouriteApps.contains(bundleID)
            ? favouriteScript(bundleID, "set favorited of current track to \(on)", "set loved of current track to \(on)") : nil
    }
    private static func favouriteScript(_ bundleID: String, _ verb: String, _ older: String) -> String {
        func run(_ verb: String) -> String { "run script \"tell application id \\\"\(bundleID)\\\" to \(verb)\"" }
        return "try\n\(run(verb))\non error\n\(run(older))\nend try"
    }

    static func percent(_ level: Double) -> Int { Int((min(1, max(0, level.isFinite ? level : 0)) * 100).rounded()) }
    static func level(percent: Int) -> Double { min(1, max(0, Double(percent) / 100)) }
}

// Music's / Spotify's repeat setting. A click on 🔁 moves to `next(for:)`: off → all → one → off in Music, off ↔ on in Spotify.
enum AppRepeat: String, Equatable {
    case off, all, one
    func next(for bundleID: String) -> AppRepeat {
        switch self {
        case .off: return .all
        case .all: return bundleID == "com.apple.Music" ? .one : .off
        case .one: return .off
        }
    }
}
struct AppModes: Equatable {
    var shuffle: Bool
    var repeatMode: AppRepeat
    // From the read script's two answers (AppVolume.modesScript): Music's repeat is text, Spotify's a boolean.
    static func parse(shuffle: Bool, repeatText: String?, repeatFlag: Bool?) -> AppModes {
        let mode = repeatText.flatMap { AppRepeat(rawValue: $0.lowercased()) } ?? (repeatFlag == true ? .all : .off)
        return AppModes(shuffle: shuffle, repeatMode: mode)
    }
}

// Hands `work` the newest value only, one at a time on `queue`: a slider moves far faster than an app answers Apple
// Events, so values sent while one is being applied collapse into the latest.
final class CoalescingSender<Value> {
    private let queue: DispatchQueue
    private let work: (Value) -> Void
    private let lock = NSLock()
    private var pending: Value?
    private var busy = false
    init(queue: DispatchQueue, work: @escaping (Value) -> Void) { self.queue = queue; self.work = work }
    func send(_ value: Value) {
        lock.lock(); pending = value
        let start = !busy
        busy = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }
    private func drain() {
        while true {
            lock.lock()
            guard let value = pending else { busy = false; lock.unlock(); return }
            pending = nil
            lock.unlock()
            work(value)
        }
    }
}

// Runs the adapter while someone wants it — the panel while it's visible, the artwork window while it's open — and
// reports what's playing on the main thread, only when it changes. Call from the main thread.
final class NowPlayingMonitor {
    enum Client: Hashable { case panel, viewer, ticker }   // the panel, the music window, the menu-bar ticker (3.26: always on while its preference is)
    static let backoff: [TimeInterval] = [2, 10, 60]   // restarts after an unexpected exit; then it gives up
    static let quickExit: TimeInterval = 15             // an adapter that dies sooner counts as failing
    static let clearDelay: TimeInterval = 0.6           // "nothing playing" must hold this long (start-up, track changes)

    var onUpdate: ((NowPlayingInfo?) -> Void)?
    private(set) var current: NowPlayingInfo?
    private(set) var gaveUp = false
    var isRunning: Bool { process?.isRunning == true }

    private let ignoring: Set<String>
    private let launch: () -> Process?
    private let deliver: (@escaping () -> Void) -> Void
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let parseQueue = DispatchQueue(label: "watch.nowplaying")
    private var clients = Set<Client>()
    private var process: Process?
    private var generation = 0          // output or exit from a process we've stopped is dropped
    private var clearToken = 0
    private var restartToken = 0
    private var restartPending = false
    private var quickFailures = 0

    init(ignoring: Set<String> = [Bundle.main.bundleIdentifier ?? "com.jacob.watch"],
         launch: @escaping () -> Process? = { NowPlayingAdapter.bundled.process() },
         deliver: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) }) {
        self.ignoring = ignoring; self.launch = launch; self.deliver = deliver; self.schedule = schedule
    }

    func want(_ client: Client, _ on: Bool) {
        if on { clients.insert(client) } else { clients.remove(client) }
        if clients.isEmpty { stop() } else { start() }
    }
    func stopAll() { clients.removeAll(); stop() }

    private func start() {
        guard process == nil, !gaveUp, !restartPending, let p = launch() else { return }
        generation += 1
        let gen = generation, started = Date(), ignoring = self.ignoring, queue = parseQueue, deliver = self.deliver
        let output = Pipe(), reader = AdapterOutput(self)
        p.standardOutput = output
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            queue.async {
                let updates = reader.lines.append(chunk).map { NowPlayingInfo.parse(line: $0, ignoring: ignoring) }
                if !updates.isEmpty { deliver { reader.monitor?.received(updates, gen) } }
            }
        }
        p.terminationHandler = { _ in deliver { reader.monitor?.ended(gen, started: started) } }
        do { try p.run(); process = p }
        catch { output.fileHandleForReading.readabilityHandler = nil; giveUp() }   // perl itself won't start
    }
    private func stop() {
        restartToken += 1; restartPending = false; clearToken += 1
        guard let p = process else { return }
        generation += 1
        process = nil
        (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if p.isRunning { p.terminate() }    // SIGTERM: the adapter stops its run loop and exits
    }
    private func ended(_ gen: Int, started: Date) {
        guard gen == generation, process != nil else { return }   // stopped on purpose
        process = nil
        generation += 1
        quickFailures = Date().timeIntervalSince(started) < Self.quickExit ? quickFailures + 1 : 1
        guard quickFailures <= Self.backoff.count else { giveUp(); return }
        restartPending = true
        restartToken += 1
        let token = restartToken
        schedule(Self.backoff[quickFailures - 1]) { [weak self] in
            guard let self = self, token == self.restartToken else { return }
            self.restartPending = false
            if !self.clients.isEmpty { self.start() }
        }
    }
    private func giveUp() { gaveUp = true; apply(nil) }

    private func received(_ updates: [NowPlayingUpdate], _ gen: Int) {
        guard gen == generation else { return }
        for update in updates {
            switch update {
            case .invalid: continue
            case .info(let info): clearToken += 1; apply(info)
            case .nothing:
                guard current != nil else { continue }
                clearToken += 1
                let token = clearToken
                schedule(Self.clearDelay) { [weak self] in
                    guard let self = self, token == self.clearToken else { return }
                    self.apply(nil)
                }
            }
        }
    }
    private func apply(_ info: NowPlayingInfo?) {
        var next = info
        if let art = next?.artwork, art == current?.artwork { next?.artwork = current?.artwork }   // share the bytes
        guard next != current else { return }
        current = next
        onUpdate?(next)
    }
}

// One per adapter process: its line buffer (touched only on the parse queue) and the monitor (read only on the main
// thread, inside `deliver`). Background closures capture this, never the monitor itself.
private final class AdapterOutput {
    var lines = LineBuffer()
    weak var monitor: NowPlayingMonitor?
    init(_ monitor: NowPlayingMonitor) { self.monitor = monitor }
}
