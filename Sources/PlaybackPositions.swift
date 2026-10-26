import Foundation

// Where each video was left off, so reopening it resumes there. One UserDefaults dictionary
// (`playbackPositions`): key → [seconds, last-saved time]. Keys: `yt:<id>` for YouTube (any link shape
// to the same video resumes), the path for local files, the URL for everything else.
struct PlaybackPositions {
    static let shared = PlaybackPositions(defaults: .standard)
    static let limit = 300          // newest entries kept
    static let minimum = 5.0        // the first few seconds aren't worth resuming
    static let endMargin = 15.0     // this close to the end counts as finished → start over next time
    let defaults: UserDefaults
    private let storeKey = "playbackPositions"

    static func key(source: String, youtubeID: String?) -> String {
        if let id = youtubeID { return "yt:" + id }
        if source.hasPrefix("file://"), let u = URL(string: source) { return u.standardizedFileURL.path }
        if source.hasPrefix("/") { return URL(fileURLWithPath: source).standardizedFileURL.path }
        return source
    }
    private var all: [String: [Double]] { defaults.dictionary(forKey: storeKey) as? [String: [Double]] ?? [:] }

    func position(for key: String) -> Double? { all[key]?.first }
    // `duration` nil = unknown or live; a position near the end (or near the start) forgets the video.
    func save(_ seconds: Double, duration: Double?, for key: String) {
        guard seconds.isFinite else { return }
        if seconds < Self.minimum { clear(key); return }
        if let d = duration, d.isFinite, d > 0, seconds >= d - Self.endMargin { clear(key); return }
        var dict = all
        dict[key] = [seconds, Date().timeIntervalSinceReferenceDate]
        if dict.count > Self.limit {
            let oldest = dict.sorted { ($0.value.last ?? 0) < ($1.value.last ?? 0) }.prefix(dict.count - Self.limit)
            oldest.forEach { dict.removeValue(forKey: $0.key) }
        }
        defaults.set(dict, forKey: storeKey)
    }
    func clear(_ key: String) {
        var dict = all
        guard dict.removeValue(forKey: key) != nil else { return }
        defaults.set(dict, forKey: storeKey)
    }
}
