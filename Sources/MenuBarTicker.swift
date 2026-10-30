import AppKit

// A click-through clip: its text never takes the click from the menu-bar button under it.
private final class TickerClip: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// 3.26 — the playing song's name and artist as one very small line in the menu bar (Preferences ▸ "Show the playing song in the
// menu bar"), always there for a glance. It is its own status item beside Watch's icon, created while a song is known and
// removed when nothing plays, so there is never an empty gap. Text that fits stands still; longer text scrolls like iTunes's
// display (Marquee), except while paused (dimmed and still) or with Reduce Motion on. Clicking it does what the icon does.
final class MenuBarTicker: NSObject {
    static let font = NSFont.systemFont(ofSize: 11)
    static let padding: CGFloat = 6
    private var item: NSStatusItem?
    private let clip = TickerClip()
    private let strip = NSView()                        // the labels, slid as one by the animation
    private let labels = [NSTextField(labelWithString: ""), NSTextField(labelWithString: "")]   // the text and its repeat
    private var shown: (text: String, playing: Bool)?
    private(set) var marquee: Marquee?                  // the plan for what's showing (checked by the harness)
    private(set) var isScrolling = false
    var isShowing: Bool { item != nil }
    var text: String? { shown?.text }
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) { self.onClick = onClick }
    deinit { hide() }

    func show(_ text: String, playing: Bool) {
        if shown?.text == text && shown?.playing == playing { return }
        shown = (text, playing)
        let item = self.item ?? makeItem()
        let width = ceil((text as NSString).size(withAttributes: [.font: Self.font]).width) + 1
        let plan = Marquee(textWidth: width)
        marquee = plan
        isScrolling = playing && plan.scrolls && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        item.length = plan.window + 2 * Self.padding
        item.button?.setAccessibilityLabel("Now playing: \(text)")
        item.button?.toolTip = text
        let height = max(item.button?.bounds.height ?? 0, NSStatusBar.system.thickness)
        clip.frame = NSRect(x: Self.padding, y: 0, width: plan.window, height: height)
        let lineHeight = ceil(Self.font.boundingRectForFont.height)
        for (i, label) in labels.enumerated() {
            label.stringValue = text
            label.textColor = playing ? .labelColor : .secondaryLabelColor
            label.lineBreakMode = isScrolling ? .byClipping : .byTruncatingTail
            label.isHidden = i == 1 && !isScrolling
            let x = i == 0 ? 0 : plan.travel
            label.frame = NSRect(x: x, y: ((height - lineHeight) / 2).rounded(), width: isScrolling ? width : plan.window, height: lineHeight)
        }
        strip.frame = NSRect(x: 0, y: 0, width: isScrolling ? plan.travel + width : plan.window, height: height)
        strip.layer?.removeAnimation(forKey: "ticker")
        guard isScrolling else { return }
        let slide = CAKeyframeAnimation(keyPath: "transform.translation.x")
        slide.values = [0.0, 0.0, Double(-plan.travel)]
        slide.keyTimes = [0, NSNumber(value: plan.restFraction), 1]
        slide.duration = plan.duration
        slide.repeatCount = .infinity
        strip.layer?.add(slide, forKey: "ticker")
    }

    func hide() {
        strip.layer?.removeAnimation(forKey: "ticker")
        if let item = item { NSStatusBar.system.removeStatusItem(item) }
        item = nil; shown = nil; marquee = nil; isScrolling = false
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: 0)
        if let b = item.button {
            b.target = self; b.action = #selector(clicked)
            b.sendAction(on: [.leftMouseUp])
            clip.wantsLayer = true
            clip.layer?.masksToBounds = true
            clip.autoresizingMask = [.height]
            strip.wantsLayer = true
            strip.autoresizingMask = [.height]
            for label in labels {
                label.font = Self.font
                label.autoresizingMask = [.minYMargin, .maxYMargin]
                strip.addSubview(label)
            }
            clip.addSubview(strip)
            b.addSubview(clip)
        }
        self.item = item
        return item
    }
    @objc private func clicked() { onClick() }
}
