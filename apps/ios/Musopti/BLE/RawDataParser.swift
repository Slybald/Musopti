import Foundation

struct IMUSample {
    let accelX: Float
    let accelY: Float
    let accelZ: Float
    let gyroX: Float
    let gyroY: Float
    let gyroZ: Float
    let timestampMs: UInt32
}

enum RawDataParser {
    private static let sampleSize = 28 // 6 floats + 1 uint32

    static func parse(from data: Data) -> [IMUSample]? {
        guard data.count >= 2 else { return nil }
        guard data.readUInt8(at: 0) == 1 else { return nil }

        guard let countByte = data.readUInt8(at: 1) else { return nil }
        let count = Int(countByte)
        let expectedSize = 2 + count * sampleSize
        guard data.count >= expectedSize else { return nil }

        var samples: [IMUSample] = []
        samples.reserveCapacity(count)

        for i in 0..<count {
            let offset = 2 + i * sampleSize
            guard let accelX = data.readFloat32LE(at: offset),
                  let accelY = data.readFloat32LE(at: offset + 4),
                  let accelZ = data.readFloat32LE(at: offset + 8),
                  let gyroX = data.readFloat32LE(at: offset + 12),
                  let gyroY = data.readFloat32LE(at: offset + 16),
                  let gyroZ = data.readFloat32LE(at: offset + 20),
                  let timestampMs = data.readUInt32LE(at: offset + 24)
            else { return nil }

            samples.append(IMUSample(
                accelX: accelX,
                accelY: accelY,
                accelZ: accelZ,
                gyroX: gyroX,
                gyroY: gyroY,
                gyroZ: gyroZ,
                timestampMs: timestampMs
            ))
        }

        return samples
    }
}
