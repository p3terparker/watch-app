import AppKit

// The Up Next list that drops down under the music window (3.21), like Music's MiniPlayer: a child window that moves with
// it, as wide as it (at least 300 pt), up to 360 pt tall; with no room below it flips above, or the window moves up for it (DrawerLayout). Sections: History
// (collapsed) · Now Playing · Playing Next (what you added; Clear) · Continue Playing (the rest of the list) · Then (the
// app the queue hands back to). Drag rows to reorder, ⌫ removes, double-click or Return plays a row, Esc closes; drop
// files, folders and links anywhere in it; right-click for more. It shows and edits whatever its closures say — the
// universal queue for the music window.
final class QueueDrawer: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    static let rowType = NSPasteboard.PasteboardType("com.jacob.watch.queue-item")
    static let minWidth: CGFloat = 300, maxHeight: CGFloat = 360, minHeight: CGFloat = 120, gap: CGFloat = 6, barHeight: CGFloat = 30

    enum Section { case history, now, next, rest }
    enum Row {
        case header(String)
        case historyToggle(Int)
        case item(QueueItem, Section)
        case note(String, button: String?, action: (() -> Void)?)
    }

    let window: NSWindow
    private(set) weak var parent: NSWindow?
    private let table = QueueTableView()
    private let scroll = NSScrollView()
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private(set) var rows: [Row] = []
    private var dropTargets: [Int?] = []              // per row: the play-order position a drop above it means
    private var endTarget: Int?
    private var showHistory = false
    private var observers: [NSObjectProtocol] = []
    private var placing = false                    // moving the parent for the list re-enters place() through its didMove

    // What to show and what to do with it.
    var queue: () -> PlayQueue? = { nil }
    var nowPlaying: () -> QueueItem? = { nil }        // no queue running: the song the music window follows
    var continueIn: () -> String? = { nil }           // the app's name to hand back to ("Then: Continue in Music")
    var held: () -> Bool = { false }
    var onPlay: ((UUID) -> Void)?
    var onRemove: ((Set<UUID>) -> Void)?
    var onMove: (([UUID], Int) -> Void)?
    var onInsert: (([QueueItem], Int?) -> Void)?      // nil position: no queue yet — Play Later
    var onClear: (() -> Void)?
    var onResume: (() -> Void)?
    var extraMenu: ((QueueItem) -> [NSMenuItem])?     // Add to Favourites, Show in Finder, Copy Link…

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.minWidth, height: 200),
                          styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "Up Next"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(b)?.isHidden = true }
        window.isMovable = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.backgroundColor = .clear
        let glass = makeGlassContentView()
        window.contentView = glass

        let title = NSTextField(labelWithString: "UP NEXT")
        title.font = .boldSystemFont(ofSize: 10); title.textColor = .secondaryLabelColor
        clearButton.bezelStyle = .inline; clearButton.controlSize = .small; clearButton.font = .systemFont(ofSize: 10.5)
        clearButton.target = self; clearButton.action = #selector(clearTapped); clearButton.toolTip = "Remove everything you added"
        let close = NSButton(title: "", image: sym("xmark.circle.fill"), target: self, action: #selector(closeTapped))
        close.isBordered = false; close.contentTintColor = .tertiaryLabelColor; close.toolTip = "Close (Esc)"
        let bar = NSStackView(views: [title, NSView(), clearButton, close]); bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(bar)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.style = .plain
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowSizeStyle = .custom
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.allowsMultipleSelection = true
        table.selectionHighlightStyle = .regular
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(doubleClicked)
        table.registerForDraggedTypes([Self.rowType, .fileURL, .URL, .string])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.onDelete = { [weak self] in self?.removeSelected() }
        table.onReturn = { [weak self] in self?.playSelected() }
        table.onEscape = { [weak self] in self?.hide() }
        let menu = NSMenu(); menu.delegate = self
        table.menu = menu
        scroll.documentView = table
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(scroll)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -8),
            bar.topAnchor.constraint(equalTo: glass.topAnchor, constant: 6),
            bar.heightAnchor.constraint(equalToConstant: Self.barHeight - 10),
            scroll.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -4),
            scroll.topAnchor.constraint(equalTo: glass.topAnchor, constant: Self.barHeight),
            scroll.bottomAnchor.constraint(equalTo: glass.bottomAnchor, constant: -4),
        ])
    }

    // MARK: showing

    var isShown: Bool { window.isVisible }
    func toggle(under parent: NSWindow) { isShown ? hide() : show(under: parent) }
    func show(under parent: NSWindow) {
        if self.parent !== parent { stopObserving() }
        self.parent = parent
        window.level = parent.level
        reload()
        if window.parent !== parent { parent.addChildWindow(window, ordered: .above) }
        window.orderFront(nil)
        place()
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in self?.place() })
        }
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in self?.hide() })
        }
    }
    @objc func hide() {
        parent?.removeChildWindow(window)
        window.orderOut(nil)
        stopObserving()
    }
    private func stopObserving() { observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = [] }

    // Under the parent, as wide as it (at least minWidth); DrawerLayout decides when there's no room below — the window
    // moves up for it, except while you drag or resize it.
    func place() {
        guard let p = parent, isShown, !placing else { return }
        placing = true
        defer { placing = false }
        let content = rows.indices.reduce(CGFloat(0)) { $0 + rowHeight($1) }
        let height = min(Self.maxHeight, Self.barHeight + max(content, 34) + 8)
        let width = max(Self.minWidth, p.frame.width)
        guard let vis = (p.screen ?? NSScreen.main)?.visibleFrame else {
            window.setFrame(NSRect(x: p.frame.minX, y: p.frame.minY - Self.gap - height, width: width, height: height), display: true)
            return
        }
        let userMoving = p.inLiveResize || NSEvent.pressedMouseButtons & 1 != 0
        let placed = DrawerLayout.place(parent: p.frame, height: height, minHeight: Self.minHeight, width: width, gap: Self.gap,
                                        in: vis, moveParent: !userMoving)
        if placed.parent != p.frame { p.setFrame(placed.parent, display: true) }
        if placed.list != window.frame { window.setFrame(placed.list, display: true) }
    }
    var isAbove: Bool { (parent?.frame.maxY ?? 0) <= window.frame.minY }

    // MARK: rows

    // Rebuilds the rows from the queue (or, with none, the song the music window follows).
    func reload() {
        rows = []; dropTargets = []; endTarget = nil
        func add(_ row: Row, _ target: Int?) { rows.append(row); dropTargets.append(target) }
        if held() { add(.note("Up Next is paused — the music app took over.", button: "Resume", action: { [weak self] in self?.onResume?() }), nil) }
        if let q = queue(), let now = q.current {
            let s = q.sections()
            if !s.history.isEmpty {
                add(.historyToggle(s.history.count), nil)
                if showHistory { s.history.forEach { add(.item($0, .history), nil) } }
            }
            add(.header("Now Playing"), nil)
            add(.item(now, .now), nil)
            add(.header("Playing Next"), q.pos + 1)
            if s.playingNext.isEmpty {
                add(.note("Right-click anything in Watch ▸ Play Next, or drop songs, videos and files here.", button: nil, action: nil), q.pos + 1)
            }
            for (i, item) in s.playingNext.enumerated() { add(.item(item, .next), q.pos + 1 + i) }
            let restStart = q.pos + 1 + s.playingNext.count
            if !s.continuing.isEmpty {
                add(.header(q.name == "Up Next" ? "Continue Playing" : "Continue Playing — \(q.name)"), restStart)
                for (i, item) in s.continuing.enumerated() { add(.item(item, .rest), restStart + i) }
            }
            endTarget = q.order.count
            clearButton.isHidden = s.playingNext.isEmpty && !s.continuing.contains { $0.added }
        } else {
            if let now = nowPlaying() {
                add(.header("Now Playing"), nil)
                add(.item(now, .now), nil)
            }
            add(.note(nowPlaying() == nil ? "Nothing is playing. Right-click a video or song in Watch ▸ Play Next, or drop files and links here."
                                          : "Add something with Play Next / Play Later, or drop it here — it plays when this song ends.",
                      button: nil, action: nil), 0)
            endTarget = 0
            clearButton.isHidden = true
        }
        if let app = continueIn() { add(.header("Then"), endTarget); add(.note("↩︎ Continue in \(app) — its own Up Next", button: nil, action: nil), endTarget) }
        table.reloadData()
        place()
    }
    private func rowHeight(_ i: Int) -> CGFloat {
        switch rows[i] {
        case .header, .historyToggle: return 22
        case .item: return 34
        case .note(let text, let button, _): return button == nil ? (text.count > 60 ? 40 : 28) : 34
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rowHeight(row) }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { if case .item = rows[row] { return true }; return false }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            return Self.label(title.uppercased(), size: 10, weight: .bold, colour: .tertiaryLabelColor, inset: 8)
        case .historyToggle(let count):
            let b = NSButton(title: "\(showHistory ? "▾" : "▸") HISTORY (\(count))", target: self, action: #selector(toggleHistory))
            b.isBordered = false; b.font = .boldSystemFont(ofSize: 10); b.contentTintColor = .tertiaryLabelColor
            b.alignment = .left
            return Self.wrap(b, inset: 8)
        case .item(let item, let section):
            return QueueRowView(item: item, playing: section == .now, played: section == .history)
        case .note(let text, let button, let action):
            let l = NSTextField(wrappingLabelWithString: text)
            l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor; l.maximumNumberOfLines = 2
            l.preferredMaxLayoutWidth = max(160, (parent?.frame.width ?? Self.minWidth) - (button == nil ? 24 : 110))
            var views: [NSView] = [l]
            if let title = button, let action = action {
                let b = ClosureButton(symbol: "play.fill", tip: title) { _ in action() }
                b.constraints.filter { $0.firstAttribute == .width && $0.secondItem == nil }.forEach { $0.isActive = false }   // fits its title
                b.title = title; b.imagePosition = .imageLeading; b.bezelStyle = .inline; b.isBordered = true
                views.append(b)
            }
            let s = NSStackView(views: views); s.spacing = 6; s.alignment = .centerY
            return Self.wrap(s, inset: 8)
        }
    }
    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight, colour: NSColor, inset: CGFloat) -> NSView {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight); l.textColor = colour; l.lineBreakMode = .byTruncatingTail
        return wrap(l, inset: inset)
    }
    private static func wrap(_ view: NSView, inset: CGFloat) -> NSView {
        let holder = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor, constant: -inset),
            view.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
        ])
        return holder
    }
    @objc private func toggleHistory() { showHistory.toggle(); reload() }

    // MARK: actions

    private func item(at row: Int) -> (QueueItem, Section)? {
        guard rows.indices.contains(row), case .item(let item, let section) = rows[row] else { return nil }
        return (item, section)
    }
    @objc private func doubleClicked() {
        guard let (item, section) = item(at: table.clickedRow), section != .now else { return }
        onPlay?(item.id)
    }
    private func playSelected() {
        guard let row = table.selectedRowIndexes.first, let (item, section) = item(at: row), section != .now else { return }
        onPlay?(item.id)
    }
    private func removeSelected() {
        let ids = Set(table.selectedRowIndexes.compactMap { row -> UUID? in
            guard let (item, section) = item(at: row), section == .next || section == .rest else { return nil }
            return item.id
        })
        if !ids.isEmpty { onRemove?(ids) }
    }
    @objc private func clearTapped() { onClear?() }
    @objc private func closeTapped() { hide() }

    // Right-click a row: Play Now · Play Next · Remove — and the app's extras (Favourites, Finder, Copy Link…).
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let (item, section) = item(at: table.clickedRow) else { return }
        if section != .now { menu.addItem(ClosureMenuItem("Play Now") { [weak self] in self?.onPlay?(item.id) }) }
        if section == .rest || (section == .next && item.id != queue()?.sections().playingNext.first?.id), let q = queue() {
            menu.addItem(ClosureMenuItem("Play Next") { [weak self] in self?.onMove?([item.id], q.pos + 1) })
        }
        if section == .next || section == .rest { menu.addItem(ClosureMenuItem("Remove from Up Next") { [weak self] in self?.onRemove?([item.id]) }) }
        let extra = extraMenu?(item) ?? []
        if !extra.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            extra.forEach(menu.addItem)
        }
    }

    // MARK: drag and drop — rows move; files, folders and links from elsewhere go in where they're dropped

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let (item, section) = item(at: row), section == .next || section == .rest else { return nil }
        let p = NSPasteboardItem()
        p.setString(item.id.uuidString, forType: Self.rowType)
        p.setString(SpotifyLink.isSpotify(item.url) ? SpotifyLink.webURL(item.url) : item.url, forType: .string)
        return p
    }
    // The play-order position a drop above `row` means; nil where nothing may go (above Now Playing, in History).
    func target(above row: Int) -> Int? { row < rows.count ? dropTargets[row] : endTarget }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        var above = row
        if dropOperation == .on { above = row + 1 }
        guard target(above: above) != nil else { return [] }
        tableView.setDropRow(above, dropOperation: .above)
        return (info.draggingSource as AnyObject?) === tableView ? .move : .copy
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let pb = info.draggingPasteboard
        let ids = (pb.pasteboardItems ?? []).compactMap { $0.string(forType: Self.rowType) }.compactMap(UUID.init(uuidString:))
        if !ids.isEmpty, let position = target(above: row) { onMove?(ids, position); return true }
        let items = Self.items(from: pb)
        guard !items.isEmpty else { return false }
        onInsert?(items, queue() == nil ? nil : target(above: row))
        return true
    }
    // What a drop from elsewhere holds: media files, a folder's media (Finder order), links (one per line in text).
    static func items(from pb: NSPasteboard) -> [QueueItem] {
        var out: [QueueItem] = []
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            for u in urls {
                if u.isFileURL {
                    var folder: ObjCBool = false
                    if FileManager.default.fileExists(atPath: u.path, isDirectory: &folder), folder.boolValue { out += PlayQueue.media(inFolder: u) }
                    else if PlayQueue.mediaKind(u.pathExtension) != nil { out.append(QueueItem(url: u.path, title: u.deletingPathExtension().lastPathComponent)) }
                } else if looksLikeURL(u.absoluteString) || SpotifyLink.uri(u.absoluteString) != nil {
                    out.append(QueueItem(url: u.absoluteString))
                }
            }
            if !out.isEmpty { return out }
        }
        for line in (pb.string(forType: .string) ?? "").split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if looksLikeURL(s) || SpotifyLink.uri(s) != nil { out.append(QueueItem(url: s)) }
        }
        return out
    }
}

// The list: ⌫ removes, Return plays, Esc closes.
final class QueueTableView: NSTableView {
    var onDelete: (() -> Void)?
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 51, 117: onDelete?()          // delete, forward delete
        case 36, 76:  onReturn?()          // return, enter
        case 53:      onEscape?()
        default:      super.keyDown(with: e)
        }
    }
}

// One row: thumbnail (16:9 for videos, square for music), title, "source · length"; Now Playing in bold with a speaker,
// what already played dimmed.
final class QueueRowView: NSTableCellView {
    init(item: QueueItem, playing: Bool, played: Bool) {
        super.init(frame: .zero)
        let music = item.source == .audio || item.source.isExternal
        let thumb = ThumbView()
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true; thumb.layer?.cornerRadius = 3; thumb.layer?.masksToBounds = true
        thumb.contentTintColor = .tertiaryLabelColor
        if let art = item.artwork ?? VideoLinks.thumbnail(item.url) { thumb.load(art) }
        else { thumb.show(sym(item.source == .spotify ? "music.note.list" : music ? "music.note" : "play.rectangle")) }
        let title = NSTextField(labelWithString: item.title ?? QueueRowView.fallbackTitle(item))
        title.font = .systemFont(ofSize: 12, weight: playing ? .semibold : .medium)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let meta = NSTextField(labelWithString: [Self.source(item), item.subtitle ?? "", formatDuration(item.duration)].filter { !$0.isEmpty }.joined(separator: " · "))
        meta.font = .systemFont(ofSize: 10.5); meta.textColor = .secondaryLabelColor; meta.lineBreakMode = .byTruncatingTail
        meta.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let texts = NSStackView(views: [title, meta]); texts.orientation = .vertical; texts.alignment = .leading; texts.spacing = 1
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var views: [NSView] = [thumb, texts]
        if playing {
            let speaker = NSImageView(image: sym("speaker.wave.2.fill"))
            speaker.symbolConfiguration = .init(pointSize: 9, weight: .semibold); speaker.contentTintColor = .controlAccentColor
            views.insert(speaker, at: 0)
        }
        let row = NSStackView(views: views); row.spacing = 8; row.alignment = .centerY; row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        let (w, h): (CGFloat, CGFloat) = music ? (24, 24) : (40, 22)
        NSLayoutConstraint.activate([
            thumb.widthAnchor.constraint(equalToConstant: w), thumb.heightAnchor.constraint(equalToConstant: h),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        if played { alphaValue = 0.5 }
        toolTip = item.title.map { "\($0)\n\(item.url)" } ?? item.url
    }
    required init?(coder: NSCoder) { fatalError() }
    static func source(_ item: QueueItem) -> String {
        switch item.source {
        case .spotify: return "Spotify"
        case .music:   return "Music"
        case .file:    return "File"
        case .audio:   return item.url.hasPrefix("/") || item.url.hasPrefix("file://") ? "File" : VideoLinks.site(item.url)
        case .web:     return VideoLinks.site(item.url)
        }
    }
    static func fallbackTitle(_ item: QueueItem) -> String {
        if item.url.hasPrefix("/") || item.url.hasPrefix("file://") { return (item.url as NSString).lastPathComponent }
        return item.url.replacingOccurrences(of: #"^https?://(www\.)?"#, with: "", options: .regularExpression)
    }
}
