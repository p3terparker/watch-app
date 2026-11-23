// Appended to main.swift (cut at "Entry point") by youtube_probe.py: the player's own YouTube pipeline —
// resolveStream → each plan in order → DashHLSBridge → AVPlayer — on real links, saying where it breaks.
// Diagnostic only: it plays nothing on screen, sends no cookies, and reports instead of asserting.
import AVFoundation

setvbuf(stdout, nil, _IOLBF, 0)
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)

func say(_ s: String) { print(s); fflush(stdout) }
func spin(_ seconds: Double, until done: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if done() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
    return done()
}
func mb(_ n: Int) -> String { String(format: "%.1f MB", Double(n) / 1_048_576) }
func clock(_ s: Double) -> String { s.isFinite ? formatDuration(s) : "?" }
func describe(_ s: StreamRef) -> String {
    "\(s.height.map { "\($0)p" } ?? "audio") \(s.vcodec ?? "-")/\(s.acodec ?? "-") \(s.proto) \(s.ext) "
        + "\((s.bitrate ?? 0) / 1000) kb/s, url \(s.url.absoluteString.count) chars"
}

// The first 64 KB of a file, as fetchIndex asks for it, with what came back.
func rawHead(_ s: StreamRef) -> String {
    var r = URLRequest(url: s.url, timeoutInterval: 15)
    r.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
    s.headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
    final class Answer { var text = "no answer"; var finished = false }
    let answer = Answer()
    URLSession.shared.dataTask(with: r) { d, resp, err in
        let h = resp as? HTTPURLResponse
        let boxes = d.map { DashHLSBridge.boxes($0).map { "\($0.type)@\($0.offset)+\($0.size)" }.joined(separator: " ") } ?? ""
        answer.text = "HTTP \(h?.statusCode ?? 0), \(d?.count ?? 0) bytes, Content-Range \(h?.value(forHTTPHeaderField: "Content-Range") ?? "-")"
            + (err.map { ", error \($0.localizedDescription)" } ?? "") + ", boxes: \(boxes)"
        answer.finished = true
    }.resume()
    _ = spin(20) { answer.finished }
    return answer.text
}

func probeIndex(_ s: StreamRef) {
    var result: DashHLSBridge.Index??
    DashHLSBridge.fetchIndex(s) { result = .some($0) }
    _ = spin(40) { result != nil }
    guard let idx = result ?? nil else {
        say("      index: NONE — \(rawHead(s))")
        var again: DashHLSBridge.Index??
        DashHLSBridge.fetchIndex(s) { again = .some($0) }
        _ = spin(40) { again != nil }
        say("      index, second try: \((again ?? nil) == nil ? "NONE again" : "ok — the first failure was transient")")
        return
    }
    let total = idx.segments.reduce(0) { $0 + $1.duration }
    let end = idx.segments.last.map { $0.offset + $0.length } ?? 0
    let longest = idx.segments.map { $0.length }.max() ?? 0
    say("      index: \(idx.segments.count) segments, \(clock(total)), file ≈ \(mb(end)) (past 4 GB: \(end > Int(UInt32.max))), "
        + "init \(idx.initLength) B, largest segment \(mb(longest))")
}

final class Watcher {
    let item: AVPlayerItem
    var errors: [String] = []
    var tokens: [NSObjectProtocol] = []
    init(_ item: AVPlayerItem) {
        self.item = item
        tokens.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemNewErrorLogEntry, object: item, queue: .main) { [weak self] _ in
            guard let self = self, let e = item.errorLog()?.events.last else { return }
            let uri = (e.uri ?? "").prefix(90)
            self.errors.append("\(e.errorStatusCode) \(e.errorDomain): \(e.errorComment ?? "") [\(uri)]")
        })
        tokens.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
            self?.errors.append("playback stalled at \(clock(item.currentTime().seconds))")
        })
        tokens.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] n in
            let e = n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            self?.errors.append("failed to play to end: \(e?.localizedDescription ?? "?") \(e?.userInfo ?? [:])")
        })
    }
    deinit { for t in tokens { NotificationCenter.default.removeObserver(t) } }
    func flush(_ indent: String) {
        for e in errors.suffix(12) { say("\(indent)log: \(e)") }
        errors.removeAll()
        if let a = item.accessLog()?.events.last {
            say("\(indent)access: \(Int(a.indicatedBitrate / 1000)) kb/s indicated, \(Int(a.observedBitrate / 1000)) kb/s observed, "
                + "\(a.numberOfMediaRequests) requests, \(a.numberOfStalls) stalls, \(mb(Int(a.numberOfBytesTransferred))) transferred")
        }
    }
}

// Plays one asset muted for a few seconds at the start, the middle and near the end (a resume lands anywhere).
// Returns true when it became ready — the point after which the player stops trying the next plan.
func playCheck(_ asset: AVURLAsset, indent: String) -> Bool {
    let item = AVPlayerItem(asset: asset)
    item.preferredMaximumResolution = StreamLadder.cap(points: PlayerWindowController.standardSize, scale: 2)
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
    item.add(output)
    let watcher = Watcher(item)
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    let began = Date()
    player.play()
    let ready = spin(45) { item.status != .unknown }
    let took = Date().timeIntervalSince(began)
    guard ready, item.status == .readyToPlay else {
        say("\(indent)NOT READY after \(String(format: "%.1f", took)) s: status \(item.status.rawValue), "
            + "error \(item.error.map { "\(($0 as NSError).domain) \(($0 as NSError).code) \($0.localizedDescription) \(($0 as NSError).userInfo)" } ?? "none")")
        watcher.flush(indent)
        player.pause()
        return false
    }
    let duration = item.duration.seconds
    say("\(indent)ready in \(String(format: "%.1f", took)) s; duration \(clock(duration)); picture \(Int(item.presentationSize.width))×\(Int(item.presentationSize.height))")
    var spots: [(String, Double)] = [("start", 0)]
    if duration.isFinite, duration > 120 { spots += [("middle", duration / 2), ("near the end", duration - 90)] }
    for (name, at) in spots {
        if at > 0 {
            var seeked: Bool?
            player.seek(to: CMTime(seconds: at, preferredTimescale: 600), toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
                        toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600)) { seeked = $0 }
            _ = spin(30) { seeked != nil }
            if seeked != true { say("\(indent)\(name) (\(clock(at))): seek \(seeked == nil ? "never finished" : "cancelled")"); watcher.flush(indent); continue }
        }
        let from = player.currentTime().seconds
        let t0 = Date()
        let moved = spin(25) { player.currentTime().seconds >= from + 3 }
        let frame = output.hasNewPixelBuffer(forItemTime: player.currentTime()) || output.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil) != nil
        say("\(indent)\(name) (\(clock(at))): \(moved ? "PLAYS" : "STUCK") — \(clock(from)) → \(clock(player.currentTime().seconds)) in "
            + "\(String(format: "%.1f", Date().timeIntervalSince(t0))) s, frames: \(frame), rate \(player.rate), "
            + "waiting: \(player.reasonForWaitingToPlay?.rawValue ?? "-"), status \(item.status.rawValue)")
        watcher.flush(indent)
    }
    player.pause()
    return true
}

// The player's order: the first plan that becomes ready is the one that plays.
func runPlans(_ plans: [StreamPlan]) {
    for (i, plan) in plans.enumerated() {
        say("  trying plan \(i + 1):")
        var asset: AVURLAsset?
        var bridge: DashHLSBridge?
        switch plan {
        case .single(let s): asset = AVURLAsset(url: s.url, options: s.assetOptions)
        case .split(let videos, let audio):
            var made = false
            let t0 = Date()
            DashHLSBridge.make(videos: videos, audio: audio) { b, a in bridge = b; asset = a; made = true }
            _ = spin(60) { made }
            guard let b = bridge else { say("    bridge: NONE after \(String(format: "%.1f", Date().timeIntervalSince(t0))) s (player moves on)"); continue }
            let sizes = b.playlists.sorted { $0.key < $1.key }.map { "\($0.key) \(mb($0.value.count))" }.joined(separator: ", ")
            say("    bridge in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s — playlists: \(sizes)")
        }
        guard let a = asset else { continue }
        let ready = playCheck(a, indent: "    ")
        withExtendedLifetime(bridge) {}
        if ready { say("  → the player would stay on plan \(i + 1)"); return }
    }
    say("  → no plan played: the player shows its failure card")
}

// Long videos without YouTube: fixture renditions hours long (youtube_probe.py makes them with the bundled FFmpeg and serves
// them by range), behind URLs as long as YouTube's, so the bridge builds playlists the size a long video gets.
// Fixture sets: "base|label,video file,audio file,declared video kb/s;…" (Tests/youtube_probe.py serves them).
if let fixtures = ProcessInfo.processInfo.environment["WATCH_PROBE_FIXTURES"] {
    let parts = fixtures.split(separator: "|").map(String.init)
    let base = parts[0], pad = String(repeating: "x", count: 1200)
    for set in parts.dropFirst().joined(separator: "|").split(separator: ";").map({ $0.split(separator: ",").map(String.init) }) where set.count == 4 {
        let (name, vfile, afile, kbps) = (set[0], set[1], set[2], Double(set[3]) ?? 800)
        say("\n=== fixture \(name): \(vfile) + \(afile), video declared at \(Int(kbps)) kb/s, YouTube-length URLs")
        func ref(_ file: String, _ tag: Int, video: Bool) -> StreamRef {
            var f: [String: Any] = ["url": "\(base)\(file)?v=\(tag)&pad=\(pad)", "protocol": "https", "ext": video ? "mp4" : "m4a",
                                    "vcodec": video ? "avc1.64001e" : "none", "acodec": video ? "none" : "mp4a.40.2",
                                    "tbr": video ? kbps * Double(4 - tag) / 4 : 16.0]
            if video { f["width"] = 160; f["height"] = 90 }
            return StreamRef(f)!
        }
        let videos = (0..<4).map { ref(vfile, $0, video: true) }
        let audio = ref(afile, 9, video: false)
        say("    video:"); probeIndex(videos[0])
        say("    audio:"); probeIndex(audio)
        runPlans([.split(videos: videos, audio: audio), .split(videos: [videos[0]], audio: audio)])
    }
}

let links = Array(CommandLine.arguments.dropFirst())
for link in links {
    say("\n=== \(link)")
    var resolved: ResolvedStream?
    var lastError = ""
    for attempt in 1...3 where resolved == nil {
        var done = false
        let t0 = Date()
        resolveStream(link) { res, err in resolved = res; lastError = err; done = true }
        _ = spin(90) { done }
        say("  resolve attempt \(attempt): \(resolved == nil ? "FAILED — \(lastError)" : "ok") in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
        if resolved == nil, PlaybackFailure.wantsSignIn(lastError) { _ = spin(Double(10 * attempt)) { false } } else if resolved == nil { break }
    }
    guard let res = resolved else { continue }
    say("  title: \(res.title ?? "?") · duration \(clock(res.duration ?? .nan)) · live \(res.isLive) · \(res.plans.count) plans")
    for (i, plan) in res.plans.enumerated() {
        switch plan {
        case .single(let s): say("  plan \(i + 1): single — \(describe(s))")
        case .split(let videos, let audio):
            say("  plan \(i + 1): split — \(videos.count) video rendition(s) + audio")
            for v in videos { say("    video \(describe(v))") }
            say("    audio \(describe(audio))")
        }
    }
    // Each distinct file's sidx, as the bridge reads it.
    var seen = Set<URL>()
    for plan in res.plans {
        guard case .split(let videos, let audio) = plan else { continue }
        for s in videos + [audio] where !s.isHLS && seen.insert(s.url).inserted {
            say("    \(s.height.map { "\($0)p" } ?? "audio"):"); probeIndex(s)
        }
    }
    runPlans(res.plans)
}
say("\nprobe finished")
exit(0)
