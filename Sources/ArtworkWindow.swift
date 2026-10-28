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
final class ArtworkWindowController: NSObject, NSWindowDelegate {
    static let minSide: CGFloat = 240, maxSide: CGFloat = 600
    static let placeholderDelay: TimeInterval = 1.5    // Music often sends a new track's artwork just after its title
    static let idleDelay: TimeInterval = 2.5           // full screen: caption, "…" and pointer hide after this

    let window: NSWindow
    var onClose: (() -> Void)?
    var onSearch: ((String) -> Void)?
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
        content.onHover = { [weak self] inside in self?.pointerMoved(inside: inside) }
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

    // Window: the artwork fills it, caption along the bottom. Full screen: ArtworkLayout — the artwork centred with
    // rounded corners and a shadow, the caption centred under it, "…" clear of the menu bar.
    private func layoutViews() {
        let b = content.bounds, full = inFullScreen
        background.frame = b
        if full {
            let spot = ArtworkLayout.fullScreen(artwork: imageView.image.map(Self.pixelSize) ?? NSSize(width: 1, height: 1), in: b.size)
            artHolder.frame = spot.art
            shade.frame = spot.caption
            dotButton.frame = NSRect(x: b.width - 40, y: b.height - 56, width: 16, height: 16)
        } else {
            artHolder.frame = b
            shade.frame = NSRect(x: 0, y: 0, width: b.width, height: 64)
            dotButton.frame = NSRect(x: b.width - 20, y: b.height - 20, width: 16, height: 16)
        }
        imageView.frame = artHolder.bounds
        imageView.layer?.cornerRadius = full ? 8 : 0
        artHolder.shadow = full ? artShadow : nil
        shade.showsGradient = !full
        let styles: [(NSTextField, CGFloat, NSFont.Weight, CGFloat)] = full    // label, size, weight, y
            ? [(titleLabel, 22, .semibold, 32), (detailLabel, 15, .regular, 6)]
            : [(titleLabel, 13, .semibold, 28), (detailLabel, 11, .regular, 11)]
        let inset: CGFloat = full ? 0 : 12
        for (label, size, weight, y) in styles {
            label.font = .systemFont(ofSize: size, weight: weight)
            label.alignment = full ? .center : .left
            label.frame = NSRect(x: inset, y: y, width: max(0, shade.bounds.width - 2 * inset), height: size + (full ? 6 : 4))
        }
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
        pointerMoved(inside: true)                      // show the caption, then let it fade
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

    // Hover shows the caption and "…"; in full screen they — and the pointer — hide again after idleDelay.
    private func pointerMoved(inside: Bool) {
        fadeChrome(visible: inside)
        idleWork?.cancel()
        guard inFullScreen, inside else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.inFullScreen else { return }
            self.fadeChrome(visible: false)
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleDelay, execute: work)
    }
    private func fadeChrome(visible: Bool) {
        let target: CGFloat = visible ? 1 : 0
        guard dotButton.alphaValue != target else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = visible ? 0.15 : 0.25
            dotButton.animator().alphaValue = target
            shade.animator().alphaValue = target
        }
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
        idleWork?.cancel()
        if savedAspect != nil { inFullScreen = false; restoreWindowed(refit: false) }   // closed by the system mid-full-screen
        onClose?()
    }
}

// The window's content: hover reveals the caption, right-click shows the menu; Esc (leaves full screen, else closes),
// ⌘W, ⌃⌘F / F and double-click (full screen). Dragging anywhere moves the window — the top edge too: like
// PlayerSurfaceView it keeps title-bar-area clicks, so a double-click there doesn't zoom the window.
final class ArtworkContentView: NSView {
    var onHover: ((Bool) -> Void)?
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
    override func mouseEntered(with e: NSEvent) { onHover?(true) }
    override func mouseMoved(with e: NSEvent) { onHover?(true) }
    override func mouseExited(with e: NSEvent) { onHover?(false) }
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
