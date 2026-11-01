import Foundation
import IOBluetooth
let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
for device in devices where device.name?.contains("WH-CH720N") == true {
    print("Device: \(device.name ?? "?") connected=\(device.isConnected())")
    for record in device.services as? [IOBluetoothSDPServiceRecord] ?? [] {
        var channel: BluetoothRFCOMMChannelID = 0
        let result = record.getRFCOMMChannelID(&channel)
        print("Service: \(record.getServiceName() ?? "?") channel=\(channel) result=\(result)")
    }
    for uuid in ["96CC203E-5068-46AD-B32D-E316F5E069BA", "956C7B26-D49A-4BA8-B03F-B17D393CB6E2"] {
        let data = UUID(uuidString: uuid)!.uuid
        let sdp = withUnsafeBytes(of: data) { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
        if let record = device.getServiceRecord(for: sdp) {
            var channel: BluetoothRFCOMMChannelID = 0
            print("Sony \(uuid): \(record.getRFCOMMChannelID(&channel)) channel=\(channel)")
        } else { print("Sony \(uuid): absent") }
    }
}
