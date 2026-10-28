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
    expect(adapter.arguments == [adapter.script.path, adapter.framework.path, "stream", "--no-diff", "--debounce=150"], "stream only, full state, paths with spaces intact")
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
    expect(square.art == CGRect(x: 441, y: 213, width: 558, height: 558), "square art: 62% of the height, centred")
    expect(square.caption == CGRect(x: 441, y: 129, width: 558, height: 64), "caption centred under the art")
    expect(square.caption.origin.y + square.caption.size.height + ArtworkLayout.gap == square.art.origin.y, "gap between art and caption")
    let wide = ArtworkLayout.fullScreen(artwork: CGSize(width: 640, height: 360), in: screen)
    expect(wide.art.size == CGSize(width: 992, height: 558) && wide.art.origin.x == 224, "16:9 art keeps its shape")
    let tallScreen = ArtworkLayout.fullScreen(artwork: CGSize(width: 600, height: 600), in: CGSize(width: 800, height: 1200))
    expect(tallScreen.art.size == CGSize(width: 560, height: 560) && tallScreen.caption.size.width == 560, "narrow screen: 70% of the width")
    let small = ArtworkLayout.fullScreen(artwork: CGSize(width: 100, height: 100), in: screen)
    expect(small.caption.size.width == 558 && small.art.size.width == 558, "small art is scaled up to the same spot")
    expect(ArtworkLayout.fullScreen(artwork: .zero, in: screen).art.size == CGSize(width: 558, height: 558), "unknown shape: square")
}
