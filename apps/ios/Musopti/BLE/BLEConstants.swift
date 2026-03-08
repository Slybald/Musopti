import CoreBluetooth

enum BLEConstants {
    static let deviceName = "Musopti"

    nonisolated(unsafe) static let serviceUUID = CBUUID(string: "4D55534F-5054-4900-0001-000000000000")
    nonisolated(unsafe) static let eventCharUUID = CBUUID(string: "4D55534F-5054-4900-0001-000000000001")
    nonisolated(unsafe) static let configCharUUID = CBUUID(string: "4D55534F-5054-4900-0001-000000000002")
    nonisolated(unsafe) static let rawDataCharUUID = CBUUID(string: "4D55534F-5054-4900-0001-000000000003")
    nonisolated(unsafe) static let statusCharUUID = CBUUID(string: "4D55534F-5054-4900-0001-000000000004")

    static let eventPayloadSize = 12
    static let configPayloadSize = 12
    static let statusPayloadSize = 14
    static let maxRawSamplesPerPacket = 7
    static let rawSampleSize = 28
}
