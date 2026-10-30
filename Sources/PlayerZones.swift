import Foundation
import CoreGraphics

// What a click does depends on where it lands on the player, split into thirds each way:
//
//   resize  │ resize │ resize        top third: double-click resizes
//   ────────┼────────┼────────
//   back 10 │  play  │ fwd 10        centre: click plays/pauses; left/right thirds: double-click skips 10 s
//   ────────┼────────┼────────
//   back 10 │ resize │ fwd 10        bottom middle: double-click resizes
//
// Points are AppKit view coordinates (y grows upward). Pure, so `test.sh` covers it.
enum PlayerZone: Equatable {
    case resize, playPause, skipBack, skipForward

    static func at(_ p: CGPoint, in size: CGSize) -> PlayerZone {
        guard size.width > 0, size.height > 0 else { return .resize }
        let col = min(2, max(0, Int(p.x / (size.width / 3))))
        let row = min(2, max(0, Int((size.height - p.y) / (size.height / 3))))   // 0 = top third
        switch (row, col) {
        case (0, _): return .resize
        case (_, 0): return .skipBack
        case (_, 2): return .skipForward
        case (1, 1): return .playPause
        default:     return .resize                                             // bottom middle
        }
    }
}

// The music window's clicks (3.20): a single click anywhere plays/pauses, so only double-clicks have zones — narrow strips
// at the far left/right edges skip ∓10 s, and anywhere else opens the source in its app. A strip is 15% of the width but
// at least 36 pt (never more than a third). Points are AppKit view coordinates. Pure, so `test.sh` covers it.
enum MusicZone: Equatable {
    case skipBack, skipForward, main
    static let stripFraction: CGFloat = 0.15, minStrip: CGFloat = 36
    // 3.25: two clicks make a double-click only within this of each other — tighter than the system's interval (0.5 s by
    // default). A single click plays/pauses once the window and `clickMargin` have passed (≈ 0.32 s, was ≈ 0.55 s).
    static let doubleClickWindow: TimeInterval = 0.3, clickMargin: TimeInterval = 0.02

    // The system's double-click interval, shortened to `doubleClickWindow` (a user who set a faster one keeps it).
    static func window(system interval: TimeInterval) -> TimeInterval { interval > 0 ? min(interval, doubleClickWindow) : doubleClickWindow }
    static func strip(width: CGFloat) -> CGFloat { min(width / 3, max(minStrip, width * stripFraction)) }
    static func at(_ p: CGPoint, in size: CGSize) -> MusicZone {
        guard size.width > 0 else { return .main }
        let s = strip(width: size.width)
        if p.x < s { return .skipBack }
        if p.x >= size.width - s { return .skipForward }
        return .main
    }
}

// A run of clicks in the music window (3.25), timed by Watch rather than by AppKit's `clickCount`, which follows the system's
// longer double-click interval. A click joins the run only if the one before came at most `window` earlier; any later click is a
// fresh single click, so a slow second click never opens the app. `first`: AppKit itself counts it as the first click (the
// interval passed or the pointer moved), so it starts a run whatever the clock says. Fed timestamps (seconds on any steady
// clock, e.g. `NSEvent.timestamp`), so it is pure and `test.sh` covers it.
struct MusicClicks {
    var window: TimeInterval
    private(set) var count = 0                         // the run's length so far: 1 = single, 2 = double, 3 stacks…
    private var last: TimeInterval = 0
    init(window: TimeInterval = MusicZone.doubleClickWindow) { self.window = window }

    // The run's length including this click.
    mutating func press(at time: TimeInterval, first: Bool = false) -> Int {
        let joins = !first && count > 0 && time >= last && time - last <= window
        count = joins ? count + 1 : 1
        last = time
        return count
    }
    mutating func reset() { count = 0 }
}

// The volume control's drag (3.26), shared by the video bar and the music window. A press on the speaker is a click (mute /
// unmute) unless the pointer moves sideways more than `slop`; then it is a drag, and the level moves from where it already is
// by the distance travelled — the pointer doesn't have to be on the slider, and the level doesn't jump to it, as in Apple
// Music. `span` is how many points a drag must cover to run the whole range (the slider's own length when the pointer is on it,
// so the knob follows 1:1; at least `minSpan` from the speaker, whose slider is short). Pure, so `test.sh` covers it.
struct VolumeGesture: Equatable {
    static let slop: CGFloat = 3, minSpan: CGFloat = 80, fallbackSpan: CGFloat = 60
    let start: Double, span: CGFloat
    init(start: Double, span: CGFloat) {
        self.start = start.isFinite ? min(1, max(0, start)) : 0
        self.span = span > 0 && span.isFinite ? span : Self.fallbackSpan
    }
    // The level after the pointer has moved `dx` points (right = louder) since the press. Measured from the press, not from the
    // last event, so pulling back past either end unwinds the way it came.
    func level(afterMoving dx: CGFloat) -> Double { min(1, max(0, start + Double(dx / span))) }
    // Whether `dx` is far enough from the press to be a drag rather than a click.
    static func isDrag(_ dx: CGFloat) -> Bool { abs(dx) >= slop }
}

// Where the pointer must be for a volume slider to be out: on the speaker (a little beyond its edges), and, once the slider has
// slid out, on that too — so the pointer can travel along it without it closing. nil slider: not out. Pure.
enum VolumeHover {
    static func zone(icon: CGRect, slider: CGRect?) -> CGRect {
        let both = slider.map { icon.union($0) } ?? icon
        return both.insetBy(dx: -4, dy: -6)
    }
}
