import AppKit

// The thin white slider both windows use (the player's scrubber and volume, the artwork's timeline and volume):
// a 2 pt line, the part before the value brighter, and a dot only while it's hovered or dragged. The whole view is
// the hit area, so it's easy to grab although it looks like a hairline. `onChange(value, finished)` fires while
// dragging and once more on release with `finished` true. Ignores clicks while faded out, like FadingButton.
// `relative` (the volume sliders, 3.26): a press doesn't jump to the pointer — a drag moves the value from where it already is,
// by as far as the pointer travels (VolumeGesture), wherever on the slider it started; a click leaves it alone.
final class ThinSlider: NSView {
    static let knobRadius: CGFloat = 4
    var value: Double = 0 { didSet { if value != oldValue { needsDisplay = true } } }
    var onChange: ((Double, Bool) -> Void)?
    var relative = false
    private(set) var isTracking = false
    private var hovering = false
    private var gesture: VolumeGesture?               // relative mode: the value and span when the press began
    private var pressX: CGFloat = 0

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
    override func mouseDown(with e: NSEvent) {
        isTracking = true
        if relative {
            gesture = VolumeGesture(start: value, span: bounds.width - 2 * Self.knobRadius)
            pressX = convert(e.locationInWindow, from: nil).x
        } else {
            track(e, finished: false)
        }
    }
    override func mouseDragged(with e: NSEvent) { track(e, finished: false) }
    override func mouseUp(with e: NSEvent) { track(e, finished: true); isTracking = false; gesture = nil; needsDisplay = true }
    private func track(_ e: NSEvent, finished: Bool) {
        let x = convert(e.locationInWindow, from: nil).x
        if relative {
            guard let g = gesture else { return }
            if !finished || x != pressX { value = g.level(afterMoving: x - pressX) }   // letting go never moves it
        } else {
            value = Self.value(at: x, width: bounds.width)
        }
        setAccessibilityValue(value)
        onChange?(value, finished)
    }
}

// A button whose press is a click (its action, as usual) — or, when `onDrag` is set and the pointer moves sideways more than
// VolumeGesture.slop, a drag: `onDragStart` once, then `onDrag(distance since the press, finished)`. The speaker button of the
// volume controls (3.26): a click mutes, press-and-drag sets the level relative to where it is. Without `onDrag` it is a plain
// NSButton.
class DragButton: NSButton {
    var onDragStart: (() -> Void)?
    var onDrag: ((_ dx: CGFloat, _ finished: Bool) -> Void)?
    private(set) var isDragging = false
    private var pressX: CGFloat?
    override func mouseDown(with e: NSEvent) {
        guard onDrag != nil, isEnabled else { super.mouseDown(with: e); return }
        pressX = e.locationInWindow.x; isDragging = false
    }
    override func mouseDragged(with e: NSEvent) {
        guard let x0 = pressX else { super.mouseDragged(with: e); return }
        let dx = e.locationInWindow.x - x0
        if !isDragging {
            guard VolumeGesture.isDrag(dx) else { return }
            isDragging = true
            onDragStart?()
        }
        onDrag?(dx, false)
    }
    override func mouseUp(with e: NSEvent) {
        guard let x0 = pressX else { super.mouseUp(with: e); return }
        pressX = nil
        if isDragging {
            isDragging = false
            onDrag?(e.locationInWindow.x - x0, true)
        } else if bounds.contains(convert(e.locationInWindow, from: nil)) {
            sendAction(action, to: target)
        }
    }
}

// A borderless SF Symbol button for the playback controls: white at 85%, full white while hovered; ignores clicks
// while faded out.
final class GlyphButton: DragButton {
    var onPress: (() -> Void)?
    private let pointSize: CGFloat
    private var hovering = false { didSet { tint() } }
    var dimmed = false { didSet { tint() } }               // e.g. volume the app won't let Watch set
    // A setting that's on (shuffle, repeat) sits on a soft white pill; off shows quieter.
    var lit: Bool? { didSet { if lit != oldValue { tint() } } }

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
    private func tint() {
        let off = lit == false
        contentTintColor = NSColor.white.withAlphaComponent(dimmed ? 0.35 : hovering ? 1 : off ? 0.6 : 0.85)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = lit == true ? NSColor.white.withAlphaComponent(0.22).cgColor : nil
    }
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
