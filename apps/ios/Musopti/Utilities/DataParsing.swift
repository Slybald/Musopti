import Foundation

extension Data {
    func readUInt8(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < count else { return nil }
        return self[offset]
    }

    func readUInt16LE(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return nil }
            return baseAddress.load(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    func readUInt32LE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return nil }
            return baseAddress.load(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    func readFloat32LE(at offset: Int) -> Float? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return nil }
            return baseAddress.load(fromByteOffset: offset, as: Float.self)
        }
    }
}

extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}
