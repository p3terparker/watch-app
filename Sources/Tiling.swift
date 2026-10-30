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

// The Up Next list under the music window (QueueDrawer): below the window; above it when only that side has room;
// otherwise the window moves up just enough for the list to fit below, and on a screen too short for both the list
// shrinks to the room left (never under `minHeight`). While the user drags or resizes the window (`moveParent` false)
// it is never moved: the list takes the side with more room, shrunk to fit.
enum DrawerLayout {
    static func place(parent: CGRect, height: CGFloat, minHeight: CGFloat, width: CGFloat, gap: CGFloat, in vis: CGRect,
                      moveParent: Bool) -> (list: CGRect, parent: CGRect) {
        var p = parent, h = height, y: CGFloat
        let below = p.minY - vis.minY - gap, above = vis.maxY - p.maxY - gap
        if below >= h {
            y = p.minY - gap - h
        } else if above >= h {
            y = p.maxY + gap
        } else if moveParent {
            if p.height + gap + h > vis.height { h = max(minHeight, vis.height - p.height - gap) }
            p.origin.y = min(vis.maxY - p.height, vis.minY + h + gap)
            y = max(vis.minY, p.minY - gap - h)
        } else if below >= above {
            h = max(minHeight, min(h, below))
            y = max(vis.minY, p.minY - gap - h)
        } else {
            h = max(minHeight, min(h, above))
            y = min(vis.maxY - h, p.maxY + gap)
        }
        let x = min(max(p.minX, vis.minX), vis.maxX - width)
        return (CGRect(x: x, y: y, width: width, height: h), p)
    }
}
