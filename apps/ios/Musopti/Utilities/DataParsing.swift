import Foundation

extension Data {
    func readUInt8(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < count else { return nil }
        return self[offset]
    }

    func readUInt16LE(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return UInt16(self[offset])
            | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func readFloat32LE(at offset: Int) -> Float? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        guard let bits = readUInt32LE(at: offset) else { return nil }
        return Float(bitPattern: bits)
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
