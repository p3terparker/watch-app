import AppKit

// The thin white slider both windows use (the player's scrubber, the artwork's timeline, the volume pop-ups):
// a 2 pt line, the part before the value brighter, and a dot only while it's hovered or dragged. The whole view is
// the hit area, so it's easy to grab although it looks like a hairline. `onChange(value, finished)` fires while
// dragging and once more on release with `finished` true. Ignores clicks while faded out, like FadingButton.
// `relative` (the volume sliders, 3.26): a press doesn't jump to the pointer — a drag moves the value from where it already is,
// by as far as the pointer travels (VolumeGesture), wherever on the slider it started; a click leaves it alone.
// `vertical` (the volume pop-up, 3.26): the line runs bottom (0) to top (1) and a drag is measured up and down.
final class ThinSlider: NSView {
    static let knobRadius: CGFloat = 4
    var value: Double = 0 { didSet { if value != oldValue { needsDisplay = true } } }
    var onChange: ((Double, Bool) -> Void)?
    var relative = false
    var vertical = false { didSet { needsDisplay = true } }
    private(set) var isTracking = false
    private var hovering = false
    private var gesture: VolumeGesture?               // relative mode: the value and span when the press began
    private var pressAt: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
    }
    required init?(coder: NSCoder) { fatalError() }

    // Where a point along the view puts the value: the line runs between the knob radii at each end. (`width` is the length
    // along the slider's axis: its height when vertical.)
    static func value(at x: CGFloat, width: CGFloat) -> Double {
        let usable = width - 2 * knobRadius
        guard usable > 0 else { return 0 }
        return Double(min(1, max(0, (x - knobRadius) / usable)))
    }
    private var length: CGFloat { vertical ? bounds.height : bounds.width }

    override func draw(_ dirtyRect: NSRect) {
        let r = Self.knobRadius
        let line = vertical ? NSRect(x: (bounds.midX - 1).rounded(), y: r, width: 2, height: max(0, bounds.height - 2 * r))
                            : NSRect(x: r, y: (bounds.midY - 1).rounded(), width: max(0, bounds.width - 2 * r), height: 2)
        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: line, xRadius: 1, yRadius: 1).fill()
        var played = line
        let fraction = CGFloat(min(1, max(0, value)))
        if vertical { played.size.height = line.height * fraction } else { played.size.width = line.width * fraction }
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: played, xRadius: 1, yRadius: 1).fill()
        if hovering || isTracking {
            NSColor.white.setFill()
            let centre = vertical ? NSPoint(x: bounds.midX, y: played.maxY) : NSPoint(x: played.maxX, y: bounds.midY)
            NSBezierPath(ovalIn: NSRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)).fill()
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { alphaValue < 0.05 || isHidden ? nil : super.hitTest(point) }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with e: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with e: NSEvent) { hovering = false; needsDisplay = true }
    private func position(_ e: NSEvent) -> CGFloat {
        let p = convert(e.locationInWindow, from: nil)
        return vertical ? p.y : p.x
    }
    override func mouseDown(with e: NSEvent) {
        isTracking = true
        if relative {
            gesture = VolumeGesture(start: value, span: length - 2 * Self.knobRadius)
            pressAt = position(e)
        } else {
            track(e, finished: false)
        }
    }
    override func mouseDragged(with e: NSEvent) { track(e, finished: false) }
    override func mouseUp(with e: NSEvent) { track(e, finished: true); isTracking = false; gesture = nil; needsDisplay = true }
    private func track(_ e: NSEvent, finished: Bool) {
        let at = position(e)
        if relative {
            guard let g = gesture else { return }
            if !finished || at != pressAt { value = g.level(afterMoving: at - pressAt) }   // letting go never moves it
        } else {
            value = Self.value(at: at, width: length)
        }
        setAccessibilityValue(value)
        onChange?(value, finished)
    }
}

// The panel the volume slider lives in (3.26): a short dark rounded panel with a vertical slider, shown just above the speaker
// only while the pointer is on the speaker (or on the panel). It is a sibling of the controls in their parent view — not a
// child, which would be clipped to the row — so it works in a window of any size (VolumePopup.frame fits it above the
// speaker). Clicks on the panel stay on the panel.
final class VolumePopupView: NSView {
    let slider: ThinSlider
    init(slider: ThinSlider) {
        self.slider = slider
        super.init(frame: NSRect(x: 0, y: 0, width: VolumePopup.width, height: VolumePopup.height))
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        layer?.cornerRadius = 8
        slider.vertical = true
        slider.relative = true
        addSubview(slider)
        alphaValue = 0
        layoutSlider()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func layoutSlider() { slider.frame = bounds.insetBy(dx: 5, dy: 6) }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); layoutSlider() }
    override func hitTest(_ point: NSPoint) -> NSView? { alphaValue < 0.05 || isHidden ? nil : super.hitTest(point) }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {}           // a click on the panel itself does nothing (and is not a click on the window)
}

enum DragAxis { case horizontal, vertical }

// A button whose press is a click (its action, as usual) — or, when `onDrag` is set and the pointer moves along `dragAxis` more
// than VolumeGesture.slop, a drag: `onDragStart` once, then `onDrag(distance since the press, finished)` (right / up is
// positive). The speaker button of the volume controls (3.26): a click mutes, press-and-drag up or down sets the level relative
// to where it is. Without `onDrag` it is a plain NSButton.
class DragButton: NSButton {
    var onDragStart: (() -> Void)?
    var onDrag: ((_ distance: CGFloat, _ finished: Bool) -> Void)?
    var dragAxis = DragAxis.horizontal
    private(set) var isDragging = false
    private var pressAt: CGFloat?
    private func along(_ e: NSEvent) -> CGFloat { dragAxis == .vertical ? e.locationInWindow.y : e.locationInWindow.x }
    override func mouseDown(with e: NSEvent) {
        guard onDrag != nil, isEnabled else { super.mouseDown(with: e); return }
        pressAt = along(e); isDragging = false
    }
    override func mouseDragged(with e: NSEvent) {
        guard let start = pressAt else { super.mouseDragged(with: e); return }
        let distance = along(e) - start
        if !isDragging {
            guard VolumeGesture.isDrag(distance) else { return }
            isDragging = true
            onDragStart?()
        }
        onDrag?(distance, false)
    }
    override func mouseUp(with e: NSEvent) {
        guard let start = pressAt else { super.mouseUp(with: e); return }
        pressAt = nil
        if isDragging {
            isDragging = false
            onDrag?(along(e) - start, true)
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
