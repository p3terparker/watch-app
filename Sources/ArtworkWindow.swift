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
    // Open Artwork (the row only) · Copy · Save… · Open in Preview — then Search YouTube · Show ‹App›.
    static func menuItems(_ info: NowPlayingInfo, open: (() -> Void)?, search: @escaping (String) -> Void) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if info.artwork != nil {
            if let open = open { items.append(ClosureMenuItem("Open Artwork", handler: open)) }
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
final class ArtworkWindowController: NSObject, NSWindowDelegate {
    static let minSide: CGFloat = 240, maxSide: CGFloat = 600
    static let placeholderDelay: TimeInterval = 1.5    // Music often sends a new track's artwork just after its title

    let window: NSWindow
    var onClose: (() -> Void)?
    var onSearch: ((String) -> Void)?
    private(set) var info: NowPlayingInfo?
    private(set) var pictureData: Data?                // the artwork showing (nil: none yet, or the placeholder)
    private let content = ArtworkContentView()
    private let imageView = ArtworkImageView()
    private let shade = GradientView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let dotButton = FadingButton(title: "", image: sym("ellipsis.circle.fill"), target: nil, action: nil)
    private var placeholderToken = 0
    private var notPlaying = false

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
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentAspectRatio = NSSize(width: 1, height: 1)
        window.minSize = NSSize(width: 120, height: 120)
        window.delegate = self

        content.frame = NSRect(x: 0, y: 0, width: side, height: side)
        content.appearance = NSAppearance(named: .darkAqua)
        content.onHover = { [weak self] inside in self?.fadeChrome(visible: inside) }
        content.onMenu = { [weak self] in self?.menu() }
        content.onClose = { [weak self] in self?.window.close() }
        window.contentView = content

        imageView.frame = content.bounds; imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        content.addSubview(imageView)

        // Caption over a bottom gradient, shown with "…" while the cursor is over the window.
        shade.frame = NSRect(x: 0, y: 0, width: side, height: 64); shade.autoresizingMask = [.width, .maxYMargin]
        shade.alphaValue = 0
        content.addSubview(shade)
        let captionStyles: [(NSTextField, CGFloat, NSFont.Weight, CGFloat, CGFloat)] = [   // label, size, weight, opacity, y
            (titleLabel, 13, .semibold, 0.95, 28), (detailLabel, 11, .regular, 0.7, 11)]
        for (label, size, weight, alpha, y) in captionStyles {
            label.font = .systemFont(ofSize: size, weight: weight)
            label.textColor = NSColor.white.withAlphaComponent(alpha)
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: 12, y: y, width: side - 24, height: size + 4); label.autoresizingMask = [.width, .maxYMargin]
            shade.addSubview(label)
        }

        dotButton.target = self; dotButton.action = #selector(showMenu)
        dotButton.alphaValue = 0
        dotButton.isBordered = false; dotButton.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        dotButton.imageScaling = .scaleProportionallyDown; dotButton.toolTip = "Menu"
        dotButton.frame = NSRect(x: side - 20, y: side - 20, width: 16, height: 16)
        dotButton.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(dotButton)
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
        if window.isVisible, imageView.image != nil {
            let fade = CATransition(); fade.type = .fade; fade.duration = 0.25
            imageView.layer?.add(fade, forKey: "fade")
        }
        imageView.imageScaling = data == nil ? .scaleProportionallyDown : .scaleProportionallyUpOrDown
        imageView.image = image
        pictureData = data
        if data != nil { fitAspect(Self.pixelSize(image)) }
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

    // Album art is square, a video's thumbnail 16:9: keep the width and the top-left corner, change the height.
    private func fitAspect(_ size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
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

    private func fadeChrome(visible: Bool) {
        let target: CGFloat = visible ? 1 : 0
        guard dotButton.alphaValue != target else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = visible ? 0.15 : 0.25
            dotButton.animator().alphaValue = target
            shade.animator().alphaValue = target
        }
    }
    private func menu() -> NSMenu {
        let m = NSMenu()
        m.addItem(ClosureMenuItem("Close") { [weak self] in self?.window.close() })
        if let info = info {
            m.addItem(.separator())
            ArtworkActions.menuItems(info, open: nil, search: { [weak self] q in self?.onSearch?(q) }).forEach(m.addItem)
        }
        return m
    }
    @objc private func showMenu() {
        menu().popUp(positioning: nil, at: NSPoint(x: dotButton.frame.minX - 150, y: dotButton.frame.minY - 4), in: content)
    }
    func windowWillClose(_ notification: Notification) {
        placeholderToken += 1
        onClose?()
    }
}

// The window's content: hover reveals the caption, right-click shows the menu, Esc / ⌘W close. Dragging anywhere
// moves the window — the top edge too: like PlayerSurfaceView it keeps title-bar-area clicks, so a double-click there
// doesn't zoom the window.
final class ArtworkContentView: NSView {
    var onHover: ((Bool) -> Void)?
    var onMenu: (() -> NSMenu?)?
    var onClose: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with e: NSEvent) { onHover?(true) }
    override func mouseMoved(with e: NSEvent) { onHover?(true) }
    override func mouseExited(with e: NSEvent) { onHover?(false) }
    override func mouseDown(with e: NSEvent) { if e.clickCount == 1 { window?.performDrag(with: e) } }
    override func menu(for event: NSEvent) -> NSMenu? { onMenu?() }
    override func keyDown(with e: NSEvent) {
        let command = e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        if e.keyCode == 53 || (command && e.charactersIgnoringModifiers == "w") { onClose?() } else { super.keyDown(with: e) }
    }
}

// The picture never takes clicks or drags (they go to the content view, which moves the window).
final class ArtworkImageView: NSImageView {
    override init(frame: NSRect) { super.init(frame: frame); isEditable = false; unregisterDraggedTypes() }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// Black → clear, bottom to top, under the caption.
final class GradientView: NSView {
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override func makeBackingLayer() -> CALayer {
        let g = CAGradientLayer()
        g.colors = [NSColor.black.withAlphaComponent(0.7).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
        g.startPoint = CGPoint(x: 0.5, y: 0); g.endPoint = CGPoint(x: 0.5, y: 1)
        return g
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
