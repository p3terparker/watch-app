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

enum ArtworkLayout {
    static let captionHeight: CGFloat = 64, gap: CGFloat = 20

    // Full screen: the artwork centred at up to 70% of the width and 62% of the height (keeping its shape), with the
    // caption block centred under it; the pair is centred vertically. Unflipped coordinates (y up), like AppKit.
    static func fullScreen(artwork: CGSize, in screen: CGSize) -> (art: CGRect, caption: CGRect) {
        let shape = artwork.width > 0 && artwork.height > 0 ? artwork : CGSize(width: 1, height: 1)
        let scale = min(screen.width * 0.7 / shape.width, screen.height * 0.62 / shape.height)
        let w = (shape.width * scale).rounded(), h = (shape.height * scale).rounded()
        let bottom = ((screen.height - h - gap - captionHeight) / 2).rounded()
        let art = CGRect(x: ((screen.width - w) / 2).rounded(), y: bottom + captionHeight + gap, width: w, height: h)
        let captionWidth = min(screen.width * 0.8, max(w, 480)).rounded()
        let caption = CGRect(x: ((screen.width - captionWidth) / 2).rounded(), y: bottom, width: captionWidth, height: captionHeight)
        return (art, caption)
    }
}
