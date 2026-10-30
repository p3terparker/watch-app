import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Now Playing without MediaRemote: adapter lines are fixtures and the adapter process is /bin/sh.
private let png1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
private let watchID: Set<String> = ["com.jacob.watch"]

private func adapterLine(_ payload: Any, type: String = "data", diff: Bool = false) -> Data {
    try! JSONSerialization.data(withJSONObject: ["type": type, "diff": diff, "payload": payload])
}
private func adapterText(_ payload: Any) -> String { String(decoding: adapterLine(payload), as: UTF8.self) }
private func song(_ title: String, artist: String = "Artist", album: String? = "Album", playing: Bool = true,
                  bundle: String = "com.apple.Music", artwork: String? = png1x1, mime: String? = "image/png") -> [String: Any] {
    var p: [String: Any] = ["title": title, "artist": artist, "bundleIdentifier": bundle, "playing": playing, "elapsedTime": 12.5]
    if let a = album { p["album"] = a }
    if let a = artwork { p["artworkData"] = a }
    if let m = mime { p["artworkMimeType"] = m }
    return p
}
private func info(_ u: NowPlayingUpdate) -> NowPlayingInfo? { if case .info(let i) = u { return i }; return nil }
@discardableResult
private func pumpUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    return condition()
}
private func shell(_ script: String, _ env: [String: String] = [:], into launched: inout [Process]) -> Process {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", script]
    p.environment = env
    launched.append(p)
    return p
}

func checkNowPlaying() {
    // Parsing one `stream --no-diff` line.
    let music = info(NowPlayingInfo.parse(line: adapterLine(song("Song")), ignoring: watchID))
    expect(music?.title == "Song" && music?.artist == "Artist" && music?.album == "Album" && music?.isPlaying == true, "full payload parses")
    expect(music?.artwork == Data(base64Encoded: png1x1) && music?.artworkExtension == "png", "artwork decoded with its type")
    expect(music?.appBundleID == "com.apple.Music" && music?.youtubeQuery == "Song Artist", "app and YouTube query")
    expect(music?.suggestedFileName(extension: "png") == "Artist – Album.png", "save name is artist – album")
    expect(NowPlayingInfo.parse(line: adapterLine([String: Any]()), ignoring: watchID) == .nothing, "empty payload = nothing playing")
    expect(NowPlayingInfo.parse(line: adapterLine(NSNull()), ignoring: watchID) == .nothing, "null payload = nothing playing")
    var untitled = song("x"); untitled.removeValue(forKey: "title")
    expect(NowPlayingInfo.parse(line: adapterLine(untitled), ignoring: watchID) == .nothing, "no title = nothing")
    expect(NowPlayingInfo.parse(line: adapterLine(song("   ")), ignoring: watchID) == .nothing, "blank title = nothing")
    expect(NowPlayingInfo.parse(line: adapterLine(song("Own", bundle: "com.jacob.watch")), ignoring: watchID) == .nothing, "Watch's own media ignored")
    var webKit = song("Clip", bundle: "com.apple.WebKit.GPU"); webKit["parentApplicationBundleIdentifier"] = "com.apple.Safari"
    expect(info(NowPlayingInfo.parse(line: adapterLine(webKit), ignoring: watchID))?.appBundleID == "com.apple.Safari", "browser media named by its parent app")
    webKit["parentApplicationBundleIdentifier"] = "com.jacob.watch"
    expect(NowPlayingInfo.parse(line: adapterLine(webKit), ignoring: watchID) == .nothing, "Watch's own web view ignored")
    expect(info(NowPlayingInfo.parse(line: adapterLine(song("P", playing: false)), ignoring: watchID))?.isPlaying == false, "paused")
    var noState = song("N"); noState.removeValue(forKey: "playing")
    expect(info(NowPlayingInfo.parse(line: adapterLine(noState), ignoring: watchID))?.isPlaying == false, "unknown state is not playing")
    let bare = info(NowPlayingInfo.parse(line: adapterLine(song("B", album: nil, artwork: nil)), ignoring: watchID))
    expect(bare?.artwork == nil && bare?.artworkMIME == nil && bare?.artworkExtension == nil, "no artwork")
    expect(bare?.suggestedFileName(extension: "jpg") == "Artist – B.jpg", "single without album uses the title")
    expect(info(NowPlayingInfo.parse(line: adapterLine(song("Bad", artwork: "%%%")), ignoring: watchID))?.artwork == nil, "bad base64 dropped")
    expect(NowPlayingInfo.parse(line: Data("not json".utf8), ignoring: watchID) == .invalid, "bad JSON ignored")
    expect(NowPlayingInfo.parse(line: adapterLine(song("D"), diff: true), ignoring: watchID) == .invalid, "partial (diff) line ignored")
    expect(NowPlayingInfo.parse(line: adapterLine(song("E"), type: "error"), ignoring: watchID) == .invalid, "other line types ignored")

    // File types and names.
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10]) + Data(count: 10)
    expect(NowPlayingInfo(title: "t", bundleID: "b", isPlaying: true, artwork: jpeg).artworkExtension == "jpg", "JPEG sniffed without a MIME type")
    expect(NowPlayingInfo(title: "t", bundleID: "b", isPlaying: true, artwork: Data([1, 2, 3])).artworkExtension == nil, "unknown bytes stay unnamed")
    expect(NowPlayingInfo(title: "t", bundleID: "b", isPlaying: true, artwork: jpeg, artworkMIME: "image/jpeg").artworkExtension == "jpg", "MIME type wins")
    expect(NowPlayingInfo.safeFileName("AC/DC: Live\\Set") == "AC-DC- Live-Set", "path separators replaced")
    expect(NowPlayingInfo.safeFileName("..hidden.") == "hidden" && NowPlayingInfo.safeFileName(" ") == "Artwork", "no hidden or empty names")
    expect(NowPlayingInfo.safeFileName("a\nb\u{0}c") == "a b c", "control characters replaced")
    expect(NowPlayingInfo.safeFileName(String(repeating: "x", count: 300)).count == 120, "long names capped")

    // Pipe chunks → lines.
    var lines = LineBuffer()
    expect(lines.append(Data("a".utf8)).isEmpty, "partial line held")
    expect(lines.append(Data("b\nc".utf8)) == [Data("ab".utf8)], "line completed across chunks")
    expect(lines.append(Data("\n\nd".utf8)) == [Data("c".utf8)], "blank lines skipped")
    expect(lines.append(Data("\n".utf8)) == [Data("d".utf8)], "held remainder completes")
    let big = adapterLine(song("Big", artwork: Data(count: 300_000).base64EncodedString())) + Data("\n".utf8)
    var bigBuffer = LineBuffer(), received: [Data] = []
    stride(from: 0, to: big.count, by: 65_536).forEach { received += bigBuffer.append(big.subdata(in: $0..<min($0 + 65_536, big.count))) }
    expect(received.count == 1 && info(NowPlayingInfo.parse(line: received[0], ignoring: watchID))?.artwork?.count == 300_000, "several-hundred-KB line reassembled")

    // The adapter's location, arguments and environment.
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Watch now playing \(UUID().uuidString)/Contents")
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let adapter = NowPlayingAdapter(contents: root)
    expect(!adapter.isAvailable && adapter.process() == nil, "missing adapter: feature off, nothing launched")
    try! FileManager.default.createDirectory(at: adapter.script.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! FileManager.default.createDirectory(at: adapter.framework, withIntermediateDirectories: true)
    try! Data().write(to: adapter.script)
    expect(!adapter.isAvailable, "script alone is not enough")
    try! Data().write(to: adapter.framework.appendingPathComponent("MediaRemoteAdapter"))
    expect(adapter.isAvailable == FileManager.default.isExecutableFile(atPath: "/usr/bin/perl"), "complete adapter found (with system perl)")
    expect(adapter.arguments == [adapter.script.path, adapter.framework.path, "stream", "--no-diff", "--debounce=150", "--micros"], "stream, full state, paths with spaces intact")
    expect(!adapter.arguments.contains { ["send", "seek", "test", "shuffle", "repeat", "speed", "get"].contains($0) }, "never a playback or test command")
    let env = NowPlayingAdapter.environment(["PATH": "/opt/homebrew/bin", "HOME": "/Users/x", "PERL5OPT": "-Mevil", "PERL5LIB": "/x", "PERLLIB": "/y",
                                            "PERL_MB_OPT": "z", "DYLD_INSERT_LIBRARIES": "/z.dylib", "MEDIAREMOTEADAPTER_OPTION_no_artwork": "", "ADAPTER_TEST_MODE": "1"])
    expect(env == ["PATH": "/usr/bin:/bin", "HOME": "/Users/x"], "nothing from the shell can reach perl or the adapter")
    if let p = adapter.process(environment: ["PERL5OPT": "-Mevil"]) {
        expect(p.executableURL?.path == "/usr/bin/perl" && p.environment?["PERL5OPT"] == nil, "launches system perl with a clean environment")
    }

    // The monitor: demand-driven process, de-duplicated updates, debounced "nothing", restart back-off.
    var launched: [Process] = [], restarts: [(TimeInterval, () -> Void)] = []
    var script = #"printf '%s\n%s\n%s\n' "$ONE" "$ONE" "$TWO"; exec sleep 30"#
    var lineEnv = ["ONE": adapterText(song("One")), "TWO": adapterText(song("Two", playing: false))]
    let monitor = NowPlayingMonitor(ignoring: watchID, launch: { shell(script, lineEnv, into: &launched) },
                                    schedule: { delay, work in restarts.append((delay, work)) })
    var updates: [NowPlayingInfo?] = []
    monitor.onUpdate = { updates.append($0) }
    monitor.want(.panel, true)
    monitor.want(.viewer, true)
    expect(launched.count == 1 && monitor.isRunning, "one adapter process for both clients")
    expect(pumpUntil { updates.count >= 2 }, "updates arrive")
    pumpUntil(0.3) { false }
    expect(updates.map { $0?.title } == ["One", "Two"] && updates[1]?.isPlaying == false, "duplicate lines suppressed, changes delivered")
    monitor.want(.panel, false)
    expect(monitor.isRunning, "the artwork window keeps it running")
    monitor.want(.viewer, false)
    expect(!monitor.isRunning, "stopped when nobody wants it")
    expect(pumpUntil { !launched[0].isRunning } && launched[0].terminationReason == .uncaughtSignal, "adapter terminated")
    pumpUntil(0.2) { false }
    expect(restarts.isEmpty && updates.count == 2 && monitor.current?.title == "Two", "a deliberate stop is not a failure")

    // "Nothing playing" waits clearDelay; a track arriving meanwhile cancels it.
    launched = []; restarts = []; updates = []
    script = #"printf '%s\n' "$ONE" "$NONE"; sleep 1; printf '%s\n' "$NONE"; exec sleep 30"#
    lineEnv = ["ONE": adapterText(song("Three")), "NONE": adapterText([String: Any]())]
    monitor.want(.panel, true)
    expect(pumpUntil { updates.count == 1 && restarts.count == 1 }, "nothing-playing is debounced")
    expect(restarts[0].0 == NowPlayingMonitor.clearDelay && updates.last??.title == "Three", "clear delay scheduled")
    expect(pumpUntil { restarts.count == 2 }, "second nothing-playing")
    restarts[0].1()
    expect(updates.count == 1, "a superseded clear does nothing")
    restarts[1].1()
    expect(updates.count == 2 && updates.last! == nil && monitor.current == nil, "nothing playing clears the row")
    monitor.stopAll()

    // An adapter that keeps dying is restarted after 2, 10, 60 s, then given up for the session.
    launched = []; restarts = []; updates = []
    script = "exit 1"
    let failing = NowPlayingMonitor(ignoring: watchID, launch: { shell(script, [:], into: &launched) },
                                    schedule: { delay, work in restarts.append((delay, work)) })
    failing.want(.panel, true)
    for (attempt, delay) in NowPlayingMonitor.backoff.enumerated() {
        expect(pumpUntil { restarts.count == attempt + 1 }, "restart scheduled after exit \(attempt + 1)")
        expect(restarts[attempt].0 == delay, "back-off \(delay) s")
        restarts[attempt].1()
        expect(launched.count == attempt + 2, "restarted")
    }
    expect(pumpUntil { failing.gaveUp }, "gives up after repeated quick failures")
    failing.want(.viewer, true)
    expect(launched.count == NowPlayingMonitor.backoff.count + 1 && restarts.count == NowPlayingMonitor.backoff.count, "no relaunch after giving up")

    // Hiding the panel during a back-off cancels the restart.
    launched = []; restarts = []
    let pending = NowPlayingMonitor(ignoring: watchID, launch: { shell(script, [:], into: &launched) },
                                    schedule: { delay, work in restarts.append((delay, work)) })
    pending.want(.panel, true)
    expect(pumpUntil { restarts.count == 1 }, "restart pending")
    pending.want(.panel, false)
    restarts[0].1()
    expect(launched.count == 1, "nobody wants it: no restart")
}

// The full-screen artwork's background colours and layout.
func checkArtworkStyle() {
    func picture(_ w: Int, _ h: Int, _ colour: (Int, Int) -> [UInt8]) -> [UInt8] {
        var p: [UInt8] = []
        for y in 0..<h { for x in 0..<w { p += colour(x, y) } }
        return p
    }
    let red = ArtworkPalette.gradient(pixels: picture(8, 8) { _, _ in [255, 0, 0, 255] }, width: 8, height: 8)!
    expect(red.start.g == 0 && red.start.b == 0 && abs(red.start.value - ArtworkPalette.maxValue) < 1e-9, "one colour: red, darkened for white text")
    expect(red.end.r < red.start.r && red.end.g == 0, "one colour: the second stop is a darker shade of it")
    let split = ArtworkPalette.gradient(pixels: picture(8, 8) { x, _ in x < 4 ? [0, 0, 255, 255] : [255, 255, 0, 255] }, width: 8, height: 8)!
    let stops = [split.start, split.end]
    expect(stops.contains { $0.b > 0.4 && $0.r < 0.1 } && stops.contains { $0.r > 0.4 && $0.g > 0.4 && $0.b < 0.1 }, "two colours: one stop each")
    let vivid = ArtworkPalette.gradient(pixels: picture(10, 10) { x, y in (2...7).contains(x) && (2...7).contains(y) ? [230, 30, 120, 255] : [128, 128, 128, 255] },
                                        width: 10, height: 10)!
    expect(vivid.start.r > vivid.start.g && vivid.start.saturation > 0.5, "a vivid subject leads over a larger grey area")
    expect(vivid.end.saturation < 0.1, "…and the grey ground is the second stop")
    let faint = ArtworkPalette.gradient(pixels: picture(4, 4) { _, _ in [128, 0, 0, 128] }, width: 4, height: 4)!
    expect(abs(faint.start.r - ArtworkPalette.maxValue) < 0.01, "premultiplied alpha is undone")
    expect(ArtworkPalette.gradient(pixels: picture(4, 4) { _, _ in [0, 0, 0, 0] }, width: 4, height: 4) == nil, "transparent: no colours")
    expect(ArtworkPalette.gradient(pixels: [1, 2, 3], width: 4, height: 4) == nil, "short sample rejected")
    expect(ArtworkPalette.tone(RGB(r: 1, g: 1, b: 1)) == RGB(r: 0.55, g: 0.55, b: 0.55), "white toned down")
    expect(ArtworkPalette.tone(RGB(r: 0, g: 0, b: 0)) == RGB(r: 0.1, g: 0.1, b: 0.1), "black lifted to a dark grey")

    let screen = CGSize(width: 1440, height: 900)
    let square = ArtworkLayout.fullScreen(artwork: CGSize(width: 600, height: 600), in: screen)
    expect(square.art == CGRect(x: 441, y: 226, width: 558, height: 558), "square art: 62% of the height, centred with its caption and controls")
    expect(square.caption == CGRect(x: 441, y: 142, width: 558, height: 64), "caption centred under the art")
    expect(square.controls == CGRect(x: 441, y: 116, width: 558, height: 26), "the controls' one row reserved under the caption")
    expect(square.caption.origin.y + square.caption.size.height + ArtworkLayout.gap == square.art.origin.y, "gap between art and caption")
    expect(square.controls.origin.y + square.controls.size.height == square.caption.origin.y, "controls directly under the caption")
    let wide = ArtworkLayout.fullScreen(artwork: CGSize(width: 640, height: 360), in: screen)
    expect(wide.art.size == CGSize(width: 992, height: 558) && wide.art.origin.x == 224, "16:9 art keeps its shape")
    let tallScreen = ArtworkLayout.fullScreen(artwork: CGSize(width: 600, height: 600), in: CGSize(width: 800, height: 1200))
    expect(tallScreen.art.size == CGSize(width: 560, height: 560) && tallScreen.caption.size.width == 560, "narrow screen: 70% of the width")
    let small = ArtworkLayout.fullScreen(artwork: CGSize(width: 100, height: 100), in: screen)
    expect(small.caption.size.width == 558 && small.art.size.width == 558, "small art is scaled up to the same spot")
    expect(ArtworkLayout.fullScreen(artwork: .zero, in: screen).art.size == CGSize(width: 558, height: 558), "unknown shape: square")
    checkControlRow()
}

// The music window's one row of controls: ⏮ ⏯ ⏭ from the left, elapsed · timeline · remaining, shuffle · repeat, volume at
// the right; what doesn't fit drops out in a fixed order and the timeline keeps a usable length.
func checkControlRow() {
    func row(_ w: CGFloat, timeline: Bool = true, long: Bool = false, modes: Bool = true, volume: ControlRowVolume = .slider) -> ControlRow {
        ArtworkLayout.controlRow(width: w, timeline: timeline, longClock: long, modes: modes, volume: volume)
    }
    let wide = row(376)                                       // a 400 pt window
    let all = [wide.previous, wide.playPause, wide.next, wide.elapsed, wide.timeline, wide.remaining, wide.shuffle, wide.repeatMode,
               wide.volumeIcon, wide.volume].compactMap { $0 }
    expect(all.count == 10, "a wide window shows every part")
    expect(wide.previous!.minX == 0 && wide.previous!.maxX < wide.playPause!.minX && wide.playPause!.maxX < wide.next!.minX,
           "⏮ ⏯ ⏭ from the left edge")
    expect(wide.next!.maxX < wide.elapsed!.minX && wide.elapsed!.maxX <= wide.timeline!.minX && wide.timeline!.maxX <= wide.remaining!.minX,
           "then elapsed, the timeline and remaining")
    expect(wide.remaining!.maxX < wide.shuffle!.minX && wide.shuffle!.maxX < wide.repeatMode!.minX && wide.repeatMode!.maxX < wide.volumeIcon!.minX
           && wide.volumeIcon!.maxX < wide.volume!.minX && wide.volume!.maxX == 376, "then shuffle, repeat and the volume at the right edge")
    expect(all.allSatisfy { abs($0.midY - ArtworkLayout.controlsHeight / 2) <= 1 && $0.maxY <= ArtworkLayout.controlsHeight && $0.minY >= 0 },
           "one row: everything centred on the same line")
    for i in all.indices { for j in all.indices where j > i { expect(!all[i].intersects(all[j]), "parts \(i) and \(j) don't overlap") } }
    expect(wide.timeline!.width >= 120, "a 400 pt window has a long timeline (\(wide.timeline!.width))")
    let usual = row(276)                                      // the usual 300 pt window
    expect(usual.elapsed == nil && usual.remaining != nil && usual.shuffle != nil && usual.repeatMode != nil && usual.volume != nil
           && usual.previous != nil && usual.timeline!.width >= ArtworkLayout.minTimeline, "300 pt: only the elapsed time gives way")
    let smaller = row(220)
    expect(smaller.shuffle == nil && smaller.repeatMode == nil && smaller.volume != nil, "then shuffle/repeat")
    let narrow = row(200)
    expect(narrow.volume == nil && narrow.volumeIcon != nil && narrow.remaining != nil, "then the volume slider (the speaker stays)")
    let tiny = row(100)
    expect(tiny.previous == nil && tiny.next == nil && tiny.remaining == nil && tiny.playPause != nil && tiny.timeline != nil,
           "a tiny window keeps ⏯ and the timeline")
    expect([usual, narrow, tiny].allSatisfy { ($0.timeline?.maxX ?? 0) <= ($0.shuffle ?? $0.volumeIcon ?? CGRect(x: 10_000, y: 0, width: 0, height: 0)).minX },
           "the timeline never runs into the right-hand parts")
    let noLength = row(376, timeline: false)
    expect(noLength.timeline == nil && noLength.elapsed == nil && noLength.remaining == nil && noLength.shuffle != nil, "no length: no timeline or times")
    let other = row(376, modes: false, volume: .none)
    expect(other.shuffle == nil && other.volumeIcon == nil && other.timeline!.maxX > 340, "an app Watch can't script: the timeline takes the room")
    let denied = row(376, volume: .icon)
    expect(denied.volume == nil && denied.volumeIcon != nil, "not allowed: the speaker alone")
    expect(row(376, long: true).elapsed!.width > wide.elapsed!.width, "hour-long tracks get wider times")
}

// The artwork window's playback controls: timing from the stream, the requests they send, the app volume scripts.
func checkPlaybackControls() {
    var timed = song("Timed")
    timed["durationMicros"] = 240_000_000; timed["elapsedTimeMicros"] = 72_500_000
    timed["timestampEpochMicros"] = 1_800_000_000_000_000; timed["playbackRate"] = 1
    let t = info(NowPlayingInfo.parse(line: adapterLine(timed), ignoring: watchID))!
    let reported = Date(timeIntervalSince1970: 1_800_000_000)
    expect(t.duration == 240 && t.elapsed == 72.5 && t.elapsedAt == reported && t.rate == 1, "timing parsed from microseconds")
    expect(t.position(at: reported.addingTimeInterval(10)) == 82.5, "position moves on while playing")
    expect(t.position(at: reported.addingTimeInterval(1_000)) == 240, "never past the end")
    expect(t.position(at: reported.addingTimeInterval(-5)) == 72.5, "a clock behind the report doesn't go backwards")
    var paused = t; paused.isPlaying = false
    expect(paused.position(at: reported.addingTimeInterval(10)) == 72.5, "paused: the position stays")
    var unrated = t; unrated.rate = 0
    expect(unrated.position(at: reported.addingTimeInterval(4)) == 76.5, "playing with no rate counts as 1×")
    var double = t; double.rate = 2
    expect(double.position(at: reported.addingTimeInterval(4)) == 80.5, "playback rate respected")
    let radio = info(NowPlayingInfo.parse(line: adapterLine(song("Radio")), ignoring: watchID))!
    expect(radio.duration == nil && radio.position(at: reported) == nil, "no timing: no timeline")
    var zero = timed; zero["durationMicros"] = 0
    expect(info(NowPlayingInfo.parse(line: adapterLine(zero), ignoring: watchID))?.duration == nil, "zero length is no length")
    expect(NowPlayingInfo.clock(72.9) == "1:12" && NowPlayingInfo.clock(171, remaining: true) == "-2:51", "clock")
    expect(NowPlayingInfo.clock(3723) == "1:02:03" && NowPlayingInfo.clock(-4) == "0:00" && NowPlayingInfo.clock(.nan) == "0:00", "clock: hours, negatives, NaN")

    let adapter = NowPlayingAdapter(contents: URL(fileURLWithPath: "/Watch Fixture.app/Contents"))
    expect(adapter.arguments.suffix(4) == ["stream", "--no-diff", "--debounce=150", "--micros"], "stream reports microsecond timing")
    expect(adapter.arguments(for: .command(.pause)).suffix(2) == ["send", "1"], "pause is send 1")
    expect(adapter.arguments(for: .command(.play)).suffix(2) == ["send", "0"] && adapter.arguments(for: .command(.next)).suffix(2) == ["send", "4"]
           && adapter.arguments(for: .command(.previous)).suffix(2) == ["send", "5"], "play 0 · next 4 · previous 5")
    expect(adapter.arguments(for: .seek(83.25)).suffix(2) == ["seek", "83250000"] && adapter.arguments(for: .seek(-3)).last == "0", "seek in microseconds, never negative")
    let every = [NowPlayingRequest.command(.play), .command(.pause), .command(.next), .command(.previous), .seek(1)].flatMap(adapter.arguments(for:))
    expect(!every.contains("test") && !every.contains("stream"), "controls never run test (or a second stream)")

    expect(AppVolume.readScript("com.apple.Music") == #"tell application id "com.apple.Music" to get sound volume"#, "Music addressed by bundle id")
    expect(AppVolume.writeScript("com.spotify.client", level: 0.426) == #"tell application id "com.spotify.client" to set sound volume to 43"#, "Spotify set, rounded")
    expect(AppVolume.writeScript("com.apple.Music", level: 7) == #"tell application id "com.apple.Music" to set sound volume to 100"#
           && AppVolume.percent(-1) == 0 && AppVolume.percent(.nan) == 0, "levels clamped")
    expect(AppVolume.readScript("com.google.Chrome") == nil && AppVolume.writeScript("com.google.Chrome", level: 1) == nil, "unsupported apps get no script")
    expect(AppVolume.level(percent: 64) == 0.64 && AppVolume.level(percent: 250) == 1, "percent to level")

    // Coalescing: values sent while one is being applied collapse into the newest.
    let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
    let applied = NSMutableArray()
    let sender = CoalescingSender<Int>(queue: DispatchQueue(label: "fixture.coalesce")) { value in
        applied.add(value)
        if value == 1 { started.signal(); release.wait() }
        if value == 4 { finished.signal() }
    }
    sender.send(1)
    started.wait()
    sender.send(2); sender.send(3); sender.send(4)
    release.signal()
    expect(finished.wait(timeout: .now() + 5) == .success && applied as? [Int] == [1, 4], "only the newest value follows the one in flight")

    // The remote: one adapter run per request, stopped if it hangs.
    var requests: [NowPlayingRequest] = [], launched: [Process] = []
    let remote = NowPlayingRemote(timeout: 0.3) { request in
        requests.append(request)
        return shell("exec sleep 30", [:], into: &launched)
    }
    expect(remote.send(.command(.next)) != nil && requests == [.command(.next)], "a click sends one request")
    expect(pumpUntil { !launched[0].isRunning } && launched[0].terminationReason == .uncaughtSignal, "a hung adapter run is stopped")
    expect(NowPlayingRemote { _ in nil }.send(.command(.play)) == nil, "no adapter: nothing sent")
}

// The music window follows music only; Music/Spotify broadcasts; commands addressed to the app.
func checkMusicSources() {
    let own: Set<String> = ["com.jacob.watch"]
    func source(_ bundle: String, parent: String? = nil, type: String? = nil) -> NowPlayingInfo {
        NowPlayingInfo(title: "T", bundleID: bundle, parentBundleID: parent, isPlaying: true, mediaType: type)
    }
    expect(source("com.apple.Music").isMusicSource(ignoring: own) && source("com.spotify.client").isMusicSource(ignoring: own), "Music and Spotify are music")
    expect(source("com.apple.podcasts").isMusicSource(ignoring: own), "Podcasts counts (audio)")
    expect(!source("com.google.Chrome").isMusicSource(ignoring: own) && !source("com.apple.Safari").isMusicSource(ignoring: own), "browsers never")
    expect(!source("com.apple.WebKit.GPU").isMusicSource(ignoring: own), "a web page's media process never")
    expect(!source("com.apple.WebKit.GPU", parent: "com.jacob.watch").isMusicSource(ignoring: own) && !source("com.jacob.watch").isMusicSource(ignoring: own), "Watch's own playback never")
    expect(!source("com.apple.WebKit.GPU", parent: "com.apple.Safari", type: "MRMediaRemoteMediaTypeMusic").isMusicSource(ignoring: own), "a browser stays out even when it says music")
    expect(source("com.example.player", type: "MRMediaRemoteMediaTypeMusic").isMusicSource(ignoring: own), "an unknown app that says it plays music counts")
    expect(!source("com.example.player").isMusicSource(ignoring: own) && !source("com.apple.TV", type: "video").isMusicSource(ignoring: own), "an unknown or video app doesn't")
    var withType = song("Typed", bundle: "com.example.player"); withType["mediaType"] = "MRMediaRemoteMediaTypeMusic"
    expect(info(NowPlayingInfo.parse(line: adapterLine(withType), ignoring: [])).map { $0.isMusicSource(ignoring: own) } == true, "media type read from the stream")
    expect(info(NowPlayingInfo.parse(line: adapterLine(song("Own", bundle: "com.jacob.watch")), ignoring: []))?.isMusicSource(ignoring: own) == false,
           "with nothing ignored, Watch's own report arrives — and is not music")

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let music: [AnyHashable: Any] = ["Name": "Song", "Artist": "Artist", "Album": "Album", "Player State": "Playing", "Total Time": 241_000]
    let heard = NowPlayingInfo.broadcast(music, app: "com.apple.Music", at: now)
    expect(heard?.title == "Song" && heard?.isPlaying == true && heard?.duration == 241 && heard?.elapsed == nil && heard?.bundleID == "com.apple.Music", "Music broadcast")
    let spotify: [AnyHashable: Any] = ["Name": "Track", "Artist": "A", "Player State": "Paused", "Duration": 180_000, "Playback Position": 42.5]
    let paused = NowPlayingInfo.broadcast(spotify, app: "com.spotify.client", at: now)
    expect(paused?.isPlaying == false && paused?.duration == 180 && paused?.elapsed == 42.5 && paused?.elapsedAt == now, "Spotify broadcast with its position")
    expect(NowPlayingInfo.broadcast(["Name": "x", "Player State": "Stopped"], app: "com.apple.Music") == nil, "stopped: nothing")
    expect(NowPlayingInfo.broadcast(["Player State": "Playing"], app: "com.apple.Music") == nil, "no name: nothing")
    expect(NowPlayingInfo.broadcasts["com.apple.Music.playerInfo"] == "com.apple.Music" && NowPlayingInfo.broadcasts["com.spotify.client.PlaybackStateChanged"] == "com.spotify.client", "broadcast names")

    var rich = info(NowPlayingInfo.parse(line: adapterLine(song("Song")), ignoring: []))!
    rich.duration = 241; rich.elapsed = 60; rich.elapsedAt = now; rich.rate = 1
    let pausedSame = NowPlayingInfo.broadcast(["Name": "Song", "Artist": "Artist", "Album": "Album", "Player State": "Paused", "Total Time": 241_000], app: "com.apple.Music")!
    let merged = NowPlayingInfo.merge(pausedSame, onto: rich, at: now.addingTimeInterval(10))
    expect(merged.artwork == rich.artwork && merged.isPlaying == false && merged.elapsed == 70 && merged.position(at: now.addingTimeInterval(100)) == 70,
           "same track: artwork kept, the clock stops where it was")
    let next = NowPlayingInfo.broadcast(["Name": "Next", "Artist": "Artist", "Album": "Album", "Player State": "Playing"], app: "com.apple.Music")!
    expect(NowPlayingInfo.merge(next, onto: rich).title == "Next" && NowPlayingInfo.merge(next, onto: rich).artwork == nil, "a new track replaces it")

    expect(AppVolume.commandScript(.command(.pause), bundleID: "com.apple.Music") == #"tell application id "com.apple.Music" to pause"#, "pause Music itself")
    expect(AppVolume.commandScript(.command(.play), bundleID: "com.spotify.client") == #"tell application id "com.spotify.client" to play"#, "play Spotify itself")
    expect(AppVolume.commandScript(.command(.next), bundleID: "com.apple.Music")?.hasSuffix("to next track") == true
           && AppVolume.commandScript(.command(.previous), bundleID: "com.apple.Music")?.hasSuffix("to previous track") == true, "next / previous track")
    expect(AppVolume.commandScript(.seek(83.256), bundleID: "com.apple.Music")?.hasSuffix("to set player position to 83.26") == true
           && AppVolume.commandScript(.seek(-4), bundleID: "com.apple.Music")?.hasSuffix("position to 0.00") == true, "seek in seconds, never negative")
    expect(AppVolume.commandScript(.command(.play), bundleID: "com.google.Chrome") == nil, "no script for other apps")
    expect(AppVolume.artworkScript("com.apple.Music")?.contains("raw data of artwork 1 of current track") == true
           && AppVolume.artworkScript("com.spotify.client")?.contains("artwork url of current track") == true && AppVolume.artworkScript("x") == nil, "artwork scripts")
    // The music window's 🔀 🔁: the app's own settings, addressed by bundle id; never Watch's queue.
    expect(AppVolume.modesScript("com.apple.Music") == #"tell application id "com.apple.Music" to get {shuffle enabled, (song repeat as string)}"#
           && AppVolume.modesScript("com.spotify.client") == #"tell application id "com.spotify.client" to get {shuffling, repeating}"#
           && AppVolume.modesScript("com.apple.podcasts") == nil, "reading shuffle and repeat")
    expect(AppVolume.shuffleScript("com.apple.Music", on: true) == #"tell application id "com.apple.Music" to set shuffle enabled to true"#
           && AppVolume.shuffleScript("com.spotify.client", on: false) == #"tell application id "com.spotify.client" to set shuffling to false"#
           && AppVolume.shuffleScript("com.google.Chrome", on: true) == nil, "setting shuffle")
    expect(AppVolume.repeatScript("com.apple.Music", .one) == #"tell application id "com.apple.Music" to set song repeat to one"#
           && AppVolume.repeatScript("com.apple.Music", .off)?.hasSuffix("song repeat to off") == true
           && AppVolume.repeatScript("com.spotify.client", .all)?.hasSuffix("set repeating to true") == true
           && AppVolume.repeatScript("com.spotify.client", .off)?.hasSuffix("set repeating to false") == true, "setting repeat")
    expect(AppRepeat.off.next(for: "com.apple.Music") == .all && AppRepeat.all.next(for: "com.apple.Music") == .one
           && AppRepeat.one.next(for: "com.apple.Music") == .off, "Music: off → all → one → off")
    expect(AppRepeat.off.next(for: "com.spotify.client") == .all && AppRepeat.all.next(for: "com.spotify.client") == .off,
           "Spotify: on/off only")
    expect(AppModes.parse(shuffle: true, repeatText: "one", repeatFlag: nil) == AppModes(shuffle: true, repeatMode: .one)
           && AppModes.parse(shuffle: false, repeatText: "ALL", repeatFlag: nil).repeatMode == .all
           && AppModes.parse(shuffle: false, repeatText: nil, repeatFlag: true) == AppModes(shuffle: false, repeatMode: .all)
           && AppModes.parse(shuffle: false, repeatText: "bogus", repeatFlag: nil).repeatMode == .off, "reading the answers")
    expect(AppVolume.revealScript("com.apple.Music")?.hasSuffix("to reveal current track") == true && AppVolume.revealScript("com.spotify.client") == nil,
           "double-click reveals the song in Music only")
}
