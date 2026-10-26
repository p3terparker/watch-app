import Foundation

func checkMediaTools() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Watch tools fixture \(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let tools = MediaTools(directory: root)
    expect(tools.missing == MediaTools.names, "missing bundle never falls back to host Homebrew")
    expect(tools.process(["--version"]) == nil, "incomplete bundle cannot launch")
    expect(tools.executable("../other") == nil, "only named helpers resolve")
    for name in MediaTools.names {
        let path = root.appendingPathComponent(name)
        try! "#!/bin/sh\nprintf '%s\\n' 'Fixture \(name) 1.0'\n".write(to: path, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }
    expect(tools.missing.isEmpty, "complete fixture bundle found")
    let process = tools.process(["ytsearch18:hello world"], environment: ["PATH": "/opt/homebrew/bin", "PYTHONPATH": "/untrusted", "HOME": root.path], cache: root)!
    expect(process.executableURL?.path == root.appendingPathComponent("yt-dlp").path, "launch uses bundle executable")
    expect(process.arguments?.last == "ytsearch18:hello world", "query stays one argument")
    expect(process.arguments?.contains("deno:" + root.appendingPathComponent("deno").path) == true, "runtime explicitly bundled even with spaces")
    expect(process.arguments?.contains(root.path) == true, "ffmpeg explicitly bundled")
    expect(process.arguments?.contains("--ignore-config") == true, "host yt-dlp configuration ignored")
    expect(process.arguments?.contains("--no-plugin-dirs") == true, "host plugins disabled")
    expect(process.arguments?.contains("--no-remote-components") == true, "no implicit helper downloads")
    expect(process.environment?["PATH"] == root.path + ":/usr/bin:/bin:/usr/sbin:/sbin", "host PATH cannot supply helpers")
    expect(process.environment?["PYTHONPATH"] == nil, "Python contamination removed")
    expect(process.environment?["DENO_DIR"] == root.appendingPathComponent("deno").path, "runtime cache lies outside bundle")
    expect(tools.check().allSatisfy { $0.ok && $0.detail.hasPrefix("Fixture") }, "readiness actually executes all four fixtures")
    try! FileManager.default.removeItem(at: root.appendingPathComponent("ffprobe"))
    expect(tools.process(["--version"]) == nil, "partly missing helpers fail closed")
    expect(tools.check().first(where: { $0.name == "ffprobe" })?.ok == false, "guide reports missing helper")
}
