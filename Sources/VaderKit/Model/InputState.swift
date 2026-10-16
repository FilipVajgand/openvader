import Foundation

/// One live input report (`5A A5 EF`), streamed at about 500 Hz while the
/// raw stream is enabled. This is the physical state, before any on-board
/// remapping.
///
///     [3..10]  LX LY RX RY, int16 LE, centre 0, +Y up
///     [11]     Up Right Down Left A B View X
///     [12]     Y Menu LB RB LT RT L3 R3
///     [13]     C Z M1 M2 M3 M4 LM RM
///     [14]     Fn(0x01) Turbo(0x02) Home(0x08)
///     [15..16] LT RT, 0...255
///     [17..22] gyro x y z, int16 LE, 2000 dps full scale
///     [23..28] accel x y z, int16 LE, 4096 = 1 g
public struct InputState: Sendable, Equatable {
    public var buttons: Set<ControllerKey> = []
    public var leftStick = SIMD2<Double>(0, 0)
    public var rightStick = SIMD2<Double>(0, 0)
    public var leftTrigger = 0.0
    public var rightTrigger = 0.0
    /// Degrees per second.
    public var gyro = SIMD3<Double>(0, 0, 0)
    /// g.
    public var accel = SIMD3<Double>(0, 0, 0)
    public var unknownBits: [Int: UInt8] = [:]

    public init() {}

    static let bitMap: [(Int, UInt8, ControllerKey)] = [
        (11, 0x01, .up), (11, 0x02, .right), (11, 0x04, .down), (11, 0x08, .left),
        (11, 0x10, .a), (11, 0x20, .b), (11, 0x40, .select), (11, 0x80, .x),
        (12, 0x01, .y), (12, 0x02, .start), (12, 0x04, .lb), (12, 0x08, .rb),
        (12, 0x10, .lt), (12, 0x20, .rt), (12, 0x40, .l3), (12, 0x80, .r3),
        (13, 0x01, .c), (13, 0x02, .z), (13, 0x04, .m1), (13, 0x08, .m2),
        (13, 0x10, .m3), (13, 0x20, .m4), (13, 0x40, .lm), (13, 0x80, .rm),
        (14, 0x01, .fn), (14, 0x02, .turbo), (14, 0x08, .home),
    ]

    static let knownMasks: [Int: UInt8] = Dictionary(bitMap.map { ($0.0, $0.1) }, uniquingKeysWith: |)

    public init?(report r: [UInt8]) {
        guard r.count >= 29, r[0] == 0x5A, r[1] == 0xA5, r[2] == Command.inputReport.rawValue else { return nil }
        func s16(_ o: Int) -> Double { Double(Int16(bitPattern: UInt16(r[o]) | UInt16(r[o + 1]) << 8)) }
        leftStick = SIMD2(s16(3) / 32767, s16(5) / 32767)
        rightStick = SIMD2(s16(7) / 32767, s16(9) / 32767)
        leftTrigger = Double(r[15]) / 255
        rightTrigger = Double(r[16]) / 255
        let dps = 2000.0 / 32768.0
        gyro = SIMD3(s16(17) * dps, s16(19) * dps, s16(21) * dps)
        accel = SIMD3(s16(23) / 4096, s16(25) / 4096, s16(27) / 4096)
        for (offset, mask, key) in Self.bitMap where r[offset] & mask != 0 { buttons.insert(key) }
        for (offset, mask) in Self.knownMasks where r[offset] & ~mask != 0 { unknownBits[offset] = r[offset] & ~mask }
    }
}
