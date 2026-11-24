import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Quality that follows the window, why a video didn't play, and the playback log.
func checkStreams() {
    func format(_ id: String, _ height: Int, _ tbr: Double, vcodec: String = "avc1.640028", proto: String = "https", ext: String = "mp4",
                acodec: String = "none") -> [String: Any] {
        ["format_id": id, "height": height, "width": height * 16 / 9, "tbr": tbr, "vcodec": vcodec, "acodec": acodec,
         "protocol": proto, "ext": ext, "url": "https://fixture.invalid/\(id)"]
    }
    let chosen = format("137", 1080, 4400)
    let formats = [format("160", 144, 100), format("133", 240, 250), format("134", 360, 650), format("134b", 360, 500),
                   format("135", 480, 1100), format("136", 720, 2300), format("398", 720, 2000, vcodec: "av01.0.05M.08"),
                   format("247", 720, 1800, vcodec: "vp9"), format("22", 720, 2500, acodec: "mp4a.40.2"),
                   format("95", 720, 2600, proto: "m3u8_native"), format("299", 1080, 6000), chosen]
    let ladder = StreamLadder.renditions(chosen: chosen, formats: formats).map { $0["format_id"] as? String ?? "" }
    expect(ladder == ["137", "136", "135", "134"], "chosen first, then the best H.264 video-only https MP4 per lower height: \(ladder)")
    let at720 = StreamLadder.renditions(chosen: format("136", 720, 2300), formats: formats).map { $0["format_id"] as? String ?? "" }
    expect(at720 == ["136", "135", "134"], "nothing above the chosen rendition")
    expect(StreamLadder.renditions(chosen: format("18", 360, 600, acodec: "mp4a.40.2"), formats: formats).count == 1, "nothing below 360p")
    var noURL = format("135", 480, 1100); noURL.removeValue(forKey: "url")
    expect(StreamLadder.renditions(chosen: chosen, formats: [noURL]).count == 1, "a format without a URL is skipped")

    let cap = StreamLadder.cap(points: CGSize(width: 440, height: 247), scale: 2)
    expect(cap == CGSize(width: 1100, height: 618), "standard window on Retina: room for 480p, not 720p")
    expect(StreamLadder.cap(points: CGSize(width: 600, height: 338), scale: 2).width >= 1280, "a ~600 pt window takes 720p")
    expect(StreamLadder.cap(points: CGSize(width: 1512, height: 850), scale: 2).height >= 1080, "a big window takes 1080p")
    expect(StreamLadder.label(height: 720) == "720p" && StreamLadder.label(height: 719.6) == "720p" && StreamLadder.label(height: 0) == nil, "quality label")

    let bot = "ERROR: [youtube] jNQXAC9IVRw: Sign in to confirm you’re not a bot. This helps protect our community. Use --cookies-from-browser or --cookies for the authentication. See  https://github.com/yt-dlp/yt-dlp/wiki/FAQ"
    expect(PlaybackFailure.wantsSignIn(bot), "the bot check wants a signed-in viewer")
    expect(PlaybackFailure.reason(bot) == "Sign in to confirm you’re not a bot. This helps protect our community.", "reason without prefix or advice: \(PlaybackFailure.reason(bot))")
    expect(PlaybackFailure.wantsSignIn("ERROR: [youtube] x: Sign in to confirm your age. This video may be inappropriate for some users."), "age gate")
    expect(!PlaybackFailure.wantsSignIn("ERROR: [youtube] x: Video unavailable") && !PlaybackFailure.wantsSignIn(YtDlpFixture.timedOut), "other failures don't")
    expect(PlaybackFailure.reason("ERROR: [youtube] abcdefghijk: Video unavailable; please report this issue on  https://github.com/yt-dlp") == "Video unavailable", "report boilerplate dropped")
    expect(PlaybackFailure.reason("") == "YouTube didn't give Watch a stream it can play." && PlaybackFailure.reason("yt-dlp timed out") == "yt-dlp timed out", "empty and plain reasons")

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Watch log fixture \(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let log = PlaybackLog(file: folder.appendingPathComponent("Logs/Watch/playback.log"), now: { Date(timeIntervalSince1970: 1_800_000_000) })
    log.write("https://www.youtube.com/watch?v=x — first\nline")
    log.write("second")
    let text = (try? String(contentsOf: log.file, encoding: .utf8)) ?? ""
    expect(text == "2027-01-15T08:00:00Z https://www.youtube.com/watch?v=x — first line\n2027-01-15T08:00:00Z second\n", "timestamped, one line each: \(text)")
    for _ in 0..<3000 { log.write(String(repeating: "x", count: 120)) }
    let trimmed = (try? Data(contentsOf: log.file)) ?? Data()
    let lines = String(decoding: trimmed, as: UTF8.self).split(separator: "\n")
    expect(trimmed.count <= PlaybackLog.limit + 200 && lines.allSatisfy { $0.hasPrefix("2027-01-15T08:00:00Z ") }, "kept under the limit, whole lines only")
}

// 3.27: the bridge declares each rendition's real peak and average bit rate (from its sidx), not yt-dlp's average.
func checkSegmentIndex() {
    // Three 5 s segments of 1, 3 and 2 MB, then a 0.2 s tail of 0.5 MB (20 Mb/s over that sliver).
    let idx = SegmentIndex(initLength: 800, segments: [(800, 1_000_000, 5), (1_000_800, 3_000_000, 5), (4_000_800, 2_000_000, 5),
                                                       (6_000_800, 500_000, 0.2)])
    expect(idx.peak == 4_800_000, "peak = the busiest whole segment, 3 MB in 5 s (\(idx.peak))")
    expect(abs(idx.average - 3_421_053) <= 1, "average = all bytes over all time (\(idx.average))")
    let short = SegmentIndex(initLength: 0, segments: [(0, 100_000, 0.5), (100_000, 50_000, 0.25)])
    expect(short.peak == 1_600_000, "only short segments: they count (\(short.peak))")
    let empty = SegmentIndex(initLength: 0, segments: [(0, 100, 0)])
    expect(empty.peak == 0 && empty.average == 0, "no time at all: nothing to declare, the bridge falls back to yt-dlp's figure")
}
// 3.27: a video that never starts (black picture, controls up) moves on to the next plan; one that stops after errors reloads.
func checkStallWatch() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    var w = StallWatch(start: t0)
    var v: StallWatch.Verdict = .fine
    for s in stride(from: 2.0, through: 24, by: 2) { v = w.tick(now: at(s), time: 0, paused: false, errors: 0) }
    expect(v == .fine, "still within the start limit")
    expect(w.tick(now: at(26), time: 0, paused: false, errors: 0) == .nextPlan, "nothing for 25 s: the next plan")
    // Resumed at 1:30:00: the seek's jump isn't playback, so the start limit still applies.
    w = StallWatch(start: t0)
    _ = w.tick(now: at(2), time: 0, paused: false, errors: 0)
    for s in stride(from: 4.0, through: 24, by: 2) { v = w.tick(now: at(s), time: 5400, paused: false, errors: 0) }
    expect(v == .fine && !w.everPlayed, "a resume seek is not playback")
    expect(w.tick(now: at(26), time: 5400, paused: false, errors: 0) == .nextPlan, "stuck at the resume spot: the next plan")
    // Paused by the user before it ever played: no verdict.
    w = StallWatch(start: t0)
    for s in stride(from: 2.0, through: 60, by: 2) { v = w.tick(now: at(s), time: 0, paused: true, errors: 0) }
    expect(v == .fine, "paused isn't stalled")
    // Playing, then stuck: only with new errors in AVPlayer's log (a slow network just buffers).
    w = StallWatch(start: t0)
    for s in stride(from: 2.0, through: 10, by: 2) { _ = w.tick(now: at(s), time: s - 2, paused: false, errors: 1) }
    expect(w.everPlayed, "the clock moving is playback")
    for s in stride(from: 12.0, through: 60, by: 2) { v = w.tick(now: at(s), time: 8, paused: false, errors: 1) }
    expect(v == .fine, "stopped without new errors: keep waiting")
    w = StallWatch(start: t0)
    for s in stride(from: 2.0, through: 10, by: 2) { _ = w.tick(now: at(s), time: s - 2, paused: false, errors: 0) }
    for s in stride(from: 12.0, through: 28, by: 2) { v = w.tick(now: at(s), time: 8, paused: false, errors: 2) }
    expect(v == .fine, "under 20 s")
    expect(w.tick(now: at(30), time: 8, paused: false, errors: 2) == .reload, "stopped 20 s after errors: reload with fresh links")
    // A seek while playing restarts the clock.
    w = StallWatch(start: t0)
    for s in stride(from: 2.0, through: 10, by: 2) { _ = w.tick(now: at(s), time: s - 2, paused: false, errors: 0) }
    for s in stride(from: 12.0, through: 28, by: 2) { _ = w.tick(now: at(s), time: 8, paused: false, errors: 3) }
    _ = w.tick(now: at(29), time: 600, paused: false, errors: 3)
    expect(w.tick(now: at(31), time: 600, paused: false, errors: 3) == .fine, "a seek counts as moving")
}
enum YtDlpFixture { static let timedOut = "yt-dlp timed out" }
