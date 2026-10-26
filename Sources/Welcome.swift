import Cocoa

func showMediaToolUpdateHelp() {
    let alert = NSAlert()
    alert.messageText = "Media tools update with Watch"
    alert.informativeText = "Ask the person who sent you Watch for the latest installer. Quit Watch, then drag the new copy into Applications and choose Replace. Your library and settings stay in place. No Terminal or separate tool installation is needed."
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

private final class GuideStackView: NSStackView {
    override func layout() {
        super.layout()
        for case let label as NSTextField in arrangedSubviews where abs(label.preferredMaxLayoutWidth - bounds.width) > 0.5 {
            label.preferredMaxLayoutWidth = bounds.width
            label.invalidateIntrinsicContentSize()
        }
    }
}

// First-run guide. Tool checks are local and asynchronous; no account access or media playback.
final class WelcomeController: NSObject {
    let window: NSWindow
    private let stack = GuideStackView()
    private var toolLabels: [NSTextField] = []
    private var checkButton: NSButton!
    private var checking = false
    private let width: CGFloat = 480
    private let tools: MediaTools

    init(tools: MediaTools = .bundled) {
        self.tools = tools
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Welcome to Watch"; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 420)
        super.init()
        build()
    }
    func show() {
        refreshStatus(); window.center(); window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless(); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func startWatching() { window.close(); (NSApp.delegate as? AppDelegate)?.presentPanel() }
    @objc func openSignIn() { (NSApp.delegate as? AppDelegate)?.openYouTubeSignIn() }
    @objc func openLicenses() {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("ThirdParty") { NSWorkspace.shared.open(url) }
    }
    @objc func refreshStatus() {
        guard !checking else { return }
        checking = true; checkButton.isEnabled = false
        for (label, name) in zip(toolLabels, MediaTools.names) { label.stringValue = "Checking \(name)…"; label.textColor = .secondaryLabelColor }
        let tools = self.tools
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let checks = tools.check()
            DispatchQueue.main.async {
                guard let self = self else { return }
                for (label, result) in zip(self.toolLabels, checks) {
                    label.stringValue = (result.ok ? "✓ " : "⚠ ") + result.name + " — " + result.detail
                    label.textColor = result.ok ? .secondaryLabelColor : .systemOrange
                }
                self.checking = false; self.checkButton.isEnabled = true
            }
        }
    }
    private func text(_ value: String, heading: Bool = false) {
        let label = NSTextField(wrappingLabelWithString: value)
        label.isSelectable = true; label.preferredMaxLayoutWidth = width
        label.font = heading ? .boldSystemFont(ofSize: 16) : .systemFont(ofSize: 13)
        label.textColor = heading ? .labelColor : .secondaryLabelColor
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded
        stack.addArrangedSubview(button); return button
    }
    private func build() {
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let doc = FlippedView(); doc.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack); scroll.documentView = doc
        NSLayoutConstraint.activate([
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -24),
        ])
        window.contentView!.addSubview(scroll)
        text("Ready to watch", heading: true)
        text("Everything you need is included. No Homebrew, Python or Terminal setup.")
        text("1. Open Watch from Applications. Click its ▶ icon in the menu bar, or press ⌥⌘Y.\n2. Type to search YouTube, or paste a video link and press Return.\n3. Click a result to play. Use its ↓ button to download.")
        let start = button("Start Watching", #selector(startWatching)); start.keyEquivalent = "\r"
        text("Connect YouTube · optional", heading: true)
        text("Public search and most public videos work without signing in. To try your History and Playlists, connect the YouTube session in Chrome or Safari. The assistant explains the macOS permission needed. Private or restricted videos may still be unavailable.")
        _ = button("Connect YouTube…", #selector(openSignIn))
        text("Included media tools", heading: true)
        for name in MediaTools.names {
            let label = NSTextField(wrappingLabelWithString: name)
            label.font = .systemFont(ofSize: 11); label.preferredMaxLayoutWidth = width
            stack.addArrangedSubview(label); label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            toolLabels.append(label)
        }
        checkButton = button("Check Tools Again", #selector(refreshStatus))
        text("If a tool is missing or cannot start, replace Watch with a fresh copy from your sender. Updated tools arrive with updated versions of Watch.")
        text("Browser tabs · optional", heading: true)
        text("To see videos open in your browser, enable “Allow JavaScript from Apple Events” in that browser’s developer menu, then use Watch Preferences → Allow Browser Access. This is separate from YouTube sign-in.")
        _ = button("Open Third-Party Notices", #selector(openLicenses))
    }
}
