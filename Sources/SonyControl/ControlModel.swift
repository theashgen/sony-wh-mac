import Foundation
import Combine
import WidgetShared
import WidgetKit

@MainActor
final class ControlModel: ObservableObject {
    @Published private(set) var status: HeadphoneStatus?
    @Published private(set) var connected = false
    @Published private(set) var working = false
    @Published private(set) var message = "Connecting to headphones…"
    @Published private(set) var error: String?
    @Published private(set) var pendingMode: String?
    @Published private(set) var lastDuration: Int?
    @Published private(set) var pendingVoice: Bool?
    @Published private(set) var pendingPreset: String?
    private var pendingLevel: Int?
    @Published var sliderLevel = 20.0
    var sliderEditing = false
    private var headphones: Headphones?
    private var wantsConnection = true
    private var reconnect: Task<Void, Never>?
    private var backoff: UInt64 = 2
    private var queue: [Intent] = []
    private var periodic: Timer?
    private var worker: Task<Void, Never>?
    private let widgetServer = WidgetStatusServer()
    private var widgetRefresh: Task<Void, Never>?
    private var lastWidgetState: WidgetSnapshot?
    var onStatus: ((HeadphoneStatus?) -> Void)?

    enum Intent {
        case mode(String), level(Int), voice(Bool), eq(String), refresh
        var key: Int {
            switch self { case .mode: return 0; case .level: return 1; case .voice: return 2; case .eq: return 3; case .refresh: return 4 }
        }
    }
    func start() {
        widgetServer.start()
        enqueue(.refresh)
        periodic = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.connected, !self.working, !self.sliderEditing else { return }
                self.enqueue(.refresh)
            }
        }
    }
    func enqueue(_ intent: Intent) {
        wantsConnection = true
        reconnect?.cancel(); reconnect = nil
        error = nil
        // Coalesce unsent changes of the same control; never drop a click because we're busy.
        queue.removeAll { $0.key == intent.key || (intent.key != 4 && $0.key == 4) }
        queue.append(intent)
        switch intent {
        case .mode(let mode): pendingMode = mode
        case .level(let value): pendingMode = "ambient"; pendingLevel = value
        case .voice(let value): pendingMode = "ambient"; pendingVoice = value
        case .eq(let name): pendingPreset = name
        default: break
        }
        drain()
    }
    private func publishWidget() {
        let snapshot = WidgetSnapshot(battery: status?.battery, mode: status?.mode ?? "Disconnected", connected: connected)
        widgetServer.update(snapshot)
        guard lastWidgetState?.battery != snapshot.battery || lastWidgetState?.mode != snapshot.mode || lastWidgetState?.connected != snapshot.connected else { return }
        lastWidgetState = snapshot
        widgetRefresh?.cancel()
        widgetRefresh = Task {
            do { try await Task.sleep(nanoseconds: 750_000_000) } catch { return }
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
        }
    }
    private func update(_ status: HeadphoneStatus) {
        self.status = status
        if !sliderEditing && pendingLevel == nil { sliderLevel = Double(status.level) }
        onStatus?(status)
        publishWidget()
    }
    private func connectIfNeeded() async throws -> Headphones {
        if let headphones, headphones.isConnected { return headphones }
        headphones?.close(); headphones = nil
        connected = false; message = "Connecting to headphones…"
        let client = try await Headphones()
        guard wantsConnection, !Task.isCancelled else { client.close(); throw CancellationError() }
        headphones = client
        client.onChange = { [weak self] in self?.update($0) }
        client.onDisconnect = { [weak self, weak client] in
            guard let self, self.headphones === client else { return }
            self.connected = false
            self.message = "Disconnected · retrying…"
            self.publishWidget()
            self.scheduleReconnect()
        }
        connected = true; backoff = 2; lastDuration = nil
        if let snapshot = client.snapshot { update(snapshot) }
        return client
    }
    private func drain() {
        guard !working else { return }
        working = true
        worker = Task {
            defer {
                working = false; pendingMode = nil; pendingVoice = nil; pendingPreset = nil; pendingLevel = nil
                if let status, !sliderEditing { sliderLevel = Double(status.level) }
                if connected { message = "Connected" }
                if !queue.isEmpty && wantsConnection { drain() }
            }
            while !queue.isEmpty && wantsConnection {
                let intent = queue.removeFirst()
                let started = Date()
                do {
                    let wasConnected = connected
                    let client = try await connectIfNeeded()
                    message = intent.key == 4 ? "Refreshing…" : "Applying setting…"
                    switch intent {
                    case .mode(let mode): try await client.setMode(mode)
                    case .level(let value): try await client.setMode("ambient", level: value)
                    case .voice(let enabled): try await client.setMode("ambient", voice: enabled)
                    case .eq(let name): try await client.setEq(name)
                    case .refresh:
                        if wasConnected { _ = try await client.status(refresh: true) }
                    }
                    if let snapshot = client.snapshot { update(snapshot) }
                    if intent.key != 4 { lastDuration = Int(Date().timeIntervalSince(started) * 1000) }
                } catch {
                    if Task.isCancelled { break }
                    self.error = String(describing: error)
                    message = connected ? "Setting wasn't applied" : "Couldn't connect"
                    queue.removeAll()
                    if headphones?.isConnected != true {
                        connected = false; headphones?.close(); headphones = nil
                        scheduleReconnect()
                    }
                }
            }
        }
    }
    private func scheduleReconnect() {
        guard wantsConnection, reconnect == nil else { return }
        let seconds = backoff
        backoff = min(backoff * 2, 30)
        reconnect = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            guard let self, self.wantsConnection else { return }
            self.reconnect = nil
            self.enqueue(.refresh)
        }
    }
    func disconnect() {
        wantsConnection = false
        worker?.cancel(); worker = nil
        reconnect?.cancel(); reconnect = nil
        queue.removeAll(); pendingMode = nil; pendingVoice = nil; pendingPreset = nil; pendingLevel = nil
        headphones?.close(); headphones = nil
        connected = false; message = "Controls disconnected · audio stays connected"
        error = nil
        publishWidget()
    }
    func stop() { periodic?.invalidate(); periodic = nil; disconnect(); widgetRefresh?.cancel(); widgetRefresh = nil; widgetServer.stop(); WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind) }
}

extension ControlModel {
    /// Exercises the same queued actions used by the widget, then restores the user's state.
    func verifyWidgetQueue() async throws {
        try await waitUntilIdle()
        guard let original = status, let client = headphones, connected else { throw Failure("Widget could not connect for verification.") }
        do {
            enqueue(.mode("off"))
            try await Task.sleep(nanoseconds: 30_000_000)
            enqueue(.mode("anc"))
            enqueue(.mode("ambient"))
            try await waitUntilIdle()
            guard status?.mode == "Ambient", error == nil else { throw Failure("Quick mode clicks did not settle to Ambient.") }
            enqueue(.level(7))
            try await Task.sleep(nanoseconds: 30_000_000)
            enqueue(.level(12))
            enqueue(.voice(true))
            enqueue(.voice(false))
            try await waitUntilIdle()
            guard status?.level == 12, status?.voice == false, status?.mode == "Ambient", error == nil else { throw Failure("Queued ambient changes did not settle correctly.") }
            guard status?.battery != nil || original.battery == nil else { throw Failure("Battery was erased during control changes.") }
            print("Widget queue verified: rapid mode changes, ambient levels, voice toggles, retained battery")
        } catch {
            let failure = error
            try await client.setAnc(original.anc)
            try await client.restoreEq(original.eq)
            throw failure
        }
        try await client.setAnc(original.anc)
        try await client.restoreEq(original.eq)
        update(try await client.status(refresh: true))
        guard status?.anc == original.anc, status?.eq == original.eq else { throw Failure("Widget verification did not restore original settings.") }
        print("Widget original sound and EQ restored: \(status!.description)")
        // Deliberate release/reconnect must preserve the displayed battery and allow fresh controls.
        disconnect()
        guard status?.battery == original.battery else { throw Failure("Disconnect erased the retained battery.") }
        enqueue(.refresh)
        try await waitUntilIdle()
        guard connected, error == nil else { throw Failure("Widget reconnect check failed.") }
        print("Widget disconnect/reconnect verified")
    }
    private func waitUntilIdle() async throws {
        let deadline = Date().addingTimeInterval(20)
        while working && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        guard !working else { throw Failure("Widget action queue did not finish.") }
    }
}
