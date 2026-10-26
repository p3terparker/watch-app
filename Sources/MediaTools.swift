import Foundation

// Watch owns its helper set. No Homebrew/PATH fallback: a damaged package must be reported, not masked.
struct MediaTools {
    static let names = ["yt-dlp", "ffmpeg", "ffprobe", "deno"]
    static let bundled = MediaTools(directory: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers"))
    let directory: URL

    func executable(_ name: String) -> URL? {
        guard Self.names.contains(name) else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
    var missing: [String] { Self.names.filter { executable($0) == nil } }

    func arguments(_ args: [String]) -> [String] {
        ["--ignore-config", "--no-plugin-dirs", "--no-remote-components", "--no-js-runtimes",
         "--js-runtimes", "deno:" + directory.appendingPathComponent("deno").path,
         "--ffmpeg-location", directory.path] + args
    }
    func environment(_ inherited: [String: String], cache: URL) -> [String: String] {
        var env = inherited
        env["PATH"] = directory.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        env["DENO_DIR"] = cache.appendingPathComponent("deno").path
        env["DENO_NO_UPDATE_CHECK"] = "1"
        for key in ["PYTHONHOME", "PYTHONPATH", "DYLD_LIBRARY_PATH", "DYLD_FRAMEWORK_PATH"] { env.removeValue(forKey: key) }
        return env
    }
    func process(_ args: [String], environment: [String: String] = ProcessInfo.processInfo.environment,
                 cache: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("com.jacob.watch/media-tools")) -> Process? {
        guard missing.isEmpty, let exe = executable("yt-dlp") else { return nil }
        let p = Process()
        p.executableURL = exe
        p.arguments = arguments(args)
        p.environment = self.environment(environment, cache: cache)
        p.standardInput = FileHandle.nullDevice
        return p
    }

    struct Check {
        let name: String
        let detail: String
        let ok: Bool
    }
    // Local executable checks only. Pipes drain concurrently, and a hung helper is terminated after 12 s.
    func check() -> [Check] {
        Self.names.map { name in
            guard let exe = executable(name) else { return Check(name: name, detail: "Missing — replace Watch with a fresh copy.", ok: false) }
            let p = Process(), output = Pipe()
            p.executableURL = exe
            p.arguments = [name == "ffmpeg" || name == "ffprobe" ? "-version" : "--version"]
            p.environment = environment(["HOME": NSHomeDirectory()], cache: FileManager.default.temporaryDirectory.appendingPathComponent("watch-tool-check"))
            p.standardInput = FileHandle.nullDevice; p.standardOutput = output; p.standardError = FileHandle.nullDevice
            do {
                try p.run()
                let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 12, execute: timeout)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit(); timeout.cancel()
                let line = String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
                return Check(name: name, detail: p.terminationStatus == 0 ? String(line.prefix(90)) : "Couldn't start — replace Watch with a fresh copy.", ok: p.terminationStatus == 0)
            } catch { return Check(name: name, detail: "Couldn't start — replace Watch with a fresh copy.", ok: false) }
        }
    }
}
