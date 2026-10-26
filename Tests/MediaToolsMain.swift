// Compiled as main.swift by bundled.py; exercises the production launch boundary.
import Foundation
let tools = MediaTools(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
let args = Array(CommandLine.arguments.dropFirst(2))
if args == ["check"] {
    let checks = tools.check()
    for check in checks { print("\(check.name): \(check.ok) \(check.detail)") }
    exit(checks.allSatisfy(\.ok) ? 0 : 1)
}
guard let process = tools.process(args, cache: URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!).appendingPathComponent(".cache/watch")) else { fatalError("Incomplete tools") }
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
