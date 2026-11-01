import Foundation

public func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }
public func frame(type: UInt8 = 0x0c, sequence: UInt8, payload: [UInt8]) -> [UInt8] {
    let size = UInt32(payload.count)
    var body = [type, sequence, UInt8(truncatingIfNeeded: size >> 24), UInt8(truncatingIfNeeded: size >> 16), UInt8(truncatingIfNeeded: size >> 8), UInt8(truncatingIfNeeded: size)] + payload
    body.append(body.reduce(UInt8(0), &+))
    return [0x3e] + body.flatMap { (0x3c...0x3e).contains($0) ? [0x3d, $0 & 0xef] : [$0] } + [0x3c]
}

public struct Packet: Equatable {
    public let type: UInt8
    public let sequence: UInt8
    public let payload: [UInt8]
}

/// Incrementally decodes a stream; malformed frames are discarded at delimiters.
public struct FrameDecoder {
    private var buffer: [UInt8] = []
    private var active = false
    public init() {}
    public mutating func feed(_ bytes: [UInt8]) -> [Packet] {
        var packets: [Packet] = []
        for byte in bytes {
            if byte == 0x3e { buffer = []; active = true }
            else if byte == 0x3c, active {
                active = false
                if let packet = decode(buffer) { packets.append(packet) }
                buffer = []
            } else if active {
                buffer.append(byte)
                if buffer.count > 65536 { buffer = []; active = false }
            }
        }
        return packets
    }
    private func decode(_ escaped: [UInt8]) -> Packet? {
        var body: [UInt8] = []; var escape = false
        for byte in escaped {
            if escape {
                guard (0x2c...0x2e).contains(byte) else { return nil }
                body.append(byte | 0x10); escape = false
            } else if byte == 0x3d { escape = true }
            else { body.append(byte) }
        }
        guard !escape, body.count >= 7, body[1] <= 1,
              body.dropLast().reduce(UInt8(0), &+) == body.last! else { return nil }
        let length = body[2..<6].reduce(0) { $0 * 256 + Int($1) }
        guard length == body.count - 7 else { return nil }
        return Packet(type: body[0], sequence: body[1], payload: Array(body[6..<(6 + length)]))
    }
}

/// CH720N sound semantics, shared with offline regression checks.
public struct SoundSetting {
    private let payload: [UInt8]
    public init?(payload: [UInt8]) {
        guard payload.count == 7, [0x67, 0x68, 0x69].contains(payload[0]), payload[1] == 0x17,
              payload[2] <= 1, payload[3] <= 1, payload[4] <= 1, payload[5] <= 1,
              (1...20).contains(payload[6]) else { return nil }
        self.payload = payload
    }
    public func setting(mode: String, level: Int? = nil, voice: Bool? = nil) -> [UInt8]? {
        guard ["anc", "ambient", "off"].contains(mode), level == nil || (1...20).contains(level!) else { return nil }
        var state = payload
        state[0] = 0x68; state[2] = 1
        state[3] = mode == "off" ? 0 : 1
        // Off must use the ASM selector on this firmware.
        state[4] = mode == "anc" ? 0 : 1
        if let level { state[6] = UInt8(level) }
        if let voice { state[5] = voice ? 1 : 0 }
        return state
    }
}
