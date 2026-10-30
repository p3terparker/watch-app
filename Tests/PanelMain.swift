// Appended to a scratch copy of main.swift by panel.py; never compiled into the shipped app.
final class FixturePanel: AppDelegate {
    struct Request {
        let query: String
        let limit: Int
        let task: YtDlpTask
        let done: ([YTVideo]?, String) -> Void
    }
    var requests: [Request] = []
    var plays: [String] = []
    override func performSearch(_ query: String, limit: Int, completion: @escaping ([YTVideo]?, String) -> Void) -> YtDlpTask {
        let task = YtDlpTask()
        requests.append(Request(query: query, limit: limit, task: task, done: completion))
        return task
    }
    override func play(_ raw: String, queue: PlayQueue? = nil) { liveSearch.cancel(); plays.append(raw) }
    // Podcasts (3.22): fixture answers in place of the podcast directory and feeds.
    var podcastSearches: [(query: String, done: ([PodcastShow]?, String) -> Void)] = []
    var episodeFetches: [(link: String, done: (PodcastShow?, [PodcastEpisode], String) -> Void)] = []
    var episodeLookups: [String] = []
    var episodeAnswer: PodcastEpisode?
    override func performPodcastSearch(_ query: String, completion: @escaping ([PodcastShow]?, String) -> Void) {
        podcastSearches.append((query, completion))
    }
    override func fetchEpisodes(_ link: String, completion: @escaping (PodcastShow?, [PodcastEpisode], String) -> Void) {
        episodeFetches.append((link, completion))
    }
    override func resolveEpisode(_ link: String, completion: @escaping (PodcastEpisode?) -> Void) {
        episodeLookups.append(link); completion(episodeAnswer)
    }
    // Your Music library (3.23): fixture answers in place of Music.
    var librarySearches: [(query: String, done: (LibraryAnswer) -> Void)] = []
    override func performLibrarySearch(_ query: String, completion: @escaping (LibraryAnswer) -> Void) {
        librarySearches.append((query, completion))
    }
}
let testApp = NSApplication.shared
// Do not assign an application delegate or run applicationDidFinishLaunching.
testApp.setActivationPolicy(.prohibited)
let suite = "glasskit-watch-panel-tests-\(ProcessInfo.processInfo.processIdentifier)"
let fixtureDefaults = UserDefaults(suiteName: suite)!
fixtureDefaults.removePersistentDomain(forName: suite)
var checkCount = 0
var failureCount = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checkCount += 1
    if !condition() { failureCount += 1; print("FAIL: \(message)") }
}
func pump(_ seconds: TimeInterval = 0.05) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
let cancelledTask = YtDlpTask()
cancelledTask.cancel()
let neverStarted = Process()
neverStarted.executableURL = URL(fileURLWithPath: "/usr/bin/true")
check(try! !cancelledTask.launch(neverStarted), "cancel before launch prevents process creation")
let runningTask = YtDlpTask()
let sleeper = Process()
sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
sleeper.arguments = ["3"]
check(try! runningTask.launch(sleeper), "fixture process launches")
runningTask.cancel(); sleeper.waitUntilExit()
check(!sleeper.isRunning && sleeper.terminationReason == .uncaughtSignal, "cancellation terminates launched fixture process")
let panel = FixturePanel()
panel.setupPanel()
panel.dropdown.appearance = NSAppearance(named: .darkAqua)
let size = panel.dropdown.frame.size
func layout() { panel.dropdown.contentView!.layoutSubtreeIfNeeded(); pump() }
func rows(_ stack: NSStackView) -> [BrowseRowView] { stack.arrangedSubviews.compactMap { $0 as? BrowseRowView } }
func type(_ text: String) {
    panel.searchField.stringValue = text
    panel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: panel.searchField))
}
func snapshot(_ name: String) {
    layout()
    let view = panel.dropdown.contentView!
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}
func video(_ n: Int) -> YTVideo {
    YTVideo(url: "https://fixtures.invalid/clip\(n).mp4", title: "Fixture video \(n)", thumbnail: nil, channel: "Fixture channel", views: 1000, duration: 150)
}
for n in 1...100 {
    let v = video(n)
    panel.links.add(v.url)
    panel.links.update(v.url, with: LinkInfo(title: v.title, duration: v.duration))
    if n <= 12 { panel.favourites.add(v.url, info: LinkInfo(title: v.title, duration: v.duration)) }
}
panel.rebuildClipSection(); layout()
check(rows(panel.clipSection).count == 100, "all 100 recent links are present at initial size")
check(size.width == 320 && size.height == 250, "existing 320x250 window size")
check(panel.mainScroll.documentView!.frame.height > panel.mainScroll.contentSize.height, "full list exceeds viewport")
snapshot("recent-top")
let last = rows(panel.clipSection).last!
last.scrollToVisible(last.bounds); layout()
check(panel.mainScroll.contentView.bounds.minY > 0, "last row can scroll into view")
check(!last.visibleRect.isEmpty, "last row visible")
check(panel.dropdown.frame.size == size, "scrolling does not resize window")
snapshot("recent-bottom")
panel.showFavouritesList(); layout()
check(rows(panel.clipSection).count == 12, "all favourites present")
check(panel.mainScroll.contentView.bounds.minY == 0, "tab switch resets scroll")
check(panel.dropdown.frame.size == size, "tab switch keeps size")
snapshot("favourites")
panel.showRecentList()
panel.dropdown.makeFirstResponder(panel.searchField)
let fieldEditor = panel.searchField.currentEditor()
check(fieldEditor != nil, "search field obtains an editor")
// Delegate callbacks and the real main-queue debounce, without a network service.
type("ca"); pump(0.1); type("cats")
check(panel.requests.isEmpty, "no immediate request while typing")
pump(0.42)
check(panel.requests.map(\.query) == ["cats"], "typing launches one debounced search without Return")
check(RecentSearches.shared.all.isEmpty, "automatic search does not store partial history")
let old = panel.requests[0]
type("dogs")
check(old.task.isCancelled, "editing cancels the active task immediately")
old.done([video(1)], "")
check(panel.browseStack.isEmpty, "late result cannot repaint during debounce")
check(panel.searchCache.value(for: "cats") == nil, "late result cannot cache")
pump(0.42)
check(panel.requests.last?.query == "dogs", "new query starts")
panel.requests.last!.done((1...18).map(video), "")
check(rows(panel.browseList).count == 18, "results rendered")
check(panel.searchField.currentEditor() === fieldEditor, "rendering results preserves field editor")
check(panel.dropdown.frame.size == size, "search does not resize panel")
snapshot("search-results")
let count = panel.requests.count
panel.submitField(); pump(0.42)
check(panel.requests.count == count, "Return does not duplicate completed live search")
check(RecentSearches.shared.all == ["dogs"], "explicit Return remembers the query")
let editor = NSTextView()
_ = panel.control(panel.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
_ = panel.control(panel.searchField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
check(panel.plays == [video(1).url], "arrow + Return plays selected result")
let more = NSButton(title: "Show More Results", target: nil, action: nil)
panel.loadMoreResults(more)
check(panel.requests.last?.limit == 36, "Show More requests next page")
panel.requests.last!.done((1...36).map(video), "")
check(rows(panel.browseList).count == 36, "Show More appends without duplicates")
// Cancel field action must return home, never play clipboard.
panel.searchField.stringValue = ""; panel.searchFieldAction(panel.searchField)
check(panel.browseStack.isEmpty && rows(panel.clipSection).count == 100, "clear returns full recent list")
check(panel.plays.count == 1, "clear never plays anything")
type("Fixture")
let localBefore = panel.requests.count
_ = panel.control(panel.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
pump(0.42)
check(panel.requests.count == localBefore && panel.highlighted == 0, "keyboard local selection is not replaced by pending search")
type("instant"); panel.submitField()
let instant = panel.requests.last!
check(instant.query == "instant", "Return bypasses debounce")
let instantCount = panel.requests.count
panel.submitField(); pump(0.42)
check(panel.requests.count == instantCount, "Return during running search does not duplicate")
_ = panel.control(panel.searchField, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
check(instant.task.isCancelled && panel.browseStack.isEmpty && panel.searchField.stringValue.isEmpty, "Escape clears and cancels")
instant.done([video(2)], "")
check(panel.browseStack.isEmpty, "Escape rejects late result")
for input in ["https://youtu.be/example", "https://youtube.com/playlist?list=fixture", "/tmp/uncreated.mp4", "~/Movies/uncreated.mp4", "file:///tmp/a.mp4"] {
    let before = panel.requests.count
    type("pending"); type(input); pump(0.42)
    check(panel.requests.count == before, "link/path never auto-searches: \(input)")
}
let beforeComposition = panel.requests.count
panel.searchField.stringValue = "日本"
panel.fieldTextChanged(composing: true); pump(0.42)
check(panel.requests.count == beforeComposition, "IME composition waits")
panel.fieldTextChanged(); pump(0.42)
check(panel.requests.last?.query == "日本", "committed IME text searches")
panel.requests.last!.done([], "")
check(rows(panel.browseList).isEmpty, "empty search has no stale rows")
snapshot("empty-search")
type("offline"); panel.submitField()
panel.requests.last!.done(nil, YtDlp.timedOutError)
if case .message(_, let message, _)? = panel.browseStack.last?.page {
    check(message.contains("time"), "timeout explains failure")
} else { check(false, "timeout renders error page") }
snapshot("timeout")
panel.reloadPage()
check(panel.requests.last?.query == "offline", "retry uses same query")
panel.requests.last!.done([video(3)], "")
panel.browseBack()
let beforeCache = panel.requests.count
type("offline"); panel.submitField()
check(panel.requests.count == beforeCache && rows(panel.browseList).count == 1, "cached repeat needs no request")
type("back pending"); panel.browseBack(); pump(0.42)
check(panel.requests.count == beforeCache, "Back cancels pending debounce")
type("hide pending"); panel.minimizeToMenuBar(); pump(0.42)
check(panel.requests.count == beforeCache, "hide cancels pending debounce")
type("hide running"); panel.submitField()
let hidden = panel.requests.last!
panel.minimizeToMenuBar()
check(hidden.task.isCancelled, "hide cancels in-flight search")
hidden.done([video(4)], "")
check(panel.browseStack.isEmpty, "hidden completion cannot recreate page")
check(panel.dropdown.frame.size == size, "all interactions preserve panel dimensions")
// Native cancel button dispatches its action through the actual search field cell.
panel.searchField.stringValue = ""
panel.searchFieldAction(panel.searchField)
// Now Playing: fixture updates go straight to the panel; this harness has no adapter, so no perl process runs.
func artwork(_ width: Int, _ height: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemPink.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSColor.systemIndigo.setFill(); NSRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
func nowPlayingFixture(_ title: String, _ art: Data?, playing: Bool = true) -> NowPlayingInfo {
    NowPlayingInfo(title: title, artist: "Fixture Artist", album: "Fixture Album", bundleID: "com.apple.Music", isPlaying: playing,
                   artwork: art, artworkMIME: art == nil ? nil : "image/png")
}
func texts(_ view: NSView) -> [String] { ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap(texts) }
// Music/Spotify without Apple Events: records what Watch would set or send, and hands over fixture artwork.
final class FixtureMusicApp: MusicAppControl {
    var sets: [Double] = []
    var performed: [(request: NowPlayingRequest, app: String)] = []
    var artworkAsked: [String] = []
    var artworkReply: Data?
    override func check(_ bundleID: String, completion: @escaping (AppVolumeAccess, Double?) -> Void) {
        completion(AppVolume.supported.contains(bundleID) ? .granted : .unsupported, 0.4)
    }
    override func requestAccess(_ bundleID: String, completion: @escaping (AppVolumeAccess) -> Void) { completion(.granted) }
    override func set(_ bundleID: String, _ level: Double) { sets.append(level) }
    override func perform(_ request: NowPlayingRequest, bundleID: String, completion: @escaping (Bool) -> Void) {
        performed.append((request, bundleID)); completion(true)
    }
    override func artwork(_ bundleID: String, completion: @escaping (Data?) -> Void) { artworkAsked.append(bundleID); completion(artworkReply) }
    // Shuffle/repeat: the scripts Watch would run, applied to what the fixture app then reports, as the real app would.
    var modeScripts: [String] = []
    var modesReply = AppModes(shuffle: false, repeatMode: .off)
    var revealed: [String] = []
    override func modes(_ bundleID: String, completion: @escaping (AppModes?) -> Void) {
        completion(AppVolume.supported.contains(bundleID) ? modesReply : nil)
    }
    override func setMode(_ script: String?, bundleID: String, completion: @escaping (Bool) -> Void) {
        guard let script = script else { completion(false); return }
        modeScripts.append(script)
        if script.contains("shuffle enabled to") || script.contains("shuffling to") { modesReply.shuffle = script.hasSuffix("true") }
        for mode in [AppRepeat.off, .all, .one] where script.hasSuffix("song repeat to \(mode.rawValue)") { modesReply.repeatMode = mode }
        if script.contains("set repeating to") { modesReply.repeatMode = script.hasSuffix("true") ? .all : .off }
        completion(true)
    }
    override func reveal(_ bundleID: String) { revealed.append(bundleID) }
    // 3.26: Apple Music's ★ — what the fixture app reports, and what Watch set (never the real app).
    var favouriteReply = false
    var favouriteSets: [Bool] = []
    override func favourite(_ bundleID: String, completion: @escaping (Bool?) -> Void) {
        completion(AppVolume.favouriteApps.contains(bundleID) ? favouriteReply : nil)
    }
    override func setFavourite(_ on: Bool, bundleID: String, completion: @escaping (Bool) -> Void) {
        guard AppVolume.favouriteApps.contains(bundleID) else { completion(false); return }
        favouriteSets.append(on); favouriteReply = on; completion(true)
    }
    // 3.24: Watch pausing/resuming the app for its own playback (never asks). Off unless a check turns it on, so the
    // other checks' command counts stay as they were.
    var recordsAllowed = false
    override func performIfAllowed(_ request: NowPlayingRequest, bundleID: String, completion: @escaping (Bool) -> Void) {
        guard recordsAllowed else { completion(false); return }
        performed.append((request, bundleID)); completion(true)
    }
    var playedScripts: [(script: String, app: String)] = []
    var spotifyScripts: [String] { playedScripts.filter { $0.app == SpotifyLink.bundleID }.map { $0.script } }
    override func playScript(_ script: String, app id: String, completion: @escaping (Bool) -> Void) {
        playedScripts.append((script, id)); completion(true)
    }
}
let fixtureMusic = FixtureMusicApp()
panel.musicControl = fixtureMusic
// Real events through PlayerSurfaceView: a single click is its mouseDown waiting on the event queue for the mouse-up
// (click vs drag); the later clicks of a quick run arrive with their click count.
func mouse(_ type: NSEvent.EventType, _ view: NSView, _ point: NSPoint, clicks: Int) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                       windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
}
func click(_ view: PlayerSurfaceView, at point: NSPoint) {
    testApp.postEvent(mouse(.leftMouseUp, view, point, clicks: 1), atStart: false)
    guard testApp.nextEvent(matching: .leftMouseUp, until: Date().addingTimeInterval(1), inMode: .eventTracking, dequeue: false) != nil else {
        check(false, "a posted mouse-up reaches the event queue"); return
    }
    view.mouseDown(with: mouse(.leftMouseDown, view, point, clicks: 1))
}
func multiClick(_ view: PlayerSurfaceView, at point: NSPoint, clicks: Int) { view.mouseDown(with: mouse(.leftMouseDown, view, point, clicks: clicks)) }
func key(_ view: NSView, _ code: UInt16, _ characters: String) {
    view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: view.window!.windowNumber, context: nil, characters: characters,
                                        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!)
}
func waitFor(_ seconds: TimeInterval, _ done: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !done() && Date() < end { pump(0.05) }
    return done()
}
// The music window's controls come up after a short dwell on the caption (3.25): hover there and wait for them, then for their
// animation to settle (snapshots).
func revealControls(_ window: ArtworkWindowController?) -> Bool {
    guard let window = window else { return false }
    window.pointerMoved(at: NSPoint(x: window.surface.bounds.midX, y: 30))
    let shown = waitFor(3) { window.controlsRevealed && window.controls.alphaValue > 0.9 }
    pump(ArtworkWindowController.revealDuration + 0.1)
    return shown
}
let square = artwork(600, 600), wide = artwork(640, 360)
check(panel.nowPlayingRow.isHidden, "no Now Playing row while nothing plays")
panel.nowPlayingChanged(nowPlayingFixture("Fixture Song", square)); layout()
check(!panel.nowPlayingRow.isHidden && rows(panel.nowPlayingRow).count == 1, "Now Playing row appears")
check((panel.nowPlayingRow.superview as? NSStackView)?.arrangedSubviews.first === panel.nowPlayingRow, "row sits above the list tabs")
check(rows(panel.clipSection).count == 100, "the row stays out of the list (and ↑/↓)")
check(texts(panel.nowPlayingRow).contains("Fixture Song"), "row shows the title")
snapshot("now-playing")
panel.nowPlayingChanged(nowPlayingFixture("Fixture Song", square, playing: false)); layout()
check(texts(panel.nowPlayingRow).contains { $0.hasPrefix("Fixture Artist") && $0.hasSuffix("Paused") }, "paused state shown")
let rowMenu = rows(panel.nowPlayingRow).first?.onMenu?()?.items.map(\.title) ?? []
check(rowMenu.prefix(2) == ["Open Artwork", "Open Full Screen"] && rowMenu.contains("Save Artwork…") && rowMenu.contains("Search YouTube for “Fixture Song”"), "row menu")
type("Fixture")
check(panel.nowPlayingRow.isHidden, "hidden while the field filters")
panel.searchField.stringValue = ""; panel.searchFieldAction(panel.searchField)
check(!panel.nowPlayingRow.isHidden, "back when the field clears")
Prefs.showNowPlaying = false; panel.nowPlayingSettingsChanged()
check(panel.nowPlayingRow.isHidden, "Preference off hides the row")
Prefs.showNowPlaying = true; panel.nowPlayingSettingsChanged()
check(!panel.nowPlayingRow.isHidden, "Preference on shows it again")
// 3.26: the menu-bar ticker — off by default; on, one line "Song – Artist" in its own status item (still while paused or when it
// fits, scrolling when it doesn't), gone with the song and with the preference.
check(!Prefs.showTicker && panel.ticker == nil, "the menu-bar ticker is off by default")
Prefs.showTicker = true; panel.tickerSettingChanged()
check(panel.ticker?.isShowing == true && panel.ticker?.text == "Fixture Song – Fixture Artist", "on: the paused song, one line (\(String(describing: panel.ticker?.text)))")
check(panel.ticker?.isScrolling == false && panel.ticker?.marquee?.scrolls == false, "…short and paused, so it stands still")
let longTitle = "A Very Long Song Title That Could Not Possibly Fit In A Small Menu Bar Window At Once"
panel.nowPlayingChanged(nowPlayingFixture(longTitle, square)); pump(0.1)
check(panel.ticker?.text == longTitle + " – Fixture Artist" && panel.ticker?.marquee?.scrolls == true && panel.ticker?.marquee?.window == Marquee.maxWidth,
      "a long title is cut to a 150 pt window")
check(panel.ticker?.isScrolling == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "…and scrolls while it plays (unless Reduce Motion is on)")
panel.nowPlayingChanged(nowPlayingFixture(longTitle, square, playing: false)); pump(0.1)
check(panel.ticker?.isScrolling == false, "…and stops while paused")
panel.nowPlayingChanged(nowPlayingFixture("Fixture Song", square, playing: false)); pump(0.1)
Prefs.showTicker = false; panel.tickerSettingChanged()
check(panel.ticker == nil, "off again: the item is gone")
panel.openArtwork(); pump(0.3)
let viewer = panel.artworkWindow!
check(viewer.musicApp === fixtureMusic, "the music window controls Music/Spotify through the app's own MusicAppControl")
let opened = viewer.window.frame
check(viewer.window.isVisible && opened.width == opened.height, "artwork window opens square for square art")
check(opened.width >= ArtworkWindowController.minSide && opened.width <= ArtworkWindowController.maxSide, "opens at the artwork's own size, within limits")
func viewerSnapshot(_ name: String) {
    let view = viewer.window.contentView!
    view.layoutSubtreeIfNeeded(); pump()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png"))
}
viewerSnapshot("artwork-window")
let viewerMenu = viewer.makeMenu()
check(viewerMenu.items.map(\.title).prefix(2) == ["Close", "Enter Full Screen"], "window menu offers full screen")
let backgroundMenu = viewerMenu.items.first { $0.title == "Full-Screen Background" }?.submenu
check(backgroundMenu?.items.map(\.title) == ["Artwork Colours", "Black"] && backgroundMenu?.items.first?.state == .on, "background choice, colours by default")
let fixtureColours = ArtworkWindowController.palette(NSImage(data: square)!)
check(fixtureColours != nil && fixtureColours!.0 != fixtureColours!.1, "two colours picked from the pink/indigo fixture")
check(viewer.backgroundColours != nil, "artwork-coloured background in use")
func choose(_ item: NSMenuItem?) { if let item = item, let action = item.action { _ = (item.target as AnyObject?)?.perform(action, with: item) } }
choose(backgroundMenu?.items.last)
check(!Prefs.artworkColourBackground && viewer.backgroundColours == nil, "Black background chosen and remembered")
choose(viewer.makeMenu().items.first { $0.title == "Full-Screen Background" }?.submenu?.items.first)
check(Prefs.artworkColourBackground && viewer.backgroundColours != nil, "back to artwork colours")
panel.nowPlayingChanged(nowPlayingFixture("Second Song", wide)); pump(0.5)
let followed = viewer.window.frame
check(viewer.pictureData == wide && viewer.info?.title == "Second Song", "window follows the next track")
check(abs(followed.width / followed.height - 16.0 / 9.0) < 0.02 && abs(followed.maxY - opened.maxY) < 1 && followed.minX == opened.minX,
      "aspect follows the artwork, top-left corner kept")
panel.nowPlayingChanged(nowPlayingFixture("Third Song", nil))
check(viewer.pictureData == wide, "a track without artwork keeps the old picture for a moment")
pump(ArtworkWindowController.placeholderDelay + 0.3)
check(viewer.pictureData == nil, "then the app's icon stands in")
// Playback controls (3.25): hovering anywhere shows the caption, but the controls come up only after a short dwell on the caption
// or just above it, and go a moment after the pointer leaves; they send requests only when clicked (recorded here).
let appRouting = viewer.onCommand               // AppDelegate's: Music/Spotify addressed by AppleScript (fixtureMusic here)
var sent: [NowPlayingRequest] = []
viewer.onCommand = { sent.append($0) }
var timedSong = nowPlayingFixture("Timed Song", square)
timedSong.duration = 200; timedSong.elapsed = 50; timedSong.elapsedAt = Date(); timedSong.rate = 1
panel.nowPlayingChanged(timedSong); pump(0.5)
let area = viewer.window.contentView!.bounds
let revealZone = ArtworkLayout.revealZone(window: area.size, revealed: false), keepZone = ArtworkLayout.revealZone(window: area.size, revealed: true)
check(revealZone.height > ArtworkLayout.windowBand && keepZone.height > revealZone.height && keepZone.maxY + 10 < area.height,
      "the window leaves room above the reveal and keep zones (\(area.size), \(revealZone), \(keepZone))")
viewer.pointerMoved(at: nil); _ = waitFor(2) { !viewer.chromeVisible && !viewer.controlsRevealed }     // start with the pointer away
viewer.pointerMoved(at: NSPoint(x: area.midX, y: area.maxY - 20))
check(viewer.chromeVisible, "hovering anywhere over the window shows the caption and the buttons")
pump(ArtworkWindowController.revealDwell + 0.3)
check(!viewer.controlsRevealed && viewer.controls.alphaValue < 0.05, "…but not the playback controls: the pointer isn't on the caption (\(viewer.controls.alphaValue))")
viewer.pointerMoved(at: NSPoint(x: area.midX, y: revealZone.maxY + 6))
pump(ArtworkWindowController.revealDwell + 0.3)
check(!viewer.controlsRevealed, "just beyond the reach above the caption: still not")
viewer.pointerMoved(at: NSPoint(x: area.midX, y: 28)); viewer.pointerMoved(at: NSPoint(x: area.midX, y: area.maxY - 20))
pump(ArtworkWindowController.revealDwell + 0.3)
check(!viewer.controlsRevealed, "a quick sweep across the caption, gone before the dwell, doesn't flash the controls")
timedSong.elapsedAt = Date(); panel.nowPlayingChanged(timedSong)     // the timeline check below counts from here, not from before the waits
let approach = Date()
viewer.pointerMoved(at: NSPoint(x: area.midX, y: revealZone.maxY - 4))
check(!viewer.controlsRevealed, "just above the caption they wait out a short dwell first")
check(waitFor(3) { viewer.controlsRevealed && viewer.controls.alphaValue > 0.9 }, "…then come up, as the pointer approaches the text")
check(Date().timeIntervalSince(approach) >= ArtworkWindowController.revealDwell - 0.02, "…not before the dwell")
check(viewer.chromeVisible, "the caption stays")
pump(ArtworkWindowController.revealDuration + 0.1)
check(!viewer.controls.volumeIcon.isHidden && abs(viewer.controls.volume.value - 0.4) < 0.001, "Music's own volume shows its level (the slider itself is in a pop-up)")
check(abs(viewer.controls.timeline.value - 0.25) < 0.02, "timeline at the reported position")
// One row under the caption: ⏮ ⏯ ⏭ from the left, the timeline, then Music's own shuffle/repeat and its volume.
let musicRow = viewer.controls
check(musicRow.frame.minY == 6 && musicRow.frame.height == ArtworkLayout.controlsHeight, "the controls are one row along the bottom (\(musicRow.frame))")
check(!musicRow.previous.isHidden && musicRow.previous.frame.minX == 0 && musicRow.previous.frame.maxX < musicRow.playPause.frame.minX
      && musicRow.playPause.frame.maxX < musicRow.next.frame.minX && musicRow.next.frame.maxX < musicRow.timeline.frame.minX, "⏮ ⏯ ⏭ left of the timeline")
check(!musicRow.shuffle.isHidden && !musicRow.repeatButton.isHidden && !musicRow.favourite.isHidden && musicRow.timeline.frame.maxX < musicRow.favourite.frame.minX
      && musicRow.favourite.frame.maxX < musicRow.shuffle.frame.minX && musicRow.repeatButton.frame.maxX < musicRow.volumeIcon.frame.minX
      && musicRow.volumeIcon.frame.maxX == musicRow.bounds.width, "★, shuffle, repeat, then the speaker at the right edge")
let contentView = viewer.window.contentView!
check(!musicRow.volumeOpen && musicRow.volumePopup.superview === contentView && musicRow.volumePopup.alphaValue < 0.05
      && musicRow.volumePopup.hitTest(NSPoint(x: musicRow.volumePopup.frame.midX, y: musicRow.volumePopup.frame.midY)) == nil,
      "the volume slider is always hidden until the pointer is on the speaker (its pop-up sits beside the row, in the window)")
check([musicRow.previous, musicRow.playPause, musicRow.next, musicRow.timeline, musicRow.favourite, musicRow.shuffle, musicRow.repeatButton, musicRow.volumeIcon]
      .allSatisfy { abs($0.frame.midY - musicRow.playPause.frame.midY) <= 1 }, "everything on the same line")
viewerSnapshot("artwork-controls")
// 3.26 ★: Apple Music's own favourite flag, read when the controls come up and set in the background by a click — Music isn't
// brought forward, and Watch's own Favourites list (the right-click menu) is untouched.
check(viewer.isFavourite == false && fixtureMusic.favouriteSets.isEmpty, "the ★ reads Music's flag (off) and sets nothing by itself")
let favouritesBefore = Favourites.shared.all().count
musicRow.favourite.performClick(nil); pump(0.1)
check(fixtureMusic.favouriteSets == [true] && viewer.isFavourite == true, "★ favourites the song in Music")
musicRow.favourite.performClick(nil); pump(0.1)
check(fixtureMusic.favouriteSets == [true, false] && viewer.isFavourite == false, "…and a second click removes it")
check(Favourites.shared.all().count == favouritesBefore && fixtureMusic.revealed.isEmpty, "Watch's own Favourites list is separate, and Music stays where it was")
fixtureMusic.favouriteReply = true
viewer.show(timedSong); musicRow.pointerMoved(at: nil); pump(0.05)
var nextSong = timedSong; nextSong.title = "Another Song"; viewer.show(nextSong); pump(0.1)
check(viewer.isFavourite == true, "a new song reads its own flag (\(String(describing: viewer.isFavourite)))")
fixtureMusic.favouriteReply = false; viewer.show(timedSong); pump(0.1)
check(viewer.isFavourite == false, "…and back")
// 🔀 🔁 set Music's own shuffle and repeat (never Watch's queue), lit while on.
check(musicRow.shuffle.lit == false && musicRow.repeatButton.lit == false, "Music's shuffle and repeat read as off")
musicRow.shuffle.performClick(nil); pump(0.1)
check(fixtureMusic.modeScripts.last?.hasSuffix("set shuffle enabled to true") == true && musicRow.shuffle.lit == true, "🔀 turns Music's shuffle on")
musicRow.repeatButton.performClick(nil); pump(0.1)
check(fixtureMusic.modeScripts.last?.hasSuffix("set song repeat to all") == true && musicRow.repeatButton.lit == true, "🔁 repeats all")
musicRow.repeatButton.performClick(nil); pump(0.1)
check(fixtureMusic.modeScripts.last?.hasSuffix("set song repeat to one") == true && viewer.appModes?.repeatMode == .one, "then this song")
musicRow.repeatButton.performClick(nil); musicRow.shuffle.performClick(nil); pump(0.1)
check(viewer.appModes == AppModes(shuffle: false, repeatMode: .off) && musicRow.repeatButton.lit == false && musicRow.shuffle.lit == false
      && fixtureMusic.modeScripts.count == 5, "then off again; one script per click")
viewer.controls.playPause.performClick(nil)
check(sent == [.command(.pause)] && viewer.info?.isPlaying == false, "play/pause on a playing track sends pause and shows paused at once")
viewer.controls.next.performClick(nil)
viewer.controls.previous.performClick(nil)
check(sent.suffix(2) == [.command(.next), .command(.previous)], "next and previous")
viewer.controls.timeline.onChange?(0.5, true)
check(sent.last == .seek(100), "letting go of the timeline halfway seeks to half the length")
viewer.controls.volume.onChange?(0.7, true)
check(fixtureMusic.sets.last == 0.7, "the volume slider sets the app's own volume")
// 3.26: the slider is hidden unless the pointer is on the speaker, then pops up above it; a click mutes, a drag up or down from the
// speaker moves the volume from where it is — the pointer needn't be on the slider.
let speaker = NSPoint(x: musicRow.volumeIcon.frame.midX, y: musicRow.volumeIcon.frame.midY)
musicRow.pointerMoved(at: NSPoint(x: musicRow.timeline.frame.midX, y: speaker.y))
check(!musicRow.volumeOpen, "the pointer elsewhere on the row leaves the slider hidden")
musicRow.pointerMoved(at: speaker); pump(0.3)
let popupFrame = musicRow.volumePopup.frame, speakerInWindow = musicRow.convert(musicRow.volumeIcon.frame, to: contentView)
check(musicRow.volumeOpen && musicRow.volumePopup.alphaValue > 0.9, "on the speaker the slider pops up")
check(popupFrame.minY >= speakerInWindow.maxY && popupFrame.height > popupFrame.width && abs(popupFrame.midX - speakerInWindow.midX) <= 14 && contentView.bounds.contains(popupFrame),
      "…above the speaker, upright, inside the window (\(popupFrame) over \(speakerInWindow))")
check(musicRow.volume.vertical && musicRow.volume.relative && musicRow.volumePopup.slider === musicRow.volume, "…a vertical slider that drags from where it is")
let upOnto = musicRow.convert(NSPoint(x: popupFrame.midX, y: popupFrame.midY), from: contentView)
musicRow.pointerMoved(at: upOnto); pump(ArtworkControlsView.volumeCloseDelay + 0.3)
check(musicRow.volumeOpen, "moving up from the speaker onto the panel keeps it up")
musicRow.volume.value = 0.7        // the callback above doesn't move the slider itself; a real drag would have
musicRow.volumeIcon.onDragStart?(); musicRow.volumeIcon.onDrag?(8, false)
check(abs((fixtureMusic.sets.last ?? 0) - 0.8) < 0.001 && abs(musicRow.volume.value - 0.8) < 0.001, "dragging up from the speaker raises the volume from 70% by 1/80 per point")
musicRow.volumeIcon.onDrag?(-8, true)
check(abs((fixtureMusic.sets.last ?? 0) - 0.6) < 0.001, "pulling back unwinds it, measured from the press: \(String(describing: fixtureMusic.sets.last))")
musicRow.volumeIcon.performClick(nil); pump(0.1)
check(fixtureMusic.sets.last == 0 && musicRow.volume.value == 0, "a click on the speaker mutes")
musicRow.volumeIcon.performClick(nil); pump(0.1)
check(abs((fixtureMusic.sets.last ?? 0) - 0.6) < 0.001, "…and the next unmutes to where it was")
musicRow.pointerMoved(at: NSPoint(x: musicRow.timeline.frame.midX, y: speaker.y))
check(waitFor(2) { !musicRow.volumeOpen && musicRow.volumePopup.alphaValue < 0.05 }, "off the speaker and the panel it goes again")
// …at any window size: the speaker stays in the row and the panel fits above it, even in a small window (a stand-alone row, so the
// live music window's size — which later checks rely on — stays as it is).
let smallHost = NSView(frame: NSRect(x: 0, y: 0, width: 150, height: 90))
let smallRow = ArtworkControlsView(frame: NSRect(x: 12, y: 6, width: 126, height: ArtworkLayout.controlsHeight))
smallHost.addSubview(smallRow)
smallRow.setVolume(access: .granted, appName: "Music")
let smallSpeaker = NSPoint(x: smallRow.volumeIcon.frame.midX, y: smallRow.volumeIcon.frame.midY)
check(!smallRow.volumeIcon.isHidden && smallRow.volumePopup.superview === smallHost, "in a 150 pt window the speaker is still in the row")
smallRow.pointerMoved(at: smallSpeaker); pump(0.3)
check(smallRow.volumeOpen && smallRow.volumePopup.alphaValue > 0.9 && smallHost.bounds.contains(smallRow.volumePopup.frame)
      && smallRow.volumePopup.frame.minY >= smallRow.frame.maxY,
      "…and the slider pops up above it, inside the window (\(smallRow.volumePopup.frame) in \(smallHost.bounds))")
smallRow.collapseVolume()
check(!smallRow.volumeOpen && smallRow.volumePopup.alphaValue < 0.05, "and goes with the controls")
// The real mouse paths: DragButton (click vs drag) and a relative ThinSlider, driven with events.
final class ClickCounter: NSObject { var hits = 0; @objc func hit() { hits += 1 } }
let counter = ClickCounter()
let probe = DragButton(frame: NSRect(x: 4, y: 40, width: 20, height: 20))
probe.target = counter; probe.action = #selector(ClickCounter.hit)
var probeDrags: [(CGFloat, Bool)] = [], probeStarts = 0
probe.onDragStart = { probeStarts += 1 }
probe.onDrag = { probeDrags.append(($0, $1)) }
viewer.window.contentView!.addSubview(probe)
let probeMid = NSPoint(x: 10, y: 10)
probe.mouseDown(with: mouse(.leftMouseDown, probe, probeMid, clicks: 1))
probe.mouseDragged(with: mouse(.leftMouseDragged, probe, NSPoint(x: 12, y: 10), clicks: 1))
probe.mouseUp(with: mouse(.leftMouseUp, probe, NSPoint(x: 12, y: 10), clicks: 1))
check(counter.hits == 1 && probeStarts == 0 && probeDrags.isEmpty, "a press that moves under 3 pt is a click")
probe.mouseDown(with: mouse(.leftMouseDown, probe, probeMid, clicks: 1))
probe.mouseDragged(with: mouse(.leftMouseDragged, probe, NSPoint(x: 20, y: 10), clicks: 1))
check(probeStarts == 1 && probe.isDragging && probeDrags.count == 1 && abs(probeDrags[0].0 - 10) < 0.01 && !probeDrags[0].1, "moving sideways starts a drag")
probe.mouseDragged(with: mouse(.leftMouseDragged, probe, NSPoint(x: 6, y: 10), clicks: 1))
probe.mouseUp(with: mouse(.leftMouseUp, probe, NSPoint(x: 6, y: 10), clicks: 1))
check(counter.hits == 1 && probeStarts == 1 && !probe.isDragging && probeDrags.count == 3 && abs(probeDrags[2].0 + 4) < 0.01 && probeDrags[2].1,
      "…reported as the distance from the press, ending with finished and no click")
probe.removeFromSuperview()
let probeSlider = ThinSlider(frame: NSRect(x: 4, y: 40, width: 108, height: 18))
probeSlider.relative = true; probeSlider.value = 0.5
var sliderEvents: [(Double, Bool)] = []
probeSlider.onChange = { sliderEvents.append(($0, $1)) }
viewer.window.contentView!.addSubview(probeSlider)
probeSlider.mouseDown(with: mouse(.leftMouseDown, probeSlider, NSPoint(x: 8, y: 9), clicks: 1))
check(probeSlider.value == 0.5 && sliderEvents.isEmpty, "pressing a relative slider far from its knob doesn't move it")
probeSlider.mouseDragged(with: mouse(.leftMouseDragged, probeSlider, NSPoint(x: 28, y: 9), clicks: 1))
check(abs(probeSlider.value - 0.7) < 0.001 && sliderEvents.last?.1 == false, "dragging 20 pt of a 100 pt line moves it 20%, from where it was")
probeSlider.mouseUp(with: mouse(.leftMouseUp, probeSlider, NSPoint(x: 28, y: 9), clicks: 1))
check(abs(probeSlider.value - 0.7) < 0.001 && sliderEvents.last?.1 == true && !probeSlider.isTracking, "letting go keeps it and says it's finished")
probeSlider.mouseDown(with: mouse(.leftMouseDown, probeSlider, NSPoint(x: 90, y: 9), clicks: 1))
probeSlider.mouseUp(with: mouse(.leftMouseUp, probeSlider, NSPoint(x: 90, y: 9), clicks: 1))
check(abs(probeSlider.value - 0.7) < 0.001 && sliderEvents.last?.1 == true, "a plain click on the line leaves it alone")
probeSlider.removeFromSuperview()
// The pop-up's slider runs bottom to top, and the speaker drags up and down.
let upright = ThinSlider(frame: NSRect(x: 4, y: 40, width: 18, height: 108))
upright.vertical = true; upright.relative = true; upright.value = 0.5
var uprightEvents: [(Double, Bool)] = []
upright.onChange = { uprightEvents.append(($0, $1)) }
viewer.window.contentView!.addSubview(upright)
upright.mouseDown(with: mouse(.leftMouseDown, upright, NSPoint(x: 9, y: 8), clicks: 1))
upright.mouseDragged(with: mouse(.leftMouseDragged, upright, NSPoint(x: 9, y: 28), clicks: 1))
check(abs(upright.value - 0.7) < 0.001 && uprightEvents.last?.1 == false, "dragging a vertical slider up 20 pt of its 100 pt line raises it 20%, from where it was")
upright.mouseDragged(with: mouse(.leftMouseDragged, upright, NSPoint(x: 9, y: -12), clicks: 1))
check(abs(upright.value - 0.3) < 0.001, "down lowers it (measured from the press)")
upright.mouseUp(with: mouse(.leftMouseUp, upright, NSPoint(x: 9, y: -12), clicks: 1))
check(abs(upright.value - 0.3) < 0.001 && uprightEvents.last?.1 == true, "letting go keeps it")
upright.removeFromSuperview()
let vertical = DragButton(frame: NSRect(x: 4, y: 40, width: 20, height: 20))
vertical.dragAxis = .vertical
var verticalDrags: [(CGFloat, Bool)] = []
vertical.onDrag = { verticalDrags.append(($0, $1)) }
viewer.window.contentView!.addSubview(vertical)
// A button's own coordinates are flipped (y grows downward), so the events are built from window points: "up" is up on screen.
let pressedAt = vertical.convert(NSPoint(x: 10, y: 10), to: nil)
let movedUp = { (dy: CGFloat, dx: CGFloat) -> NSPoint in vertical.convert(NSPoint(x: pressedAt.x + dx, y: pressedAt.y + dy), from: nil) }
vertical.mouseDown(with: mouse(.leftMouseDown, vertical, movedUp(0, 0), clicks: 1))
vertical.mouseDragged(with: mouse(.leftMouseDragged, vertical, movedUp(1, 20), clicks: 1))
check(verticalDrags.isEmpty, "sideways movement doesn't start a vertical drag")
vertical.mouseDragged(with: mouse(.leftMouseDragged, vertical, movedUp(12, 0), clicks: 1))
check(verticalDrags.count == 1 && abs(verticalDrags[0].0 - 12) < 0.01 && !verticalDrags[0].1,
      "moving up 12 pt on screen starts a drag of +12 (\(verticalDrags))")
vertical.mouseDragged(with: mouse(.leftMouseDragged, vertical, movedUp(-6, 0), clicks: 1))
check(verticalDrags.count == 2 && abs(verticalDrags[1].0 + 6) < 0.01, "moving down below the press is negative (\(verticalDrags))")
vertical.mouseUp(with: mouse(.leftMouseUp, vertical, movedUp(-6, 0), clicks: 1))
check(verticalDrags.count == 3 && verticalDrags[2].1 && abs(verticalDrags[2].0 + 6) < 0.01,
      "…and ends finished on release at the same distance (\(verticalDrags))")
vertical.removeFromSuperview()
// Once up, a larger zone keeps them, so the band growing and the text lifting can't make them flicker.
viewer.pointerMoved(at: NSPoint(x: area.midX, y: revealZone.maxY + 10)); pump(ArtworkWindowController.hideDelay + 0.3)
check(viewer.controlsRevealed, "they stay while the pointer is in the larger keep zone, above where it revealed them")
// Leaving the keep zone takes them away after a moment (not at once); the caption stays while the pointer is over the window.
let leftZone = Date()
viewer.pointerMoved(at: NSPoint(x: area.midX, y: keepZone.maxY + 10))
check(viewer.controlsRevealed, "moving off doesn't snap them away")
check(waitFor(ArtworkWindowController.hideDelay + 3) { !viewer.controlsRevealed }, "they go a moment after the pointer leaves the keep zone")
check(Date().timeIntervalSince(leftZone) >= ArtworkWindowController.hideDelay - 0.05, "…after the delay, not before")
check(waitFor(2) { viewer.controls.alphaValue < 0.05 }, "the controls fade out")
check(viewer.chromeVisible, "the caption stays while the pointer is over the window")
// Back on the caption they return; leaving and coming straight back keeps them (the wait is cancelled).
check(revealControls(viewer), "back on the caption: the controls return")
viewer.pointerMoved(at: nil); viewer.pointerMoved(at: NSPoint(x: 20, y: 20)); pump(ArtworkWindowController.hideDelay + 0.3)
check(viewer.controlsRevealed && viewer.chromeVisible, "coming back before the delay is up keeps them")
viewer.pointerMoved(at: NSPoint(x: area.midX, y: keepZone.maxY + 10)); viewer.pointerMoved(at: NSPoint(x: 20, y: 20)); pump(ArtworkWindowController.hideDelay + 0.3)
check(viewer.controlsRevealed, "…also from above them")
// Leaving the window takes the caption and the controls together, after the delay.
let leftWindow = Date()
viewer.pointerMoved(at: nil)
check(viewer.controlsRevealed && viewer.chromeVisible, "leaving the window doesn't snap them away")
check(waitFor(ArtworkWindowController.hideDelay + 3) { !viewer.controlsRevealed && !viewer.chromeVisible }, "caption and controls go a moment after the pointer leaves the window")
check(Date().timeIntervalSince(leftWindow) >= ArtworkWindowController.hideDelay - 0.05, "…after the delay, not before")
// Videos never take over the music window: a browser tab, a page's WebKit media process or Watch's own player holding
// macOS's single "now playing" slot leaves the song, its picture and its controls where they were.
for (bundle, parent) in [("com.google.Chrome", nil), ("com.apple.WebKit.GPU", "com.apple.Safari"), ("com.apple.WebKit.GPU", nil),
                         ("com.jacob.watch", nil)] as [(String, String?)] {
    var clip = nowPlayingFixture("Video Clip", wide)
    clip.bundleID = bundle; clip.parentBundleID = parent; clip.mediaType = "video"
    panel.nowPlayingChanged(clip); pump(0.1)
    check(viewer.info?.title == "Timed Song" && viewer.pictureData == square && panel.nowPlayingInfo?.title == "Timed Song",
          "a video from \(parent ?? bundle) leaves the music window on the song")
}
check(texts(panel.nowPlayingRow).contains("Timed Song"), "and the panel's Now Playing row")
check(!viewer.controls.playPause.dimmed, "Music stays controllable while a video holds the slot")
// A click goes to Music itself (AppleScript to its bundle id), so it can never pause the video holding the slot. It waits
// out the music window's own short double-click window first (MusicZone, 3.25), so a double-click's first click doesn't
// play/pause.
viewer.onCommand = appRouting
let centre = NSPoint(x: viewer.surface.bounds.midX, y: viewer.surface.bounds.midY)
check(viewer.clickDelay <= MusicZone.doubleClickWindow + MusicZone.clickMargin + 0.001 && viewer.clickDelay < NSEvent.doubleClickInterval + 0.05,
      "the single-click delay is short, under the old interval + 0.05 s (\(viewer.clickDelay))")
let firstClick = Date()
click(viewer.surface, at: centre)
check(fixtureMusic.performed.isEmpty, "a single click waits to be sure it isn't a double-click")
check(waitFor(viewer.clickDelay + 3) { fixtureMusic.performed.count == 1 }, "…then it plays/pauses")
check(Date().timeIntervalSince(firstClick) >= viewer.clickDelay - 0.05, "…not before the window is over")
check(fixtureMusic.performed.last?.request == .command(.play) && fixtureMusic.performed.last?.app == "com.apple.Music",
      "it plays/pauses Music itself: \(fixtureMusic.performed)")
viewer.onCommand = { sent.append($0) }
// The music window's clicks (MusicZone, MusicClicks) and the player's keys.
sent = []
// Waits for each click's result rather than a fixed pause: a busy runner can be late on the delayed single click (3.23 run 1).
click(viewer.surface, at: centre); _ = waitFor(viewer.clickDelay + 2) { !sent.isEmpty }
check(sent == [.command(.pause)] && viewer.info?.isPlaying == false, "a click in the middle pauses: \(sent)")
let corner = NSPoint(x: 6, y: viewer.surface.bounds.height - 6)
click(viewer.surface, at: corner); _ = waitFor(viewer.clickDelay + 2) { sent.count == 2 }
check(sent.last == .command(.play) && viewer.info?.isPlaying == true, "a click anywhere — even a corner — plays")
click(viewer.surface, at: NSPoint(x: centre.x, y: 12)); _ = waitFor(viewer.clickDelay + 2) { sent.count == 3 }
check(sent.count == 3 && sent.last == .command(.pause), "and pauses again (the bottom edge too)")
var openedSources: [String] = []
viewer.onOpenSource = { openedSources.append($0.appBundleID) }
// A real double-click is a click and then another within the window.
click(viewer.surface, at: centre); multiClick(viewer.surface, at: centre, clicks: 2)
check(openedSources == ["com.apple.Music"], "a double-click within the window opens the song in Music")
pump(viewer.clickDelay + 0.15)
check(sent.count == 3, "…without playing/pausing (\(sent))")
// A second click after the window is a fresh single click, though AppKit (its interval is longer) would call it a double-click:
// it plays/pauses and never opens the app.
let side = viewer.surface.bounds.size
let leftSide = NSPoint(x: side.width * 0.05, y: side.height * 0.4), rightSide = NSPoint(x: side.width * 0.95, y: side.height * 0.4)
check(MusicZone.at(leftSide, in: side) == .skipBack && MusicZone.at(rightSide, in: side) == .skipForward, "fixture points sit in the edge strips")
func seekCount() -> Int { sent.filter { if case .seek = $0 { return true }; return false }.count }
let beforeSlow = sent.count
click(viewer.surface, at: centre)
check(waitFor(viewer.clickDelay + 2) { sent.count == beforeSlow + 1 }, "a single click plays/pauses once the window has passed")
multiClick(viewer.surface, at: centre, clicks: 2)
check(openedSources.count == 1, "a second click after the window does not open the app")
check(waitFor(viewer.clickDelay + 2) { sent.count == beforeSlow + 2 }, "…it is a single click of its own and plays/pauses (\(sent))")
let seeksBefore = seekCount()
click(viewer.surface, at: rightSide)
check(waitFor(viewer.clickDelay + 2) { sent.count == beforeSlow + 3 }, "an edge click plays/pauses too")
multiClick(viewer.surface, at: rightSide, clicks: 2)
check(waitFor(viewer.clickDelay + 2) { sent.count == beforeSlow + 4 } && seekCount() == seeksBefore, "a slow second click on an edge is a single click, not a skip (\(sent))")
// Two single clicks in a row, far apart (AppKit counts each as a first click): the first isn't swallowed by the second.
click(viewer.surface, at: leftSide); click(viewer.surface, at: rightSide)
check(waitFor(viewer.clickDelay + 2) { sent.count == beforeSlow + 6 }, "two separate clicks play/pause twice (\(sent))")
pump(viewer.clickDelay + 0.15)
check(sent.count == beforeSlow + 6 && seekCount() == seeksBefore && openedSources.count == 1, "…and nothing more")
pump(ArtworkWindowController.seekHold + 0.1)            // the timeline seek above no longer counts
let from = viewer.info?.position(at: Date()) ?? -100
func seeked(_ expected: Double) -> Bool { if case .seek(let t)? = sent.last { return abs(t - expected) < 0.001 }; return false }
click(viewer.surface, at: rightSide); multiClick(viewer.surface, at: rightSide, clicks: 2)
check(seeked(from + 10), "double-click the right edge: +10 s (\(from) → \(String(describing: sent.last)))")
multiClick(viewer.surface, at: rightSide, clicks: 3)
check(seeked(from + 20), "the next click of the run stacks: +10 s more")
click(viewer.surface, at: leftSide); multiClick(viewer.surface, at: leftSide, clicks: 2)
check(seeked(from + 10), "double-click the left edge: back 10 s")
let inward = NSPoint(x: side.width * 0.25, y: side.height * 0.4)
click(viewer.surface, at: inward); multiClick(viewer.surface, at: inward, clicks: 2)
check(seeked(from + 10) && openedSources.count == 2, "a quarter of the way in, a double-click opens the source instead of skipping")
check(fixtureMusic.revealed.isEmpty, "the harness never reaches a real app")
key(viewer.surface, 124, "\u{F703}")
check(seeked(from + 15), "→ +5 s")
key(viewer.surface, 123, "\u{F702}")
check(seeked(from + 10), "← -5 s")
key(viewer.surface, 49, " ")
check(sent.last == .command(.play) && viewer.info?.isPlaying == true, "space plays")
let sentSoFar = sent.count
// Another audio app takes over the window; its controls work only while it holds the slot (they'd reach the video otherwise).
let episode = NowPlayingInfo(title: "Fixture Episode", artist: "Fixture Show", album: nil, bundleID: "com.apple.podcasts", isPlaying: true,
                             artwork: square, artworkMIME: "image/png")
panel.nowPlayingChanged(episode); pump(0.5)
check(viewer.info?.title == "Fixture Episode", "Podcasts does take over the music window")
check(revealControls(viewer), "resting on the caption reveals the controls")
check(viewer.controlsRevealed && viewer.controls.volumeIcon.isHidden && viewer.controls.volumePopup.alphaValue < 0.05, "no volume for an app Watch can't set")
check(viewer.controls.timeline.isHidden, "no length: no timeline")
check(!viewer.controls.playPause.dimmed, "controllable while it holds the slot")
var tab = nowPlayingFixture("Video Clip", wide)
tab.bundleID = "com.google.Chrome"
panel.nowPlayingChanged(tab); pump(0.1)
check(viewer.info?.title == "Fixture Episode" && viewer.controls.playPause.dimmed, "a video taking the slot leaves Podcasts showing, controls dimmed")
check(viewer.controls.shuffle.isHidden && viewer.controls.repeatButton.isHidden, "no shuffle/repeat for an app Watch can't script")
viewer.pointerMoved(at: nil)
check(waitFor(ArtworkWindowController.hideDelay + 3) { !viewer.controlsRevealed } && sent.count == sentSoFar,
      "leaving the window hides them; nothing was sent without a click (\(sent.count) vs \(sentSoFar))")
panel.nowPlayingChanged(nil)
check(!panel.nowPlayingRow.isHidden && viewer.info?.title == "Fixture Episode", "the video stopping doesn't clear the music")
panel.nowPlayingChanged(episode); panel.nowPlayingChanged(nil)
check(panel.nowPlayingRow.isHidden, "the music app stopping clears it")
// Music's own track-change broadcast, heard while a video holds the slot: the song changes, its artwork comes from Music.
panel.nowPlayingChanged(tab)
fixtureMusic.artworkReply = wide
func musicBroadcast(_ info: [String: Any]) {
    panel.musicBroadcast(Notification(name: Notification.Name("com.apple.Music.playerInfo"), object: nil, userInfo: info))
}
musicBroadcast(["Name": "Broadcast Song", "Artist": "Fixture Artist", "Album": "Fixture Album", "Player State": "Playing", "Total Time": 180_000])
pump(0.3)
check(viewer.info?.title == "Broadcast Song" && viewer.info?.appBundleID == "com.apple.Music" && viewer.info?.duration == 180 && !panel.nowPlayingRow.isHidden,
      "Music's broadcast changes the song while a video holds the slot")
check(fixtureMusic.artworkAsked == ["com.apple.Music"] && viewer.pictureData == wide, "its artwork comes from Music")
check(!viewer.controls.playPause.dimmed, "and its controls work (addressed to Music)")
musicBroadcast(["Name": "Broadcast Song", "Artist": "Fixture Artist", "Album": "Fixture Album", "Player State": "Paused", "Total Time": 180_000])
check(viewer.info?.isPlaying == false && viewer.pictureData == wide && fixtureMusic.artworkAsked.count == 1, "pausing the same song keeps its artwork, asks nothing")
musicBroadcast(["Player State": "Stopped"])
check(panel.nowPlayingRow.isHidden, "Music stopping clears the row")
panel.nowPlayingChanged(nil)
panel.nowPlayingChanged(nowPlayingFixture("Fixture Song", square)); pump(0.3)
// The player's volume: hidden until the speaker is hovered, then a vertical slider in a panel above it, at any bar width.
let barHost = NSView(frame: NSRect(x: 0, y: 0, width: 408, height: 120))
let bar = PlayerControlBar(frame: NSRect(x: 0, y: 6, width: 408, height: 20))
barHost.addSubview(bar)
var volumes: [Double] = []
bar.onVolume = { volumes.append($0) }
bar.update(playing: true, muted: false, volume: 0.8, current: 30, duration: 120)
let barPanel = barHost.subviews.compactMap { $0 as? VolumePopupView }.first!
let barVolume = barPanel.slider
check(!bar.volumeOpen && barPanel.alphaValue < 0.05 && barVolume.vertical, "player volume hidden at rest")
bar.pointerMoved(at: NSPoint(x: 408 - 13, y: 10)); pump(0.3)
check(bar.volumeOpen && barPanel.alphaValue > 0.9 && abs(barVolume.value - 0.8) < 0.001, "hovering the speaker pops the volume up")
check(barPanel.frame.minY >= bar.frame.maxY && barHost.bounds.contains(barPanel.frame) && barPanel.frame.height > barPanel.frame.width,
      "…above the bar, upright, inside the window (\(barPanel.frame))")
check(bar.isScrubbing, "the bar stays up while the volume is")
barVolume.onChange?(0.3, false)
check(volumes == [0.3], "dragging it sets the volume")
bar.update(playing: true, muted: true, volume: 0.3, current: 30, duration: 120)
check(barVolume.value == 0, "muted shows as zero")
bar.pointerMoved(at: NSPoint(x: 20, y: 10)); _ = waitFor(2) { !bar.volumeOpen }
check(!bar.volumeOpen && barPanel.alphaValue < 0.05 && !bar.isScrubbing, "it goes after the pointer leaves")
let narrowHost = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 60))
let narrowBar = PlayerControlBar(frame: NSRect(x: 0, y: 6, width: 100, height: 20))
narrowHost.addSubview(narrowBar)
let narrowPanel = narrowHost.subviews.compactMap { $0 as? VolumePopupView }.first!
narrowBar.pointerMoved(at: NSPoint(x: 100 - 13, y: 10)); pump(0.3)
check(narrowBar.volumeOpen && narrowPanel.alphaValue > 0.9 && narrowHost.bounds.contains(narrowPanel.frame), "even in a narrow bar (100 pt) the volume pops up, inside the window (\(narrowPanel.frame))")
let tinyBar = PlayerControlBar(frame: NSRect(x: 0, y: 6, width: 60, height: 20))
check(!tinyBar.subviews.contains { $0 is NSButton && $0.isHidden && ($0 as? NSButton)?.toolTip?.hasPrefix("Volume") == true }, "and the speaker is still in a 60 pt bar")
// Windows never cover each other (when the screen has room): a new player's spot avoids the music window. The music
// window sits where it opens for real, under the menu-bar icon at the top right (the harness has no icon; CI's screen is
// 1024×768 at 1×, too small for two windows side by side when one is centred).
if let visible = viewer.window.screen?.visibleFrame {
    viewer.window.setFrame(NSRect(x: visible.maxX - 300, y: visible.maxY - 300, width: 300, height: 300), display: true)
}
let freeSpot = panel.windowManager.freeFrame(size: NSSize(width: 440, height: 275), anchor: nil)
check(!freeSpot.intersects(viewer.window.frame), "a new player's spot avoids the music window (\(freeSpot) vs \(viewer.window.frame))")
// The video player end to end on a local file made by the bundled FFmpeg (panel.py): it plays natively, and the click
// zones, keys, volume and resizing act on it — the basics every release must keep.
var fixturePlayer: PlayerWindowController?
if let video = ProcessInfo.processInfo.environment["WATCH_FIXTURE_VIDEO"] {
    Prefs.playerVolume = 0.5
    let player = panel.windowManager.open(video, anchor: nil)
    fixturePlayer = player
    check(!player.window.frame.intersects(viewer.window.frame), "a new player opens beside the music window, not on it")
    check(waitFor(20) { player.isPlayingNatively && player.isPlaying && player.playbackTime > 0.5 } && !player.showsFailure,
          "the video plays in Watch's own player, not a web page")
    let s = player.clickSurface
    var b = s.bounds.size
    let middle = NSPoint(x: b.width / 2, y: b.height / 2)
    click(s, at: middle)
    check(!player.isPlaying, "a centre click pauses")
    click(s, at: middle)
    check(player.isPlaying, "another plays")
    click(s, at: middle); pump(0.3)
    let t0 = player.playbackTime
    let back = NSPoint(x: b.width * 0.15, y: b.height * 0.4), ahead = NSPoint(x: b.width * 0.85, y: b.height * 0.4)
    func near(_ t: Double) -> Bool { abs(player.playbackTime - t) <= 0.6 }
    multiClick(s, at: ahead, clicks: 2)
    check(waitFor(3) { near(t0 + 10) }, "double-click right: +10 s (\(t0) → \(player.playbackTime))")
    multiClick(s, at: ahead, clicks: 2); multiClick(s, at: ahead, clicks: 3)
    check(waitFor(3) { near(t0 + 30) }, "a quick run of clicks stacks, +10 s each (→ \(player.playbackTime))")
    multiClick(s, at: back, clicks: 2)
    check(waitFor(3) { near(t0 + 20) }, "double-click left: -10 s (→ \(player.playbackTime))")
    multiClick(s, at: middle, clicks: 2)
    check(!player.isPlaying, "the centre's double-click doesn't toggle again")
    key(s, 124, "\u{F703}")
    check(waitFor(3) { near(t0 + 25) }, "→ +5 s (→ \(player.playbackTime))")
    key(s, 123, "\u{F702}")
    check(waitFor(3) { near(t0 + 20) }, "← -5 s (→ \(player.playbackTime))")
    key(s, 49, " ")
    check(player.isPlaying, "space plays")
    key(s, 49, " ")
    check(!player.isPlaying, "and pauses")
    key(s, 126, "\u{F700}")
    check(abs(player.playbackVolume - 0.6) < 0.001, "↑ raises the volume")
    key(s, 125, "\u{F701}"); key(s, 125, "\u{F701}")
    check(abs(player.playbackVolume - 0.4) < 0.001 && abs(Prefs.playerVolume - 0.4) < 0.001, "↓ lowers it, remembered for the next window")
    let playerBar = player.window.contentView!.subviews.compactMap { $0 as? PlayerControlBar }.first
    let playerVolume = player.window.contentView!.subviews.compactMap { $0 as? VolumePopupView }.first?.slider
    playerVolume?.onChange?(0.25, true)
    check(playerVolume != nil && abs(player.playbackVolume - 0.25) < 0.001, "the bar's volume slider sets it")
    let cap = player.qualityLimit
    check(cap.width > 0 && cap == StreamLadder.cap(points: player.window.contentView!.bounds.size, scale: player.window.backingScaleFactor),
          "the quality cap follows the video area (\(cap))")
    player.window.setContentSize(NSSize(width: 880, height: 495)); pump(0.2)
    check(abs(player.videoArea.width - 880) < 2 && abs(player.videoArea.height - 495) < 2, "resizing resizes the video (\(player.videoArea.size))")
    check(player.qualityLimit.width > cap.width * 1.9, "and raises the quality cap (\(cap) → \(player.qualityLimit))")
    check(player.menuTitles.contains("Playing at 360p"), "the menu says which quality is playing: \(player.menuTitles)")
    b = s.bounds.size
    multiClick(s, at: NSPoint(x: b.width / 2, y: b.height * 0.9), clicks: 2); pump(0.6)
    let restored = player.window.contentView!.bounds.size
    check(abs(restored.width - PlayerWindowController.standardSize.width) < 2 && abs(player.qualityLimit.width - cap.width) < 2,
          "double-clicking the top returns to the standard size, the cap with it (\(restored))")
} else {
    print("SKIP player checks: no fixture video")
}
key(viewer.surface, 53, "\u{1b}")
check(!viewer.window.isVisible, "Esc closes the artwork window")
if let player = fixturePlayer {
    panel.nowPlayingChanged(nowPlayingFixture("Fixture Song", artwork(300, 300))); pump(0.1)   // a window that fits beside it
    panel.openArtwork(); pump(0.3)
    check(viewer.window.isVisible && !viewer.window.frame.intersects(player.window.frame), "the music window opens beside a player, never on it")
    viewer.close(); player.window.close(); pump(0.2)
}
panel.nowPlayingChanged(nil)
check(panel.nowPlayingRow.isHidden, "nothing playing hides the row")
// Up Next under the music window (3.21): Play Next / Play Later on rows; while Music plays, additions wait for its song,
// play in Watch (a file in the music window, a video in a video window beside it), then Music carries on. Fixture Music only.
let queueRowMenu = panel.linkMenu("https://youtu.be/fixture", title: "Fixture", removable: true).items.map(\.title)
check(Array(queueRowMenu.prefix(3)) == ["Play", "Play Next", "Play Later"], "rows offer Play Next and Play Later under Play: \(queueRowMenu)")
check(!panel.linkMenu("https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6", title: nil, removable: false).items.map(\.title).contains("Download"),
      "no Download for a Spotify link")
func drawerTitles(_ d: QueueDrawer) -> [String] { d.rows.compactMap { if case .item(let item, _) = $0 { return item.title }; return nil } }
func windowSnapshot(_ window: NSWindow, _ name: String) {
    guard let view = window.contentView else { return }
    view.layoutSubtreeIfNeeded(); pump()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png"))
}
if let video = ProcessInfo.processInfo.environment["WATCH_FIXTURE_VIDEO"] {
    let tone = URL(fileURLWithPath: video).deletingLastPathComponent().appendingPathComponent("a.m4a").path
    var ending = nowPlayingFixture("Ending Song", square)
    ending.duration = 200; ending.elapsed = 198.8; ending.elapsedAt = Date(); ending.rate = 1
    panel.nowPlayingChanged(ending); pump(0.2)
    fixtureMusic.performed = []
    let up = panel.upNext
    up.appIsRunning = { _ in true }                     // fixture Music "runs" (the real app never does here)
    panel.enqueue([QueueItem(url: tone, title: "Fixture Tone")], .later); pump(0.5)
    check(up.queue?.handBack == "com.apple.Music" && up.queue?.current?.source == .music && up.queue?.sections().playingNext.map(\.title) == ["Fixture Tone"],
          "while Music plays, Play Later waits for its song")
    check(up.engine == .external("com.apple.Music") && fixtureMusic.performed.isEmpty, "nothing is sent to Music yet")
    let musicWindow = panel.artworkWindow!
    let drawer = panel.queueDrawer
    check(musicWindow.window.isVisible && drawer?.isShown == true, "the music window opens with Up Next under it")
    if let d = drawer {
        check(drawerTitles(d) == ["Ending Song", "Fixture Tone"], "the list: Music's song now, the file next: \(drawerTitles(d))")
        check(d.rows.contains { if case .note(let text, _, _) = $0 { return text.contains("Continue in Music") }; return false }, "then: continue in Music")
        let w = d.window.frame, m = musicWindow.window.frame
        check(w.maxY <= m.minY || w.minY >= m.maxY, "the list sits under (or above) the window, never over it (\(w) vs \(m))")
        check(abs(w.width - max(QueueDrawer.minWidth, m.width)) < 1, "as wide as the window, at least 300 pt")
        windowSnapshot(d.window, "up-next")
    }
    // Music moves on to its own next song: Watch pauses it there, from the start, and plays the file in the music window.
    musicBroadcast(["Name": "Music's Next", "Artist": "Fixture Artist", "Album": "Fixture Album", "Player State": "Playing", "Total Time": 180_000])
    pump(0.5)
    check(fixtureMusic.performed.map { $0.request } == [.command(.pause), .seek(0)] && fixtureMusic.performed.allSatisfy { $0.app == "com.apple.Music" },
          "at the song's end Watch pauses Music on its next song, rewound: \(fixtureMusic.performed)")
    check(up.engine == .native && musicWindow.info?.appBundleID == UniversalQueue.ownID, "the file plays in Watch, shown in the music window")
    check(waitFor(6) { (musicWindow.info?.position(at: Date()) ?? 0) > 0.5 && musicWindow.info?.isPlaying == true }, "Watch's own player is playing it")
    check(revealControls(musicWindow), "resting on the caption reveals Watch's own item's controls")
    check(musicWindow.controls.shuffle.isHidden && !musicWindow.controls.volumeIcon.isHidden, "Watch's own item: no shuffle/repeat (those are the apps'), Watch's volume")
    viewerSnapshot("music-window-own-item")
    _ = waitFor(3) { musicWindow.info?.isPlaying == true }
    musicWindow.controls.playPause.performClick(nil)
    check(waitFor(3) { musicWindow.info?.isPlaying == false } && fixtureMusic.performed.count == 2,
          "⏯ pauses Watch's player, not Music (\(fixtureMusic.performed.count) sent to Music)")
    musicWindow.controls.playPause.performClick(nil); pump(0.2)
    // A video queued next opens in a video window beside the music window and runs from the queue. GitHub's Mac has a
    // 1024×768 screen, where a 477 pt music window and its list leave no room for a player beside them (it would cascade,
    // as on any full screen): a smaller music window at the top left leaves room on the right.
    if let vis = musicWindow.window.screen?.visibleFrame {
        musicWindow.window.setFrame(NSRect(x: vis.minX, y: vis.maxY - 240, width: 240, height: 240), display: true); pump(0.2)
    }
    if let d = drawer {
        check(!d.window.frame.intersects(musicWindow.window.frame), "the list follows the window (\(d.window.frame) vs \(musicWindow.window.frame))")
    }
    let before = panel.windowManager.players.count
    up.insert([QueueItem(url: video, title: "Fixture Video")], at: (up.queue?.pos ?? 0) + 1)
    if let id = up.queue?.peek(1, wrap: false)?.id { up.jump(to: id) }
    pump(0.5)
    let queued = panel.windowManager.players.last
    check(panel.windowManager.players.count == before + 1 && up.engine == .video && queued?.onEnded != nil && queued?.onShowList != nil,
          "a queued video opens in a video window that the queue drives (its ⌥⌘U shows the music window's list)")
    let queuedFrame = queued?.window.frame ?? musicWindow.window.frame
    check(!queuedFrame.intersects(musicWindow.window.frame) && !(drawer?.window.frame.intersects(queuedFrame) ?? false),
          "beside the music window and its list, not on them (\(queuedFrame))")
    check(waitFor(10) { queued?.isPlaying == true } && musicWindow.info?.title == "Fixture Video", "the music window shows the video playing beside it")
    // Up Next runs out: the video window closes and Music carries on with its own Up Next.
    fixtureMusic.performed = []
    up.advance(); pump(0.4)
    check(up.queue == nil && panel.windowManager.players.count == before, "the queue's video window closes when the queue moves on")
    check(fixtureMusic.performed.map { $0.request } == [.command(.play)] && fixtureMusic.performed.first?.app == "com.apple.Music",
          "when Up Next runs out, Music carries on: \(fixtureMusic.performed)")
    check(musicWindow.info?.title == "Music's Next" && musicWindow.musicApp === fixtureMusic, "the music window follows Music again")
    // A Spotify link plays in the Spotify app as the queue's item (fixture: the script is recorded, never run).
    panel.nowPlayingChanged(nil); musicBroadcast(["Player State": "Stopped"]); pump(0.1)
    panel.playSpotify("https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6"); pump(0.3)
    check(fixtureMusic.spotifyScripts == [#"tell application id "com.spotify.client" to play track "spotify:track:6rqhFgbbKwnb9MLmUQDhG6""#]
          && up.engine == .external("com.spotify.client"), "a Spotify link plays in Spotify, by its URI")
    musicWindow.close(); pump(0.3)
    check(up.queue == nil && panel.queueDrawer?.isShown != true, "closing the music window ends the queue and its list")
} else {
    print("SKIP queue playback checks: no fixture media")
}
// Podcasts (3.22): the Podcasts tab above search results searches the podcast directory (fixture answers here), a show
// lists its episodes, and an episode plays in the music window, resuming where it was left and getting its ✓ at the end.
func serviceTabs() -> NSSegmentedControl? {
    panel.browseList.arrangedSubviews.lazy.compactMap { ($0 as? NSStackView)?.arrangedSubviews.first as? NSSegmentedControl }.first
}
panel.searchService = .youtube
type("fixture talk"); _ = waitFor(3) { panel.requests.last?.query == "fixture talk" }   // the 0.35 s debounce, however busy the runner
let youtubeAsked = panel.requests.last
check(youtubeAsked?.query == "fixture talk" && serviceTabs()?.selectedSegment == 0, "a search starts on YouTube, with the YouTube | Podcasts tabs")
if let tabs = serviceTabs() {
    tabs.selectedSegment = 1
    panel.searchServiceChosen(tabs)
}
check(panel.podcastSearches.map { $0.query } == ["fixture talk"] && youtubeAsked?.task.isCancelled == true, "Podcasts searches the same words; YouTube's search stops")
panel.podcastSearches.last?.done([PodcastShow(title: "Fixture Talk", author: "Fixture FM", feedURL: "https://feeds.fixture.invalid/talk", artwork: nil,
                                              appleID: "1234567890"),
                                  PodcastShow(title: "Fixture Feed Only", author: nil, feedURL: "https://feeds.fixture.invalid/only", artwork: nil, appleID: nil)], "")
check(rows(panel.browseList).count == 2 && serviceTabs()?.selectedSegment == 1, "the shows found, under the Podcasts tab")
check(serviceTabs()?.refusesFirstResponder == true, "the tabs never take the field's typing focus")
snapshot("podcast-results")
let youtubeCount = panel.requests.count
type("fixture news"); _ = waitFor(3) { panel.podcastSearches.last?.query == "fixture news" }
check(panel.podcastSearches.last?.query == "fixture news" && panel.requests.count == youtubeCount, "typing again searches podcasts until the tab changes")
panel.podcastSearches.last?.done([PodcastShow(title: "Fixture Talk", author: "Fixture FM", feedURL: nil, artwork: nil, appleID: "1234567890")], "")
rows(panel.browseList).first?.onClick?()
check(panel.episodeFetches.last?.link == "https://podcasts.apple.com/podcast/id1234567890", "a show opens its episodes (by its Apple Podcasts id)")
if let video = ProcessInfo.processInfo.environment["WATCH_FIXTURE_VIDEO"] {
    let tone = URL(fileURLWithPath: video).deletingLastPathComponent().appendingPathComponent("a.m4a").path
    let show = PodcastShow(title: "Fixture Talk", author: "Fixture FM", feedURL: nil, artwork: nil, appleID: "1234567890")
    let first = PodcastEpisode(title: "Fixture Episode", audioURL: tone, published: Date(timeIntervalSinceNow: -86400), duration: 60,
                               show: "Fixture Talk", appleID: "1000000000001", showID: "1234567890")
    let older = PodcastEpisode(title: "Older Episode", audioURL: "https://cdn.fixture.invalid/older.mp3", duration: 1800, show: "Fixture Talk")
    PlaybackPositions.shared.save(20, duration: 60, for: "podcast:1000000000001")
    panel.episodeFetches.last?.done(show, [first, older], "")
    check(panel.browseTitle.stringValue == "Fixture Talk" && rows(panel.browseList).count == 2 && serviceTabs() == nil, "the show's episodes, newest first")
    snapshot("podcast-episodes")
    let up = panel.upNext
    rows(panel.browseList).first?.onClick?(); pump(0.3)
    let musicWindow = panel.artworkWindow
    check(up.engine == .native && up.queue?.current?.source == .podcast && musicWindow?.window.isVisible == true,
          "an episode plays in Watch, in the music window")
    check(waitFor(6) { (musicWindow?.info?.position(at: Date()) ?? 0) >= 19.5 } && (musicWindow?.info?.position(at: Date()) ?? 99) < 30,
          "it resumes where it was left (\(musicWindow?.info?.position(at: Date()) ?? -1))")
    panel.systemTick()
    check(panel.systemSource == .queue && panel.systemNowPlaying.published?.title == "Fixture Episode",
          "macOS's Now Playing (Control Center, media keys) shows the episode: \(panel.systemNowPlaying.published?.title ?? "nothing")")
    check(revealControls(musicWindow), "resting on the caption reveals the episode's controls")
    _ = waitFor(3) { musicWindow?.info?.isPlaying == true }
    musicWindow?.controls.playPause.performClick(nil)
    check(waitFor(3) { musicWindow?.info?.isPlaying == false } && (PlaybackPositions.shared.position(for: "podcast:1000000000001") ?? 0) >= 20,
          "⏯ pauses it and remembers where it is (\(PlaybackPositions.shared.position(for: "podcast:1000000000001") ?? -1))")
    viewerSnapshot("music-window-podcast")
    up.command(.seek(57)); up.command(.command(.play))
    check(waitFor(8) { up.queue == nil }, "it plays to the end, and Up Next ends with it")
    check(WatchedVideos.shared.isWatched("podcast:1000000000001") && PlaybackPositions.shared.position(for: "podcast:1000000000001") == nil,
          "an episode heard to the end gets its ✓ and starts from the top next time")
    // An Apple Podcasts episode link (pasted, or from Recent Links): looked up, then played; its Recent Links row is named.
    let link = "https://podcasts.apple.com/gb/podcast/fixture-talk/id1234567890?i=1000000000002"
    panel.episodeAnswer = PodcastEpisode(title: "Looked Up Episode", audioURL: tone, duration: 60, show: "Fixture Talk",
                                         appleID: "1000000000002", showID: "1234567890")
    panel.playEpisodeLink(link); pump(0.3)
    check(panel.episodeLookups.last == link && up.queue?.current?.title == "Looked Up Episode" && up.queue?.current?.page != nil
          && up.engine == .native, "an episode link is looked up and played")
    check(panel.links.link(for: link)?.title == "Looked Up Episode", "and its Recent Links row is named")
    check(up.queue?.current?.resumeKey == "podcast:1000000000002", "resume by episode, whatever the link looks like")
    panel.artworkWindow?.close(); pump(0.3)
    check(up.queue == nil, "closing the music window stops it")
} else {
    print("SKIP podcast playback checks: no fixture media")
}
// Your Music library (3.23): the Music tab searches Music's own library (fixture answers; no Music here). Without Music
// running, or without permission, the page says so with the button that fixes it — never a prompt of its own; a song plays
// in Music by its id, through Up Next, and Music carries on with its own Up Next afterwards.
func messageButton() -> NSButton? {
    panel.browseList.arrangedSubviews.compactMap { $0 as? NSStackView }.flatMap { $0.arrangedSubviews }.compactMap { $0 as? NSButton }.first
}
type("back in black"); _ = waitFor(3) { panel.podcastSearches.last?.query == "back in black" }
if let tabs = serviceTabs() {
    tabs.selectedSegment = 2
    panel.searchServiceChosen(tabs)
}
check(panel.librarySearches.map { $0.query } == ["back in black"] && serviceTabs()?.selectedSegment == 2, "the Music tab searches your library")
panel.librarySearches.last?.done(.needsAccess)
check(messageButton()?.title == "Allow…", "not yet allowed: an Allow… button (\(messageButton()?.title ?? "none"))")
panel.reloadPage()
panel.librarySearches.last?.done(.notRunning)
check(panel.librarySearches.count == 2 && messageButton()?.title == "Open Music", "Music not open: Open Music")
panel.reloadPage()
panel.librarySearches.last?.done(.songs([LibrarySong(persistentID: "0123456789ABCDEF", title: "Back in Black", artist: "AC/DC",
                                                     album: "Back in Black", duration: 255)]))
check(rows(panel.browseList).count == 1 && messageButton() == nil, "the library's songs")
snapshot("music-library")
fixtureMusic.playedScripts = []
rows(panel.browseList).first?.onClick?(); pump(0.3)
check(fixtureMusic.playedScripts.map { $0.script } == [MusicLibrary.playScript("0123456789ABCDEF")!] && fixtureMusic.playedScripts.first?.app == "com.apple.Music",
      "a library song plays in Music, by its id: \(fixtureMusic.playedScripts)")
check(panel.upNext.engine == .external("com.apple.Music") && panel.upNext.queue?.handBack == "com.apple.Music",
      "as Up Next's item, with Music carrying on afterwards")
panel.artworkWindow?.close(); pump(0.3)
check(panel.upNext.queue == nil && panel.upNext.saved?.items.map(\.title) == ["Back in Black"] && UniversalQueue().saved?.items.first?.title == "Back in Black",
      "closing the music window keeps Up Next to resume — after a relaunch too (3.24)")
// A video window's own Up Next list (3.23): the same drop-down, under the video window — here, its folder.
if let video = ProcessInfo.processInfo.environment["WATCH_FIXTURE_VIDEO"] {
    let tone = URL(fileURLWithPath: video).deletingLastPathComponent().appendingPathComponent("a.m4a").path
    let player = panel.windowManager.open(video, anchor: nil)
    _ = waitFor(10) { player.isPlaying }
    player.toggleUpNextList(); pump(0.3)
    if let list = player.upNextList {
        check(list.isShown && waitFor(3) { drawerTitles(list) == ["player", "v180", "v360"] }, "⌥⌘U drops this window's own Up Next down: \(drawerTitles(list))")
        let l = list.window.frame, w = player.window.frame
        check(l.maxY <= w.minY || l.minY >= w.maxY, "under (or over) the video window, never on it (\(l) vs \(w))")
        player.insertIntoUpNext([QueueItem(url: tone, title: "Fixture Tone"), QueueItem(url: "https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6")], at: nil)
        check(drawerTitles(list) == ["player", "Fixture Tone", "v180", "v360"], "a dropped file plays next here; a Spotify song stays out: \(drawerTitles(list))")
        windowSnapshot(list.window, "video-up-next")
        if let id = player.queue?.items.first(where: { $0.title == "Fixture Tone" })?.id { list.onPlay?(id) }
        pump(0.3)
        check(player.sourceURL == tone && drawerTitles(list).first == "Fixture Tone", "double-click plays it in this window")
        player.window.close(); pump(0.2)
        check(!list.isShown, "the list goes with its window")
    } else {
        check(false, "⌥⌘U makes a list")
        player.window.close(); pump(0.2)
    }
}
// 3.24: a video takes macOS's Now Playing (media keys reach it), Music pauses while it plays and plays again when it closes
// (fixture Music, already allowed); Finder's Open With puts an audio file in the music window; the saved Up Next resumes.
if let video = ProcessInfo.processInfo.environment["WATCH_FIXTURE_VIDEO"] {
    let tone = URL(fileURLWithPath: video).deletingLastPathComponent().appendingPathComponent("a.m4a").path
    var background = nowPlayingFixture("Background Song", square)
    background.isPlaying = true
    panel.nowPlayingChanged(background); pump(0.1)
    fixtureMusic.performed = []; fixtureMusic.recordsAllowed = true
    Prefs.pauseMusicWhilePlaying = true; Prefs.resumeMusicAfter = true
    let player = panel.windowManager.open(video, anchor: nil)
    panel.ensureSystemTick()
    check(waitFor(10) { player.isPlaying && panel.pausedForWatch == "com.apple.Music" }, "Music pauses while a video plays")
    check(fixtureMusic.performed.map { $0.request } == [.command(.pause)] && fixtureMusic.performed.first?.app == "com.apple.Music",
          "by a pause sent to Music itself: \(fixtureMusic.performed)")
    check(waitFor(3) { panel.systemSource == .player(0) && panel.systemNowPlaying.published?.isPlaying == true },
          "the video holds macOS's Now Playing: \(panel.systemSource)")
    panel.systemNowPlaying.handle(.command(.pause)); pump(0.3)
    check(!player.isPlaying, "a media key pauses it")
    panel.systemNowPlaying.handle(.command(.play)); pump(0.3)
    check(player.isPlaying, "and plays it again")
    player.window.close()
    check(waitFor(4) { fixtureMusic.performed.last?.request == .command(.play) } && panel.pausedForWatch == nil, "closing the video plays Music again")
    fixtureMusic.recordsAllowed = false
    panel.nowPlayingChanged(nil); musicBroadcast(["Player State": "Stopped"]); pump(0.1)
    panel.openFiles([tone]); pump(0.5)
    check(panel.upNext.engine == .native && panel.upNext.queue?.current?.url == tone && panel.artworkWindow?.window.isVisible == true,
          "Open With ▸ Watch: an audio file plays in the music window")
    panel.artworkWindow?.close(); pump(0.3)
    check(panel.upNext.saved?.items.first?.url == tone, "kept to resume")
    panel.upNext.resumeSaved(); pump(0.5)
    check(panel.upNext.engine == .native && panel.upNext.queue?.current?.url == tone, "Resume plays it again")
    panel.artworkWindow?.close(); pump(0.3)
}
panel.searchService = .youtube
type(""); pump(0.1)
panel.dropdown.appearance = NSAppearance(named: .aqua)
snapshot("recent-light")
panel.dropdown.setContentSize(NSSize(width: 260, height: 200)); layout()
check(rows(panel.clipSection).count == 100, "manual small resize retains full list")
snapshot("recent-small")
// Quality follows the window: DashHLSBridge describes every rendition (fixture 360p + 180p H.264 and AAC, laid out like
// YouTube's and served by range from panel.py's local server), shown in a PlayerVideoView as in the player, with the
// player's cap (StreamLadder.cap of the video area). The sizes work at 1× and 2×: 240×135 pt allows only 180p, 880×495 pt 360p.
if let base = ProcessInfo.processInfo.environment["WATCH_FIXTURE_BASE"] {
    func rendition(_ name: String, _ vcodec: String, _ acodec: String, _ size: (Int, Int)?, kbps: Double) -> StreamRef {
        var f: [String: Any] = ["url": base + name, "protocol": "https", "ext": name.hasSuffix(".m4a") ? "m4a" : "mp4",
                                "vcodec": vcodec, "acodec": acodec, "tbr": kbps]
        if let size = size { f["width"] = size.0; f["height"] = size.1 }
        return StreamRef(f)!
    }
    var made: (bridge: DashHLSBridge?, asset: AVURLAsset?)?
    DashHLSBridge.make(videos: [rendition("v360.mp4", "avc1.64001e", "none", (640, 360), kbps: 500),
                                rendition("v180.mp4", "avc1.640015", "none", (320, 180), kbps: 200)],
                       audio: rendition("a.m4a", "none", "mp4a.40.2", nil, kbps: 128)) { made = ($0, $1) }
    _ = waitFor(15) { made != nil }
    if let bridge = made?.bridge, let asset = made?.asset {
        let screen = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 240, height: 135), styleMask: [.titled, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        screen.isReleasedWhenClosed = false
        let videoView = PlayerVideoView(frame: screen.contentView!.bounds)
        videoView.autoresizingMask = [.width, .height]
        screen.contentView!.addSubview(videoView)
        func playerCap() -> CGSize { StreamLadder.cap(points: screen.contentView!.bounds.size, scale: screen.backingScaleFactor) }
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4
        item.preferredMaximumResolution = playerCap()
        let bridged = AVPlayer(playerItem: item)
        bridged.isMuted = true
        videoView.playerLayer.player = bridged
        screen.orderFront(nil)
        bridged.play()
        func accessLog() -> String {
            let events = item.accessLog()?.events ?? []
            return "cap \(item.preferredMaximumResolution), " + events.map {
                "\(Int($0.indicatedBitrate / 1000)) kb/s chosen, \(Int($0.observedBitrate / 1000)) kb/s measured, \($0.numberOfMediaRequests) requests"
            }.joined(separator: " | ")
        }
        check(waitFor(20) { item.status == .readyToPlay && item.presentationSize.height > 0 },
              "the bridge's multi-rendition playlist plays (\(item.error?.localizedDescription ?? "no error"))")
        check(item.presentationSize.height == 180, "a small window gets the small rendition (\(item.presentationSize); \(accessLog()))")
        screen.setContentSize(NSSize(width: 880, height: 495))
        item.preferredMaximumResolution = playerCap()           // as PlayerWindowController.windowDidResize does
        check(waitFor(40) { item.presentationSize.height == 360 }, "a bigger window switches up (now \(item.presentationSize); \(accessLog()))")
        bridged.pause()
        screen.close()
        withExtendedLifetime(bridge) {}
    } else {
        check(false, "the bridge reads the fixture renditions' indexes")
    }
} else {
    print("SKIP bridge checks: no fixture renditions")
}
let guideTools = FileManager.default.temporaryDirectory.appendingPathComponent("Watch guide fixture \(UUID().uuidString)")
try! FileManager.default.createDirectory(at: guideTools, withIntermediateDirectories: true)
for name in MediaTools.names {
    let path = guideTools.appendingPathComponent(name)
    try! "#!/bin/sh\nprintf '%s\\n' 'Fixture \(name) 1.0'\n".write(to: path, atomically: true, encoding: .utf8)
    try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
}
let guide = WelcomeController(tools: MediaTools(directory: guideTools))
guide.window.appearance = NSAppearance(named: .aqua)
guide.window.contentView!.layoutSubtreeIfNeeded(); pump()
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
let guideViews = descendants(guide.window.contentView!)
let labels = guideViews.compactMap { $0 as? NSTextField }
let text = labels.map(\.stringValue).joined(separator: "\n")
check(!text.contains("brew install") && !text.contains("curl -") && !text.contains("Open Terminal"), "first-run guide requires no Terminal")
let buttons = guideViews.compactMap { $0 as? NSButton }
check(buttons.contains { $0.title == "Start Watching" && $0.keyEquivalent == "\r" }, "guide has a primary start action")
check(buttons.contains { $0.title == "Connect YouTube…" }, "guide has optional YouTube action")
guide.refreshStatus()
let guideDeadline = Date().addingTimeInterval(10)
while Date() < guideDeadline && labels.filter({ $0.stringValue.hasPrefix("✓ ") }).count < 4 { pump(0.1) }
check(labels.filter { $0.stringValue.hasPrefix("✓ ") }.count == 4, "guide runs and reports all four bundled helpers")
func guideSnapshot(_ name: String) {
    let view = guide.window.contentView!
    view.layoutSubtreeIfNeeded(); pump(); view.layoutSubtreeIfNeeded()
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    let flattened = NSImage(size: view.bounds.size)
    flattened.lockFocus()
    NSColor.white.setFill(); view.bounds.fill()
    NSImage(cgImage: rep.cgImage!, size: view.bounds.size).draw(in: view.bounds)
    flattened.unlockFocus()
    let bitmap = NSBitmapImageRep(data: flattened.tiffRepresentation!)!
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png"))
}
guideSnapshot("first-run")
try! FileManager.default.removeItem(at: guideTools.appendingPathComponent("deno"))
guide.refreshStatus()
let missingDeadline = Date().addingTimeInterval(10)
while Date() < missingDeadline && !labels.contains(where: { $0.stringValue.contains("⚠ deno") }) { pump(0.1) }
check(labels.contains { $0.stringValue.contains("⚠ deno") && $0.stringValue.contains("replace Watch") }, "damaged helper has no-terminal recovery")
guide.window.setContentSize(NSSize(width: 500, height: 420)); guideSnapshot("first-run-small")
let guideScroll = guide.window.contentView!.subviews.compactMap { $0 as? NSScrollView }.first!
let lastGuideButton = buttons.last!
lastGuideButton.scrollToVisible(lastGuideButton.bounds); pump()
check(guideScroll.contentView.bounds.minY > 0 && !lastGuideButton.visibleRect.isEmpty, "small guide scrolls to final action")
guideSnapshot("first-run-bottom")
guide.window.close()
try! FileManager.default.removeItem(at: guideTools)
panel.liveSearch.cancel(); panel.browseTask?.cancel()
panel.dropdown.close()
fixtureDefaults.removePersistentDomain(forName: suite)
print("Watch isolated panel: \(checkCount) checks, \(failureCount) failures")
exit(failureCount == 0 ? 0 : 1)
