import Foundation

/// What a factory-fresh Vader 5 Pro (firmware 7.1.5.0) stores, read off a
/// real controller. This is device state, not vendor software. The four
/// profiles differ only in the digit of their name.
public enum FactoryData {
    /// The mapping profile for slot `profile` (0...3).
    public static func mapping(profile: Int) -> MappingProfile {
        var b = [UInt8](repeating: 0xFF, count: MappingProfile.size)
        func put(_ offset: Int, _ bytes: [UInt8]) { b.replaceSubrange(offset..<offset + bytes.count, with: bytes) }
        put(0, [0x02, 0x03, 0x4D, 0x20, 0x04, 0x28, 0xA0, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00])
        for i in 0..<32 { put(13 + 3 * i, [0xFF, 0x00, 0x00]) }
        let stick: [UInt8] = [0x00, 0x05, 0x3F, 0x3F, 0x7F, 0x7F, 0x7F]
        put(109, stick)
        put(116, stick)
        let trigger: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF]
        put(123, trigger)
        put(130, trigger)
        put(137, [0x00, 0x0C, 0x00, 0x04, 0x19, 0x14, 0x00, 0x00])
        put(145, [0x00, 0x00, 0x3C, 0xFF, 0x32, 0x00, 0x50, 0xFF, 0x32])
        let gears: [UInt8] = [0x01, 0x33, 0x72, 0x05, 0x01, 0x32, 0x00, 0xFF, 0x28, 0x78, 0x05, 0x00, 0x32, 0x00]
        put(154, [0x00] + gears + gears)
        put(183, [0x00, 0x00])
        let force: [UInt8] = [0x00, 0x00, 0x0A, 0x0A, 0x64, 0x01, 0xFF, 0x46] + [UInt8](repeating: 0, count: 12)
        put(185, force)
        put(205, force)
        put(230, [UInt8](repeating: 0, count: 6))
        // Name "配置N" (Chinese for "configuration N"), then zero padding.
        put(770, [0x4D, 0x91, 0x6E, 0x7F, UInt8(0x31 + profile), 0x00] + [UInt8](repeating: 0, count: 10))
        let table: [UInt8] = [0x00, 0x2D, 0x3A, 0x47, 0x54, 0x61, 0x6E, 0x7B, 0x89, 0x96, 0x00, 0x00]
        put(790, table)
        put(802, table)
        put(820, [0x03, 0x03, 0x03, 0x03, 0x03])
        put(830, [0x00, 0x3F, 0x3F, 0x7F, 0x7F, 0x7F])
        return MappingProfile(bytes: b)
    }

    /// The factory light-bar animation: 10 LEDs × 10 frames.
    public static var lighting: LightingConfig {
        LightingConfig(bytes: hex(
            "000300000904140a0700ffffffffffffffffffff9f0060b60049d4002bff0000d42a00b649009f60008e7100808000718e"
            + "0071008e8000808e00719f0060b60049d4002bff0000d42a00b649009f60002a00d54900b660009f71008e8000808e0071"
            + "9f0060b60049d4002bff00000049b6002bd40000ff2a00d54900b660009f71008e8000808e00719f006000808000718e00"
            + "609f0049b6002bd40000ff2a00d54900b660009f71008e00b649009f60008e7100808000718e00609f0049b6002bd40000"
            + "ff2a00d52bd40000ff0000d52a00b649009f60008e7100808000718e00609f0049b6718e00609f0049b6002bd40000ff00"
            + "00d52a00b649009f60008e710080809f60008e7100808000718e00609f0049b6002bd40000ff0000d52a00b649ff0000d4"
            + "2a00b649009f60008e7100808000718e00609f0049b6002bd400"))
    }

    /// An empty macro store as the factory leaves it.
    public static var macroBytes: [UInt8] {
        var b = [UInt8](repeating: 0xFF, count: 1660)
        b.replaceSubrange(0..<24, with: [0x00, 0x01] + [UInt8](repeating: 0, count: 22))
        b.replaceSubrange(1656..<1660, with: [0, 0, 0, 0])
        return b
    }

    static func hex(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            out.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return out
    }
}
