import Foundation

public struct WidgetSnapshot: Codable {
    public var battery: Int?
    public var mode: String
    public var connected: Bool
    public var updatedAt: Date
    public init(battery: Int?, mode: String, connected: Bool, updatedAt: Date = Date()) {
        self.battery = battery; self.mode = mode; self.connected = connected; self.updatedAt = updatedAt
    }
    public static let kind = "SonyHeadphoneWidget"
    // Read-only, loopback-only status endpoint; all commands go through the app's URL handler.
    public static let statusURL = URL(string: "http://127.0.0.1:52721/v1/status")!
    public static func read() async -> WidgetSnapshot? {
        var request = URLRequest(url: statusURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        request.httpMethod = "GET"
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
