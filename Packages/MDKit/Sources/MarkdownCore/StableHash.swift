/// Deterministic 64-bit FNV-1a. Swift's `Hasher` is randomly seeded per
/// process, which would make block ids unstable across launches and tests.
struct StableHash {
    private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

    mutating func combine(_ string: some StringProtocol) {
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01b3
        }
    }

    mutating func combine(_ int: Int) {
        var v = UInt64(bitPattern: Int64(int))
        for _ in 0..<8 {
            value ^= v & 0xff
            value = value &* 0x0000_0100_0000_01b3
            v >>= 8
        }
    }
}
