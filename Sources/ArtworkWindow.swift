import AppKit

// Copy · Save · Open in Preview · Search YouTube · Show ‹App› for the Now Playing artwork — shared by the panel's
// Now Playing row and the artwork window. None of it sends anything to the playing app, so playback is untouched.
enum ArtworkActions {
    private static var names: [String: String] = [:]     // main thread only
    static func appName(_ bundleID: String) -> String {
        if let name = names[bundleID] { return name }
        var name = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
        if name == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path)
        }
        var result = name ?? bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        if result.hasSuffix(".app") { result = String(result.dropLast(4)) }
        names[bundleID] = result
        return result
    }
    static func appIcon(_ bundleID: String) -> NSImage? {
        if let icon = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.icon { return icon }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
    // Brings the app forward the way the Dock would — no Apple Events, so no Automation prompt.
    static func showApp(_ info: NowPlayingInfo) {
        NSRunningApplication.runningApplications(withBundleIdentifier: info.appBundleID).first?.activate(options: [])
    }
    // The original bytes; only a format we can't name is re-encoded (as PNG).
    static func fileData(_ info: NowPlayingInfo) -> (data: Data, ext: String)? {
        guard let data = info.artwork else { return nil }
        if let ext = info.artworkExtension { return (data, ext) }
        guard let tiff = NSImage(data: data)?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        return (png, "png")
    }
    static func copy(_ info: NowPlayingInfo) {
        guard let data = info.artwork, let image = NSImage(data: data) else { return }
        let item = NSPasteboardItem()
        let types: [String: String] = ["jpg": "public.jpeg", "png": "public.png", "gif": "com.compuserve.gif", "heic": "public.heic", "webp": "org.webmproject.webp"]
        if let ext = info.artworkExtension, let uti = types[ext] { item.setData(data, forType: NSPasteboard.PasteboardType(uti)) }
        if let tiff = image.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }
    static func save(_ info: NowPlayingInfo) {
        guard let file = fileData(info) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = info.suggestedFileName(extension: file.ext)
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }   // modal level: above the floating windows
        do { try file.data.write(to: url, options: .atomic) } catch { NSAlert(error: error).runModal() }
    }
    // One reused file in Caches (the folder is emptied first), opened in Preview.
    static func openInPreview(_ info: NowPlayingInfo) {
        guard let file = fileData(info) else { return }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("com.jacob.watch/artwork")
        try? FileManager.default.removeItem(at: dir)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(info.suggestedFileName(extension: file.ext))
            try file.data.write(to: url, options: .atomic)
            if let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
                NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
            } else { NSWorkspace.shared.open(url) }
        } catch { NSAlert(error: error).runModal() }
    }
    // Open Artwork · Open Full Screen (the row only) · Copy · Save… · Open in Preview — then Search YouTube · Show ‹App›.
    static func menuItems(_ info: NowPlayingInfo, open: (() -> Void)?, fullScreen: (() -> Void)?, search: @escaping (String) -> Void) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if info.artwork != nil {
            if let open = open { items.append(ClosureMenuItem("Open Artwork", handler: open)) }
            if let fullScreen = fullScreen { items.append(ClosureMenuItem("Open Full Screen", handler: fullScreen)) }
            items.append(ClosureMenuItem("Copy Artwork") { ArtworkActions.copy(info) })
            items.append(ClosureMenuItem("Save Artwork…") { ArtworkActions.save(info) })
            items.append(ClosureMenuItem("Open in Preview") { ArtworkActions.openInPreview(info) })
            items.append(.separator())
        }
        let short = info.title.count > 40 ? String(info.title.prefix(39)) + "…" : info.title
        let query = info.youtubeQuery
        items.append(ClosureMenuItem("Search YouTube for “\(short)”") { search(query) })
        items.append(ClosureMenuItem("Show \(appName(info.appBundleID))") { ArtworkActions.showApp(info) })
        return items
    }
}

// The Now Playing artwork in a floating, borderless window styled like the players. It follows the music: each
// update replaces the picture (a short cross-fade) and the caption without ordering the window front or taking
// focus. Hovering shows the caption and "…"; right-click shows the same menu; Esc or ⌘W closes.
// Full screen (double-click, ⌃⌘F or F, or the menu) is macOS full screen on its own Space: the artwork centred over
// a gradient of its own colours or black (Full-Screen Background ▸, `Prefs.artworkColourBackground`) with the caption
// under it; the caption, "…" and the pointer hide after a few idle seconds. Esc leaves full screen.
// Playback controls (ArtworkControlsView) slide in under the caption while the pointer is on it: timeline, ⏮ ⏯ ⏭ and
// Music's / Spotify's own volume. They act on the other app only when clicked (`onCommand` → NowPlayingRemote).
final class ArtworkWindowController: NSObject, NSWindowDelegate {
    static let minSide: CGFloat = 240, maxSide: CGFloat = 600
    static let placeholderDelay: TimeInterval = 1.5    // Music often sends a new track's artwork just after its title
    static let idleDelay: TimeInterval = 2.5           // full screen: caption, "…" and pointer hide after this
    static let revealDelay: TimeInterval = 0.15, collapseDelay: TimeInterval = 0.4
    static let seekHold: TimeInterval = 2              // show a seek's target until the app reports it (or this long)

    let window: NSWindow
    var onClose: (() -> Void)?
    var onSearch: ((String) -> Void)?
    var onCommand: ((NowPlayingRequest) -> Void)?
    var appVolume = AppVolumeControl()                 // replaceable in tests
    private(set) var controlsRevealed = false
    private(set) var volumeAccess: AppVolumeAccess = .unsupported
    private(set) var info: NowPlayingInfo?
    private(set) var pictureData: Data?                // the artwork showing (nil: none yet, or the placeholder)
    private(set) var inFullScreen = false
    private(set) var backgroundColours: (NSColor, NSColor)?   // the gradient showing; nil = black
    private let content = ArtworkContentView()
    private let background = ArtworkBackgroundView()
    private let artHolder = NSView()                   // casts the artwork's shadow in full screen
    private let imageView = ArtworkImageView()
    private let shade = GradientView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let dotButton = FadingButton(title: "", image: sym("ellipsis.circle.fill"), target: nil, action: nil)
    let controls = ArtworkControlsView()
    private var chromeVisible = false
    private var revealWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var tick: Timer?
    private var seekTarget: (seconds: Double, at: Date)?
    private var volumeApp: String?                     // the app `volumeAccess` belongs to
    private var askingVolume = false
    private var lastVolume = 0.5                       // what the speaker icon restores after muting
    private let artShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.45); s.shadowBlurRadius = 30; s.shadowOffset = NSSize(width: 0, height: -10)
        return s
    }()
    private var placeholderToken = 0
    private var notPlaying = false
    private var idleWork: DispatchWorkItem?
    private var savedAspect: NSSize?                   // the windowed aspect lock, set aside while in full screen
    private var closeAfterFullScreen = false

    override init() {
        let side: CGFloat = 320
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "Artwork"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(b)?.isHidden = true }
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 120, height: 120)
        window.delegate = self
        restoreWindowed(refit: false)                  // floating level, Space behaviour
        window.contentAspectRatio = NSSize(width: 1, height: 1)

        content.frame = NSRect(x: 0, y: 0, width: side, height: side)
        content.appearance = NSAppearance(named: .darkAqua)
        content.onLayout = { [weak self] in self?.layoutViews() }
        content.onPointer = { [weak self] point in self?.pointerMoved(at: point) }
        content.onMenu = { [weak self] in self?.makeMenu() }
        content.onClose = { [weak self] in self?.close() }
        content.onToggleFullScreen = { [weak self] in self?.toggleFullScreen() }
        content.onEscape = { [weak self] in
            guard let self = self else { return }
            if self.inFullScreen { self.toggleFullScreen() } else { self.close() }
        }
        window.contentView = content

        content.addSubview(background)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        artHolder.wantsLayer = true
        artHolder.addSubview(imageView)
        content.addSubview(artHolder)
        // Caption — over a bottom gradient in the window, under the artwork in full screen — shown with "…" on hover.
        shade.alphaValue = 0
        content.addSubview(shade)
        for (label, alpha) in [(titleLabel, CGFloat(0.95)), (detailLabel, CGFloat(0.7))] {
            label.textColor = NSColor.white.withAlphaComponent(alpha)
            label.lineBreakMode = .byTruncatingTail
            shade.addSubview(label)
        }
        dotButton.target = self; dotButton.action = #selector(showMenu)
        dotButton.alphaValue = 0
        dotButton.isBordered = false; dotButton.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        dotButton.imageScaling = .scaleProportionallyDown; dotButton.toolTip = "Menu"
        content.addSubview(dotButton)
        controls.alphaValue = 0
        controls.previous.onPress = { [weak self] in self?.onCommand?(.command(.previous)) }
        controls.next.onPress = { [weak self] in self?.onCommand?(.command(.next)) }
        controls.playPause.onPress = { [weak self] in self?.playPause() }
        controls.timeline.onChange = { [weak self] value, finished in self?.scrubbed(to: value, finished: finished) }
        controls.volume.onChange = { [weak self] value, finished in self?.volumeChanged(to: value, finished: finished) }
        controls.volumeIcon.onPress = { [weak self] in self?.toggleMute() }
        content.addSubview(controls)
        layoutViews()
    }

    // First open (or bring back): shows `info`, sized to the artwork's own resolution and placed on the panel's spot
    // (the panel then hides, as with the first video) or under the menu-bar icon.
    func present(_ info: NowPlayingInfo, replacing panel: NSRect?, anchor: NSStatusItem?) {
        let wasVisible = window.isVisible
        show(info)
        if !wasVisible {
            let screen = panel.flatMap { WindowManager.screen(for: $0) } ?? anchor?.button?.window?.screen ?? NSScreen.main
            let size = initialSize(on: screen)
            window.contentAspectRatio = size
            if let frame = panel.map({ WindowManager.frame(replacing: $0, size: size) }) ?? anchor.flatMap({ WindowManager.frame(under: $0, size: size) }) {
                window.setFrame(frame, display: true)
            } else { window.setContentSize(size); window.center() }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(content)
    }
    // Close — from full screen, after leaving it, so the window doesn't vanish mid-animation on its own Space.
    func close() {
        if inFullScreen { closeAfterFullScreen = true; window.toggleFullScreen(nil) } else { window.close() }
    }

    // A follow update. Nothing playing keeps the last picture; a new track without artwork keeps the old one for a
    // moment, then shows the app's icon.
    func show(_ new: NowPlayingInfo?) {
        guard let new = new else { notPlaying = true; updateCaption(); return }
        let newTrack = new.itemKey != info?.itemKey
        info = new; notPlaying = false
        updateCaption()
        if controlsRevealed {
            refreshControls()
            if new.appBundleID != volumeApp { refreshVolume() }
        }
        if let art = new.artwork {
            placeholderToken += 1
            if art != pictureData, let image = NSImage(data: art) { setPicture(image, data: art) }
        } else if pictureData == nil {
            placeholderToken += 1
            showPlaceholder()
        } else if newTrack {
            placeholderToken += 1
            let token = placeholderToken
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.placeholderDelay) { [weak self] in
                guard let self = self, token == self.placeholderToken else { return }
                self.showPlaceholder()
            }
        }
    }

    private func setPicture(_ image: NSImage, data: Data?) {
        let animate = window.isVisible && imageView.image != nil
        if animate {
            let fade = CATransition(); fade.type = .fade; fade.duration = 0.25
            imageView.layer?.add(fade, forKey: "fade")
        }
        imageView.imageScaling = data == nil ? .scaleProportionallyDown : .scaleProportionallyUpOrDown
        imageView.image = image
        pictureData = data
        refreshBackground(animated: animate)
        if inFullScreen { layoutViews() } else if data != nil { fitAspect(Self.pixelSize(image)) }
    }
    private func showPlaceholder() {
        guard let info = info else { return }
        let icon = (ArtworkActions.appIcon(info.appBundleID)?.copy() as? NSImage) ?? sym("music.note")
        icon.size = NSSize(width: 96, height: 96)
        setPicture(icon, data: nil)
    }
    private func updateCaption() {
        guard let info = info else { return }
        titleLabel.stringValue = info.title
        var detail = [[info.artist, info.album].compactMap { $0 }.joined(separator: " — ")].filter { !$0.isEmpty }
        detail.append(ArtworkActions.appName(info.appBundleID))
        if notPlaying { detail.append("Not playing") } else if !info.isPlaying { detail.append("Paused") }
        detailLabel.stringValue = detail.joined(separator: " · ")
        imageView.setAccessibilityLabel("Artwork: \(info.title)" + (info.artist.map { " by \($0)" } ?? ""))
    }
    // The gradient follows the artwork (black for the placeholder, or when Black is chosen).
    private func refreshBackground(animated: Bool) {
        backgroundColours = Prefs.artworkColourBackground && pictureData != nil ? imageView.image.flatMap(Self.palette) : nil
        background.show(backgroundColours, animated: animated)
    }
    // Two colours from the artwork (ArtworkPalette), from a 16×16 sample.
    static func palette(_ image: NSImage) -> (NSColor, NSColor)? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn, let colours = ArtworkPalette.gradient(pixels: pixels, width: side, height: side) else { return nil }
        func colour(_ c: RGB) -> NSColor { NSColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1) }
        return (colour(colours.start), colour(colours.end))
    }

    // Window: the artwork fills it, caption along the bottom; revealing the controls grows that band upward by their
    // height and lifts the text. Full screen: ArtworkLayout — the artwork centred with rounded corners and a shadow,
    // the caption centred under it, the controls' (reserved) row under that, "…" clear of the menu bar.
    private func layoutViews(animated: Bool = false) {
        let b = content.bounds, full = inFullScreen
        let lift = controlsRevealed && !full ? ArtworkLayout.controlsHeight : 0
        let shadeFrame: NSRect, controlsFrame: NSRect
        background.frame = b
        if full {
            let spot = ArtworkLayout.fullScreen(artwork: imageView.image.map(Self.pixelSize) ?? NSSize(width: 1, height: 1), in: b.size)
            artHolder.frame = spot.art
            shadeFrame = spot.caption; controlsFrame = spot.controls
            dotButton.frame = NSRect(x: b.width - 40, y: b.height - 56, width: 16, height: 16)
        } else {
            artHolder.frame = b
            shadeFrame = NSRect(x: 0, y: 0, width: b.width, height: ArtworkLayout.windowBand + lift)
            controlsFrame = NSRect(x: 12, y: 6, width: max(0, b.width - 24), height: ArtworkLayout.controlsHeight)
            dotButton.frame = NSRect(x: b.width - 20, y: b.height - 20, width: 16, height: 16)
        }
        imageView.frame = artHolder.bounds
        imageView.layer?.cornerRadius = full ? 8 : 0
        artHolder.shadow = full ? artShadow : nil
        shade.showsGradient = !full
        let styles: [(NSTextField, CGFloat, NSFont.Weight, CGFloat)] = full    // label, size, weight, y
            ? [(titleLabel, 22, .semibold, 32), (detailLabel, 15, .regular, 6)]
            : [(titleLabel, 13, .semibold, 28 + lift), (detailLabel, 11, .regular, 11 + lift)]
        let inset: CGFloat = full ? 0 : 12
        let controlsAlpha: CGFloat = controlsRevealed && chromeVisible ? 1 : 0
        func place(_ view: NSView, _ frame: NSRect) { if animated { view.animator().frame = frame } else { view.frame = frame } }
        let apply = {
            place(self.shade, shadeFrame)
            for (label, size, weight, y) in styles {
                label.font = .systemFont(ofSize: size, weight: weight)
                label.alignment = full ? .center : .left
                place(label, NSRect(x: inset, y: y, width: max(0, shadeFrame.width - 2 * inset), height: size + (full ? 6 : 4)))
            }
            place(self.controls, controlsFrame)
            if animated { self.controls.animator().alphaValue = controlsAlpha } else { self.controls.alphaValue = controlsAlpha }
        }
        if animated { NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.2; apply() } } else { apply() }
    }

    // Album art is square, a video's thumbnail 16:9: keep the width and the top-left corner, change the height.
    private func fitAspect(_ size: NSSize) {
        guard !inFullScreen, size.width > 0, size.height > 0 else { return }
        let ratio = size.width / size.height, current = window.contentAspectRatio
        guard current.height <= 0 || abs(current.width / current.height - ratio) > 0.01 else { return }
        window.contentAspectRatio = size
        var f = window.frame
        let height = (f.width / ratio).rounded()
        f.origin.y += f.height - height; f.size.height = height
        if let vis = WindowManager.screen(for: f)?.visibleFrame { f = WindowManager.clamp(f, to: vis) }
        window.setFrame(f, display: true, animate: window.isVisible)
    }
    // Its own pixels at the screen's scale — sharp — kept between minSide and min(maxSide, 70% of the screen height).
    private func initialSize(on screen: NSScreen?) -> NSSize {
        let scale = screen?.backingScaleFactor ?? 2
        let pixels = imageView.image.map(Self.pixelSize) ?? NSSize(width: 640, height: 640)
        let natural = NSSize(width: pixels.width / scale, height: pixels.height / scale)
        let longest = max(natural.width, natural.height, 1)
        let cap = min(Self.maxSide, (screen?.visibleFrame.height ?? 900) * 0.7)
        let target = min(max(longest, Self.minSide), cap)
        return NSSize(width: (natural.width * target / longest).rounded(), height: (natural.height * target / longest).rounded())
    }
    static func pixelSize(_ image: NSImage) -> NSSize {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    // MARK: full screen
    // macOS full screen on its own Space. The window normally floats, keeps its aspect ratio and joins other apps'
    // full-screen Spaces; all three are set aside for full screen and restored afterwards (restoreWindowed).
    func toggleFullScreen() {
        if !inFullScreen {
            savedAspect = window.contentAspectRatio
            window.contentResizeIncrements = NSSize(width: 1, height: 1)   // clears the aspect-ratio lock
            window.level = .normal
            window.collectionBehavior = [.fullScreenPrimary]
        }
        window.toggleFullScreen(nil)
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        inFullScreen = true
        layoutViews()
        pointerMoved(at: NSPoint(x: content.bounds.midX, y: content.bounds.maxY))   // show the caption, then let it fade
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        inFullScreen = false
        idleWork?.cancel()
        layoutViews()
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        restoreWindowed(refit: !closeAfterFullScreen)
        if closeAfterFullScreen { closeAfterFullScreen = false; window.close() }
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        inFullScreen = false
        restoreWindowed(refit: false)
        layoutViews()
    }
    private func restoreWindowed(refit: Bool) {
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        if let aspect = savedAspect, aspect.width > 0, aspect.height > 0 { window.contentAspectRatio = aspect }
        savedAspect = nil
        if refit, pictureData != nil, let image = imageView.image { fitAspect(Self.pixelSize(image)) }   // the track may have changed
    }

    // Hover shows the caption and "…"; resting on the caption (or the revealed controls) slides the controls in. In
    // full screen they — and the pointer — hide again after idleDelay, unless the pointer is on the controls.
    func pointerMoved(at point: NSPoint?) {
        fadeChrome(visible: point != nil)
        let over = point.map { controlsZone.contains($0) } ?? false
        if over {
            collapseWork?.cancel(); collapseWork = nil
            if !controlsRevealed && revealWork == nil { revealWork = after(Self.revealDelay) { $0.revealWork = nil; $0.setControls(revealed: true) } }
        } else {
            revealWork?.cancel(); revealWork = nil
            if point == nil, !controls.isInteracting { collapseWork?.cancel(); collapseWork = nil; setControls(revealed: false) }
            else if controlsRevealed && collapseWork == nil {
                collapseWork = after(Self.collapseDelay) { me in
                    me.collapseWork = nil
                    if !me.controls.isInteracting { me.setControls(revealed: false) }
                }
            }
        }
        idleWork?.cancel()
        guard inFullScreen, point != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.inFullScreen else { return }
            let m = self.content.convert(self.window.mouseLocationOutsideOfEventStream, from: nil)
            if self.controls.isInteracting || (self.controlsRevealed && self.controlsZone.contains(m)) { self.pointerMoved(at: m); return }
            self.fadeChrome(visible: false)
            self.setControls(revealed: false)
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleDelay, execute: work)
    }
    // The caption band (grown while the controls show); in full screen the caption plus the controls' row.
    private var controlsZone: NSRect { inFullScreen ? shade.frame.union(controls.frame) : shade.frame }
    private func after(_ delay: TimeInterval, _ body: @escaping (ArtworkWindowController) -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem { [weak self] in if let self = self { body(self) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return work
    }
    private func fadeChrome(visible: Bool) {
        chromeVisible = visible
        let target: CGFloat = visible ? 1 : 0, controlsTarget: CGFloat = visible && controlsRevealed ? 1 : 0
        guard dotButton.alphaValue != target || controls.alphaValue != controlsTarget else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = visible ? 0.15 : 0.25
            dotButton.animator().alphaValue = target
            shade.animator().alphaValue = target
            controls.animator().alphaValue = controlsTarget
        }
    }

    // MARK: playback controls
    private func setControls(revealed: Bool) {
        guard revealed != controlsRevealed else { return }
        controlsRevealed = revealed
        tick?.invalidate(); tick = nil
        if revealed {
            refreshControls()
            refreshVolume()
            tick = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshControls() }
        }
        layoutViews(animated: window.isVisible)
    }
    // Play/pause icon and the timeline. After a seek the dragged-to time shows until the app reports it (seekHold).
    private func refreshControls() {
        guard let info = info else { return }
        controls.setPlaying(info.isPlaying)
        let duration = info.duration ?? 0
        controls.showsTimeline = duration > 0
        guard duration > 0, !controls.timeline.isTracking else { return }
        var position = info.position(at: Date()) ?? 0
        if let target = seekTarget {
            let since = Date().timeIntervalSince(target.at), wanted = target.seconds + (info.isPlaying ? since : 0)
            if since < Self.seekHold, abs(position - wanted) > 1.5 { position = min(wanted, duration) } else { seekTarget = nil }
        }
        controls.setTime(position: position, duration: duration)
    }
    // Sends play or pause from what's showing and shows the result straight away; the stream confirms it.
    private func playPause() {
        guard var shown = info else { return }
        let now = Date()
        if shown.isPlaying {
            shown.elapsed = shown.position(at: now); shown.elapsedAt = now; shown.isPlaying = false
            onCommand?(.command(.pause))
        } else {
            shown.elapsedAt = now; shown.isPlaying = true
            onCommand?(.command(.play))
        }
        info = shown
        updateCaption()
        refreshControls()
    }
    private func scrubbed(to value: Double, finished: Bool) {
        guard let duration = info?.duration, duration > 0 else { return }
        controls.setTime(position: value * duration, duration: duration, movingSlider: false)
        guard finished else { return }
        seekTarget = (value * duration, Date())
        onCommand?(.seek(value * duration))
    }

    // Music's / Spotify's own volume: checked (never asked) when the controls appear; the first drag of a not-yet-
    // allowed app asks macOS once, on release, then applies.
    private func refreshVolume() {
        guard let id = info?.appBundleID else { return }
        volumeApp = id
        appVolume.check(id) { [weak self] access, level in
            guard let self = self, self.volumeApp == id else { return }
            self.volumeAccess = access
            if let level = level, !self.controls.volume.isTracking { self.controls.volume.value = level; if level > 0 { self.lastVolume = level } }
            self.controls.setVolume(access: access, appName: ArtworkActions.appName(id))
        }
    }
    private func volumeChanged(to value: Double, finished: Bool) {
        guard let id = volumeApp else { return }
        controls.setVolume(access: volumeAccess, appName: ArtworkActions.appName(id))
        if value > 0 && finished { lastVolume = value }
        switch volumeAccess {
        case .granted: appVolume.set(id, value)
        case .undetermined where finished && !askingVolume:
            askingVolume = true
            appVolume.requestAccess(id) { [weak self] access in
                guard let self = self else { return }
                self.askingVolume = false
                guard self.volumeApp == id else { return }
                self.volumeAccess = access
                self.controls.setVolume(access: access, appName: ArtworkActions.appName(id))
                if access == .granted { self.appVolume.set(id, self.controls.volume.value) }
            }
        default: break
        }
    }
    private func toggleMute() {
        guard volumeAccess == .granted || volumeAccess == .undetermined else { return }
        controls.volume.value = controls.volume.value > 0 ? 0 : lastVolume
        volumeChanged(to: controls.volume.value, finished: true)
    }

    // Close · Enter/Exit Full Screen · Full-Screen Background ▸ Artwork Colours / Black — then the artwork actions.
    func makeMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(ClosureMenuItem("Close") { [weak self] in self?.close() })
        let full = ClosureMenuItem(inFullScreen ? "Exit Full Screen" : "Enter Full Screen") { [weak self] in self?.toggleFullScreen() }
        full.keyEquivalent = "f"; full.keyEquivalentModifierMask = [.control, .command]   // shown only; the content view handles the keys
        m.addItem(full)
        let backgrounds = NSMenu()
        for (title, colours) in [("Artwork Colours", true), ("Black", false)] {
            let item = ClosureMenuItem(title) { [weak self] in
                Prefs.artworkColourBackground = colours
                self?.refreshBackground(animated: true)
            }
            item.state = Prefs.artworkColourBackground == colours ? .on : .off
            backgrounds.addItem(item)
        }
        let backgroundItem = NSMenuItem(title: "Full-Screen Background", action: nil, keyEquivalent: "")
        backgroundItem.submenu = backgrounds
        m.addItem(backgroundItem)
        if let info = info {
            m.addItem(.separator())
            ArtworkActions.menuItems(info, open: nil, fullScreen: nil, search: { [weak self] q in self?.onSearch?(q) }).forEach(m.addItem)
        }
        return m
    }
    @objc private func showMenu() {
        makeMenu().popUp(positioning: nil, at: NSPoint(x: dotButton.frame.minX - 150, y: dotButton.frame.minY - 4), in: content)
    }
    func windowWillClose(_ notification: Notification) {
        placeholderToken += 1
        idleWork?.cancel(); revealWork?.cancel(); collapseWork?.cancel(); revealWork = nil; collapseWork = nil
        tick?.invalidate(); tick = nil
        controlsRevealed = false; chromeVisible = false
        layoutViews()
        if savedAspect != nil { inFullScreen = false; restoreWindowed(refit: false) }   // closed by the system mid-full-screen
        onClose?()
    }
}

// The window's content: hover reveals the caption, right-click shows the menu; Esc (leaves full screen, else closes),
// ⌘W, ⌃⌘F / F and double-click (full screen). Dragging anywhere moves the window — the top edge too: like
// PlayerSurfaceView it keeps title-bar-area clicks, so a double-click there doesn't zoom the window.
final class ArtworkContentView: NSView {
    var onPointer: ((NSPoint?) -> Void)?                // where the pointer is; nil once it leaves
    var onMenu: (() -> NSMenu?)?
    var onClose: (() -> Void)?
    var onEscape: (() -> Void)?
    var onToggleFullScreen: (() -> Void)?
    var onLayout: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); onLayout?() }
    override func mouseEntered(with e: NSEvent) { onPointer?(convert(e.locationInWindow, from: nil)) }
    override func mouseMoved(with e: NSEvent) { onPointer?(convert(e.locationInWindow, from: nil)) }
    override func mouseExited(with e: NSEvent) { onPointer?(nil) }
    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { onToggleFullScreen?() } else if e.clickCount == 1 { window?.performDrag(with: e) }
    }
    override func menu(for event: NSEvent) -> NSMenu? { onMenu?() }
    override func keyDown(with e: NSEvent) {
        let mods = e.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = e.charactersIgnoringModifiers?.lowercased()
        if e.keyCode == 53 { onEscape?() }
        else if mods == .command && key == "w" { onClose?() }
        else if key == "f" && (mods.isEmpty || mods == [.control, .command]) { onToggleFullScreen?() }
        else { super.keyDown(with: e) }
    }
}

// The picture never takes clicks or drags (they go to the content view, which moves the window).
final class ArtworkImageView: NSImageView {
    override init(frame: NSRect) { super.init(frame: frame); isEditable = false; unregisterDraggedTypes() }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// Full screen's backdrop: a top-left → bottom-right gradient of the artwork's colours, or black. Changes cross-fade.
final class ArtworkBackgroundView: NSView {
    private let gradient = CAGradientLayer()
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override func makeBackingLayer() -> CALayer {
        gradient.startPoint = CGPoint(x: 0, y: 1); gradient.endPoint = CGPoint(x: 1, y: 0)
        gradient.colors = [NSColor.black.cgColor, NSColor.black.cgColor]
        return gradient
    }
    func show(_ colours: (NSColor, NSColor)?, animated: Bool) {
        if animated {
            let fade = CATransition(); fade.type = .fade; fade.duration = 0.4
            gradient.add(fade, forKey: "fade")
        }
        let (start, end) = colours ?? (NSColor.black, NSColor.black)
        gradient.colors = [start.cgColor, end.cgColor]
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// Black → clear, bottom to top, under the window's caption (clear in full screen, where the caption sits under the art).
final class GradientView: NSView {
    var showsGradient = true { didSet { if showsGradient != oldValue { (layer as? CAGradientLayer)?.colors = colours } } }
    private var colours: [CGColor] {
        showsGradient ? [NSColor.black.withAlphaComponent(0.7).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
                      : [NSColor.clear.cgColor, NSColor.clear.cgColor]
    }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override func makeBackingLayer() -> CALayer {
        let g = CAGradientLayer()
        g.colors = colours
        g.startPoint = CGPoint(x: 0.5, y: 0); g.endPoint = CGPoint(x: 0.5, y: 1)
        return g
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// The artwork window's playback controls, revealed by hovering its caption: a timeline with elapsed / remaining time,
// ⏮ ⏯ ⏭ in the middle and — for an app whose volume Watch can set — that app's volume at the right. Clicks on empty
// space fall through (the window still drags from there); nothing is clickable while it's faded out.
final class ArtworkControlsView: NSView {
    let timeline = ThinSlider(), volume = ThinSlider()
    let previous = GlyphButton(symbol: "backward.fill", pointSize: 13, tip: "Previous")
    let playPause = GlyphButton(symbol: "play.fill", pointSize: 15, tip: "Play")
    let next = GlyphButton(symbol: "forward.fill", pointSize: 13, tip: "Next")
    let volumeIcon = GlyphButton(symbol: "speaker.wave.2.fill", pointSize: 11, tip: "Volume")
    private let elapsedLabel = NSTextField(labelWithString: "0:00"), remainingLabel = NSTextField(labelWithString: "-0:00")
    private static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
    var showsTimeline = true { didSet { if showsTimeline != oldValue { layoutParts() } } }
    private(set) var access: AppVolumeAccess = .unsupported
    private var longClock = false
    var isInteracting: Bool { timeline.isTracking || volume.isTracking }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for label in [elapsedLabel, remainingLabel] {
            label.font = Self.timeFont; label.textColor = NSColor.white.withAlphaComponent(0.6)
            addSubview(label)
        }
        elapsedLabel.alignment = .left; remainingLabel.alignment = .right
        for v in [timeline, previous, playPause, next, volumeIcon, volume] as [NSView] { addSubview(v) }
        timeline.setAccessibilityLabel("Position")
        volume.setAccessibilityLabel("Volume")
        layoutParts()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); layoutParts() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard alphaValue >= 0.05, !isHidden, let hit = super.hitTest(point) else { return nil }
        return hit === self ? nil : hit
    }

    func setPlaying(_ playing: Bool) {
        playPause.setSymbol(playing ? "pause.fill" : "play.fill")
        playPause.toolTip = playing ? "Pause" : "Play"
    }
    // `movingSlider` false while the timeline is being dragged: the labels follow the finger, the slider is already there.
    func setTime(position: Double, duration: Double, movingSlider: Bool = true) {
        if movingSlider { timeline.value = duration > 0 ? position / duration : 0 }
        elapsedLabel.stringValue = NowPlayingInfo.clock(position)
        remainingLabel.stringValue = NowPlayingInfo.clock(duration - position, remaining: true)
        let long = duration >= 3600
        if long != longClock { longClock = long; layoutParts() }
    }
    func setVolume(access: AppVolumeAccess, appName: String) {
        self.access = access
        volumeIcon.setSymbol(volumeSymbol(volume.value))
        volumeIcon.dimmed = access == .denied
        switch access {
        case .granted: volumeIcon.toolTip = "\(appName) volume — click to mute"
        case .undetermined: volumeIcon.toolTip = "Drag to set \(appName)'s volume (macOS asks once)"
        case .denied: volumeIcon.toolTip = "Watch isn't allowed to set \(appName)'s volume. Allow it in System Settings ▸ Privacy & Security ▸ Automation."
        case .unsupported: volumeIcon.toolTip = nil
        }
        layoutParts()
    }

    // Timeline row on top (times hide below 170 pt), buttons centred underneath; the volume takes the right edge when
    // it fits beside them (slider, else just the icon).
    private func layoutParts() {
        let w = bounds.width, h = bounds.height, row = h - 18
        let times = showsTimeline && w >= 170, labelWidth: CGFloat = longClock ? 46 : 34
        timeline.isHidden = !showsTimeline
        elapsedLabel.isHidden = !times; remainingLabel.isHidden = !times
        if times {
            elapsedLabel.frame = NSRect(x: 0, y: row + 2, width: labelWidth, height: 13)
            remainingLabel.frame = NSRect(x: w - labelWidth, y: row + 2, width: labelWidth, height: 13)
            timeline.frame = NSRect(x: labelWidth + 4, y: row, width: max(0, w - 2 * labelWidth - 8), height: 18)
        } else {
            timeline.frame = NSRect(x: 0, y: row, width: w, height: 18)
        }
        let size: CGFloat = 26, gap: CGFloat = 10, mid = (w / 2).rounded()
        previous.frame = NSRect(x: mid - size * 1.5 - gap, y: 2, width: size, height: size)
        playPause.frame = NSRect(x: mid - size / 2, y: 2, width: size, height: size)
        next.frame = NSRect(x: mid + size / 2 + gap, y: 2, width: size, height: size)
        let clear = next.frame.maxX + 8, icon: CGFloat = 18, slider: CGFloat = 48
        let slides = access == .granted || access == .undetermined
        volumeIcon.isHidden = access == .unsupported || w - icon < clear
        volume.isHidden = volumeIcon.isHidden || !slides || w - icon - 4 - slider < clear
        if volume.isHidden {
            volumeIcon.frame = NSRect(x: w - icon, y: 6, width: icon, height: 18)
        } else {
            volume.frame = NSRect(x: w - slider, y: 6, width: slider, height: 18)
            volumeIcon.frame = NSRect(x: w - slider - 4 - icon, y: 6, width: icon, height: 18)
        }
    }
}

enum AppVolumeAccess { case unsupported, granted, undetermined, denied }

// Runs AppVolume's scripts off the main thread (an app can take a moment to answer Apple Events), only for a running,
// supported app. `check` never asks macOS; only `requestAccess` (the first drag, on release) can show its prompt.
// Drags send through a CoalescingSender, so the app only ever gets the newest level.
class AppVolumeControl {
    private let queue = DispatchQueue(label: "watch.appvolume")
    private lazy var sender = CoalescingSender<(String, Double)>(queue: queue) { request in
        if let script = AppVolume.writeScript(request.0, level: request.1) { _ = Self.run(script) }
    }
    func check(_ bundleID: String, completion: @escaping (AppVolumeAccess, Double?) -> Void) {
        guard AppVolume.supported.contains(bundleID), Self.isRunning(bundleID) else { completion(.unsupported, nil); return }
        queue.async {
            let access = Self.access(automationPermission(bundleID, ask: false))
            let level = access == .granted ? AppVolume.readScript(bundleID).flatMap(Self.run).map { AppVolume.level(percent: Int($0.int32Value)) } : nil
            DispatchQueue.main.async { completion(access, level) }
        }
    }
    func requestAccess(_ bundleID: String, completion: @escaping (AppVolumeAccess) -> Void) {
        guard AppVolume.supported.contains(bundleID), Self.isRunning(bundleID) else { completion(.unsupported); return }
        queue.async {
            let access = Self.access(automationPermission(bundleID, ask: true))
            DispatchQueue.main.async { completion(access) }
        }
    }
    func set(_ bundleID: String, _ level: Double) { sender.send((bundleID, level)) }

    static func access(_ status: OSStatus) -> AppVolumeAccess {
        switch status {
        case noErr: return .granted
        case errAEWouldRequireUserConsent: return .undetermined
        case OSStatus(procNotFound): return .unsupported
        default: return .denied
        }
    }
    private static func isRunning(_ bundleID: String) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else { return nil }
        return result
    }
}
