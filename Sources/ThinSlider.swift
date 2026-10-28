import AppKit

// The thin white slider both windows use (the player's scrubber and volume, the artwork's timeline and volume):
// a 2 pt line, the part before the value brighter, and a dot only while it's hovered or dragged. The whole view is
// the hit area, so it's easy to grab although it looks like a hairline. `onChange(value, finished)` fires while
// dragging and once more on release with `finished` true. Ignores clicks while faded out, like FadingButton.
final class ThinSlider: NSView {
    static let knobRadius: CGFloat = 4
    var value: Double = 0 { didSet { if value != oldValue { needsDisplay = true } } }
    var onChange: ((Double, Bool) -> Void)?
    private(set) var isTracking = false
    private var hovering = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
    }
    required init?(coder: NSCoder) { fatalError() }

    // Where a point along the view puts the value: the line runs between the knob radii at each end.
    static func value(at x: CGFloat, width: CGFloat) -> Double {
        let usable = width - 2 * knobRadius
        guard usable > 0 else { return 0 }
        return Double(min(1, max(0, (x - knobRadius) / usable)))
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = Self.knobRadius
        let line = NSRect(x: r, y: (bounds.midY - 1).rounded(), width: max(0, bounds.width - 2 * r), height: 2)
        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: line, xRadius: 1, yRadius: 1).fill()
        var played = line
        played.size.width = line.width * CGFloat(min(1, max(0, value)))
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: played, xRadius: 1, yRadius: 1).fill()
        if hovering || isTracking {
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: played.maxX - r, y: bounds.midY - r, width: 2 * r, height: 2 * r)).fill()
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { alphaValue < 0.05 || isHidden ? nil : super.hitTest(point) }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with e: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with e: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseDown(with e: NSEvent) { isTracking = true; track(e, finished: false) }
    override func mouseDragged(with e: NSEvent) { track(e, finished: false) }
    override func mouseUp(with e: NSEvent) { track(e, finished: true); isTracking = false; needsDisplay = true }
    private func track(_ e: NSEvent, finished: Bool) {
        value = Self.value(at: convert(e.locationInWindow, from: nil).x, width: bounds.width)
        setAccessibilityValue(value)
        onChange?(value, finished)
    }
}

// A borderless SF Symbol button for the playback controls: white at 85%, full white while hovered; ignores clicks
// while faded out.
final class GlyphButton: NSButton {
    var onPress: (() -> Void)?
    private let pointSize: CGFloat
    private var hovering = false { didSet { tint() } }
    var dimmed = false { didSet { tint() } }               // e.g. volume the app won't let Watch set

    init(symbol: String, pointSize: CGFloat, tip: String) {
        self.pointSize = pointSize
        super.init(frame: .zero)
        title = ""; isBordered = false; imagePosition = .imageOnly; imageScaling = .scaleNone
        toolTip = tip
        target = self; action = #selector(fire)
        setSymbol(symbol)
        tint()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }
    func setSymbol(_ name: String) { image = sym(name).withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold)) }
    private func tint() { contentTintColor = NSColor.white.withAlphaComponent(dimmed ? 0.35 : hovering ? 1 : 0.85) }
    @objc private func fire() { onPress?() }
    override func hitTest(_ point: NSPoint) -> NSView? { alphaValue < 0.05 || isHidden ? nil : super.hitTest(point) }
    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }
}

// The speaker glyph for a volume level, shared by the player's and the artwork window's volume.
func volumeSymbol(_ level: Double, muted: Bool = false) -> String {
    if muted || level <= 0 { return "speaker.slash.fill" }
    return level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
}
