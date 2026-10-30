import Foundation
#if canImport(CoreGraphics)
import CoreGraphics   // CGRect members (see GOTCHAS); Linux Foundation has its own
#endif

// The full-screen artwork's look: the background gradient's colours (taken from the artwork) and where the artwork
// and its caption sit on the screen. Pure — ArtworkWindow.swift samples the image and applies the result.
struct RGB: Equatable {
    var r: Double, g: Double, b: Double            // 0…1
    var value: Double { max(r, g, b) }              // HSV brightness
    var saturation: Double { value == 0 ? 0 : (value - min(r, g, b)) / value }
    func distance(to o: RGB) -> Double { ((r - o.r) * (r - o.r) + (g - o.g) * (g - o.g) + (b - o.b) * (b - o.b)).squareRoot() }
    func scaled(_ f: Double) -> RGB { RGB(r: min(1, r * f), g: min(1, g * f), b: min(1, b * f)) }
}

enum ArtworkPalette {
    static let maxValue = 0.55, minValue = 0.10   // dark enough for white text, never pure black
    static let distinct = 0.25                      // how far apart the two colours must be to count as two

    // The artwork's two main colours, for a top-left → bottom-right gradient. `pixels` is a small width×height RGBA
    // sample (premultiplied alpha). Colours are counted in a coarse 4×4×4 grid, weighting coloured pixels above greys
    // so a vivid subject can lead over a large dull area; the second colour is the strongest one clearly different
    // from the first (else a darker first). nil when the picture is fully transparent.
    static func gradient(pixels: [UInt8], width: Int, height: Int) -> (start: RGB, end: RGB)? {
        guard width > 0, height > 0, pixels.count >= width * height * 4 else { return nil }
        struct Bin { var weight = 0.0, r = 0.0, g = 0.0, b = 0.0 }
        var bins: [Int: Bin] = [:]
        for i in 0..<(width * height) {
            let a = Double(pixels[i * 4 + 3]) / 255
            guard a > 0.5 else { continue }
            let c = RGB(r: min(1, Double(pixels[i * 4]) / 255 / a), g: min(1, Double(pixels[i * 4 + 1]) / 255 / a),
                        b: min(1, Double(pixels[i * 4 + 2]) / 255 / a))
            let key = Int(c.r * 3.999) << 4 | Int(c.g * 3.999) << 2 | Int(c.b * 3.999)
            let w = 1 + 2 * c.saturation * c.value
            bins[key, default: Bin()].weight += w
            bins[key]!.r += c.r * w; bins[key]!.g += c.g * w; bins[key]!.b += c.b * w
        }
        let ranked = bins.sorted { $0.value.weight != $1.value.weight ? $0.value.weight > $1.value.weight : $0.key < $1.key }
            .map { RGB(r: $0.value.r / $0.value.weight, g: $0.value.g / $0.value.weight, b: $0.value.b / $0.value.weight) }
        guard let first = ranked.first else { return nil }
        let second = ranked.dropFirst().first { $0.distance(to: first) > distinct } ?? first.scaled(0.5)
        return (tone(first), tone(second))
    }
    // Same hue and saturation, brightness kept between minValue and maxValue.
    static func tone(_ c: RGB) -> RGB {
        let v = c.value
        if v == 0 { return RGB(r: minValue, g: minValue, b: minValue) }
        if v > maxValue { return c.scaled(maxValue / v) }
        if v < minValue { return c.scaled(minValue / v) }
        return c
    }
}

// Where each playback control sits in the music window's one row under the caption: ⏮ ⏯ ⏭ from the left edge, then
// elapsed · timeline · remaining, then ★ · shuffle · repeat and the volume (slider, speaker) at the right edge. nil = not shown.
struct ControlRow: Equatable {
    var previous: CGRect?, playPause: CGRect?, next: CGRect?
    var elapsed: CGRect?, timeline: CGRect?, remaining: CGRect?
    var favourite: CGRect?
    var shuffle: CGRect?, repeatMode: CGRect?
    var volumeIcon: CGRect?, volume: CGRect?
}
// no app volume · the speaker alone (the slider is tucked away, or not allowed) · speaker + the slider slid out (3.26: only
// while the pointer is on the speaker)
enum ControlRowVolume { case none, icon, slider }

enum ArtworkLayout {
    static let captionHeight: CGFloat = 64, gap: CGFloat = 20
    static let controlsHeight: CGFloat = 26                     // one row: buttons, timeline, shuffle/repeat, volume
    static let windowBand: CGFloat = 64                         // the window's caption band; + controlsHeight when revealed
    static let minTimeline: CGFloat = 48
    // 3.25: the controls come up when the pointer is over the caption band or this far above it, so they are there as it moves
    // toward the text. On a small window the reach is capped at a share of its height.
    static let revealReach: CGFloat = 40, maxReachShare: CGFloat = 0.3

    // Where the pointer reveals the controls (`revealed` false) or keeps them showing (true): full width, from the bottom edge
    // up to the caption band plus the reach. Once revealed the band has grown by the controls' row (the text lifts), and the
    // zone grows with it — so the lift itself can't take the pointer out of it and make them flicker. Unflipped coordinates
    // (y up), like the window's surface; empty for an empty window.
    static func revealZone(window: CGSize, revealed: Bool) -> CGRect {
        guard window.width > 0, window.height > 0 else { return .zero }
        let band = windowBand + (revealed ? controlsHeight : 0)
        let reach = min(revealReach, window.height * maxReachShare)
        return CGRect(x: 0, y: 0, width: window.width, height: min(window.height, band + reach))
    }

    // The controls' row at `width`. When it can't all fit, parts drop out in this order: the elapsed time, shuffle/repeat,
    // the volume slider (the speaker stays), the remaining time and the ★ (3.26), ⏮/⏭ — the timeline (when there's a length) and
    // ⏯ stay. `modes`: shuffle/repeat can be set for this app. `favourite`: the app has a ★ Watch can set (Apple Music), left of
    // shuffle. Unflipped coordinates (y up), centred vertically in `height`.
    static func controlRow(width w: CGFloat, height h: CGFloat = controlsHeight, timeline: Bool, longClock: Bool,
                           modes: Bool, volume: ControlRowVolume, favourite: Bool = false) -> ControlRow {
        let side: CGFloat = 20, play: CGFloat = 22, mode: CGFloat = 18, icon: CGFloat = 16, slider: CGFloat = 40
        let label: CGFloat = longClock ? 42 : 28, gap: CGFloat = 6, tight: CGFloat = 2
        // Drop level n removes the first n parts of the order above.
        func width(_ level: Int) -> CGFloat {
            var x = play + (level < 5 ? 2 * (side + 1) : 0)
            if timeline { x += gap + (level < 1 ? label + tight : 0) + minTimeline + (level < 4 ? tight + label : 0) }
            if modes && level < 2 { x += gap + 2 * mode + 1 }
            if favourite && level < 4 { x += (modes && level < 2 ? 1 : gap) + mode }   // beside shuffle, or after the speaker's gap
            if volume != .none { x += gap + icon + (volume == .slider && level < 3 ? tight + slider : 0) }
            return x
        }
        let level = (0...5).first { width($0) <= w } ?? 5
        func y(_ height: CGFloat) -> CGFloat { ((h - height) / 2).rounded() }
        var row = ControlRow()
        var x: CGFloat = 0
        let skips = level < 5
        if skips { row.previous = CGRect(x: x, y: y(side), width: side, height: side); x += side + 1 }
        row.playPause = CGRect(x: x, y: y(play), width: play, height: play); x += play
        if skips { x += 1; row.next = CGRect(x: x, y: y(side), width: side, height: side); x += side }
        var right = w
        if volume != .none {
            // The speaker stays at the right edge, where the pointer is; the slider slides out to its left (3.26).
            row.volumeIcon = CGRect(x: right - icon, y: y(18), width: icon, height: 18); right -= icon
            if volume == .slider && level < 3 { row.volume = CGRect(x: right - tight - slider, y: y(18), width: slider, height: 18); right -= tight + slider }
            right -= gap
        }
        let star = favourite && level < 4
        if modes && level < 2 {
            row.repeatMode = CGRect(x: right - mode, y: y(mode), width: mode, height: mode); right -= mode + 1
            row.shuffle = CGRect(x: right - mode, y: y(mode), width: mode, height: mode); right -= mode + (star ? 1 : gap)
        }
        if star {
            row.favourite = CGRect(x: right - mode, y: y(mode), width: mode, height: mode); right -= mode + gap
        }
        if timeline {
            x += gap
            if level < 1 { row.elapsed = CGRect(x: x, y: y(13), width: label, height: 13); x += label + tight }
            if level < 4 { row.remaining = CGRect(x: right - label, y: y(13), width: label, height: 13); right -= label + tight }
            row.timeline = CGRect(x: x, y: y(18), width: max(0, right - x), height: 18)
        }
        return row
    }

    // Full screen: the artwork centred at up to 70% of the width and 62% of the height (keeping its shape), the caption
    // centred under it and the playback controls' row under that — reserved even while they're hidden, so the artwork
    // never moves when they appear. The group is centred vertically. Unflipped coordinates (y up), like AppKit.
    //
    // 3.26: `scale` resizes the picture (1 = the size above; dragging it changes the factor). It runs from a quarter of the usual
    // size (`minFullScreenScale`) up to filling the screen — touching top and bottom, or both sides if the picture is wider than
    // the screen. Once the picture and the stack under it (gap + caption + controls) no longer fit together the group isn't
    // centred any more: the picture's top stays on the screen's top edge and it grows downward, so the caption and controls
    // slide down with its bottom edge, and `chrome` (1 → 0) fades them out; when the picture fills the screen's height they are
    // gone, off the bottom.
    static let minFullScreenScale: CGFloat = 0.25
    private static func shaped(_ artwork: CGSize) -> CGSize { artwork.width > 0 && artwork.height > 0 ? artwork : CGSize(width: 1, height: 1) }
    private static func usualScale(_ shape: CGSize, _ screen: CGSize) -> CGFloat { min(screen.width * 0.7 / shape.width, screen.height * 0.62 / shape.height) }
    static func fullScreenScaleRange(artwork: CGSize, in screen: CGSize) -> ClosedRange<CGFloat> {
        let shape = shaped(artwork)
        guard screen.width > 0, screen.height > 0 else { return 1...1 }
        let fill = min(screen.width / shape.width, screen.height / shape.height)
        return minFullScreenScale...max(1, fill / usualScale(shape, screen))
    }
    static func fullScreen(artwork: CGSize, in screen: CGSize, scale factor: CGFloat = 1)
        -> (art: CGRect, caption: CGRect, controls: CGRect, chrome: CGFloat) {
        let shape = shaped(artwork)
        let range = fullScreenScaleRange(artwork: artwork, in: screen)
        let scale = usualScale(shape, screen) * min(max(factor.isFinite ? factor : 1, range.lowerBound), range.upperBound)
        let w = (shape.width * scale).rounded(), h = (shape.height * scale).rounded()
        let stack = gap + captionHeight + controlsHeight
        let artY: CGFloat = h + stack <= screen.height ? ((screen.height - h - stack) / 2).rounded() + stack : max(0, screen.height - h)
        let art = CGRect(x: ((screen.width - w) / 2).rounded(), y: artY, width: w, height: h)
        let captionWidth = min(screen.width * 0.8, max(w, 480)).rounded()
        let x = ((screen.width - captionWidth) / 2).rounded()
        let caption = CGRect(x: x, y: artY - gap - captionHeight, width: captionWidth, height: captionHeight)
        let controls = CGRect(x: x, y: caption.minY - controlsHeight, width: captionWidth, height: controlsHeight)
        return (art, caption, controls, min(1, max(0, artY / stack)))
    }

    // Dragging the full-screen picture (3.26) resizes it as if it were grabbed by the point pressed: moving the pointer away from
    // the picture's centre grows it, towards the centre shrinks it, in proportion — a corner grabbed 200 pt out and pulled 100 pt
    // further is 1.5 times as big. The factor is measured from the press (`start` is the scale then, `art` the picture's frame
    // then), so pulling back unwinds, and clamped to `range`. Pressing within 12 pt of the centre has no direction of its own:
    // dragging right grows it. Distances under 60 pt count as 60, so a press near the centre doesn't make it jumpy.
    static func resizedScale(from start: CGFloat, art: CGRect, press: CGPoint, to point: CGPoint, range: ClosedRange<CGFloat>) -> CGFloat {
        let vx = press.x - art.midX, vy = press.y - art.midY
        let r = (vx * vx + vy * vy).squareRoot()
        let (ux, uy): (CGFloat, CGFloat) = r >= 12 ? (vx / r, vy / r) : (1, 0)
        let outward = (point.x - press.x) * ux + (point.y - press.y) * uy
        let reach = max(r, 60)
        let scale = start * (reach + outward) / reach
        return min(max(scale.isFinite ? scale : start, range.lowerBound), range.upperBound)
    }
}
