import Foundation
import SonyProtocol

let args = Array(CommandLine.arguments.dropFirst()).filter { $0 != "--verbose" }
let verbose = CommandLine.arguments.contains("--verbose")
if args == ["menu"] || (args.isEmpty && Bundle.main.bundlePath.hasSuffix(".app")) { MainActor.assumeIsolated { runMenuBar() } }
let usage = """
sony-control menu                   Open the menu bar popover
sony-control status                 Read battery, sound mode, and EQ
sony-control anc                    Enable noise cancellation
sony-control off                    Disable noise cancellation/ambient sound
sony-control ambient [1–20] [voice|normal]  Enable ambient sound; optional voice focus
sony-control eq <preset>            Select a saved EQ preset
sony-control verify                 Test modes/EQ and restore original settings

EQ presets: \(presets.map { $0.0 }.joined(separator: ", "))
Add --verbose for Bluetooth packet logs. Requires WH-CH720N paired to this Mac.
"""
if args.isEmpty || args == ["--help"] { print(usage); exit(0) }
Task { @MainActor in
do {
    guard ["status", "anc", "off", "ambient", "eq", "verify"].contains(args[0]) else { throw Failure(usage) }
    if args[0] == "eq" { guard args.count == 2, presets.contains(where: { $0.0 == args[1] }) else { throw Failure(usage) } }
    else if args[0] == "ambient" {
        guard args.count <= 3, args.count < 2 || Int(args[1]).map({ (1...20).contains($0) }) == true, args.count < 3 || ["voice", "normal"].contains(args[2]) else { throw Failure(usage) }
    } else { guard args.count == 1 else { throw Failure(usage) } }
    let headphones = try await Headphones(verbose: verbose)
    defer { headphones.close() }
    switch args[0] {
    case "anc", "off": try await headphones.setMode(args[0])
    case "ambient": try await headphones.setMode("ambient", level: args.count > 1 ? Int(args[1]) : nil, voice: args.count > 2 ? args[2] == "voice" : nil)
    case "eq": try await headphones.setEq(args[1])
    case "verify": try await headphones.verify(); exit(0)
    default: break
    }
    print(try await headphones.status().description)
    exit(0)
} catch { fputs("Error: \(error)\n", stderr); exit(1) }

}
RunLoop.main.run()
