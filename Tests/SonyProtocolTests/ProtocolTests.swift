import Foundation
import SonyProtocol

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    if actual != expected { fatalError("Expected \(expected), received \(actual)", file: file, line: line) }
}
func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    if !value { fatalError("Assertion failed", file: file, line: line) }
}
@main
struct ProtocolChecks {
    static func main() {
        let checks = ProtocolChecks()
        checks.testCapturedProtocolQuery()
        checks.testCapturedHeadsetResponseAcrossChunks()
        checks.testSonyReservedByteEscapes()
        checks.testCorruptionAndResynchronization()
        checks.testInvalidLengthSequenceAndDanglingEscape()
        checks.testAmbientTransitionsPreserveVoiceAndLevel()
        checks.testOffUsesAmbientSelector()
        checks.testInvalidAmbientLevelsRejected()
        print("8 protocol checks passed")
    }
    func testCapturedProtocolQuery() {
        expectEqual(frame(sequence: 0, payload: [0, 0]), [0x3e, 0x0c, 0, 0, 0, 0, 2, 0, 0, 0x0e, 0x3c])
        expectEqual(frame(type: 1, sequence: 1, payload: []), [0x3e, 1, 1, 0, 0, 0, 0, 2, 0x3c])
    }
    func testCapturedHeadsetResponseAcrossChunks() {
        var decoder = FrameDecoder()
        let captured: [UInt8] = [0x3e, 0x0c, 0, 0, 0, 0, 8, 1, 0, 3, 0, 0x10, 2, 0, 0, 0x2a, 0x3c]
        expectTrue(decoder.feed(Array(captured.prefix(9))).isEmpty)
        let packets = decoder.feed(Array(captured.dropFirst(9)))
        expectEqual(packets.count, 1)
        expectEqual(packets.first?.payload, [1, 0, 3, 0, 0x10, 2, 0, 0])
    }
    func testSonyReservedByteEscapes() {
        let encoded = frame(sequence: 0, payload: [0x3c, 0x3d, 0x3e])
        expectEqual(Array(encoded[7..<13]), [0x3d, 0x2c, 0x3d, 0x2d, 0x3d, 0x2e])
        var decoder = FrameDecoder()
        expectEqual(decoder.feed(encoded).first?.payload, [0x3c, 0x3d, 0x3e])
    }
    func testCorruptionAndResynchronization() {
        var decoder = FrameDecoder()
        var corrupt = frame(sequence: 0, payload: [0, 0]); corrupt[9] ^= 1
        let valid = frame(type: 1, sequence: 1, payload: [])
        expectEqual(decoder.feed([0x55, 0x66] + corrupt + valid).map(\.type), [1])
    }
    func testInvalidLengthSequenceAndDanglingEscape() {
        var decoder = FrameDecoder()
        // Checksums are valid, but lengths or sequence values are not.
        expectTrue(decoder.feed([0x3e, 1, 0, 0, 0, 0, 2, 3, 0x3c]).isEmpty)
        expectTrue(decoder.feed([0x3e, 1, 2, 0, 0, 0, 0, 3, 0x3c]).isEmpty)
        expectTrue(decoder.feed([0x3e, 1, 0x3d, 0x3c]).isEmpty)
    }

    func testAmbientTransitionsPreserveVoiceAndLevel() {
        let state: [UInt8] = [0x67, 0x17, 1, 1, 0, 1, 13]
        let sound = SoundSetting(payload: state)!
        expectEqual(sound.setting(mode: "ambient"), [0x68, 0x17, 1, 1, 1, 1, 13])
        expectEqual(sound.setting(mode: "ambient", level: 8), [0x68, 0x17, 1, 1, 1, 1, 8])
        expectEqual(sound.setting(mode: "ambient", voice: false), [0x68, 0x17, 1, 1, 1, 0, 13])
        expectEqual(sound.setting(mode: "anc"), [0x68, 0x17, 1, 1, 0, 1, 13])
    }
    func testOffUsesAmbientSelector() {
        let state = SoundSetting(payload: [0x67, 0x17, 1, 1, 0, 0, 20])!
        expectEqual(state.setting(mode: "off"), [0x68, 0x17, 1, 0, 1, 0, 20])
    }
    func testInvalidAmbientLevelsRejected() {
        let state = SoundSetting(payload: [0x67, 0x17, 1, 1, 0, 0, 20])!
        expectTrue(state.setting(mode: "ambient", level: 0) == nil)
        expectTrue(state.setting(mode: "ambient", level: 21) == nil)
        expectTrue(state.setting(mode: "boost") == nil)
        expectTrue(SoundSetting(payload: [0x67, 0x17, 1, 1, 0, 0, 0]) == nil)
    }
}
