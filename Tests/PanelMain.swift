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
let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: viewer.window.windowNumber,
                              context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
viewer.window.contentView!.keyDown(with: escape)
check(!viewer.window.isVisible, "Esc closes the artwork window")
panel.nowPlayingChanged(nil)
check(panel.nowPlayingRow.isHidden, "nothing playing hides the row")
panel.dropdown.appearance = NSAppearance(named: .aqua)
snapshot("recent-light")
panel.dropdown.setContentSize(NSSize(width: 260, height: 200)); layout()
check(rows(panel.clipSection).count == 100, "manual small resize retains full list")
snapshot("recent-small")
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
