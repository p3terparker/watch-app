import Foundation

// What another app is playing (Music, Spotify, a browser video…), from macOS's Now Playing info. Since macOS 15.4
// only Apple-signed processes may read it, so the bundled mediaremote-adapter runs inside /usr/bin/perl (see
// GOTCHAS). Read-only by design: Watch only ever runs the adapter's `stream` command — never send/seek/test, which
// would control or disturb the other app's playback.
struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String?
    var album: String?
    var bundleID: String
    var parentBundleID: String?
    var isPlaying: Bool
    var artwork: Data?
    var artworkMIME: String?

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
        let artwork = (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        return .info(NowPlayingInfo(title: title, artist: text("artist"), album: text("album"), bundleID: bundle,
                                    parentBundleID: parent, isPlaying: payload["playing"] as? Bool ?? false,
                                    artwork: artwork, artworkMIME: artwork == nil ? nil : text("artworkMimeType")))
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
    // Full state on every line (no diff merging); updates only come on track changes, play/pause and seeks.
    var arguments: [String] { [script.path, framework.path, "stream", "--no-diff", "--debounce=150"] }
    // Nothing from the user's shell may reach perl or the adapter: no PERL5OPT/PERL5LIB, no DYLD_*, no adapter options.
    static func environment(_ inherited: [String: String]) -> [String: String] {
        var env = inherited.filter { key, _ in
            !(key.hasPrefix("PERL") || key.hasPrefix("DYLD_") || key.hasPrefix("MEDIAREMOTEADAPTER_") || key == "ADAPTER_TEST_MODE")
        }
        env["PATH"] = "/usr/bin:/bin"
        return env
    }
    func process(environment: [String: String] = ProcessInfo.processInfo.environment) -> Process? {
        guard isAvailable else { return nil }
        let p = Process()
        p.executableURL = Self.perl
        p.arguments = arguments
        p.environment = Self.environment(environment)
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice   // every stderr line is a non-fatal adapter message
        return p
    }
}

// Runs the adapter while someone wants it — the panel while it's visible, the artwork window while it's open — and
// reports what's playing on the main thread, only when it changes. Call from the main thread.
final class NowPlayingMonitor {
    enum Client: Hashable { case panel, viewer }
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
