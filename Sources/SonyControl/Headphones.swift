import Foundation
import IOBluetooth
import SonyProtocol

let presets: [(String, UInt8)] = [("off", 0), ("bright", 16), ("excited", 17), ("mellow", 18), ("relaxed", 19), ("vocal", 20), ("treble", 21), ("bass", 22), ("speech", 23), ("manual", 160), ("custom1", 161), ("custom2", 162)]

struct HeadphoneStatus {
    let anc: [UInt8]
    let battery: Int?
    let eq: [UInt8]
    var mode: String { anc[3] == 0 ? "Off" : (anc[4] == 0 ? "ANC" : "Ambient") }
    var voice: Bool { anc[5] == 1 }
    var level: Int { Int(anc[6]) }
    var preset: String { presets.first { $0.1 == eq[2] }?.0 ?? String(format: "0x%02x", eq[2]) }
    var description: String { "WH-CH720N · Battery \(battery.map { "\($0)%" } ?? "unknown")\nSound: \(mode) · Ambient level \(level) · Voice focus \(voice ? "on" : "off")\nEQ: \(preset)" }
}

@MainActor
final class Headphones {
    let link: Link
    private var cachedAnc: [UInt8]?
    private var cachedEq: [UInt8]?
    private var battery: Int?
    var onChange: ((HeadphoneStatus) -> Void)?
    var onDisconnect: (() -> Void)?
    var isConnected: Bool { !link.closed }
    var snapshot: HeadphoneStatus? {
        guard let anc = cachedAnc, let eq = cachedEq else { return nil }
        return HeadphoneStatus(anc: anc, battery: battery, eq: eq)
    }

    init(verbose: Bool = false) async throws {
        link = Link(verbose: verbose)
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let matches = devices.filter { $0.name == "WH-CH720N" }
        guard matches.count == 1, let device = matches.first else { throw Failure("Connect one WH-CH720N to this Mac in Bluetooth settings.") }
        link.onPayload = { [weak self] in self?.receive($0) }
        link.onDisconnect = { [weak self] in self?.onDisconnect?() }
        do {
            try await link.open(device)
            let info = try await link.request([0, 0], response: 1)
            guard info.count == 8, info[2] == 3 else { throw Failure("Unsupported Sony protocol: \(hex(info))") }
            let functions = try await link.request([6, 0], response: 7)
            guard functions.count >= 3, functions.count == Int(functions[2]) * 2 + 3 else { throw Failure("Malformed feature response.") }
            let ids = stride(from: 3, to: functions.count, by: 2).map { functions[$0] }
            guard ids.contains(0x6b), ids.contains(0x50), ids.contains(0x20) else { throw Failure("This headset does not advertise the expected WH-CH720N controls.") }
            _ = try await status(refresh: true)
        } catch { link.close(); throw error }
    }
    private func receive(_ payload: [UInt8]) {
        guard payload.count >= 2 else { return }
        switch (payload[0], payload[1]) {
        case (0x67, 0x17), (0x69, 0x17):
            guard SoundSetting(payload: payload) != nil, payload[2] == 1 else { return }
            var state = payload; state[0] = 0x67; cachedAnc = state
        case (0x57, 0), (0x59, 0):
            guard payload.count >= 4, payload.count == Int(payload[3]) + 4 else { return }
            var state = payload; state[0] = 0x57; cachedEq = state
        case (0x23, 0), (0x25, 0):
            guard payload.count == 4 else { return }
            battery = payload[2] <= 100 ? Int(payload[2]) : nil
        default: return
        }
        if let snapshot { onChange?(snapshot) }
    }
    func status(refresh: Bool = false) async throws -> HeadphoneStatus {
        if refresh || snapshot == nil {
            _ = try await ancState(refresh: true)
            _ = try await link.request([0x22, 0], response: 0x23)
            _ = try await eqState(refresh: true)
        }
        guard let snapshot else { throw Failure("Headset status is incomplete.") }
        return snapshot
    }
    func ancState(refresh: Bool = false) async throws -> [UInt8] {
        if !refresh, let cachedAnc { return cachedAnc }
        let state = try await link.request([0x66, 0x17], response: 0x67)
        guard SoundSetting(payload: state) != nil else { throw Failure("Unexpected sound response: \(hex(state))") }
        // Return the actual reply; transitional notifications do not replace confirmed cache.
        return state
    }
    func eqState(refresh: Bool = false) async throws -> [UInt8] {
        if !refresh, let cachedEq { return cachedEq }
        let state = try await link.request([0x56, 0], response: 0x57)
        guard state.count >= 4, state.count == Int(state[3]) + 4 else { throw Failure("Unexpected EQ response.") }
        return state
    }
    func setAnc(_ requested: [UInt8]) async throws {
        guard SoundSetting(payload: requested) != nil else { throw Failure("Invalid sound setting.") }
        let current = try await ancState()
        // The CH720N accepts level/voice updates while ASM is active.
        if (requested[3] == 0 || requested[4] == 0), current[5...] != requested[5...] {
            var ambient = requested; ambient[3] = 1; ambient[4] = 1
            try await applyAnc(ambient)
        }
        try await applyAnc(requested)
    }
    private func applyAnc(_ requested: [UInt8]) async throws {
        if let current = cachedAnc, current[3...] == requested[3...] { return }
        var payload = requested; payload[0] = 0x68; payload[2] = 1
        try await link.send(payload)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            // Consume spontaneous notifications before requesting fallback readback.
            try await Task.sleep(nanoseconds: 80_000_000)
            if let current = cachedAnc, current[3...] == payload[3...] { return }
            let actual = try await ancState(refresh: true)
            if actual[2] == 1, actual[3...] == payload[3...] { return }
        }
        throw Failure("Headset did not apply the sound setting. Try reconnecting.")
    }
    func setMode(_ mode: String, level: Int? = nil, voice: Bool? = nil) async throws {
        let current = try await ancState()
        guard let setting = SoundSetting(payload: current)?.setting(mode: mode, level: level, voice: voice) else {
            throw Failure("Use anc, ambient, or off, with ambient level 1–20.")
        }
        try await setAnc(setting)
    }
    func setEq(_ name: String) async throws {
        guard let preset = presets.first(where: { $0.0 == name }) else { throw Failure("Unknown EQ preset: \(name)") }
        if cachedEq?[2] == preset.1 { return }
        try await link.send([0x58, 0, preset.1, 0])
        try await waitForEq { $0[2] == preset.1 }
    }
    private func waitForEq(_ matches: ([UInt8]) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 80_000_000)
            if let cachedEq, matches(cachedEq) { return }
            if matches(try await eqState(refresh: true)) { return }
        }
        throw Failure("Headset did not apply the EQ setting.")
    }
    func restoreEq(_ state: [UInt8]) async throws {
        var payload = state; payload[0] = 0x58
        try await link.send(payload)
        try await waitForEq { $0 == state }
    }
    private func restore(_ original: HeadphoneStatus) async throws {
        var errors: [String] = []
        do { try await setAnc(original.anc) } catch { errors.append("Sound: \(error)") }
        do { try await restoreEq(original.eq) } catch { errors.append("EQ: \(error)") }
        if !errors.isEmpty { throw Failure(errors.joined(separator: "; ")) }
    }
    func verify() async throws {
        let original = try await status(refresh: true)
        print("Saved original settings: \(original.description)")
        do {
            for mode in ["off", "ambient", "anc"] {
                let start = Date()
                try await setMode(mode, level: mode == "ambient" ? 10 : nil)
                print("Verified \(mode) in \(Int(Date().timeIntervalSince(start) * 1000)) ms: \(hex(try await ancState()))")
            }
            try await setMode("ambient", level: 10, voice: true)
            print("Verified ambient voice focus")
            try await setEq("off")
            print("Verified EQ off")
        } catch {
            let testError = error
            do { try await restore(original) }
            catch { throw Failure("Test failed: \(testError). RESTORE FAILED: \(error). Restore settings in Sound Connect.") }
            throw testError
        }
        try await restore(original)
        let restored = try await status(refresh: true)
        guard restored.anc == original.anc, restored.eq == original.eq else { throw Failure("Restored settings differ from the original snapshot.") }
        print("Verified original sound and EQ settings restored.\n\(restored.description)")
    }
    func close() { link.close() }
}
