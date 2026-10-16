import Foundation

/// Wire framing for the Vader 5 Pro's vendor HID interface (usage page 0xFFA0).
///
/// macOS sends the report without a report-ID byte (the interface declares
/// none), so a request on the wire is exactly:
///
///     [0] 0x5A  [1] 0xA5  [2] command  [3] length = 2 + payload.count
///     [4...] payload       [2 + length] checksum = sum(bytes[2 ..< 2 + length]) & 0xFF
///
/// padded with zeros to 32 bytes. Replies use the same magic and carry
/// `command, total packets, packet index` at bytes 2...4.
public enum Frame {
    public static let size = 32
    public static let magic: [UInt8] = [0x5A, 0xA5]

    /// Builds a padded 32-byte request frame.
    public static func request(_ command: UInt8, _ payload: [UInt8] = []) -> [UInt8] {
        precondition(payload.count + 5 <= size, "payload of \(payload.count) bytes overflows a frame")
        var frame = [UInt8](repeating: 0, count: size)
        frame[0] = magic[0]
        frame[1] = magic[1]
        frame[2] = command
        frame[3] = UInt8(2 + payload.count)
        for (i, byte) in payload.enumerated() { frame[4 + i] = byte }
        let end = 2 + Int(frame[3])
        frame[end] = checksum(frame[2..<end])
        return frame
    }

    public static func checksum<C: Collection>(_ bytes: C) -> UInt8 where C.Element == UInt8 {
        UInt8(truncatingIfNeeded: bytes.reduce(0) { $0 &+ Int($1) })
    }

    public static func isFrame(_ data: [UInt8]) -> Bool {
        data.count >= 5 && data[0] == magic[0] && data[1] == magic[1]
    }
}

/// Command identifiers of the NewXInput protocol family.
public enum Command: UInt8, CaseIterable, Sendable {
    case heartbeat = 0x01
    case readNickname = 0x02
    case hardwareStatus = 0x03
    case readUID = 0x04
    case dataReportStatus = 0x10
    case setDataReport = 0x11
    case rumble = 0x12
    case featureToggle = 0x13
    case reportRate = 0x14
    case joystickPrecision = 0x15
    case joystickSensitivity = 0x16
    case sleepTime = 0x17
    case writeNickname = 0x18
    case profileVersions = 0xA1
    case activateProfile = 0xA2
    case readMapping = 0xA3
    case writeMappingStart = 0xA4
    case writeMappingPack = 0xA5
    case saveConfig = 0xA6
    case readLighting = 0xA7
    case writeLightingStart = 0xA8
    case writeLightingPack = 0xA9
    case saveSwitchConfig = 0xAB
    case readMacros = 0xAC
    case writeMacrosStart = 0xAD
    case writeMacrosPack = 0xAE
    case inputReport = 0xEF

    /// Commands that exist in the vendor SDK and must never be sent.
    ///
    /// - `0x1F` reboots into the firmware bootloader.
    /// - `0xAF` claims to reset one profile but resets all four.
    /// - `0xFD` wipes the whole device.
    /// - `0xFE` rewrites the device identity.
    public static let forbidden: Set<UInt8> = [0x1F, 0xAF, 0xFD, 0xFE]
}

/// A parsed reply frame.
public struct Reply: Sendable, CustomStringConvertible {
    public let raw: [UInt8]

    public init?(_ raw: [UInt8]) {
        guard Frame.isFrame(raw) else { return nil }
        self.raw = raw.count >= Frame.size ? raw : raw + [UInt8](repeating: 0, count: Frame.size - raw.count)
    }

    public var command: UInt8 { raw[2] }
    public var total: Int { Int(raw[3]) }
    public var index: Int { Int(raw[4]) }

    /// Bytes 2...30 summed into byte 31.
    public var checksumOK: Bool { raw[31] == Frame.checksum(raw[2..<31]) }

    public subscript(_ i: Int) -> UInt8 { i < raw.count ? raw[i] : 0 }

    public func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }

    public var description: String {
        String(format: "<Reply 0x%02X %d/%d %@>", command, index, total, raw.hexString)
    }
}

extension Collection where Element == UInt8 {
    public var hexString: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}
