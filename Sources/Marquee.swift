import Foundation
#if canImport(CoreGraphics)
import CoreGraphics   // CGFloat on Linux Foundation has its own; see GOTCHAS
#endif

// The menu-bar ticker's text and motion (3.26; Preferences ▸ "Show the playing song in the menu bar"). Pure, so `test.sh`
// covers it — MenuBarTicker.swift draws it.
enum TickerText {
    static let separator = " – "
    // "Song – Artist" on one line, or just the song when there's no artist; nil without a song name. Line breaks and runs of
    // spaces collapse, so a title with a newline in it can't make the item tall.
    static func line(title: String, artist: String?) -> String? {
        let song = clean(title)
        guard !song.isEmpty else { return nil }
        let by = artist.map(clean) ?? ""
        return by.isEmpty ? song : song + separator + by
    }
    static func clean(_ s: String) -> String { s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
}

// A line of text shown through a window of at most `maxWidth`, like the classic iTunes display. Text that fits stands still. Longer
// text rests at its start for `restTime`, then slides left at `speed` (so it reads left to right) until a second copy, `gap`
// behind the first, is where the first began — a seamless loop. The motion itself is one Core Animation key-frame animation
// (no timer): values 0 → 0 → -travel at key times 0 → restFraction → 1.
struct Marquee: Equatable {
    static let maxWidth: CGFloat = 150, gap: CGFloat = 32, speed: CGFloat = 30
    static let restTime: TimeInterval = 2
    let textWidth: CGFloat
    let window: CGFloat                                 // the visible width: the text's own, at most `maxWidth`
    init(textWidth: CGFloat, maxWidth: CGFloat = Marquee.maxWidth) {
        let t = textWidth.isFinite ? max(0, textWidth) : 0
        self.textWidth = t
        window = min(t, max(0, maxWidth))
    }
    var scrolls: Bool { textWidth > window }
    var travel: CGFloat { scrolls ? textWidth + Self.gap : 0 }              // how far one pass slides
    var duration: TimeInterval { scrolls ? Self.restTime + TimeInterval(travel / Self.speed) : 0 }   // rest + slide
    var restFraction: Double { scrolls ? Self.restTime / duration : 1 }
    // Where the text's left edge is `t` seconds into the loop (0 while resting, then 0 down to -travel).
    func offset(at t: TimeInterval) -> CGFloat {
        guard scrolls else { return 0 }
        let phase = t.truncatingRemainder(dividingBy: duration)
        let slid = max(0, phase - Self.restTime)
        return -min(travel, CGFloat(slid) * Self.speed)
    }
}
