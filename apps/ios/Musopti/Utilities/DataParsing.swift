import Foundation

extension Data {
    func readUInt8(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < count else { return nil }
        return self[offset]
    }

    func readUInt16LE(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        var value: UInt16 = 0
        withUnsafeMutableBytes(of: &value) { destination in
            copyBytes(to: destination, from: offset..<(offset + 2))
        }
        return UInt16(littleEndian: value)
    }

    func readUInt32LE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        var value: UInt32 = 0
        withUnsafeMutableBytes(of: &value) { destination in
            copyBytes(to: destination, from: offset..<(offset + 4))
        }
        return UInt32(littleEndian: value)
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
