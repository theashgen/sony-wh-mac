import Foundation
import Network
import WidgetShared

/// A widget cannot share a protected app-group container under ad hoc signing.
/// Expose only a battery/mode snapshot on loopback; never accept commands here.
@MainActor
final class WidgetStatusServer {
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var snapshot = WidgetSnapshot(battery: nil, mode: "Disconnected", connected: false)
    func start() {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 52721)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state { NSLog("Widget status listener: %@", String(describing: error)) }
            }
            listener.start(queue: .main)
        } catch { NSLog("Widget status listener: %@", String(describing: error)) }
    }
    func update(_ snapshot: WidgetSnapshot) { self.snapshot = snapshot }
    func stop() {
        listener?.cancel(); listener = nil
        for connection in clients.values { connection.cancel() }
        clients.removeAll()
    }
    private func accept(_ connection: NWConnection) {
        guard clients.count < 8 else { connection.cancel(); return }
        let id = UUID()
        clients[id] = connection
        connection.start(queue: .main)
        receive(connection, id: id, buffer: Data())
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.clients.removeValue(forKey: id)?.cancel()
        }
    }
    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.clients[id] != nil else { return }
                var request = buffer
                request.append(data ?? Data())
                guard request.count <= 4096, error == nil else { self.clients.removeValue(forKey: id)?.cancel(); return }
                guard request.range(of: Data("\r\n\r\n".utf8)) != nil else {
                    if complete { self.clients.removeValue(forKey: id)?.cancel() }
                    else { self.receive(connection, id: id, buffer: request) }
                    return
                }
                let valid = String(decoding: request, as: UTF8.self).hasPrefix("GET /v1/status HTTP/1.")
                let body = valid ? ((try? JSONEncoder().encode(self.snapshot)) ?? Data()) : Data()
                let header = "HTTP/1.1 \(valid ? "200 OK" : "404 Not Found")\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n"
                connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { [weak self] _ in
                    Task { @MainActor in self?.clients.removeValue(forKey: id)?.cancel() }
                })
            }
        }
    }
}
