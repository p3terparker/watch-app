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
// Playback controls: revealed by resting on the caption; they send requests only when clicked (recorded here).
let appRouting = viewer.onCommand               // AppDelegate's: Music/Spotify addressed by AppleScript (fixtureMusic here)
var sent: [NowPlayingRequest] = []
viewer.onCommand = { sent.append($0) }
var timedSong = nowPlayingFixture("Timed Song", square)
timedSong.duration = 200; timedSong.elapsed = 50; timedSong.elapsedAt = Date(); timedSong.rate = 1
panel.nowPlayingChanged(timedSong); pump(0.5)
var area = viewer.window.contentView!.bounds
viewer.pointerMoved(at: NSPoint(x: area.midX, y: area.maxY - 20)); pump(0.4)
check(!viewer.controlsRevealed, "hovering the artwork shows only the caption")
viewer.pointerMoved(at: NSPoint(x: area.midX, y: 30)); pump(0.5)
check(viewer.controlsRevealed && viewer.controls.alphaValue > 0.9, "resting on the caption reveals the controls")
check(!viewer.controls.volume.isHidden && abs(viewer.controls.volume.value - 0.4) < 0.001, "Music's own volume shows its level")
check(abs(viewer.controls.timeline.value - 0.25) < 0.02, "timeline at the reported position")
viewerSnapshot("artwork-controls")
viewer.controls.playPause.performClick(nil)
check(sent == [.command(.pause)] && viewer.info?.isPlaying == false, "play/pause on a playing track sends pause and shows paused at once")
viewer.controls.next.performClick(nil)
viewer.controls.previous.performClick(nil)
check(sent.suffix(2) == [.command(.next), .command(.previous)], "next and previous")
viewer.controls.timeline.onChange?(0.5, true)
check(sent.last == .seek(100), "letting go of the timeline halfway seeks to half the length")
viewer.controls.volume.onChange?(0.7, true)
check(fixtureMusic.sets.last == 0.7, "the volume slider sets the app's own volume")
viewer.pointerMoved(at: NSPoint(x: area.midX, y: area.maxY - 20)); pump(0.8)
check(!viewer.controlsRevealed, "moving off the caption tucks the controls away")
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
// The centre click goes to Music itself (AppleScript to its bundle id), so it can never pause the video holding the slot.
viewer.onCommand = appRouting
let centre = NSPoint(x: viewer.surface.bounds.midX, y: viewer.surface.bounds.midY)
click(viewer.surface, at: centre)
check(fixtureMusic.performed.count == 1 && fixtureMusic.performed.last?.request == .command(.play) && fixtureMusic.performed.last?.app == "com.apple.Music",
      "a centre click plays/pauses Music itself: \(fixtureMusic.performed)")
viewer.onCommand = { sent.append($0) }
// The player's click zones (PlayerZone) and keys, in the music window.
sent = []
click(viewer.surface, at: centre)
check(sent == [.command(.pause)] && viewer.info?.isPlaying == false, "a centre click pauses: \(sent)")
multiClick(viewer.surface, at: centre, clicks: 2)
check(sent.count == 1, "the centre's double-click sends nothing more")
pump(ArtworkWindowController.seekHold + 0.1)            // the timeline seek above no longer counts
let side = viewer.surface.bounds.size
let leftSide = NSPoint(x: side.width * 0.15, y: side.height * 0.4), rightSide = NSPoint(x: side.width * 0.85, y: side.height * 0.4)
check(PlayerZone.at(leftSide, in: side) == .skipBack && PlayerZone.at(rightSide, in: side) == .skipForward, "fixture points sit in the side zones")
let from = viewer.info?.position(at: Date()) ?? -100
func seeked(_ expected: Double) -> Bool { if case .seek(let t)? = sent.last { return abs(t - expected) < 0.001 }; return false }
multiClick(viewer.surface, at: rightSide, clicks: 2)
check(seeked(from + 10), "double-click right: +10 s (\(from) → \(String(describing: sent.last)))")
multiClick(viewer.surface, at: rightSide, clicks: 3)
check(seeked(from + 20), "the next click of the run stacks: +10 s more")
multiClick(viewer.surface, at: leftSide, clicks: 2)
check(seeked(from + 10), "double-click left: back 10 s")
key(viewer.surface, 124, "\u{F703}")
check(seeked(from + 15), "→ +5 s")
key(viewer.surface, 123, "\u{F702}")
check(seeked(from + 10), "← -5 s")
key(viewer.surface, 49, " ")
check(sent.last == .command(.play) && viewer.info?.isPlaying == true, "space plays")
// Another audio app takes over the window; its controls work only while it holds the slot (they'd reach the video otherwise).
let episode = NowPlayingInfo(title: "Fixture Episode", artist: "Fixture Show", album: nil, bundleID: "com.apple.podcasts", isPlaying: true,
                             artwork: square, artworkMIME: "image/png")
panel.nowPlayingChanged(episode); pump(0.5)
check(viewer.info?.title == "Fixture Episode", "Podcasts does take over the music window")
area = viewer.window.contentView!.bounds
viewer.pointerMoved(at: NSPoint(x: area.midX, y: 30)); pump(0.5)
check(viewer.controlsRevealed && viewer.controls.volumeIcon.isHidden && viewer.controls.volume.isHidden, "no volume for an app Watch can't set")
check(viewer.controls.timeline.isHidden, "no length: no timeline")
check(!viewer.controls.playPause.dimmed, "controllable while it holds the slot")
var tab = nowPlayingFixture("Video Clip", wide)
tab.bundleID = "com.google.Chrome"
panel.nowPlayingChanged(tab); pump(0.1)
check(viewer.info?.title == "Fixture Episode" && viewer.controls.playPause.dimmed, "a video taking the slot leaves Podcasts showing, controls dimmed")
viewer.pointerMoved(at: nil); pump(0.3)
check(!viewer.controlsRevealed && sent.count == 7, "leaving the window hides them; nothing was sent without a click")
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
// The player's volume: tucked away until the speaker is hovered, then a slider that sets the volume.
let bar = PlayerControlBar(frame: NSRect(x: 0, y: 0, width: 408, height: 20))
var volumes: [Double] = []
bar.onVolume = { volumes.append($0) }
bar.update(playing: true, muted: false, volume: 0.8, current: 30, duration: 120)
let barVolume = bar.subviews.compactMap { $0 as? ThinSlider }.first { $0.accessibilityLabel() == "Volume" }!
check(!bar.volumeOpen && barVolume.frame.width == 0, "player volume tucked away at rest")
bar.pointerMoved(at: NSPoint(x: 408 - 13, y: 10)); pump(0.4)
check(bar.volumeOpen && barVolume.frame.width == PlayerControlBar.volumeWidth && abs(barVolume.value - 0.8) < 0.001, "hovering the speaker slides the volume out")
barVolume.onChange?(0.3, false)
check(volumes == [0.3], "dragging it sets the volume")
bar.update(playing: true, muted: true, volume: 0.3, current: 30, duration: 120)
check(barVolume.value == 0, "muted shows as zero")
bar.pointerMoved(at: NSPoint(x: 20, y: 10)); pump(0.9)
check(!bar.volumeOpen, "it tucks away after the pointer leaves")
let narrowBar = PlayerControlBar(frame: NSRect(x: 0, y: 0, width: 150, height: 20))
narrowBar.pointerMoved(at: NSPoint(x: 150 - 13, y: 10)); pump(0.3)
check(!narrowBar.volumeOpen, "no slide-out in a narrow bar")
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
    let playerVolume = playerBar?.subviews.compactMap { $0 as? ThinSlider }.first { $0.accessibilityLabel() == "Volume" }
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
