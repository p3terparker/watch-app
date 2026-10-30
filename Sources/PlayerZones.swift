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

    static func strip(width: CGFloat) -> CGFloat { min(width / 3, max(minStrip, width * stripFraction)) }
    static func at(_ p: CGPoint, in size: CGSize) -> MusicZone {
        guard size.width > 0 else { return .main }
        let s = strip(width: size.width)
        if p.x < s { return .skipBack }
        if p.x >= size.width - s { return .skipForward }
        return .main
    }
}
