import Foundation

// Download queue and format selection, shared with the isolated regression harness.
enum DownloadKind: Equatable {
    case video, audio, playlist  // video = H.264/AAC MP4 ≤1080p (opens anywhere); audio = M4A
    case originalVideo           // best video+audio exactly as the site serves it — source codecs + container, no re-encode
    case mp4Best                 // highest resolution available, as an .mp4 that plays in QuickTime (see mp4Recode)
    case originalAudio           // best audio stream, extracted without re-encoding (.opus / .m4a …)
    case mp3                     // MP3 encoded at the source audio's bit rate (probed first; see DownloadJob.mp3Kbps)
    case videoUpTo(Int)          // max height, e.g. 1080
    case exact(String, String)   // (yt-dlp format selector, menu label) — Advanced Formats
    var label: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .originalVideo: return "Original Video"
        case .mp4Best: return "MP4"
        case .originalAudio: return "Original Audio"
        case .mp3: return "MP3"
        case .playlist: return "Playlist"
        case .videoUpTo(let h): return "\(h)p"
        case .exact(_, let l): return l.components(separatedBy: " · ").first ?? "Format"
        }
    }
    var isAudio: Bool { self == .audio || self == .mp3 || self == .originalAudio }
}
final class DownloadJob {
    enum State { case queued, running, done, failed, stopped }
    let id = UUID()
    let url: String
    let kind: DownloadKind
    var title: String
    var state: State = .queued
    var percent: Double = 0
    var part = 1                 // video downloads fetch video then audio; progress restarts per part
    let dir: String              // chosen per download when Preferences ▸ "Ask where to save" is on
    var mp3Kbps: Int?            // .mp3 only: the source audio bit rate, snapped to a legal MP3 rate
    var didProbeMP3 = false      // an unknown rate is a completed probe, not a reason to probe forever
    var mp4Recode: [String]?     // .mp4Best only, set by the probe: [] = streams are MP4-native, else yt-dlp recode args
    var converting = false       // yt-dlp is re-encoding after the download finished
    var filePath: String?
    var error: String?
    var process: Process?
    init(url: String, title: String, kind: DownloadKind, dir: String) { self.url = url; self.title = title; self.kind = kind; self.dir = dir }
}
final class DownloadManager {
    private(set) var jobs: [DownloadJob] = []
    var onChange: (() -> Void)?
    var onFinish: ((DownloadJob) -> Void)?
    private var changeScheduled = false
    private let maxConcurrent = 3    // "Download All" playlists would otherwise start dozens of yt-dlps at once
    var hasRunning: Bool { jobs.contains { $0.state == .running || $0.state == .queued } }

    func start(url: String, title: String?, kind: DownloadKind, dir: String = Prefs.downloadDir) {
        let job = DownloadJob(url: url, title: title ?? url, kind: kind, dir: dir)
        jobs.insert(job, at: 0)
        changed(now: true)
        if title == nil {
            resolveTitle(url) { [weak self] t in if let t = t, job.title == job.url { job.title = t; self?.changed(now: true) } }
        }
        pump()
    }
    // Start queued jobs, oldest first, while there are free slots.
    private func pump() {
        var active = jobs.filter { $0.state == .running }.count
        for job in jobs.reversed() where job.state == .queued && active < maxConcurrent {
            job.state = .running; active += 1
            launch(job)   // Bundled tools update with the app; never self-modify signed helpers.
        }
        changed(now: true)
    }
    private func launch(_ job: DownloadJob) {
        guard job.state == .running else { pump(); return }
        // MP3 "at the source bit rate": ask yt-dlp what the best audio stream's bit rate is, then encode to match.
        if job.kind == .mp3, !job.didProbeMP3 {
            job.didProbeMP3 = true
            YtDlp.capture(["-j", "--no-playlist", "--no-warnings", "-f", "ba/b", job.url]) { [weak self] data in
                let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let br = (j?["abr"] as? Double) ?? (j?["abr"] as? Int).map(Double.init) ?? (j?["tbr"] as? Double) ?? 0
                job.mp3Kbps = Self.mp3Rate(br)
                self?.launch(job)
            }
            return
        }
        // MP4 "highest quality": top resolution is often VP9/AV1-only (YouTube 1440p/4K), which QuickTime can't play on
        // most Macs. Probe what yt-dlp would pick; if it isn't H.264/HEVC, re-encode to HEVC on the hardware encoder
        // at the source bit rate. H.264/HEVC sources are just merged — no quality loss.
        if job.kind == .mp4Best, job.mp4Recode == nil {
            YtDlp.capture(["-j", "--no-playlist", "--no-warnings"] + Self.mp4BestFormat + [job.url]) { [weak self] data in
                let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                job.mp4Recode = Self.mp4RecodeArgs(j)
                self?.launch(job)
            }
            return
        }
        try? FileManager.default.createDirectory(atPath: job.dir, withIntermediateDirectories: true)
        var args = ["-P", job.dir, "--no-warnings", "--newline", "--progress",
                    "--progress-template", "download:WATCHPROG %(progress._percent)s",
                    "--print", "after_move:WATCHFILE %(filepath)s"]
        args += job.kind == .playlist
            ? ["--yes-playlist", "-o", "%(playlist_title).120B/%(playlist_index)03d %(title).160B [%(id)s].%(ext)s"]
            : ["--no-playlist", "-o", "%(title).180B [%(id)s].%(ext)s"]
        // Video: H.264/AAC in .mp4 first so the file opens anywhere (QuickTime, Photos, iOS); else best available.
        let mp4 = ["--merge-output-format", "mp4"]
        switch job.kind {
        case .video, .playlist: args += ["-f", "bv*[vcodec^=avc1]+ba[ext=m4a]/bv*+ba/b"] + mp4
        case .videoUpTo(let h): args += ["-f", "bv*[vcodec^=avc1][height<=\(h)]+ba[ext=m4a]/bv*[height<=\(h)]+ba/b[height<=\(h)]/b"] + mp4
        case .originalVideo: args += ["-f", "bv*+ba/b"]    // yt-dlp keeps the source container (webm/mp4, mkv if mixed)
        case .mp4Best:
            let recode = job.mp4Recode ?? []
            args += Self.mp4BestFormat + (recode.isEmpty ? mp4 : ["--merge-output-format", "mkv"] + recode)
        case .audio: args += ["-f", "ba[ext=m4a]/ba/b", "-x", "--audio-format", "m4a"]
        case .originalAudio: args += ["-f", "ba/b", "-x"]  // --audio-format defaults to "best": no re-encode
        case .mp3:
            let q = (job.mp3Kbps ?? 0) > 0 ? "\(job.mp3Kbps!)K" : "0"   // unknown source rate → best VBR
            args += ["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", q]
        case .exact(let sel, _): args += ["-f", sel]
        }
        args.append(job.url)
        guard let p = YtDlp.process(args) else {
            job.state = .failed; job.error = "Watch’s included media tools are missing or incomplete. Replace Watch with a fresh copy."; changed(now: true); onFinish?(job); pump(); return
        }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        var outBuf = Data(), lastError = ""
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard !chunk.isEmpty else { h.readabilityHandler = nil; return }
            outBuf.append(chunk)
            while let nl = outBuf.firstIndex(of: 0x0A) {
                let line = String(decoding: outBuf[outBuf.startIndex..<nl], as: UTF8.self)
                outBuf.removeSubrange(outBuf.startIndex...nl)
                DispatchQueue.main.async { self?.handle(line, job) }
            }
        }
        err.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            guard !chunk.isEmpty else { h.readabilityHandler = nil; return }
            if let s = String(data: chunk, encoding: .utf8),
               let e = s.split(separator: "\n").last(where: { $0.hasPrefix("ERROR") }) { lastError = String(e) }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
                job.process = nil
                if job.state == .running {
                    if proc.terminationStatus == 0 { job.state = .done; job.percent = 100 }
                    else { job.state = .failed; job.error = lastError.isEmpty ? "yt-dlp exited with \(proc.terminationStatus)" : lastError }
                }
                self?.changed(now: true)
                self?.onFinish?(job)
                self?.pump()
            }
        }
        do { try p.run(); job.process = p }
        catch { job.state = .failed; job.error = error.localizedDescription; changed(now: true); onFinish?(job); pump() }
    }
    private func handle(_ line: String, _ job: DownloadJob) {
        if line.hasPrefix("WATCHPROG "), let v = Double(line.dropFirst(10).trimmingCharacters(in: .whitespaces)) {
            if v + 50 < job.percent { job.part += 1 }
            job.percent = v; changed(now: false)
        } else if line.hasPrefix("[VideoConvertor]") || line.hasPrefix("[ExtractAudio]") {
            job.converting = true; changed(now: true)
        } else if line.hasPrefix("WATCHFILE ") {
            job.filePath = String(line.dropFirst(10))
        }
    }
    // Highest resolution/fps, SDR; at equal quality prefer H.264 > HEVC > VP9 > AV1 and AAC, so re-encoding is the exception.
    static let mp4BestFormat = ["-f", "bv*+ba[ext=m4a]/bv*+ba/b", "-S", "res,fps,hdr:sdr,+codec:avc:m4a"]
    static func mp4RecodeArgs(_ j: [String: Any]?) -> [String] {
        guard let j = j else { return [] }   // probe failed: fall back to a plain MP4 merge
        let v = (j["vcodec"] as? String ?? "").lowercased(), a = (j["acodec"] as? String ?? "").lowercased()
        if ["avc", "h264", "hvc1", "hev1", "h265", "hevc"].contains(where: v.hasPrefix) || v == "none" || v.isEmpty { return [] }
        let req = j["requested_formats"] as? [[String: Any]] ?? []
        let num: (Any?) -> Double? = { ($0 as? Double) ?? ($0 as? Int).map(Double.init) }
        let vbr = req.compactMap { f in (f["vcodec"] as? String ?? "none") != "none" ? num(f["vbr"]) ?? num(f["tbr"]) : nil }.first
            ?? num(j["vbr"]) ?? 8000
        let audio = a.hasPrefix("mp4a") || a.hasPrefix("aac") ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", "256k"]
        let pp = (["-c:v", "hevc_videotoolbox", "-b:v", "\(max(1000, Int(vbr)))k", "-tag:v", "hvc1"] + audio).joined(separator: " ")
        return ["--recode-video", "mp4", "--postprocessor-args", "VideoConvertor:" + pp]
    }
    // Nearest legal MP3 bit rate at or above the source (e.g. 129k Opus → 160k), capped at MP3's 320k max.
    static func mp3Rate(_ kbps: Double) -> Int? {
        guard kbps > 0 else { return nil }
        let legal = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
        return legal.first { Double($0) >= kbps.rounded() } ?? 320
    }
    // SIGINT, not SIGTERM: yt-dlp finalizes what it has (a live recording becomes a playable file).
    func stop(_ job: DownloadJob) {
        guard job.state == .running || job.state == .queued else { return }
        job.state = .stopped; job.process?.interrupt(); changed(now: true)
    }
    func remove(_ job: DownloadJob) { stop(job); jobs.removeAll { $0 === job }; changed(now: true) }
    func stopAll() {
        jobs.filter { $0.state == .queued }.forEach { $0.state = .stopped }
        jobs.filter { $0.state == .running }.forEach { $0.process?.interrupt() }
    }
    // Progress lines arrive many times a second; coalesce UI refreshes to ~4/s.
    private func changed(now: Bool) {
        if now { onChange?(); return }
        guard !changeScheduled else { return }
        changeScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.changeScheduled = false; self?.onChange?() }
    }
}

