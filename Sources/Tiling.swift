import Foundation
import CoreGraphics

// Tile Windows: lays player windows out as a grid that fills one screen. Pure geometry, so `test.sh` covers it.
enum Tiling {
    // Frames for `count` 16:9 windows, largest size that fits: every column count is tried and the one giving
    // the widest window wins. Rows fill left to right from the top; a short last row is centred, and so is the grid.
    static func grid(count: Int, in area: CGRect, gap: CGFloat = 12, aspect: CGFloat = 16.0 / 9.0) -> (columns: Int, frames: [CGRect]) {
        guard count > 0 else { return (0, []) }
        let inner = area.insetBy(dx: gap, dy: gap)
        var best = (columns: 1, width: CGFloat(0))
        for cols in 1...count {
            let rows = (count + cols - 1) / cols
            let cellW = (inner.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let cellH = (inner.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            let w = min(cellW, cellH * aspect)
            if w > best.width { best = (cols, w) }
        }
        let cols = best.columns, rows = (count + cols - 1) / cols
        let w = max(1, floor(best.width)), h = max(1, floor(w / aspect))
        let gridH = CGFloat(rows) * h + CGFloat(rows - 1) * gap
        let top = inner.midY + gridH / 2
        var frames: [CGRect] = []
        for r in 0..<rows {
            let inRow = min(cols, count - r * cols)
            let rowW = CGFloat(inRow) * w + CGFloat(inRow - 1) * gap
            let x0 = (inner.midX - rowW / 2).rounded(.down)
            let y = (top - CGFloat(r + 1) * h - CGFloat(r) * gap).rounded(.down)
            for c in 0..<inRow { frames.append(CGRect(x: x0 + CGFloat(c) * (w + gap), y: y, width: w, height: h)) }
        }
        return (cols, frames)
    }

    // Which window takes which grid slot: the highest `columns` windows form the top row, ordered left to right,
    // and so on down — so re-tiling after dragging a window somewhere keeps it roughly where it was put.
    static func readingOrder(_ frames: [CGRect], columns: Int) -> [Int] {
        guard columns > 0 else { return Array(frames.indices) }
        let byHeight: [Int] = frames.indices.sorted { a, b in
            frames[a].midY != frames[b].midY ? frames[a].midY > frames[b].midY : a < b
        }
        var order: [Int] = []
        for start in stride(from: 0, to: byHeight.count, by: columns) {
            let row = byHeight[start..<min(start + columns, byHeight.count)]
            order += row.sorted { a, b in frames[a].midX != frames[b].midX ? frames[a].midX < frames[b].midX : a < b }
        }
        return order
    }
}
