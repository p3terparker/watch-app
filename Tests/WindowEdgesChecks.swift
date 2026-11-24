import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// 3.27: a dragged window stops at screen and window edges; a deliberate push or a quick throw goes through.
func checkWindowEdges() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 200, height: 100)
    let other = CGRect(x: 500, y: 250, width: 200, height: 200)

    // The stops: screen edges from inside, the other window's edges from outside, only while they overlap on the other axis.
    let across = WindowEdges.stops(horizontal: true, size: size, origin: CGPoint(x: 100, y: 300), screens: [screen, screen], windows: [other])
    expect(Set(across) == [EdgeStop(at: 0, direction: -1), EdgeStop(at: 800, direction: 1), EdgeStop(at: 300, direction: 1), EdgeStop(at: 700, direction: -1)]
           && across.count == 4, "x stops: screen left/right, the other window's left (minus our width) and right, no duplicates (\(across))")
    let clear = WindowEdges.stops(horizontal: true, size: size, origin: CGPoint(x: 100, y: 600), screens: [screen], windows: [other])
    expect(Set(clear) == [EdgeStop(at: 0, direction: -1), EdgeStop(at: 800, direction: 1)], "a window above or below ours doesn't stop it sideways")
    let touching = WindowEdges.stops(horizontal: true, size: size, origin: CGPoint(x: 100, y: 450), screens: [screen], windows: [other])
    expect(touching.count == 2, "a window that only touches at a corner doesn't count")
    let upDown = WindowEdges.stops(horizontal: false, size: size, origin: CGPoint(x: 100, y: 300), screens: [screen], windows: [other])
    expect(Set(upDown) == [EdgeStop(at: 0, direction: -1), EdgeStop(at: 700, direction: 1)], "y stops: the screen's bottom and top (\(upDown))")
    let visible = CGRect(x: 0, y: 80, width: 1000, height: 695)   // clear of the Dock and menu bar
    let both = WindowEdges.stops(horizontal: false, size: size, origin: CGPoint(x: 100, y: 300), screens: [screen, visible], windows: [])
    expect(Set(both).isSuperset(of: [EdgeStop(at: 80, direction: -1), EdgeStop(at: 675, direction: 1)]), "the Dock's and menu bar's edges stop too")

    let leftEdge = [EdgeStop(at: 0, direction: -1)]
    var t: TimeInterval = 0
    func step(_ axis: inout EdgeAxis, _ raw: CGFloat, dt: TimeInterval = 0.05) -> CGFloat {
        t += dt; return axis.step(raw: raw, time: t, stops: leftEdge)
    }
    // Slowly into the left edge: it holds there until pushed 24 pt past, then follows the pointer again.
    var slow = EdgeAxis(start: 100, time: t)
    expect(step(&slow, 80) == 80 && step(&slow, 60) == 60 && step(&slow, 40) == 40 && step(&slow, 20) == 20, "free movement before the edge")
    expect(step(&slow, 5) == 5 && step(&slow, -3) == 0 && slow.holding != nil, "crossing the edge stops the window on it")
    expect(step(&slow, -10) == 0 && step(&slow, -23) == 0, "pushing a little further still holds")
    expect(step(&slow, -24) == -24 && slow.holding == nil, "pushing \(WindowEdges.breakDistance) pt past goes through")
    expect(step(&slow, -40) == -40, "…and the window follows the pointer past the edge")
    expect(step(&slow, -20) == -20 && step(&slow, -5) == -5, "coming back from outside: that edge doesn't stop it on the way back")
    expect(step(&slow, 10) == 10 && step(&slow, -2) == 0, "once back inside, the edge holds again")
    expect(step(&slow, 6) == 6 && slow.holding == nil, "pulling back lets go at once")

    // Resting on the edge already: pushing on still meets it.
    var resting = EdgeAxis(start: 0, time: t)
    expect(step(&resting, -5) == 0 && resting.holding != nil, "a window resting on the edge resists being pushed further")

    // A quick throw goes straight through.
    var fast = EdgeAxis(start: 300, time: t)
    var landed: CGFloat = 300
    for raw in stride(from: 260 as CGFloat, through: -100, by: -40) { landed = step(&fast, raw, dt: 0.01) }
    expect(landed == -100 && fast.holding == nil && fast.speed > WindowEdges.passSpeed, "a fast throw (4000 pt/s) doesn't stop (speed \(fast.speed))")
    expect(step(&fast, -60) == -60 && step(&fast, 20) == 20 && step(&fast, 10) == 10 && step(&fast, 5) == 5, "back inside")
    expect(step(&fast, -1) == 0, "…where a slow approach meets the edge again")

    // A whole drag: the right edge of ours stops at the other window's left edge, then at the screen's right after a push.
    var drag = EdgeDrag(size: size, origin: CGPoint(x: 100, y: 300), time: t, screens: [screen], windows: [other])
    var at = CGPoint.zero
    for x in stride(from: 160 as CGFloat, through: 320, by: 40) { t += 0.05; at = drag.move(to: CGPoint(x: x, y: 300), time: t) }
    expect(at == CGPoint(x: 300, y: 300) && drag.isHolding, "stops against the other window's edge (\(at))")
    t += 0.05; at = drag.move(to: CGPoint(x: 330, y: 300), time: t)
    expect(at.x == 330 && !drag.isHolding, "a deliberate push goes past it")
    t += 0.05; at = drag.move(to: CGPoint(x: 330, y: 320), time: t)
    expect(at == CGPoint(x: 330, y: 320), "moving up and down meanwhile is free")
    for x in stride(from: 400 as CGFloat, through: 820, by: 60) { t += 0.05; at = drag.move(to: CGPoint(x: x, y: 320), time: t) }
    expect(at.x == 800, "stops at the screen's right edge (\(at))")
    for y in stride(from: 380 as CGFloat, through: 740, by: 60) { t += 0.05; at = drag.move(to: CGPoint(x: 820, y: y), time: t) }
    expect(at == CGPoint(x: 800, y: 700), "held on the right while it slides up to the top, where it stops too (\(at))")
}
