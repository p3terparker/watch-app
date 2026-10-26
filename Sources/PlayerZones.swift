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
