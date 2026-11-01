// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SonyControl", platforms: [.macOS(.v13)], products: [
    .executable(name: "sony-control", targets: ["SonyControl"])
], targets: [.target(name: "SonyProtocol"), .target(name: "WidgetShared"), .executableTarget(name: "ProtocolChecks", dependencies: ["SonyProtocol"], path: "Tests/SonyProtocolTests"), .executableTarget(name: "SonyControl", dependencies: ["SonyProtocol", "WidgetShared"], linkerSettings: [.linkedFramework("IOBluetooth")])])
