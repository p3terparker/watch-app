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
enum YtDlpFixture { static let timedOut = "yt-dlp timed out" }
