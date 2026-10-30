import Foundation
#if canImport(CoreGraphics)
import CoreGraphics   // CGSize members (see GOTCHAS); Linux Foundation has its own
#endif

// Quality that follows the window: the lower H.264 renditions YouTube offers alongside the one yt-dlp picked, so
// DashHLSBridge can describe them all and AVPlayer can switch between them; and the size cap AVPlayer is given from
// the video area (AVPlayerItem.preferredMaximumResolution). Pure — the player applies them.
enum StreamLadder {
    static let heights = [360, 480, 720, 1080]
    static let headroom: CGFloat = 1.25          // a little over the window's pixels, so 720p still fits a ~600 pt window

    // yt-dlp's chosen video format first, then for each standard height below it the best https, video-only H.264 MP4
    // at that height (highest bitrate). Formats a bridge can't use (HLS, VP9/AV1, muxed, no URL) are skipped.
    static func renditions(chosen: [String: Any], formats: [[String: Any]]) -> [[String: Any]] {
        let top = chosen["height"] as? Int ?? 0
        var best: [Int: [String: Any]] = [:]
        for f in formats {
            guard let h = f["height"] as? Int, heights.contains(h), h < top,
                  (f["vcodec"] as? String)?.hasPrefix("avc1") == true, f["acodec"] as? String == "none",
                  f["protocol"] as? String == "https", f["ext"] as? String == "mp4", f["url"] is String else { continue }
            if let current = best[h], bitrate(current) >= bitrate(f) { continue }
            best[h] = f
        }
        return [chosen] + best.keys.sorted(by: >).compactMap { best[$0] }
    }
    private static func bitrate(_ f: [String: Any]) -> Double {
        switch f["tbr"] { case let d as Double: return d; case let i as Int: return Double(i); default: return 0 }
    }

    // The most pixels worth decoding for a video area of `points` on a screen of `scale`.
    static func cap(points: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: (points.width * scale * headroom).rounded(), height: (points.height * scale * headroom).rounded())
    }
    // "720p" for the player's menu; nil before a picture size is known.
    static func label(height: Double) -> String? { height >= 1 ? "\(Int(height.rounded()))p" : nil }
}

// Why a video didn't play natively, from yt-dlp's last ERROR line.
enum PlaybackFailure {
    // YouTube wants a signed-in viewer (bot check, age gate, members-only…): worth one retry with the connected
    // browser's cookies.
    static func wantsSignIn(_ error: String) -> Bool {
        let e = error.lowercased()
        return ["sign in", "not a bot", "--cookies", "confirm your age", "age-restricted", "age restricted",
                "members-only", "members only", "login required", "private video"].contains { e.contains($0) }
    }
    // The part worth showing: without "ERROR: [youtube] <id>: " and yt-dlp's report-a-bug boilerplate.
    static func reason(_ error: String) -> String {
        var s = error.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("ERROR:") { s = String(s.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        if s.hasPrefix("["), let close = s.firstIndex(of: "]") {
            s = String(s[s.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            if let colon = s.firstIndex(of: ":"), s.distance(from: s.startIndex, to: colon) <= 20, !s[..<colon].contains(" ") {
                s = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)   // the video id
            }
        }
        for tail in ["; please report this issue", " please report this issue", " Use --cookies", " Confirm you are on the latest version"] {
            if let r = s.range(of: tail) { s = String(s[..<r.lowerBound]) }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "YouTube didn't give Watch a stream it can play." : s
    }
}

// Every playback failure, newest last — what the failure card's "Copy Details" summarises, and a file to send on:
// ~/Library/Logs/Watch/playback.log, kept under `limit` (the older half goes). Writes happen off the main thread.
final class PlaybackLog {
    static let shared = PlaybackLog(file: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Watch/playback.log"))
    static let limit = 256 << 10
    let file: URL
    private let queue = DispatchQueue(label: "watch.playbacklog")
    private let now: () -> Date
    init(file: URL, now: @escaping () -> Date = Date.init) { self.file = file; self.now = now }
    func append(_ line: String) { queue.async { self.write(line) } }
    func write(_ line: String) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = (try? Data(contentsOf: file)) ?? Data()
        if data.count > Self.limit {
            data = Data(data.suffix(Self.limit / 2))
            if let newline = data.firstIndex(of: 0x0A) { data = Data(data[data.index(after: newline)...]) }   // whole lines only
        }
        let stamp = ISO8601DateFormatter().string(from: now())
        data.append(Data("\(stamp) \(line.replacingOccurrences(of: "\n", with: " "))\n".utf8))
        try? data.write(to: file, options: .atomic)
    }
}
