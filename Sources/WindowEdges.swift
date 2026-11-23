import Foundation
#if canImport(CoreGraphics)
import CoreGraphics   // CGPoint/CGRect members (see GOTCHAS); Linux Foundation has its own
#endif

// 3.27 — edges that hold, like macOS's own windows: dragging a Watch window (players and the music window move themselves in
// PlayerSurfaceView, so they don't get the system's behaviour) stops it where one of its edges meets a screen's edge from
// inside, or another window's edge from outside. Pushing on `breakDistance` past the stop, or arriving faster than
// `passSpeed`, goes through; pulling back lets go at once. A stop that was passed holds again only once the window is back on
// the side it came from. Pure — PlayerSurfaceView's drag loop feeds it the pointer, the screens and the other windows.

// Where a window's origin stops along one axis: `at` is the origin value, `direction` the way it's reached (+1 = moving
// toward larger values, -1 = toward smaller).
struct EdgeStop: Hashable {
    let at: CGFloat
    let direction: CGFloat
}

enum WindowEdges {
    static let breakDistance: CGFloat = 24     // push this far past a stop and the window goes through
    static let passSpeed: CGFloat = 1600       // pt/s: a quick throw doesn't stop at all

    // The stops for the origin of a window of `size` at `origin` along x (`horizontal`) or y. A screen (its whole frame and
    // the part clear of the menu bar and Dock) stops the window's matching edge from inside; another window stops the facing
    // edge from outside. Either only counts while it overlaps the window on the other axis.
    static func stops(horizontal: Bool, size: CGSize, origin: CGPoint, screens: [CGRect], windows: [CGRect]) -> [EdgeStop] {
        let length = horizontal ? size.width : size.height
        let low = horizontal ? origin.y : origin.x, high = low + (horizontal ? size.height : size.width)
        func overlaps(_ r: CGRect) -> Bool {
            let (a, b) = horizontal ? (r.minY, r.maxY) : (r.minX, r.maxX)
            return min(high, b) - max(low, a) > 0
        }
        func span(_ r: CGRect) -> (CGFloat, CGFloat) { horizontal ? (r.minX, r.maxX) : (r.minY, r.maxY) }
        var out: [EdgeStop] = []
        for s in screens where overlaps(s) && !s.isEmpty {
            let (a, b) = span(s)
            out += [EdgeStop(at: a, direction: -1), EdgeStop(at: b - length, direction: 1)]
        }
        for w in windows where overlaps(w) && !w.isEmpty {
            let (a, b) = span(w)
            out += [EdgeStop(at: a - length, direction: 1), EdgeStop(at: b, direction: -1)]
        }
        var seen = Set<EdgeStop>()
        return out.filter { seen.insert($0).inserted }
    }
}

// One axis of a drag. `raw` is where the pointer alone would put the origin; `step` says where it goes.
struct EdgeAxis {
    private(set) var holding: EdgeStop?
    private(set) var speed: CGFloat = 0           // pt/s, smoothed over the last few events
    private var passed = Set<EdgeStop>()
    private var last: CGFloat
    private var lastTime: TimeInterval

    init(start: CGFloat, time: TimeInterval) { last = start; lastTime = time }

    mutating func step(raw: CGFloat, time: TimeInterval, stops: [EdgeStop]) -> CGFloat {
        let prev = last
        let dt = max(time - lastTime, 1.0 / 240)
        speed = speed / 2 + abs(raw - prev) / CGFloat(dt) / 2
        last = raw; lastTime = time
        passed = passed.filter { (raw - $0.at) * $0.direction >= 0 }      // back where it came from: it holds again
        if let h = holding {
            let past = (raw - h.at) * h.direction
            if past < 0 { holding = nil; return raw }                       // pulled back: follow the pointer again
            if past < WindowEdges.breakDistance { return h.at }
            holding = nil; passed.insert(h); return raw                     // pushed through
        }
        let moving: CGFloat = raw > prev ? 1 : raw < prev ? -1 : 0
        guard moving != 0 else { return raw }
        let crossed = stops.filter { $0.direction == moving && !passed.contains($0)
                                     && ($0.at - prev) * moving >= 0 && (raw - $0.at) * moving > 0 }   // incl. one it rests on
        guard let first = crossed.min(by: { ($0.at - prev) * moving < ($1.at - prev) * moving }) else { return raw }
        if speed >= WindowEdges.passSpeed { passed.formUnion(crossed); return raw }   // thrown past
        holding = first
        return first.at
    }
}

// A whole drag: x then y, each against the stops for where the window is on the other axis.
struct EdgeDrag {
    let size: CGSize, screens: [CGRect], windows: [CGRect]
    private(set) var origin: CGPoint
    private var x: EdgeAxis, y: EdgeAxis

    init(size: CGSize, origin: CGPoint, time: TimeInterval, screens: [CGRect], windows: [CGRect]) {
        self.size = size; self.origin = origin; self.screens = screens; self.windows = windows
        x = EdgeAxis(start: origin.x, time: time); y = EdgeAxis(start: origin.y, time: time)
    }
    var isHolding: Bool { x.holding != nil || y.holding != nil }

    mutating func move(to raw: CGPoint, time: TimeInterval) -> CGPoint {
        let nx = x.step(raw: raw.x, time: time,
                        stops: WindowEdges.stops(horizontal: true, size: size, origin: origin, screens: screens, windows: windows))
        let ny = y.step(raw: raw.y, time: time,
                        stops: WindowEdges.stops(horizontal: false, size: size, origin: CGPoint(x: nx, y: origin.y), screens: screens, windows: windows))
        origin = CGPoint(x: nx, y: ny)
        return origin
    }
}
