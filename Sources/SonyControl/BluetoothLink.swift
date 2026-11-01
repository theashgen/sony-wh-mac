import Foundation
import IOBluetooth
import SonyProtocol

/// Owned by the main actor. Delegate callbacks never block the UI or run nested loops.
@MainActor
final class Link: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private var channel: IOBluetoothRFCOMMChannel?
    private var sequence: UInt8 = 0
    private var decoder = FrameDecoder()
    private var lastReceivedSequence: UInt8?
    private var opening: CheckedContinuation<Void, Error>?
    private var transaction: Transaction?
    private(set) var closed = false
    var onPayload: (([UInt8]) -> Void)?
    var onDisconnect: (() -> Void)?
    let verbose: Bool
    private static var coordinatorStarted = false
    private static var lastClosedAt = Date.distantPast

    private struct Transaction {
        let nextSequence: UInt8
        let response: UInt8?
        let inquiry: UInt8?
        let continuation: CheckedContinuation<[UInt8], Error>
        var acknowledged = false
        var reply: [UInt8]?
    }
    init(verbose: Bool) { self.verbose = verbose }

    func open(_ device: IOBluetoothDevice) async throws {
        // IOBluetooth's coordinator starts lazily after pairedDevices(). Only cold startup waits.
        let cooldown = max(Self.coordinatorStarted ? 0 : 1, 1 - Date().timeIntervalSince(Self.lastClosedAt))
        if cooldown > 0 { try await Task.sleep(nanoseconds: UInt64(cooldown * 1_000_000_000)) }
        Self.coordinatorStarted = true
        try Task.checkCancellation()
        let uuid = UUID(uuidString: "956C7B26-D49A-4BA8-B03F-B17D393CB6E2")!.uuid
        let sdp = withUnsafeBytes(of: uuid) { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
        guard let record = device.getServiceRecord(for: sdp) else { throw Failure("Sony control service not found. Connect WH-CH720N in Bluetooth settings.") }
        var id: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&id) == kIOReturnSuccess else { throw Failure("Cannot resolve Sony control service.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            opening = continuation
            let result = device.openRFCOMMChannelAsync(&channel, withChannelID: id, delegate: self)
            if result != kIOReturnSuccess {
                opening = nil
                continuation.resume(throwing: Failure("Cannot open Bluetooth control channel (\(result)). Close Sound Connect on the phone and reconnect."))
            }
        } timeout: { [weak self] in
            guard let self, let continuation = self.opening else { return }
            self.opening = nil
            continuation.resume(throwing: Failure("Bluetooth connection timed out."))
            self.close()
        }
        if verbose { print("Connected to \(device.name ?? "headphones") on RFCOMM \(id)") }
    }

    private func write(_ bytes: [UInt8]) throws {
        guard let channel, !closed else { throw Failure("Bluetooth disconnected.") }
        var bytes = bytes
        let result = bytes.withUnsafeMutableBytes { channel.writeSync($0.baseAddress, length: UInt16($0.count)) }
        guard result == kIOReturnSuccess else { throw Failure("Bluetooth write failed (\(result)).") }
        if verbose { print("TX \(hex(bytes))") }
    }
    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length count: Int) {
        guard let pointer, count > 0 else { return }
        let bytes = Array(UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: count))
        Task { @MainActor [weak self] in self?.consume(bytes) }
    }
    private func consume(_ bytes: [UInt8]) {
        guard !closed else { return }
        if verbose { print("RX \(hex(bytes))") }
        for packet in decoder.feed(bytes) {
            if packet.type == 1, packet.payload.isEmpty {
                if transaction?.nextSequence == packet.sequence {
                    sequence = packet.sequence
                    transaction?.acknowledged = true
                    finishTransactionIfReady()
                }
            } else if packet.type == 0x0c {
                do { try write(frame(type: 1, sequence: 1 - packet.sequence, payload: [])) }
                catch { fail(error); continue }
                guard lastReceivedSequence != packet.sequence else { continue }
                lastReceivedSequence = packet.sequence
                onPayload?(packet.payload)
                if let active = transaction, let response = active.response,
                   packet.payload.first == response, packet.payload.count >= 2,
                   packet.payload[1] == active.inquiry {
                    transaction?.reply = packet.payload
                    finishTransactionIfReady()
                }
            }
        }
    }
    nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        Task { @MainActor [weak self] in self?.didOpen(error) }
    }
    private func didOpen(_ error: IOReturn) {
        guard let continuation = opening else { return }
        opening = nil
        if error == kIOReturnSuccess { continuation.resume() }
        else { continuation.resume(throwing: Failure("Bluetooth connection failed (\(error)).")) }
    }
    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        Task { @MainActor [weak self] in
            guard let self, !self.closed else { return }
            self.fail(Failure("Headphones disconnected."))
        }
    }
    private func finishTransactionIfReady() {
        guard let active = transaction, active.acknowledged,
              active.response == nil || active.reply != nil else { return }
        transaction = nil
        active.continuation.resume(returning: active.reply ?? [])
    }
    private func fail(_ error: Error) {
        if let opening { self.opening = nil; opening.resume(throwing: error) }
        if let transaction { self.transaction = nil; transaction.continuation.resume(throwing: error) }
        close()
        onDisconnect?()
    }
    func send(_ payload: [UInt8]) async throws { _ = try await exchange(payload, response: nil) }
    func request(_ payload: [UInt8], response: UInt8) async throws -> [UInt8] { try await exchange(payload, response: response) }
    private func exchange(_ payload: [UInt8], response: UInt8?) async throws -> [UInt8] {
        try Task.checkCancellation()
        guard transaction == nil else { throw Failure("Another Bluetooth request is still in progress.") }
        guard !closed else { throw Failure("Bluetooth disconnected.") }
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            transaction = Transaction(nextSequence: 1 - sequence, response: response, inquiry: payload.count > 1 ? payload[1] : nil, continuation: continuation)
            transactionID = id
            do { try write(frame(sequence: sequence, payload: payload)) }
            catch { fail(error) }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self, self.transactionID == id, self.transaction != nil else { return }
                // An ACK timeout leaves sequence ownership uncertain: reconnect before more commands.
                self.fail(Failure("No headset response to \(hex(payload)). Reconnecting…"))
            }
        }
    }
    private var transactionID: UUID?
    func close() {
        if let opening { self.opening = nil; opening.resume(throwing: CancellationError()) }
        if let transaction { self.transaction = nil; transaction.continuation.resume(throwing: CancellationError()) }
        transactionID = nil
        closed = true
        if channel != nil { Self.lastClosedAt = Date() }
        channel?.setDelegate(nil)
        _ = channel?.close()
        channel = nil
    }
}

// A bounded open without polling; its timeout task becomes a no-op after the delegate fires.
@MainActor
private func withCheckedThrowingContinuation(
    _ body: (CheckedContinuation<Void, Error>) -> Void,
    timeout: @escaping @MainActor () -> Void
) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        body(continuation)
        Task { try? await Task.sleep(nanoseconds: 10_000_000_000); timeout() }
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}
