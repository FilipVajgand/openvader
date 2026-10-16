import Foundation

public struct LEDColor: Sendable, Equatable, Hashable, Codable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    public var isBlack: Bool { red == 0 && green == 0 && blue == 0 }

    public static let black = LEDColor(red: 0, green: 0, blue: 0)

    /// h, s, v in 0...1.
    public static func hsv(_ h: Double, _ s: Double, _ v: Double) -> LEDColor {
        let h6 = (h - floor(h)) * 6
        let i = Int(h6) % 6
        let f = h6 - floor(h6)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (r, g, b): (Double, Double, Double) = switch i {
        case 0: (v, t, p)
        case 1: (q, v, p)
        case 2: (p, v, t)
        case 3: (p, q, v)
        case 4: (t, p, v)
        default: (v, p, q)
        }
        return LEDColor(red: UInt8(r * 255), green: UInt8(g * 255), blue: UInt8(b * 255))
    }
}

/// Lighting effects, numbered like Space Station's `LedType` so a profile
/// written here reads back sensibly there.
public enum LightingEffect: UInt8, Sendable, CaseIterable, Codable, Identifiable {
    case flow = 1
    case breathing = 2
    case gradient = 3
    case steady = 5
    case off = 6
    case factory = 7

    public var id: UInt8 { rawValue }

    public var title: String {
        switch self {
        case .flow: "Rainbow flow"
        case .breathing: "Breathing"
        case .gradient: "Color cycle"
        case .steady: "Steady"
        case .off: "Off"
        case .factory: "Factory animation"
        }
    }

    public var colorRange: ClosedRange<Int> {
        switch self {
        case .steady: 1...1
        case .breathing: 1...5
        case .gradient: 2...5
        case .flow, .off, .factory: 0...0
        }
    }

    public var isAnimated: Bool { self == .flow || self == .breathing || self == .gradient || self == .factory }

    /// Effects the editor offers. Factory frames can only be kept, not generated.
    public static let editable: [LightingEffect] = [.steady, .breathing, .gradient, .flow, .off]
}

/// The per-profile lighting blob (`0xA7` / `0xA8`).
///
/// The controller has no effect generator: it plays the stored colour
/// frames, cycling `loopStart...loopEnd`. Every effect is therefore built
/// here as frames. Geometry (LED count, frame count) is read from the blob,
/// never assumed.
public struct LightingConfig: Sendable, Equatable {
    public static let headerSize = 20
    public var bytes: [UInt8]

    public init(bytes: [UInt8]) { self.bytes = bytes }

    public var isValid: Bool {
        bytes.count > Self.headerSize && bytes[0] == 0 && (bytes[1] == 2 || bytes[1] == 3) && ledCount > 0
    }

    public var version: Int { Int(bytes[1]) }
    public var ledCount: Int { bytes.count > 7 ? Int(bytes[7]) : 0 }
    public var frameCount: Int { ledCount > 0 ? (bytes.count - Self.headerSize) / (ledCount * 3) : 0 }

    public var effectRaw: UInt8 { bytes[8] }
    public var effect: LightingEffect? { LightingEffect(rawValue: bytes[8]) }

    /// 0...100
    public var brightness: Int {
        get { Int(min(bytes[6], 100)) }
        set { bytes[6] = UInt8(max(0, min(100, newValue))) }
    }

    /// Frame period; larger is slower.
    public var cycleTime: Int {
        get { Int(bytes[5]) }
        set { bytes[5] = UInt8(max(1, min(255, newValue))) }
    }

    /// Flydigi's "sync grip lighting" flag (`GripSync`). It has no visible effect on the Vader 5 Pro, which
    /// has no grip lights; the light bar ignored both game and test rumble with it set. Kept as read.
    public var gripSync: Bool {
        get { bytes[9] == 1 }
        set { bytes[9] = newValue ? 1 : 0 }
    }

    public var loopStart: Int { Int(bytes[3]) }
    public var loopEnd: Int { Int(bytes[4]) }

    public func color(frame: Int, led: Int) -> LEDColor {
        let o = Self.headerSize + (frame * ledCount + led) * 3
        guard o + 2 < bytes.count else { return .black }
        return LEDColor(red: bytes[o], green: bytes[o + 1], blue: bytes[o + 2])
    }

    mutating func setColor(_ c: LEDColor, frame: Int, led: Int) {
        let o = Self.headerSize + (frame * ledCount + led) * 3
        guard o + 2 < bytes.count else { return }
        bytes[o] = c.red
        bytes[o + 1] = c.green
        bytes[o + 2] = c.blue
    }

    mutating func fill(frame: Int, with c: LEDColor) {
        for led in 0..<ledCount { setColor(c, frame: frame, led: led) }
    }

    /// The distinct colours of the stored frames, for seeding the editor.
    public var paletteGuess: [LEDColor] {
        var out: [LEDColor] = []
        for frame in 0..<frameCount {
            let c = color(frame: frame, led: 0)
            if !c.isBlack, !out.contains(c) { out.append(c) }
        }
        return out
    }

    /// Rebuilds the frames for an effect, keeping the header geometry.
    public mutating func apply(_ effect: LightingEffect, colors: [LEDColor]) {
        guard isValid, effect != .factory else { return }
        let frames = frameCount
        for f in 0..<frames { fill(frame: f, with: .black) }
        bytes[2] = 0  // click feedback latches the display; keep it off
        bytes[3] = 0
        bytes[8] = effect.rawValue
        var palette = colors.isEmpty ? [LEDColor(red: 0, green: 120, blue: 255)] : colors
        switch effect {
        case .steady:
            fill(frame: 0, with: palette[0])
            bytes[4] = 0
        case .off:
            bytes[4] = 0
        case .breathing:
            // Colour, dark, colour, dark... so the controller fades in and out.
            palette = Array(palette.prefix(max(1, frames / 2)))
            for (i, c) in palette.enumerated() { fill(frame: i * 2, with: c) }
            bytes[4] = UInt8(palette.count * 2 - 1)
        case .gradient:
            if palette.count < 2 { palette.append(palette[0]) }
            palette = Array(palette.prefix(frames))
            for (i, c) in palette.enumerated() { fill(frame: i, with: c) }
            bytes[4] = UInt8(palette.count - 1)
        case .flow:
            for f in 0..<frames {
                for led in 0..<ledCount {
                    let hue = Double(led) / Double(ledCount) + Double(f) / Double(frames)
                    setColor(.hsv(hue, 1, 1), frame: f, led: led)
                }
            }
            bytes[4] = UInt8(max(0, frames - 1))
        case .factory:
            break
        }
    }
}
